import '../events/event_model.dart';
import '../reminders/reminder_model.dart';
import '../tasks/task_model.dart';

enum PlanningEditorKind { task, event, reminder }

extension PlanningEditorKindX on PlanningEditorKind {
  String get label => switch (this) {
    PlanningEditorKind.task => 'Task',
    PlanningEditorKind.event => 'Event',
    PlanningEditorKind.reminder => 'Reminder',
  };

  String get iconLabel => switch (this) {
    PlanningEditorKind.task => 'Tasks',
    PlanningEditorKind.event => 'Calendar',
    PlanningEditorKind.reminder => 'Reminders',
  };
}

class PlanningMetadataDraft {
  const PlanningMetadataDraft({
    required this.bundleId,
    required this.createdVia,
    required this.sourceChannel,
    required this.sourceSessionId,
    required this.sourceMessageId,
    required this.linkedTaskId,
    required this.linkedEventId,
    required this.linkedReminderId,
  });

  final String bundleId;
  final String createdVia;
  final String sourceChannel;
  final String sourceSessionId;
  final String sourceMessageId;
  final String linkedTaskId;
  final String linkedEventId;
  final String linkedReminderId;

  factory PlanningMetadataDraft.forNew({
    required String createdVia,
    required String sourceChannel,
    String? sourceSessionId,
  }) {
    return PlanningMetadataDraft(
      bundleId: generatePlanningBundleId(),
      createdVia: createdVia,
      sourceChannel: sourceChannel,
      sourceSessionId: sourceSessionId?.trim() ?? '',
      sourceMessageId: '',
      linkedTaskId: '',
      linkedEventId: '',
      linkedReminderId: '',
    );
  }

  factory PlanningMetadataDraft.fromTask(
    TaskModel task, {
    required String fallbackCreatedVia,
    required String sourceChannel,
    String? sourceSessionId,
  }) {
    return PlanningMetadataDraft(
      bundleId: task.bundleId ?? generatePlanningBundleId(),
      createdVia: task.createdVia ?? fallbackCreatedVia,
      sourceChannel: task.sourceChannel ?? sourceChannel,
      sourceSessionId: task.sourceSessionId ?? sourceSessionId?.trim() ?? '',
      sourceMessageId: task.sourceMessageId ?? '',
      linkedTaskId: task.linkedTaskId ?? '',
      linkedEventId: task.linkedEventId ?? '',
      linkedReminderId: task.linkedReminderId ?? '',
    );
  }

  factory PlanningMetadataDraft.fromEvent(
    EventModel event, {
    required String fallbackCreatedVia,
    required String sourceChannel,
    String? sourceSessionId,
  }) {
    return PlanningMetadataDraft(
      bundleId: event.bundleId ?? generatePlanningBundleId(),
      createdVia: event.createdVia ?? fallbackCreatedVia,
      sourceChannel: event.sourceChannel ?? sourceChannel,
      sourceSessionId: event.sourceSessionId ?? sourceSessionId?.trim() ?? '',
      sourceMessageId: event.sourceMessageId ?? '',
      linkedTaskId: event.linkedTaskId ?? '',
      linkedEventId: event.linkedEventId ?? '',
      linkedReminderId: event.linkedReminderId ?? '',
    );
  }

  factory PlanningMetadataDraft.fromReminder(
    ReminderModel reminder, {
    required String fallbackCreatedVia,
    required String sourceChannel,
    String? sourceSessionId,
  }) {
    return PlanningMetadataDraft(
      bundleId: reminder.bundleId ?? generatePlanningBundleId(),
      createdVia: reminder.createdVia ?? fallbackCreatedVia,
      sourceChannel: reminder.sourceChannel ?? sourceChannel,
      sourceSessionId:
          reminder.sourceSessionId ?? sourceSessionId?.trim() ?? '',
      sourceMessageId: reminder.sourceMessageId ?? '',
      linkedTaskId: reminder.linkedTaskId ?? '',
      linkedEventId: reminder.linkedEventId ?? '',
      linkedReminderId: reminder.linkedReminderId ?? '',
    );
  }

  PlanningMetadataDraft copyWith({
    String? bundleId,
    String? createdVia,
    String? sourceChannel,
    String? sourceSessionId,
    String? sourceMessageId,
    String? linkedTaskId,
    String? linkedEventId,
    String? linkedReminderId,
  }) {
    return PlanningMetadataDraft(
      bundleId: bundleId ?? this.bundleId,
      createdVia: createdVia ?? this.createdVia,
      sourceChannel: sourceChannel ?? this.sourceChannel,
      sourceSessionId: sourceSessionId ?? this.sourceSessionId,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      linkedTaskId: linkedTaskId ?? this.linkedTaskId,
      linkedEventId: linkedEventId ?? this.linkedEventId,
      linkedReminderId: linkedReminderId ?? this.linkedReminderId,
    );
  }

  Map<String, dynamic> toMetadataMap({
    Map<String, dynamic> seed = const <String, dynamic>{},
  }) {
    final next = <String, dynamic>{...seed};
    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>('bundle_id', bundleId),
      MapEntry<String, String>('created_via', createdVia),
      MapEntry<String, String>('source_channel', sourceChannel),
      MapEntry<String, String>('source_session_id', sourceSessionId),
      MapEntry<String, String>('source_message_id', sourceMessageId),
      MapEntry<String, String>('linked_task_id', linkedTaskId),
      MapEntry<String, String>('linked_event_id', linkedEventId),
      MapEntry<String, String>('linked_reminder_id', linkedReminderId),
    ]) {
      final trimmed = entry.value.trim();
      if (trimmed.isNotEmpty) {
        next[entry.key] = trimmed;
      }
    }
    return next;
  }
}

String generatePlanningBundleId() {
  return 'bundle_ui_${DateTime.now().millisecondsSinceEpoch}';
}
