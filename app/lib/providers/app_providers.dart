import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../config/app_config.dart';
import '../models/api/api_error.dart';
import '../models/api/app_event_model.dart';
import '../models/chat/message_model.dart';
import '../models/chat/session_model.dart';
import '../models/connect/bootstrap_model.dart';
import '../models/connect/connection_config_model.dart';
import '../models/events/event_model.dart';
import '../models/settings/settings_model.dart';
import '../models/tasks/task_model.dart';
import '../services/api/api_client.dart';
import '../services/bootstrap/bootstrap_service.dart';
import '../services/chat/chat_service.dart';
import '../services/chat/voice_capture_service.dart';
import '../services/connect/connect_service.dart';
import '../services/demo/demo_service_bundle.dart';
import '../services/events/events_service.dart';
import '../services/home/device_service.dart';
import '../services/home/runtime_service.dart';
import '../services/notifications/notifications_service.dart';
import '../services/realtime/ws_reconnect_service.dart';
import '../services/realtime/ws_service.dart';
import '../services/reminders/reminders_service.dart';
import '../services/settings/settings_service.dart';
import '../services/storage/auth_storage_service.dart';
import '../services/tasks/tasks_service.dart';
import 'app_state.dart';

final storageServiceProvider = Provider<AuthStorageService>(
  (Ref ref) => AuthStorageService(),
);
final apiClientProvider = Provider<ApiClient>((Ref ref) {
  final client = ApiClient();
  ref.onDispose(client.dispose);
  return client;
});
final connectServiceProvider = Provider<ConnectService>(
  (Ref ref) => ConnectService(
    ref.read(storageServiceProvider),
    ref.read(apiClientProvider),
  ),
);
final bootstrapServiceProvider = Provider<BootstrapService>(
  (Ref ref) => BootstrapService(ref.read(apiClientProvider)),
);
final wsServiceProvider = Provider<WebSocketService>((Ref ref) {
  final service = WebSocketService();
  ref.onDispose(service.dispose);
  return service;
});
final wsReconnectServiceProvider = Provider<WsReconnectService>(
  (Ref ref) => WsReconnectService(ref.read(wsServiceProvider)),
);
final chatServiceProvider = Provider<ChatService>(
  (Ref ref) => ChatService(ref.read(apiClientProvider)),
);
final voiceCaptureServiceProvider = Provider<VoiceCaptureService>(
  (Ref ref) => VoiceCaptureService(),
);
final runtimeServiceProvider = Provider<RuntimeService>(
  (Ref ref) => RuntimeService(ref.read(apiClientProvider)),
);
final deviceServiceProvider = Provider<DeviceService>(
  (Ref ref) => DeviceService(ref.read(apiClientProvider)),
);
final settingsServiceProvider = Provider<SettingsService>(
  (Ref ref) => SettingsService(ref.read(apiClientProvider)),
);
final tasksServiceProvider = Provider<TasksService>(
  (Ref ref) => TasksService(ref.read(apiClientProvider)),
);
final eventsServiceProvider = Provider<EventsService>(
  (Ref ref) => EventsService(ref.read(apiClientProvider)),
);
final notificationsServiceProvider = Provider<NotificationsService>(
  (Ref ref) => NotificationsService(ref.read(apiClientProvider)),
);
final remindersServiceProvider = Provider<RemindersService>(
  (Ref ref) => RemindersService(ref.read(apiClientProvider)),
);

class AppController extends StateNotifier<AppState> {
  AppController(this.ref) : super(AppState.initial()) {
    _eventSubscription = ref
        .read(wsServiceProvider)
        .events
        .listen(_handleEvent);
    _statusSubscription = ref
        .read(wsServiceProvider)
        .status
        .listen(_handleRealtimeStatus);
    Future<void>.microtask(_restoreSavedConnection);
  }

  final Ref ref;
  StreamSubscription<AppEventModel>? _eventSubscription;
  StreamSubscription<RealtimeConnectionStatus>? _statusSubscription;

  ApiClient get _apiClient => ref.read(apiClientProvider);

  Future<void> _restoreSavedConnection() async {
    final saved = await ref.read(connectServiceProvider).loadConnection();
    if (saved == null || !saved.hasServer) {
      return;
    }
    try {
      await connect(
        host: saved.host,
        port: saved.port,
        secure: saved.secure,
        token: saved.token,
        preferredSessionId: saved.currentSessionId,
        latestEventId: saved.latestEventId,
        silent: true,
      );
    } catch (_) {
      state = state.copyWith(connection: saved);
    }
  }

