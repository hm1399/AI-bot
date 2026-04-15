part of 'app_providers.dart';

void _handleAppControllerRealtimeStatus(
  AppController controller,
  RealtimeConnectionStatus status,
) {
  controller.state = controller.state.copyWith(
    eventStreamConnected: status == RealtimeConnectionStatus.connected,
  );
}

void _applyAppControllerVoiceActivityUpdate(
  AppController controller, {
  String? transcript,
  String? response,
  String? error,
  String? stateLabel,
  String? sessionId,
  String? taskId,
  required String occurredAt,
  bool clearError = false,
}) {
  controller.state = controller.state.copyWith(
    voiceActivity: controller.state.voiceActivity.copyWith(
      lastTranscript:
          transcript ?? controller.state.voiceActivity.lastTranscript,
      lastResponse: response ?? controller.state.voiceActivity.lastResponse,
      lastError: clearError
          ? null
          : error ?? controller.state.voiceActivity.lastError,
      lastUpdatedAt: occurredAt,
      sessionId: sessionId ?? controller.state.voiceActivity.sessionId,
      taskId: taskId ?? controller.state.voiceActivity.taskId,
      state: stateLabel ?? controller.state.voiceActivity.state,
    ),
  );
}

void _applyAppControllerVoiceRuntimeSnapshot(
  AppController controller,
  dynamic rawSnapshot,
) {
  final snapshot = rawSnapshot is Map<String, dynamic>
      ? rawSnapshot
      : <String, dynamic>{};
  if (snapshot.isEmpty) {
    return;
  }
  controller.state = controller.state.copyWith(
    runtimeState: controller.state.runtimeState.copyWithVoice(
      VoiceStatusModel.fromJson(snapshot),
    ),
  );
}

