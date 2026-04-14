import '../../providers/app_state.dart';
import '../events/event_model.dart';
import '../reminders/reminder_model.dart';
import '../tasks/task_model.dart';
import 'planning_timeline_item_model.dart';

enum PlanningAgendaEntryKind { event, task, reminder }

class PlanningAgendaEntryModel {
  const PlanningAgendaEntryModel({
    required this.id,
    required this.kind,
    required this.resourceId,
    required this.title,
    required this.scheduledAt,
    required this.fromPlanningTimeline,
    this.description,
    this.endsAt,
    this.bundleId,
    this.createdVia,
    this.sourceChannel,
    this.priority,
    this.location,
    this.repeat,
    this.status,
    this.planningSurface,
    this.ownerKind,
    this.deliveryMode,
    this.completed = false,
    this.overdue = false,
    this.allDay = false,
    this.task,
    this.event,
    this.reminder,
  });

  final String id;
  final PlanningAgendaEntryKind kind;
  final String resourceId;
  final String title;
  final String? description;
  final DateTime scheduledAt;
  final DateTime? endsAt;
  final String? bundleId;
  final String? createdVia;
  final String? sourceChannel;
  final String? priority;
  final String? location;
  final String? repeat;
  final String? status;
  final String? planningSurface;
  final String? ownerKind;
  final String? deliveryMode;
  final bool completed;
  final bool overdue;
  final bool allDay;
  final bool fromPlanningTimeline;
  final TaskModel? task;
  final EventModel? event;
  final ReminderModel? reminder;

  String get dedupeKey => '${kind.name}:$resourceId';

  bool get canEdit => task != null || event != null || reminder != null;

  String? get planningSurfaceLabel => _nonEmpty(planningSurface);

  String? get ownerLabel => _nonEmpty(ownerKind);

  String? get deliveryModeLabel => _nonEmpty(deliveryMode);
}

class PlanningAgendaDataset {
  const PlanningAgendaDataset({
    required this.entries,
    required this.hiddenReminders,
    required this.timelineStatus,
    required this.timelineMessage,
    required this.usingPlanningTimeline,
    required this.degraded,
  });

  final List<PlanningAgendaEntryModel> entries;
  final List<ReminderModel> hiddenReminders;
  final FeatureStatus timelineStatus;
  final String? timelineMessage;
  final bool usingPlanningTimeline;
  final bool degraded;

  bool get planningReady =>
      timelineStatus == FeatureStatus.ready ||
      timelineStatus == FeatureStatus.demo;

  bool get planningNotReady => timelineStatus == FeatureStatus.notReady;

  List<PlanningAgendaEntryModel> entriesForDay(DateTime day) {
    return entries.where((PlanningAgendaEntryModel entry) {
      return _isSameDay(entry.scheduledAt, day);
    }).toList();
  }

  int countForDay(DateTime day) => entriesForDay(day).length;

  bool hasEntriesOnDay(DateTime day) => countForDay(day) > 0;