  Future<void> connect({
    required String host,
    required int port,
    required bool secure,
    required String token,
    String? preferredSessionId,
    String? latestEventId,
    bool silent = false,
  }) async {
    final connectService = ref.read(connectServiceProvider);
    final bootstrapService = ref.read(bootstrapServiceProvider);
    final wsReconnect = ref.read(wsReconnectServiceProvider);
    final connection = connectService.buildConnection(
      host: host,
      port: port,
      secure: secure,
      token: token,
      currentSessionId: preferredSessionId ?? '',
      latestEventId: latestEventId ?? '',
    );

    state = state.copyWith(
      isConnecting: true,
      isDemoMode: false,
      globalMessage: null,
      connection: connection,
    );

    _apiClient.setConnection(connection);
    try {
      await connectService.checkHealth(host, port, token, secure);
      final bootstrap = await bootstrapService.fetchBootstrap();
      final sessionId = _pickSessionId(
        bootstrap.sessions,
        preferredSessionId,
        connection.currentSessionId,
      );
      final nextConnection = connection.copyWith(
        currentSessionId: sessionId,
        latestEventId: connection.latestEventId.isNotEmpty
            ? connection.latestEventId
            : bootstrap.eventStream.resume.latestEventId,
      );
      _apiClient.setConnection(nextConnection);
      await connectService.saveConnection(nextConnection);
      await wsReconnect.connect(
        connection: nextConnection,
        path: bootstrap.eventStream.path,
        replayLimit: bootstrap.eventStream.resume.replayLimit,
      );
      state = state.copyWith(
        connection: nextConnection,
        isConnecting: false,
        isConnected: true,
        isDemoMode: false,
        bootstrap: bootstrap,
        capabilities: bootstrap.capabilities,
        runtimeState: bootstrap.runtime,
        sessions: bootstrap.sessions,
        globalMessage: silent ? null : 'Connected to AI-bot backend.',
      );
      await loadMessages();
    } catch (error) {
      ref.read(wsReconnectServiceProvider).disconnect();
      _apiClient.clearConnection();
      state = state.copyWith(
        isConnecting: false,
        isConnected: false,
        eventStreamConnected: false,
        bootstrap: null,
        capabilities: CapabilitiesModel.empty(),
        sessions: const <SessionModel>[],
        globalMessage: error is ApiError ? error.message : 'Connection failed.',
      );
      rethrow;
    }
  }

  String _pickSessionId(
    List<SessionModel> sessions,
    String? preferredSessionId,
    String? currentSessionId,
  ) {
    final wanted = preferredSessionId ?? currentSessionId ?? '';
    if (wanted.isNotEmpty &&
        sessions.any((SessionModel item) => item.sessionId == wanted)) {
      return wanted;
    }
    return sessions.isNotEmpty ? sessions.first.sessionId : '';
  }

  Future<void> connectDemo() async {
    ref.read(wsReconnectServiceProvider).disconnect();
    _apiClient.clearConnection();
    final demoConnection = ConnectionConfigModel(
      host: 'demo.local',
      port: 8000,
      secure: false,
      token: '',
      currentSessionId: DemoServiceBundle.sessions.first.sessionId,
      latestEventId:
          DemoServiceBundle.bootstrap.eventStream.resume.latestEventId,
    );
    await ref.read(connectServiceProvider).saveConnection(demoConnection);
    state = state.copyWith(
      connection: demoConnection,
      isConnected: true,
      isDemoMode: true,
      eventStreamConnected: true,
      bootstrap: DemoServiceBundle.bootstrap,
      capabilities: DemoServiceBundle.bootstrap.capabilities,
      runtimeState: DemoServiceBundle.runtime,
      sessions: DemoServiceBundle.sessions,
      messagesBySession: DemoServiceBundle.messagesBySession,
      settingsStatus: FeatureStatus.demo,
      settings: DemoServiceBundle.settings,
      tasksStatus: FeatureStatus.demo,
      tasks: DemoServiceBundle.tasks,
      eventsStatus: FeatureStatus.demo,
      events: DemoServiceBundle.events,
      notificationsStatus: FeatureStatus.demo,
      notifications: DemoServiceBundle.notifications,
      remindersStatus: FeatureStatus.demo,
      reminders: DemoServiceBundle.reminders,
      globalMessage: 'Demo mode activated.',
    );
  }

  Future<void> disconnect() async {
    ref.read(wsReconnectServiceProvider).disconnect();
    final keptConnection = state.connection.copyWith(
      currentSessionId: '',
      latestEventId: '',
    );
    await ref.read(connectServiceProvider).saveConnection(keptConnection);
    _apiClient.clearConnection();
    state = AppState.initial().copyWith(connection: keptConnection);
  }

