part of 'app_providers.dart';

const String _planningUnavailableMessage =
    'Planning workbench is not available on this backend.';

bool _planningAvailable(AppController controller) {
  final bootstrapPlanning =
      controller.state.bootstrap?.planning ?? const <String, dynamic>{};
  return controller.state.capabilities.planning ||
      controller.state.capabilities.planningOverview ||
      controller.state.capabilities.planningTimeline ||
      controller.state.capabilities.planningConflicts ||
      bootstrapPlanning.isNotEmpty;
}

Future<void> _loadPlanningOverview(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      planningOverviewStatus: FeatureStatus.demo,
      planningOverview: null,
      planningOverviewMessage:
          'Demo planning is derived from local sample data.',
    );
    return;
  }
  if (!_planningAvailable(controller)) {
    controller.state = controller.state.copyWith(
      planningOverviewStatus: FeatureStatus.notReady,
      planningOverview: null,
      planningOverviewMessage: _planningUnavailableMessage,
    );
    return;
  }

  controller.state = controller.state.copyWith(
    planningOverviewStatus: FeatureStatus.loading,
  );
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final overview = await controller.ref
        .read(planningServiceProvider)
        .fetchOverview();
    controller.state = controller.state.copyWith(
      planningOverviewStatus: FeatureStatus.ready,
      planningOverview: overview,
      planningOverviewMessage: null,
    );
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      planningOverviewStatus: error.isBackendNotReady
          ? FeatureStatus.notReady
          : FeatureStatus.error,
      planningOverviewMessage: error.isBackendNotReady
          ? AppConfig.backendNotReadyMessage
          : error.message,
    );
  }
}

Future<void> _loadPlanningTimeline(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      planningTimelineStatus: FeatureStatus.demo,
      planningTimeline: const <PlanningTimelineItemModel>[],
      planningTimelineMessage:
          'Demo planning is derived from local sample data.',
    );
    return;
  }
  if (!_planningAvailable(controller)) {
    controller.state = controller.state.copyWith(
      planningTimelineStatus: FeatureStatus.notReady,
      planningTimeline: const <PlanningTimelineItemModel>[],
      planningTimelineMessage: _planningUnavailableMessage,
    );
    return;
  }

  controller.state = controller.state.copyWith(
    planningTimelineStatus: FeatureStatus.loading,
  );
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final timeline = await controller.ref
        .read(planningServiceProvider)
        .fetchTimeline();
    controller.state = controller.state.copyWith(
      planningTimelineStatus: FeatureStatus.ready,
      planningTimeline: timeline,
      planningTimelineMessage: timeline.isEmpty
          ? 'No planning items are scheduled yet.'
          : null,
    );
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      planningTimelineStatus: error.isBackendNotReady
          ? FeatureStatus.notReady
          : FeatureStatus.error,
      planningTimelineMessage: error.isBackendNotReady
          ? AppConfig.backendNotReadyMessage
          : error.message,
    );
  }
}

Future<void> _loadPlanningConflicts(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      planningConflictsStatus: FeatureStatus.demo,
      planningConflicts: const <PlanningConflictModel>[],
      planningConflictsMessage:
          'Demo planning is derived from local sample data.',
    );
    return;
  }
  if (!_planningAvailable(controller)) {
    controller.state = controller.state.copyWith(
      planningConflictsStatus: FeatureStatus.notReady,
      planningConflicts: const <PlanningConflictModel>[],
      planningConflictsMessage: _planningUnavailableMessage,
    );
    return;
  }

  controller.state = controller.state.copyWith(
    planningConflictsStatus: FeatureStatus.loading,
  );
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final conflicts = await controller.ref
        .read(planningServiceProvider)
        .fetchConflicts();
    controller.state = controller.state.copyWith(
      planningConflictsStatus: FeatureStatus.ready,
      planningConflicts: conflicts,
      planningConflictsMessage: conflicts.isEmpty
          ? 'No conflicts detected right now.'
          : null,
    );
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      planningConflictsStatus: error.isBackendNotReady
          ? FeatureStatus.notReady
          : FeatureStatus.error,
      planningConflictsMessage: error.isBackendNotReady
          ? AppConfig.backendNotReadyMessage
          : error.message,
    );
  }
}

Future<void> _refreshPlanningWorkbench(AppController controller) async {
  if (!controller.state.isConnected) {
    return;
  }
  await controller.loadPlanningOverview();
  await controller.loadPlanningTimeline();
  await controller.loadPlanningConflicts();
}