  factory PlanningAgendaDataset.fromState(AppState state) {
    final eventById = <String, EventModel>{
      for (final event in state.events) event.id: event,
    };
    final taskById = <String, TaskModel>{
      for (final task in state.tasks) task.id: task,
    };
    final reminderById = <String, ReminderModel>{
      for (final reminder in state.reminders) reminder.id: reminder,
    };
    final entries = <PlanningAgendaEntryModel>[];
    final hiddenReminders = <ReminderModel>[];
    final hiddenReminderIds = <String>{};
    final seen = <String>{};
    final useTimeline =
        state.planningTimelineStatus == FeatureStatus.ready ||
        state.planningTimelineStatus == FeatureStatus.demo;

    void addEntry(PlanningAgendaEntryModel? entry) {
      if (entry == null) {
        return;
      }
      if (seen.add(entry.dedupeKey)) {
        entries.add(entry);
      }
    }

    void addHiddenReminder(ReminderModel reminder) {
      if (hiddenReminderIds.add(reminder.id)) {
        hiddenReminders.add(reminder);
      }
    }

    if (useTimeline) {
      for (final item in state.planningTimeline) {
        addEntry(
          _fromTimelineItem(
            item,
            eventById: eventById,
            taskById: taskById,
            reminderById: reminderById,
          ),
        );
      }
    }

    for (final event in state.events) {
      addEntry(_fromEvent(event, fromPlanningTimeline: false));
    }
    for (final task in state.tasks) {
      addEntry(_fromTask(task, fromPlanningTimeline: false));
    }
    for (final reminder in state.reminders.where(
      (ReminderModel item) => item.enabled,
    )) {
      if (seen.contains(
        '${PlanningAgendaEntryKind.reminder.name}:${reminder.id}',
      )) {
        continue;
      }
      if (!reminder.belongsToAgenda) {
        addHiddenReminder(reminder);
        continue;
      }
      final entry = _fromReminder(reminder, fromPlanningTimeline: false);
      if (entry == null) {
        addHiddenReminder(reminder);
        continue;
      }
      addEntry(entry);
    }

    entries.sort(_compareEntries);

    return PlanningAgendaDataset(
      entries: entries,
      hiddenReminders: hiddenReminders,
      timelineStatus: state.planningTimelineStatus,
      timelineMessage: state.planningTimelineMessage,
      usingPlanningTimeline: useTimeline,
      degraded: !useTimeline,
    );
  }
}

PlanningAgendaEntryModel? _fromTimelineItem(
  PlanningTimelineItemModel item, {
  required Map<String, EventModel> eventById,
  required Map<String, TaskModel> taskById,
  required Map<String, ReminderModel> reminderById,
}) {
  final resourceType = item.resourceType.trim().toLowerCase();
  final kind = switch (resourceType) {
    'event' => PlanningAgendaEntryKind.event,
    'task' => PlanningAgendaEntryKind.task,
    'reminder' => PlanningAgendaEntryKind.reminder,
    _ => null,
  };
  if (kind == null) {
    return null;
  }
  if (!item.belongsToAgenda) {
    return null;
  }

  final resourceId = item.resourceId.isNotEmpty
      ? item.resourceId
      : switch (kind) {
          PlanningAgendaEntryKind.event => item.linkedEventId ?? '',
          PlanningAgendaEntryKind.task => item.linkedTaskId ?? '',
          PlanningAgendaEntryKind.reminder => item.linkedReminderId ?? '',
        };
  if (resourceId.isEmpty) {
    return null;
  }

  final event = eventById[resourceId];
  final task = taskById[resourceId];
  final reminder = reminderById[resourceId];
  final scheduledAt =
      item.startAtDateTime ??
      item.dueAtDateTime ??
      item.nextTriggerDateTime ??
      item.sortAtDateTime ??
      reminder?.nextTriggerDateTime ??
      event?.startDateTime ??
      task?.dueDateTime;
  if (scheduledAt == null) {
    return null;
  }

  return PlanningAgendaEntryModel(
    id: item.id,
    kind: kind,
    resourceId: resourceId,
    title: item.title.isEmpty
        ? event?.title ?? task?.title ?? reminder?.title ?? 'Planning item'
        : item.title,
    description:
        item.description ??
        event?.description ??
        task?.description ??
        reminder?.message,
    scheduledAt: scheduledAt,
    endsAt: item.endAtDateTime ?? event?.endDateTime,
    bundleId:
        item.bundleId ??
        event?.bundleId ??
        task?.bundleId ??
        reminder?.bundleId,
    createdVia:
        item.createdVia ??
        event?.createdVia ??
        task?.createdVia ??
        reminder?.createdVia,
    sourceChannel:
        event?.sourceChannel ?? task?.sourceChannel ?? reminder?.sourceChannel,
    priority: item.priority ?? task?.priority,
    location: event?.location,
    repeat: reminder?.repeat,
    status: item.status ?? reminder?.status,
    planningSurface:
        item.planningSurfaceLabel ??
        event?.planningSurfaceLabel ??
        task?.planningSurfaceLabel ??
        reminder?.planningSurfaceLabel,
    ownerKind:
        item.ownerLabel ??
        event?.ownerLabel ??
        task?.ownerLabel ??
        reminder?.ownerLabel,
    deliveryMode:
        item.deliveryModeLabel ??
        event?.deliveryModeLabel ??
        task?.deliveryModeLabel ??
        reminder?.deliveryModeLabel,
    completed: item.completed || (task?.completed ?? false),
    overdue: item.overdue,
    allDay: item.allDay,
    fromPlanningTimeline: true,
    task: task,
    event: event,
    reminder: reminder,
  );
}