String? _readAppControllerVoiceSnapshotStatus(dynamic rawSnapshot) {
  if (rawSnapshot is! Map<String, dynamic>) {
    return null;
  }
  final value = rawSnapshot['status']?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

String? _readAppControllerVoiceEventSessionId(AppEventModel event) {
  final metadata = event.payload['metadata'];
  if (event.sessionId != null && event.sessionId!.trim().isNotEmpty) {
    return event.sessionId;
  }
  if (metadata is Map<String, dynamic>) {
    for (final key in const <String>[
      'app_session_id',
      'source_session_id',
      'session_id',
    ]) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
  }
  return null;
}

String? _readAppControllerVoiceEventTaskId(AppEventModel event) {
  final metadata = event.payload['metadata'];
  if (event.taskId != null && event.taskId!.trim().isNotEmpty) {
    return event.taskId;
  }
  if (metadata is Map<String, dynamic>) {
    final value = metadata['task_id']?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

void _handleAppControllerEvent(AppController controller, AppEventModel event) {
  if (event.eventId.isNotEmpty) {
    final nextConnection = controller.state.connection.copyWith(
      latestEventId: event.eventId,
    );
    controller.ref.read(connectServiceProvider).saveConnection(nextConnection);
    controller.ref.read(wsServiceProvider).setLatestEventId(event.eventId);
    controller.state = controller.state.copyWith(connection: nextConnection);
  }

  switch (event.eventType) {
    case 'system.hello':
      final resume = event.payload['resume'];
      if (resume is Map<String, dynamic> &&
          resume['should_refetch_bootstrap'] == true) {
        unawaited(controller.refreshAll());
      }
      break;
    case 'desktop_voice.state.changed':
      _applyAppControllerVoiceRuntimeSnapshot(controller, event.payload);
      _applyAppControllerVoiceActivityUpdate(
        controller,
        occurredAt: event.occurredAt,
        sessionId: _readAppControllerVoiceEventSessionId(event),
        taskId: _readAppControllerVoiceEventTaskId(event),
        stateLabel: event.payload['status']?.toString(),
      );
      break;
    case 'desktop_voice.transcript':
      _applyAppControllerVoiceRuntimeSnapshot(
        controller,
        event.payload['state'],
      );
      _applyAppControllerVoiceActivityUpdate(
        controller,
        transcript: event.payload['text']?.toString(),
        occurredAt: event.occurredAt,
        sessionId: _readAppControllerVoiceEventSessionId(event),
        taskId: _readAppControllerVoiceEventTaskId(event),
        stateLabel: _readAppControllerVoiceSnapshotStatus(
          event.payload['state'],
        ),
        clearError: true,
      );
      break;
    case 'desktop_voice.response':
      _applyAppControllerVoiceRuntimeSnapshot(
        controller,
        event.payload['state'],
      );
      _applyAppControllerVoiceActivityUpdate(
        controller,
        response: event.payload['text']?.toString(),
        occurredAt: event.occurredAt,
        sessionId: _readAppControllerVoiceEventSessionId(event),
        taskId: _readAppControllerVoiceEventTaskId(event),
        stateLabel: _readAppControllerVoiceSnapshotStatus(
          event.payload['state'],
        ),
        clearError: true,
      );
      break;
    case 'desktop_voice.error':
      _applyAppControllerVoiceRuntimeSnapshot(
        controller,
        event.payload['state'],
      );
      _applyAppControllerVoiceActivityUpdate(
        controller,
        error: event.payload['message']?.toString(),
        occurredAt: event.occurredAt,
        sessionId: _readAppControllerVoiceEventSessionId(event),
        taskId: _readAppControllerVoiceEventTaskId(event),
        stateLabel:
            _readAppControllerVoiceSnapshotStatus(event.payload['state']) ??
            'error',
      );
      break;
    case 'runtime.task.current_changed':
    case 'runtime.task.queue_changed':
    case 'device.state.changed':
    case 'device.status.updated':
    case 'device.interaction.recorded':
    case 'todo.summary.changed':
    case 'calendar.summary.changed':
      unawaited(controller.refreshRuntime());
      break;
    case 'runtime.experience.updated':
      final rawExperience = event.payload['experience'];
      if (rawExperience is Map<String, dynamic>) {
        final nextExperience = ExperienceRuntimeModel.fromJson(rawExperience);
        final nextRuntime = controller.state.runtimeState.copyWithExperience(
          nextExperience,
        );
        controller.state = controller.state.copyWith(runtimeState: nextRuntime);
      } else {
        unawaited(controller.refreshRuntime());
      }
      break;
    case 'device.connection.changed':
      final connected = event.payload['connected'] == true;
      controller.state = controller.state.copyWith(
        globalMessage: connected
            ? 'Device online.'
            : 'Device offline. Waiting for reconnect.',
      );
      unawaited(controller.refreshRuntime());
      break;
    case 'planning.changed':
      unawaited(controller.refreshPlanningWorkbench());
      break;
    case 'computer.action.created':
    case 'computer.action.updated':
    case 'computer.action.completed':
    case 'computer.action.cancelled':
    case 'computer.action.requires_confirmation':
      final action = controller._actionFromEvent(event);
      if (action == null) {
        unawaited(controller.loadComputerControl(silent: true));
        break;
      }
      controller._storeComputerControl(
        controller
            ._computerControlSeed(clearStatusMessage: true)
            .upsertAction(action),
        globalMessage: controller._computerActionMessage(action),
      );
      break;
    case 'session.updated':
      final rawSession = event.payload['session'];
      if (rawSession is Map<String, dynamic>) {
        final nextSession = SessionModel.fromJson(rawSession);
        controller.state = controller.state.copyWith(
          sessions: controller._replaceSession(
            controller.state.sessions,
            nextSession,
          ),
          sessionExperienceOverrides: controller._storeSessionExperience(
            controller.state.sessionExperienceOverrides,
            nextSession.sessionId,
            controller._experienceOverrideFromSession(nextSession),
          ),
        );
      }
      break;
    case 'session.message.created':
    case 'session.message.completed':
      final raw = event.payload['message'];
      if (raw is Map<String, dynamic>) {
        final sessionId = event.sessionId ?? controller.state.currentSessionId;
        final nextMessage = MessageModel.fromJson(raw);
        final existingMessages = List<MessageModel>.from(
          controller.state.messagesBySession[sessionId] ??
              const <MessageModel>[],
        );
        final alreadyPresent = existingMessages.any(
          (MessageModel item) => item.id == nextMessage.id,
        );
        final updated = controller._upsertMessage(
          existingMessages,
          nextMessage,
        );
        controller.state = controller.state.copyWith(
          messagesBySession: <String, List<MessageModel>>{
            ...controller.state.messagesBySession,
            sessionId: updated,
          },
          sessions: controller._touchSession(
            controller.state.sessions,
            sessionId,
            summary: nextMessage.text,
            lastMessageAt: nextMessage.createdAt,
            incrementCount: !alreadyPresent,
          ),
        );
      }
      break;
    case 'session.message.progress':
      final sessionId = event.sessionId ?? controller.state.currentSessionId;
      final streaming = MessageModel(
        id:
            event.payload['message_id']?.toString() ??
            'assistant-${DateTime.now().millisecondsSinceEpoch}',
        sessionId: sessionId,
        role: 'assistant',
        text: event.payload['content']?.toString() ?? '',
        status: 'streaming',
        createdAt: DateTime.now().toIso8601String(),
        metadata: event.payload['metadata'] is Map<String, dynamic>
            ? event.payload['metadata'] as Map<String, dynamic>
            : const <String, dynamic>{},
      );
      final updated = controller._upsertMessage(
        List<MessageModel>.from(
          controller.state.messagesBySession[sessionId] ??
              const <MessageModel>[],
        ),
        streaming,
      );
      controller.state = controller.state.copyWith(
        messagesBySession: <String, List<MessageModel>>{
          ...controller.state.messagesBySession,
          sessionId: updated,
        },
      );
      break;
    case 'session.message.failed':
      controller.state = controller.state.copyWith(
        globalMessage: 'Assistant response failed.',
      );
      break;
    case 'task.created':
    case 'task.updated':
      final rawTask = event.payload['task'];
      if (rawTask is Map<String, dynamic>) {
        final task = TaskModel.fromJson(rawTask);
        final existing =
            controller.state.tasks.any((TaskModel item) => item.id == task.id)
            ? controller._replaceTask(controller.state.tasks, task)
            : <TaskModel>[task, ...controller.state.tasks];
        controller.state = controller.state.copyWith(
          tasksStatus: FeatureStatus.ready,
          tasks: controller._sortTasks(existing),
          tasksMessage: null,
        );
        unawaited(controller.refreshPlanningWorkbench());
      }
      break;
    case 'task.deleted':
      final rawTask = event.payload['task'];
      if (rawTask is Map<String, dynamic>) {
        final taskId =
            rawTask['task_id']?.toString() ?? rawTask['id']?.toString();
        if (taskId != null && taskId.isNotEmpty) {
          final remaining = controller.state.tasks
              .where((TaskModel item) => item.id != taskId)
              .toList();
          controller.state = controller.state.copyWith(
            tasksStatus: FeatureStatus.ready,
            tasks: remaining,
            tasksMessage: remaining.isEmpty ? 'No tasks yet.' : null,
          );
          unawaited(controller.refreshPlanningWorkbench());
        }
      }
      break;
    case 'event.created':
    case 'event.updated':
      final rawEvent = event.payload['event'];
      if (rawEvent is Map<String, dynamic>) {
        final nextEvent = EventModel.fromJson(rawEvent);
        final existing =
            controller.state.events.any(
              (EventModel item) => item.id == nextEvent.id,
            )
            ? controller._replaceEvent(controller.state.events, nextEvent)
            : <EventModel>[nextEvent, ...controller.state.events];
        controller.state = controller.state.copyWith(
          eventsStatus: FeatureStatus.ready,
          events: controller._sortEvents(existing),
          eventsMessage: null,
        );
        unawaited(controller.refreshPlanningWorkbench());
      }
      break;
    case 'event.deleted':
      final rawEvent = event.payload['event'];
      if (rawEvent is Map<String, dynamic>) {
        final eventId =
            rawEvent['event_id']?.toString() ?? rawEvent['id']?.toString();
        if (eventId != null && eventId.isNotEmpty) {
          final remaining = controller.state.events
              .where((EventModel item) => item.id != eventId)
              .toList();
          controller.state = controller.state.copyWith(
            eventsStatus: FeatureStatus.ready,
            events: remaining,
            eventsMessage: remaining.isEmpty ? 'No upcoming events.' : null,
          );
          unawaited(controller.refreshPlanningWorkbench());
        }
      }
      break;
    case 'notification.created':
    case 'notification.updated':
      final rawNotification = event.payload['notification'];
      if (rawNotification is Map<String, dynamic>) {
        final nextNotification = NotificationModel.fromJson(rawNotification);
        final existing =
            controller.state.notifications.any(
              (NotificationModel item) => item.id == nextNotification.id,
            )
            ? controller._replaceNotification(
                controller.state.notifications,
                nextNotification,
              )
            : <NotificationModel>[
                nextNotification,
                ...controller.state.notifications,
              ];
        controller.state = controller.state.copyWith(
          notificationsStatus: FeatureStatus.ready,
          notifications: existing,
          notificationsMessage: null,
        );
        unawaited(controller.refreshPlanningWorkbench());
      }
      break;
    case 'notification.deleted':
      final rawNotification = event.payload['notification'];
      if (rawNotification is Map<String, dynamic>) {
        final notificationId = rawNotification['notification_id']?.toString();
        if (notificationId != null && notificationId.isNotEmpty) {
          final remaining = controller.state.notifications
              .where((NotificationModel item) => item.id != notificationId)
              .toList();
          controller.state = controller.state.copyWith(
            notificationsStatus: FeatureStatus.ready,
            notifications: remaining,
            notificationsMessage: remaining.isEmpty
                ? 'No notifications.'
                : null,
          );
          unawaited(controller.refreshPlanningWorkbench());
        }
      }
      break;
    case 'reminder.created':
    case 'reminder.updated':
    case 'reminder.triggered':
      final rawReminder = event.payload['reminder'];
      if (rawReminder is Map<String, dynamic>) {
        final nextReminder = ReminderModel.fromJson(rawReminder);
        final existing =
            controller.state.reminders.any(
              (ReminderModel item) => item.id == nextReminder.id,
            )
            ? controller._replaceReminder(
                controller.state.reminders,
                nextReminder,
              )
            : <ReminderModel>[nextReminder, ...controller.state.reminders];
        controller.state = controller.state.copyWith(
          remindersStatus: FeatureStatus.ready,
          reminders: controller._sortReminders(existing),
          remindersMessage: null,
        );
      }
      final rawNotification = event.payload['notification'];
      if (rawNotification is Map<String, dynamic>) {
        final nextNotification = NotificationModel.fromJson(rawNotification);
        final existing =
            controller.state.notifications.any(
              (NotificationModel item) => item.id == nextNotification.id,
            )
            ? controller._replaceNotification(
                controller.state.notifications,
                nextNotification,
              )
            : <NotificationModel>[
                nextNotification,
                ...controller.state.notifications,
              ];
        controller.state = controller.state.copyWith(
          notificationsStatus: FeatureStatus.ready,
          notifications: existing,
          notificationsMessage: null,
        );
      }
      unawaited(controller.refreshPlanningWorkbench());
      break;
    case 'reminder.deleted':
      final rawReminder = event.payload['reminder'];
      if (rawReminder is Map<String, dynamic>) {
        final reminderId = rawReminder['reminder_id']?.toString();
        if (reminderId != null && reminderId.isNotEmpty) {
          final remaining = controller.state.reminders
              .where((ReminderModel item) => item.id != reminderId)
              .toList();
          controller.state = controller.state.copyWith(
            remindersStatus: FeatureStatus.ready,
            reminders: remaining,
            remindersMessage: remaining.isEmpty ? 'No reminders.' : null,
          );
          unawaited(controller.refreshPlanningWorkbench());
        }
      }
      break;
    case 'settings.updated':
      final settings = AppSettingsModel.fromJson(event.payload);
      controller.state = controller.state.copyWith(
        settingsStatus: FeatureStatus.ready,
        settings: settings,
        settingsMessage:
            settings.applySummary ?? 'Settings refreshed from backend.',
      );
      break;
    case 'device.command.accepted':
      final command = event.payload['command']?.toString();
      controller.state = controller.state.copyWith(
        globalMessage: command == null || command.isEmpty
            ? 'Device command pending.'
            : 'Device command pending: $command.',
      );
      unawaited(controller.refreshRuntime());
      break;
    case 'device.command.updated':
      final command = event.payload['command']?.toString();
      final ok = event.payload['ok'] == true;
      final error = event.payload['error']?.toString().trim();
      final failureDetail = controller._deviceCommandFailureDetail(error);
      controller.state = controller.state.copyWith(
        globalMessage: ok
            ? command == null || command.isEmpty
                  ? 'Device command completed.'
                  : 'Device command completed: $command.'
            : command == null || command.isEmpty
            ? failureDetail == null
                  ? 'Device command failed.'
                  : 'Device command failed: $failureDetail.'
            : failureDetail == null
            ? 'Device command failed: $command.'
            : 'Device command failed: $command ($failureDetail).',
      );
      unawaited(controller.refreshRuntime());
      break;
  }
}