Future<void> _loadTasks(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      tasksStatus: FeatureStatus.demo,
      tasks: DemoServiceBundle.tasks,
      tasksMessage: 'Demo tasks are local.',
    );
    return;
  }
  controller.state = controller.state.copyWith(
    tasksStatus: FeatureStatus.loading,
  );
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final tasks = await controller.ref.read(tasksServiceProvider).listTasks();
    controller.state = controller.state.copyWith(
      tasksStatus: FeatureStatus.ready,
      tasks: tasks,
      tasksMessage: tasks.isEmpty ? 'No tasks yet.' : null,
    );
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      tasksStatus: error.isBackendNotReady
          ? FeatureStatus.notReady
          : FeatureStatus.error,
      tasksMessage: error.isBackendNotReady
          ? AppConfig.backendNotReadyMessage
          : error.message,
    );
  }
}

Future<void> _createTask(AppController controller, TaskModel task) async {
  if (controller.state.isDemoMode) {
    final created = task.copyWith();
    controller.state = controller.state.copyWith(
      tasks: controller._sortTasks(<TaskModel>[
        created,
        ...controller.state.tasks,
      ]),
      tasksMessage: 'Demo task created locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final created = await controller.ref
        .read(tasksServiceProvider)
        .createTask(task);
    controller.state = controller.state.copyWith(
      tasksStatus: FeatureStatus.ready,
      tasks: controller._sortTasks(<TaskModel>[
        created,
        ...controller.state.tasks,
      ]),
      tasksMessage: 'Task created.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      tasksStatus: FeatureStatus.error,
      tasksMessage: error.message,
    );
  }
}

Future<void> _createPlanningBundle(
  AppController controller, {
  List<TaskModel> tasks = const <TaskModel>[],
  List<EventModel> events = const <EventModel>[],
  List<ReminderModel> reminders = const <ReminderModel>[],
  String successMessage = 'Planning items created.',
}) async {
  if (tasks.isEmpty && events.isEmpty && reminders.isEmpty) {
    return;
  }

  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      tasks: controller._sortTasks(
        controller._mergeTasks(controller.state.tasks, tasks),
      ),
      events: controller._sortEvents(
        controller._mergeEvents(controller.state.events, events),
      ),
      reminders: controller._sortReminders(
        controller._mergeReminders(controller.state.reminders, reminders),
      ),
      tasksStatus: FeatureStatus.demo,
      eventsStatus: FeatureStatus.demo,
      remindersStatus: FeatureStatus.demo,
      globalMessage: 'Demo planning bundle created locally.',
    );
    return;
  }

  controller._apiClient.setConnection(controller.state.connection);
  final firstBundleId = _firstDefined<String>(<String?>[
    tasks.isEmpty ? null : tasks.first.bundleId,
    events.isEmpty ? null : events.first.bundleId,
    reminders.isEmpty ? null : reminders.first.bundleId,
  ]);
  final createdVia = _firstDefined<String>(<String?>[
    tasks.isEmpty ? null : tasks.first.createdVia,
    events.isEmpty ? null : events.first.createdVia,
    reminders.isEmpty ? null : reminders.first.createdVia,
  ]);
  final sourceChannel = _firstDefined<String>(<String?>[
    tasks.isEmpty ? null : tasks.first.sourceChannel,
    events.isEmpty ? null : events.first.sourceChannel,
    reminders.isEmpty ? null : reminders.first.sourceChannel,
  ]);
  final sourceSessionId = _firstDefined<String>(<String?>[
    tasks.isEmpty ? null : tasks.first.sourceSessionId,
    events.isEmpty ? null : events.first.sourceSessionId,
    reminders.isEmpty ? null : reminders.first.sourceSessionId,
  ]);
  final sourceMessageId = _firstDefined<String>(<String?>[
    tasks.isEmpty ? null : tasks.first.sourceMessageId,
    events.isEmpty ? null : events.first.sourceMessageId,
    reminders.isEmpty ? null : reminders.first.sourceMessageId,
  ]);

  try {
    final bundle = await controller.ref
        .read(planningServiceProvider)
        .createBundle(<String, dynamic>{
          if (firstBundleId?.isNotEmpty == true) 'bundle_id': firstBundleId,
          if (createdVia?.isNotEmpty == true) 'created_via': createdVia,
          if (sourceChannel?.isNotEmpty == true)
            'source_channel': sourceChannel,
          if (sourceSessionId?.isNotEmpty == true)
            'source_session_id': sourceSessionId,
          if (sourceMessageId?.isNotEmpty == true)
            'source_message_id': sourceMessageId,
          if (tasks.isNotEmpty)
            'tasks': tasks
                .map((TaskModel item) => item.toCreateJson())
                .toList(),
          if (events.isNotEmpty)
            'events': events
                .map((EventModel item) => item.toCreateJson())
                .toList(),
          if (reminders.isNotEmpty)
            'reminders': reminders
                .map((ReminderModel item) => item.toCreateJson())
                .toList(),
        });

    final createdTasks = _decodeTasksFromBundle(bundle);
    final createdEvents = _decodeEventsFromBundle(bundle);
    final createdReminders = _decodeRemindersFromBundle(bundle);
    final createdNotifications = _decodeNotificationsFromBundle(bundle);

    controller.state = controller.state.copyWith(
      tasksStatus: FeatureStatus.ready,
      tasks: controller._sortTasks(
        controller._mergeTasks(controller.state.tasks, createdTasks),
      ),
      tasksMessage: createdTasks.isEmpty ? controller.state.tasksMessage : null,
      eventsStatus: FeatureStatus.ready,
      events: controller._sortEvents(
        controller._mergeEvents(controller.state.events, createdEvents),
      ),
      eventsMessage: createdEvents.isEmpty
          ? controller.state.eventsMessage
          : null,
      remindersStatus: FeatureStatus.ready,
      reminders: controller._sortReminders(
        controller._mergeReminders(
          controller.state.reminders,
          createdReminders,
        ),
      ),
      remindersMessage: createdReminders.isEmpty
          ? controller.state.remindersMessage
          : null,
      notificationsStatus: createdNotifications.isEmpty
          ? controller.state.notificationsStatus
          : FeatureStatus.ready,
      notifications: createdNotifications.isEmpty
          ? controller.state.notifications
          : controller._mergeNotifications(
              controller.state.notifications,
              createdNotifications,
            ),
      notificationsMessage: createdNotifications.isEmpty
          ? controller.state.notificationsMessage
          : null,
      globalMessage: successMessage,
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(globalMessage: error.message);
  }
}