PlanningAgendaEntryModel? _fromEvent(
  EventModel event, {
  required bool fromPlanningTimeline,
}) {
  if (!event.belongsToAgenda) {
    return null;
  }
  final scheduledAt = event.startDateTime;
  if (scheduledAt == null) {
    return null;
  }
  return PlanningAgendaEntryModel(
    id: event.id,
    kind: PlanningAgendaEntryKind.event,
    resourceId: event.id,
    title: event.title,
    description: event.description,
    scheduledAt: scheduledAt,
    endsAt: event.endDateTime,
    bundleId: event.bundleId,
    createdVia: event.createdVia,
    sourceChannel: event.sourceChannel,
    location: event.location,
    planningSurface: event.planningSurfaceLabel,
    ownerKind: event.ownerLabel,
    deliveryMode: event.deliveryModeLabel,
    fromPlanningTimeline: fromPlanningTimeline,
    event: event,
  );
}

PlanningAgendaEntryModel? _fromTask(
  TaskModel task, {
  required bool fromPlanningTimeline,
}) {
  if (!task.belongsToAgenda) {
    return null;
  }
  final scheduledAt = task.dueDateTime;
  if (scheduledAt == null) {
    return null;
  }
  return PlanningAgendaEntryModel(
    id: task.id,
    kind: PlanningAgendaEntryKind.task,
    resourceId: task.id,
    title: task.title,
    description: task.description,
    scheduledAt: scheduledAt,
    bundleId: task.bundleId,
    createdVia: task.createdVia,
    sourceChannel: task.sourceChannel,
    priority: task.priority,
    planningSurface: task.planningSurfaceLabel,
    ownerKind: task.ownerLabel,
    deliveryMode: task.deliveryModeLabel,
    completed: task.completed,
    overdue: !task.completed && scheduledAt.isBefore(DateTime.now()),
    fromPlanningTimeline: fromPlanningTimeline,
    task: task,
  );
}

PlanningAgendaEntryModel? _fromReminder(
  ReminderModel reminder, {
  required bool fromPlanningTimeline,
}) {
  if (!reminder.belongsToAgenda) {
    return null;
  }
  final scheduledAt = reminder.nextTriggerDateTime;
  if (scheduledAt == null) {
    return null;
  }
  return PlanningAgendaEntryModel(
    id: reminder.id,
    kind: PlanningAgendaEntryKind.reminder,
    resourceId: reminder.id,
    title: reminder.title,
    description: reminder.message,
    scheduledAt: scheduledAt,
    bundleId: reminder.bundleId,
    createdVia: reminder.createdVia,
    sourceChannel: reminder.sourceChannel,
    repeat: reminder.repeat,
    status: reminder.status,
    planningSurface: reminder.planningSurfaceLabel,
    ownerKind: reminder.ownerLabel,
    deliveryMode: reminder.deliveryModeLabel,
    fromPlanningTimeline: fromPlanningTimeline,
    reminder: reminder,
  );
}

int _compareEntries(
  PlanningAgendaEntryModel left,
  PlanningAgendaEntryModel right,
) {
  final schedule = left.scheduledAt.compareTo(right.scheduledAt);
  if (schedule != 0) {
    return schedule;
  }
  if (left.kind != right.kind) {
    return _kindOrder(left.kind).compareTo(_kindOrder(right.kind));
  }
  return left.title.compareTo(right.title);
}

int _kindOrder(PlanningAgendaEntryKind kind) {
  return switch (kind) {
    PlanningAgendaEntryKind.event => 0,
    PlanningAgendaEntryKind.reminder => 1,
    PlanningAgendaEntryKind.task => 2,
  };
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String? _nonEmpty(String? value) {
  final cleaned = value?.trim();
  if (cleaned == null || cleaned.isEmpty) {
    return null;
  }
  return cleaned;
}