  Future<void> selectSession(String sessionId) async {
    final next = state.connection.copyWith(currentSessionId: sessionId);
    await ref.read(connectServiceProvider).saveConnection(next);
    state = state.copyWith(connection: next);
    await loadMessages();
  }

  Future<void> loadMessages() async {
    final sessionId = state.currentSessionId;
    if (sessionId.isEmpty || state.isDemoMode) {
      return;
    }
    state = state.copyWith(messagesLoading: true);
    _apiClient.setConnection(state.connection);
    try {
      final page = await ref.read(chatServiceProvider).getMessages(sessionId);
      state = state.copyWith(
        messagesLoading: false,
        messagesBySession: <String, List<MessageModel>>{
          ...state.messagesBySession,
          sessionId: page.items,
        },
      );
    } catch (error) {
      state = state.copyWith(
        messagesLoading: false,
        globalMessage: error is ApiError
            ? error.message
            : 'Failed to load messages.',
      );
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.currentSessionId.isEmpty) {
      return;
    }
    if (state.isDemoMode) {
      final now = DateTime.now();
      state = state.copyWith(
        messagesBySession: <String, List<MessageModel>>{
          ...state.messagesBySession,
          state.currentSessionId: <MessageModel>[
            ...state.currentMessages,
            MessageModel(
              id: 'demo-${now.millisecondsSinceEpoch}',
              sessionId: state.currentSessionId,
              role: 'user',
              text: text,
              status: 'completed',
              createdAt: now.toIso8601String(),
            ),
            MessageModel(
              id: 'demo-reply-${now.millisecondsSinceEpoch}',
              sessionId: state.currentSessionId,
              role: 'assistant',
              text:
                  'Demo mode keeps the reply local. Real mode waits for backend events.',
              status: 'completed',
              createdAt: now.add(const Duration(seconds: 1)).toIso8601String(),
            ),
          ],
        },
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    final result = await ref
        .read(chatServiceProvider)
        .postMessage(
          state.currentSessionId,
          content: text,
          clientMessageId: 'flutter_${DateTime.now().millisecondsSinceEpoch}',
        );
    final updated = _upsertMessage(
      List<MessageModel>.from(state.currentMessages),
      result.acceptedMessage,
    );
    state = state.copyWith(
      messagesBySession: <String, List<MessageModel>>{
        ...state.messagesBySession,
        state.currentSessionId: updated,
      },
    );
  }

  List<MessageModel> _upsertMessage(
    List<MessageModel> messages,
    MessageModel message,
  ) {
    final index = messages.indexWhere(
      (MessageModel item) => item.id == message.id,
    );
    if (index == -1) {
      messages.add(message);
    } else {
      messages[index] = message;
    }
    messages.sort(
      (MessageModel left, MessageModel right) =>
          left.createdAt.compareTo(right.createdAt),
    );
    return messages;
  }

  Future<void> refreshRuntime() async {
    if (state.isDemoMode) {
      state = state.copyWith(runtimeState: DemoServiceBundle.runtime);
      return;
    }
    _apiClient.setConnection(state.connection);
    final runtime = await ref.read(runtimeServiceProvider).fetchRuntimeState();
    state = state.copyWith(runtimeState: runtime);
  }

  Future<void> stopCurrentTask() async {
    if (state.runtimeState.currentTask == null) {
      state = state.copyWith(globalMessage: 'No running task to stop.');
      return;
    }
    if (state.isDemoMode) {
      state = state.copyWith(
        runtimeState: state.runtimeState.copyWithCurrentTask(null),
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    await ref
        .read(runtimeServiceProvider)
        .stopCurrentTask(taskId: state.runtimeState.currentTask?.taskId);
    state = state.copyWith(globalMessage: 'Stop request sent to backend.');
  }

  Future<void> speakTestPhrase() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        globalMessage: 'Demo device accepted the test phrase.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    await ref
        .read(deviceServiceProvider)
        .speak('Testing speech output from the Flutter app.');
    state = state.copyWith(globalMessage: 'Device speech request accepted.');
  }

  Future<void> triggerVoiceInput() async {
    final captured = await ref.read(voiceCaptureServiceProvider).captureText();
    if (captured == null || captured.trim().isEmpty) {
      state = state.copyWith(
        globalMessage:
            'Voice entry is reserved for the backend-aligned pipeline.',
      );
      return;
    }
    await sendMessage(captured);
  }

  Future<void> loadSettings() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        settingsStatus: FeatureStatus.demo,
        settings: DemoServiceBundle.settings,
        settingsMessage: 'Demo mode keeps settings local.',
      );
      return;
    }
    state = state.copyWith(settingsStatus: FeatureStatus.loading);
    _apiClient.setConnection(state.connection);
    try {
      final settings = await ref.read(settingsServiceProvider).getSettings();
      state = state.copyWith(
        settingsStatus: FeatureStatus.ready,
        settings: settings,
        settingsMessage: null,
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        settingsStatus: error.isBackendNotReady
            ? FeatureStatus.notReady
            : FeatureStatus.error,
        settingsMessage: error.isBackendNotReady
            ? AppConfig.backendNotReadyMessage
            : error.message,
      );
    }
  }