Future<void> _updateTask(AppController controller, TaskModel task) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      tasks: controller._sortTasks(
        controller._replaceTask(controller.state.tasks, task),
      ),
      tasksMessage: 'Demo task updated locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final updated = await controller.ref
        .read(tasksServiceProvider)
        .updateTask(task.id, task.toUpdateJson());
    controller.state = controller.state.copyWith(
      tasksStatus: FeatureStatus.ready,
      tasks: controller._sortTasks(
        controller._replaceTask(controller.state.tasks, updated),
      ),
      tasksMessage: 'Task updated.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      tasksStatus: FeatureStatus.error,
      tasksMessage: error.message,
    );
  }
}

Future<void> _deleteTask(AppController controller, String taskId) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      tasks: controller.state.tasks
          .where((TaskModel item) => item.id != taskId)
          .toList(),
      tasksMessage: 'Demo task deleted locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    await controller.ref.read(tasksServiceProvider).deleteTask(taskId);
    final remaining = controller.state.tasks
        .where((TaskModel item) => item.id != taskId)
        .toList();
    controller.state = controller.state.copyWith(
      tasksStatus: FeatureStatus.ready,
      tasks: remaining,
      tasksMessage: remaining.isEmpty ? 'No tasks yet.' : 'Task deleted.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      tasksStatus: FeatureStatus.error,
      tasksMessage: error.message,
    );
  }
}

Future<void> _loadEvents(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      eventsStatus: FeatureStatus.demo,
      events: DemoServiceBundle.events,
      eventsMessage: 'Demo events are local.',
    );
    return;
  }
  controller.state = controller.state.copyWith(
    eventsStatus: FeatureStatus.loading,
  );
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final events = await controller.ref
        .read(eventsServiceProvider)
        .listEvents();
    controller.state = controller.state.copyWith(
      eventsStatus: FeatureStatus.ready,
      events: events,
      eventsMessage: events.isEmpty ? 'No upcoming events.' : null,
    );
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      eventsStatus: error.isBackendNotReady
          ? FeatureStatus.notReady
          : FeatureStatus.error,
      eventsMessage: error.isBackendNotReady
          ? AppConfig.backendNotReadyMessage
          : error.message,
    );
  }
}

