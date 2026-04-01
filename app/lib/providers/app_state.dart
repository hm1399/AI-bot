import '../models/chat/message_model.dart';
import '../models/chat/session_model.dart';
import '../models/connect/bootstrap_model.dart';
import '../models/connect/connection_config_model.dart';
import '../models/events/event_model.dart';
import '../models/home/runtime_state_model.dart';
import '../models/notifications/notification_model.dart';
import '../models/reminders/reminder_model.dart';
import '../models/settings/settings_model.dart';
import '../models/tasks/task_model.dart';

enum FeatureStatus { idle, loading, ready, notReady, error, demo }

class AppState {
  const AppState({
    required this.connection,
    required this.isConnecting,
    required this.isConnected,
    required this.isDemoMode,
    required this.eventStreamConnected,
    required this.bootstrap,
    required this.capabilities,
    required this.runtimeState,
    required this.sessions,
    required this.messagesBySession,
    required this.messagesLoading,
    required this.settingsStatus,
    required this.settings,
    required this.settingsMessage,
    required this.tasksStatus,
    required this.tasks,
    required this.tasksMessage,
    required this.eventsStatus,
    required this.events,
    required this.eventsMessage,
    required this.notificationsStatus,
    required this.notifications,
    required this.notificationsMessage,
    required this.remindersStatus,
    required this.reminders,
    required this.remindersMessage,
    required this.globalMessage,
  });

  final ConnectionConfigModel connection;
  final bool isConnecting;
  final bool isConnected;
  final bool isDemoMode;
  final bool eventStreamConnected;
  final BootstrapModel? bootstrap;
  final CapabilitiesModel capabilities;
  final RuntimeStateModel runtimeState;
  final List<SessionModel> sessions;
  final Map<String, List<MessageModel>> messagesBySession;
  final bool messagesLoading;
  final FeatureStatus settingsStatus;
  final AppSettingsModel? settings;
  final String? settingsMessage;
  final FeatureStatus tasksStatus;
  final List<TaskModel> tasks;
  final String? tasksMessage;
  final FeatureStatus eventsStatus;
  final List<EventModel> events;
  final String? eventsMessage;
  final FeatureStatus notificationsStatus;
  final List<NotificationModel> notifications;
  final String? notificationsMessage;
  final FeatureStatus remindersStatus;
  final List<ReminderModel> reminders;
  final String? remindersMessage;
  final String? globalMessage;

  String get currentSessionId => connection.currentSessionId;

  List<MessageModel> get currentMessages =>
      messagesBySession[currentSessionId] ?? const <MessageModel>[];

  AppState copyWith({
    ConnectionConfigModel? connection,
    bool? isConnecting,
    bool? isConnected,
    bool? isDemoMode,
    bool? eventStreamConnected,
    BootstrapModel? bootstrap,
    CapabilitiesModel? capabilities,
    RuntimeStateModel? runtimeState,
    List<SessionModel>? sessions,
    Map<String, List<MessageModel>>? messagesBySession,
    bool? messagesLoading,
    FeatureStatus? settingsStatus,
    AppSettingsModel? settings,
    String? settingsMessage,
    FeatureStatus? tasksStatus,
    List<TaskModel>? tasks,
    String? tasksMessage,
    FeatureStatus? eventsStatus,
    List<EventModel>? events,
    String? eventsMessage,
    FeatureStatus? notificationsStatus,
    List<NotificationModel>? notifications,
    String? notificationsMessage,
    FeatureStatus? remindersStatus,
    List<ReminderModel>? reminders,
    String? remindersMessage,
    String? globalMessage,
  }) {
    return AppState(
      connection: connection ?? this.connection,
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      isDemoMode: isDemoMode ?? this.isDemoMode,
      eventStreamConnected: eventStreamConnected ?? this.eventStreamConnected,
      bootstrap: bootstrap ?? this.bootstrap,
      capabilities: capabilities ?? this.capabilities,
      runtimeState: runtimeState ?? this.runtimeState,
      sessions: sessions ?? this.sessions,
      messagesBySession: messagesBySession ?? this.messagesBySession,
      messagesLoading: messagesLoading ?? this.messagesLoading,
      settingsStatus: settingsStatus ?? this.settingsStatus,
      settings: settings ?? this.settings,
      settingsMessage: settingsMessage ?? this.settingsMessage,
      tasksStatus: tasksStatus ?? this.tasksStatus,
      tasks: tasks ?? this.tasks,
      tasksMessage: tasksMessage ?? this.tasksMessage,
      eventsStatus: eventsStatus ?? this.eventsStatus,
      events: events ?? this.events,
      eventsMessage: eventsMessage ?? this.eventsMessage,
      notificationsStatus: notificationsStatus ?? this.notificationsStatus,
      notifications: notifications ?? this.notifications,
      notificationsMessage: notificationsMessage ?? this.notificationsMessage,
      remindersStatus: remindersStatus ?? this.remindersStatus,
      reminders: reminders ?? this.reminders,
      remindersMessage: remindersMessage ?? this.remindersMessage,
      globalMessage: globalMessage ?? this.globalMessage,
    );
  }

  factory AppState.initial() {
    return AppState(
      connection: ConnectionConfigModel.empty(),
      isConnecting: false,
      isConnected: false,
      isDemoMode: false,
      eventStreamConnected: false,
      bootstrap: null,
      capabilities: CapabilitiesModel.empty(),
      runtimeState: RuntimeStateModel.empty(),
      sessions: const <SessionModel>[],
      messagesBySession: const <String, List<MessageModel>>{},
      messagesLoading: false,
      settingsStatus: FeatureStatus.idle,
      settings: null,
      settingsMessage: null,
      tasksStatus: FeatureStatus.idle,
      tasks: const <TaskModel>[],
      tasksMessage: null,
      eventsStatus: FeatureStatus.idle,
      events: const <EventModel>[],
      eventsMessage: null,
      notificationsStatus: FeatureStatus.idle,
      notifications: const <NotificationModel>[],
      notificationsMessage: null,
      remindersStatus: FeatureStatus.idle,
      reminders: const <ReminderModel>[],
      remindersMessage: null,
      globalMessage: null,
    );
  }
}