  Future<void> saveSettings(AppSettingsModel draft, {String? apiKey}) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        settings: draft.copyWith(
          llmApiKeyConfigured:
              state.settings?.llmApiKeyConfigured == true ||
              (apiKey?.trim().isNotEmpty ?? false),
        ),
        settingsMessage: 'Demo settings updated locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    final next = await ref
        .read(settingsServiceProvider)
        .updateSettings(draft.toUpdate(llmApiKey: apiKey));
    state = state.copyWith(
      settingsStatus: FeatureStatus.ready,
      settings: next,
      settingsMessage: 'Settings saved through the backend.',
    );
  }

  Future<void> testAiConnection() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        settingsMessage: 'Demo mode does not call the backend test endpoint.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    final result = await ref.read(settingsServiceProvider).testAiConnection();
    state = state.copyWith(
      settingsMessage: '${result.provider}/${result.model}: ${result.message}',
    );
  }

  Future<void> loadTasks() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        tasksStatus: FeatureStatus.demo,
        tasks: DemoServiceBundle.tasks,
        tasksMessage: 'Demo tasks are local.',
      );
      return;
    }
    state = state.copyWith(tasksStatus: FeatureStatus.loading);
    _apiClient.setConnection(state.connection);
    try {
      final tasks = await ref.read(tasksServiceProvider).listTasks();
      state = state.copyWith(
        tasksStatus: FeatureStatus.ready,
        tasks: tasks,
        tasksMessage: tasks.isEmpty ? 'No tasks yet.' : null,
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        tasksStatus: error.isBackendNotReady
            ? FeatureStatus.notReady
            : FeatureStatus.error,
        tasksMessage: error.isBackendNotReady
            ? AppConfig.backendNotReadyMessage
            : error.message,
      );
    }
  }

  Future<void> loadEvents() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        eventsStatus: FeatureStatus.demo,
        events: DemoServiceBundle.events,
        eventsMessage: 'Demo events are local.',
      );
      return;
    }
    state = state.copyWith(eventsStatus: FeatureStatus.loading);
    _apiClient.setConnection(state.connection);
    try {
      final events = await ref.read(eventsServiceProvider).listEvents();
      state = state.copyWith(
        eventsStatus: FeatureStatus.ready,
        events: events,
        eventsMessage: events.isEmpty ? 'No upcoming events.' : null,
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        eventsStatus: error.isBackendNotReady
            ? FeatureStatus.notReady
            : FeatureStatus.error,
        eventsMessage: error.isBackendNotReady
            ? AppConfig.backendNotReadyMessage
            : error.message,
      );
    }
  }

  Future<void> loadNotifications() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        notificationsStatus: FeatureStatus.demo,
        notifications: DemoServiceBundle.notifications,
        notificationsMessage: 'Demo notifications are local.',
      );
      return;
    }
    state = state.copyWith(notificationsStatus: FeatureStatus.loading);
    _apiClient.setConnection(state.connection);
    try {
      final items = await ref
          .read(notificationsServiceProvider)
          .listNotifications();
      state = state.copyWith(
        notificationsStatus: FeatureStatus.ready,
        notifications: items,
        notificationsMessage: items.isEmpty ? 'No notifications.' : null,
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        notificationsStatus: error.isBackendNotReady
            ? FeatureStatus.notReady
            : FeatureStatus.error,
        notificationsMessage: error.isBackendNotReady
            ? AppConfig.backendNotReadyMessage
            : error.message,
      );
    }
  }

  Future<void> loadReminders() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        remindersStatus: FeatureStatus.demo,
        reminders: DemoServiceBundle.reminders,
        remindersMessage: 'Demo reminders are local.',
      );
      return;
    }
    state = state.copyWith(remindersStatus: FeatureStatus.loading);
    _apiClient.setConnection(state.connection);
    try {
      final items = await ref.read(remindersServiceProvider).listReminders();
      state = state.copyWith(
        remindersStatus: FeatureStatus.ready,
        reminders: items,
        remindersMessage: items.isEmpty ? 'No reminders.' : null,
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        remindersStatus: error.isBackendNotReady
            ? FeatureStatus.notReady
            : FeatureStatus.error,
        remindersMessage: error.isBackendNotReady
            ? AppConfig.backendNotReadyMessage
            : error.message,
      );
    }
  }

  void _handleRealtimeStatus(RealtimeConnectionStatus status) {
    state = state.copyWith(
      eventStreamConnected: status == RealtimeConnectionStatus.connected,
    );
  }

  void _handleEvent(AppEventModel event) {
    if (event.eventId.isNotEmpty) {
      final nextConnection = state.connection.copyWith(
        latestEventId: event.eventId,
      );
      ref.read(connectServiceProvider).saveConnection(nextConnection);
      ref.read(wsServiceProvider).setLatestEventId(event.eventId);
      state = state.copyWith(connection: nextConnection);
    }

    switch (event.eventType) {
      case 'system.hello':
        final resume = event.payload['resume'];
        if (resume is Map<String, dynamic> &&
            resume['should_refetch_bootstrap'] == true) {
          unawaited(refreshRuntime());
        }
        break;
      case 'runtime.task.current_changed':
      case 'runtime.task.queue_changed':
      case 'device.connection.changed':
      case 'device.state.changed':
      case 'device.status.updated':
      case 'todo.summary.changed':
      case 'calendar.summary.changed':
        unawaited(refreshRuntime());
        break;
      case 'session.message.created':
      case 'session.message.completed':
        final raw = event.payload['message'];
        if (raw is Map<String, dynamic>) {
          final sessionId = event.sessionId ?? state.currentSessionId;
          final updated = _upsertMessage(
            List<MessageModel>.from(
              state.messagesBySession[sessionId] ?? const <MessageModel>[],
            ),
            MessageModel.fromJson(raw),
          );
          state = state.copyWith(
            messagesBySession: <String, List<MessageModel>>{
              ...state.messagesBySession,
              sessionId: updated,
            },
          );
        }
        break;
      case 'session.message.progress':
        final sessionId = event.sessionId ?? state.currentSessionId;
        final streaming = MessageModel(
          id:
              event.payload['message_id']?.toString() ??
              'assistant-${DateTime.now().millisecondsSinceEpoch}',
          sessionId: sessionId,
          role: 'assistant',
          text: event.payload['content']?.toString() ?? '',
          status: 'streaming',
          createdAt: DateTime.now().toIso8601String(),
        );
        state = state.copyWith(
          messagesBySession: <String, List<MessageModel>>{
            ...state.messagesBySession,
            sessionId: _upsertMessage(
              List<MessageModel>.from(
                state.messagesBySession[sessionId] ?? const <MessageModel>[],
              ),
              streaming,
            ),
          },
        );
        break;
      case 'session.message.failed':
        state = state.copyWith(globalMessage: 'Assistant response failed.');
        break;
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }
}