Future<void> _createEvent(AppController controller, EventModel event) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      events: controller._sortEvents(<EventModel>[
        event,
        ...controller.state.events,
      ]),
      eventsMessage: 'Demo event created locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final created = await controller.ref
        .read(eventsServiceProvider)
        .createEvent(event);
    controller.state = controller.state.copyWith(
      eventsStatus: FeatureStatus.ready,
      events: controller._sortEvents(<EventModel>[
        created,
        ...controller.state.events,
      ]),
      eventsMessage: 'Event created.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      eventsStatus: FeatureStatus.error,
      eventsMessage: error.message,
    );
  }
}

Future<void> _updateEvent(AppController controller, EventModel event) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      events: controller._sortEvents(
        controller._replaceEvent(controller.state.events, event),
      ),
      eventsMessage: 'Demo event updated locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final updated = await controller.ref
        .read(eventsServiceProvider)
        .updateEvent(event.id, event.toUpdateJson());
    controller.state = controller.state.copyWith(
      eventsStatus: FeatureStatus.ready,
      events: controller._sortEvents(
        controller._replaceEvent(controller.state.events, updated),
      ),
      eventsMessage: 'Event updated.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      eventsStatus: FeatureStatus.error,
      eventsMessage: error.message,
    );
  }
}

Future<void> _deleteEvent(AppController controller, String eventId) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      events: controller.state.events
          .where((EventModel item) => item.id != eventId)
          .toList(),
      eventsMessage: 'Demo event deleted locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    await controller.ref.read(eventsServiceProvider).deleteEvent(eventId);
    final remaining = controller.state.events
        .where((EventModel item) => item.id != eventId)
        .toList();
    controller.state = controller.state.copyWith(
      eventsStatus: FeatureStatus.ready,
      events: remaining,
      eventsMessage: remaining.isEmpty
          ? 'No upcoming events.'
          : 'Event deleted.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      eventsStatus: FeatureStatus.error,
      eventsMessage: error.message,
    );
  }
}

Future<void> _loadNotifications(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.demo,
      notifications: DemoServiceBundle.notifications,
      notificationsMessage: 'Demo notifications are local.',
    );
    return;
  }
  controller.state = controller.state.copyWith(
    notificationsStatus: FeatureStatus.loading,
  );
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final items = await controller.ref
        .read(notificationsServiceProvider)
        .listNotifications();
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.ready,
      notifications: items,
      notificationsMessage: items.isEmpty ? 'No notifications.' : null,
    );
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      notificationsStatus: error.isBackendNotReady
          ? FeatureStatus.notReady
          : FeatureStatus.error,
      notificationsMessage: error.isBackendNotReady
          ? AppConfig.backendNotReadyMessage
          : error.message,
    );
  }
}

Future<void> _markNotificationRead(
  AppController controller,
  String notificationId, {
  required bool read,
}) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      notifications: controller._replaceNotification(
        controller.state.notifications,
        controller.state.notifications
            .firstWhere((NotificationModel item) => item.id == notificationId)
            .copyWith(read: read),
      ),
      notificationsMessage: read
          ? 'Demo notification marked read.'
          : 'Demo notification marked unread.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    await controller.ref
        .read(notificationsServiceProvider)
        .markRead(notificationId, read: read);
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.ready,
      notifications: controller._replaceNotification(
        controller.state.notifications,
        controller.state.notifications
            .firstWhere((NotificationModel item) => item.id == notificationId)
            .copyWith(read: read),
      ),
      notificationsMessage: read
          ? 'Notification marked read.'
          : 'Notification marked unread.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.error,
      notificationsMessage: error.message,
    );
  }
}

Future<void> _markAllNotificationsRead(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      notifications: controller.state.notifications
          .map((NotificationModel item) => item.copyWith(read: true))
          .toList(),
      notificationsMessage: 'Demo notifications marked read.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    await controller.ref.read(notificationsServiceProvider).markAllRead();
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.ready,
      notifications: controller.state.notifications
          .map((NotificationModel item) => item.copyWith(read: true))
          .toList(),
      notificationsMessage: 'All notifications marked read.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.error,
      notificationsMessage: error.message,
    );
  }
}

Future<void> _deleteNotification(
  AppController controller,
  String notificationId,
) async {
  if (controller.state.isDemoMode) {
    final remaining = controller.state.notifications
        .where((NotificationModel item) => item.id != notificationId)
        .toList();
    controller.state = controller.state.copyWith(
      notifications: remaining,
      notificationsMessage: remaining.isEmpty
          ? 'No notifications.'
          : 'Demo notification deleted locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    await controller.ref
        .read(notificationsServiceProvider)
        .deleteNotification(notificationId);
    final remaining = controller.state.notifications
        .where((NotificationModel item) => item.id != notificationId)
        .toList();
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.ready,
      notifications: remaining,
      notificationsMessage: remaining.isEmpty
          ? 'No notifications.'
          : 'Notification deleted.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.error,
      notificationsMessage: error.message,
    );
  }
}

Future<void> _clearNotifications(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      notifications: const <NotificationModel>[],
      notificationsMessage: 'Demo notifications cleared locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    await controller.ref
        .read(notificationsServiceProvider)
        .clearNotifications();
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.ready,
      notifications: const <NotificationModel>[],
      notificationsMessage: 'Notifications cleared.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      notificationsStatus: FeatureStatus.error,
      notificationsMessage: error.message,
    );
  }
}

Future<void> _loadReminders(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      remindersStatus: FeatureStatus.demo,
      reminders: DemoServiceBundle.reminders,
      remindersMessage: 'Demo reminders are local.',
    );
    return;
  }
  controller.state = controller.state.copyWith(
    remindersStatus: FeatureStatus.loading,
  );
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final items = await controller.ref
        .read(remindersServiceProvider)
        .listReminders();
    controller.state = controller.state.copyWith(
      remindersStatus: FeatureStatus.ready,
      reminders: items,
      remindersMessage: items.isEmpty ? 'No reminders.' : null,
    );
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      remindersStatus: error.isBackendNotReady
          ? FeatureStatus.notReady
          : FeatureStatus.error,
      remindersMessage: error.isBackendNotReady
          ? AppConfig.backendNotReadyMessage
          : error.message,
    );
  }
}

Future<void> _createReminder(
  AppController controller,
  ReminderModel reminder,
) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      reminders: controller._sortReminders(<ReminderModel>[
        reminder,
        ...controller.state.reminders,
      ]),
      remindersMessage: 'Demo reminder created locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final created = await controller.ref
        .read(remindersServiceProvider)
        .createReminder(reminder);
    controller.state = controller.state.copyWith(
      remindersStatus: FeatureStatus.ready,
      reminders: controller._sortReminders(<ReminderModel>[
        created,
        ...controller.state.reminders,
      ]),
      remindersMessage: 'Reminder created.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      remindersStatus: FeatureStatus.error,
      remindersMessage: error.message,
    );
  }
}

Future<void> _updateReminder(
  AppController controller,
  ReminderModel reminder,
) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      reminders: controller._sortReminders(
        controller._replaceReminder(controller.state.reminders, reminder),
      ),
      remindersMessage: 'Demo reminder updated locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final updated = await controller.ref
        .read(remindersServiceProvider)
        .updateReminder(reminder.id, reminder.toUpdateJson());
    controller.state = controller.state.copyWith(
      remindersStatus: FeatureStatus.ready,
      reminders: controller._sortReminders(
        controller._replaceReminder(controller.state.reminders, updated),
      ),
      remindersMessage: 'Reminder updated.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      remindersStatus: FeatureStatus.error,
      remindersMessage: error.message,
    );
  }
}

Future<void> _setReminderEnabled(
  AppController controller,
  String reminderId,
  bool enabled,
) async {
  final target = controller.state.reminders.firstWhere(
    (ReminderModel item) => item.id == reminderId,
  );
  await controller.updateReminder(target.copyWith(enabled: enabled));
}

Future<void> _deleteReminder(
  AppController controller,
  String reminderId,
) async {
  if (controller.state.isDemoMode) {
    final remaining = controller.state.reminders
        .where((ReminderModel item) => item.id != reminderId)
        .toList();
    controller.state = controller.state.copyWith(
      reminders: remaining,
      remindersMessage: remaining.isEmpty
          ? 'No reminders.'
          : 'Demo reminder deleted locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    await controller.ref
        .read(remindersServiceProvider)
        .deleteReminder(reminderId);
    final remaining = controller.state.reminders
        .where((ReminderModel item) => item.id != reminderId)
        .toList();
    controller.state = controller.state.copyWith(
      remindersStatus: FeatureStatus.ready,
      reminders: remaining,
      remindersMessage: remaining.isEmpty
          ? 'No reminders.'
          : 'Reminder deleted.',
    );
    unawaited(controller.refreshPlanningWorkbench());
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      remindersStatus: FeatureStatus.error,
      remindersMessage: error.message,
    );
  }
}