final appControllerProvider = StateNotifierProvider<AppController, AppState>((
  Ref ref,
) {
  return AppController(ref);
});

final voiceAvailableProvider = Provider<bool>((Ref ref) {
  final state = ref.watch(appControllerProvider);
  return state.isDemoMode || state.capabilities.voicePipeline;
});

final currentMessagesProvider = Provider<List<MessageModel>>(
  (Ref ref) => ref.watch(appControllerProvider).currentMessages,
);

final sortedTasksProvider = Provider<List<TaskModel>>((Ref ref) {
  final tasks = List<TaskModel>.from(ref.watch(appControllerProvider).tasks);
  const order = <String, int>{'high': 0, 'medium': 1, 'low': 2};
  tasks.sort((TaskModel left, TaskModel right) {
    if (left.completed != right.completed) {
      return left.completed ? 1 : -1;
    }
    return (order[left.priority] ?? 9).compareTo(order[right.priority] ?? 9);
  });
  return tasks;
});

final upcomingEventsProvider = Provider<List<EventModel>>((Ref ref) {
  final now = DateTime.now();
  final events = List<EventModel>.from(ref.watch(appControllerProvider).events);
  events.sort(
    (EventModel left, EventModel right) =>
        left.startAt.compareTo(right.startAt),
  );
  return events.where((EventModel item) {
    final parsed = DateTime.tryParse(item.startAt);
    return parsed == null || parsed.isAfter(now);
  }).toList();
});
