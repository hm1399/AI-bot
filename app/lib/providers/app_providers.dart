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
import '../models/notifications/notification_model.dart';
import '../models/reminders/reminder_model.dart';
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

  Future<void> refreshAll() async {
    if (!state.isConnected) {
      state = state.copyWith(globalMessage: 'Connect to the backend first.');
      return;
    }

    if (state.isDemoMode) {
      final sessionId = _pickSessionId(
        DemoServiceBundle.sessions,
        state.currentSessionId,
        state.currentSessionId,
      );
      final nextConnection = state.connection.copyWith(
        currentSessionId: sessionId,
        latestEventId:
            DemoServiceBundle.bootstrap.eventStream.resume.latestEventId,
      );
      state = state.copyWith(
        connection: nextConnection,
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
        globalMessage: 'Demo workspace refreshed.',
      );
      return;
    }

    try {
      _apiClient.setConnection(state.connection);
      final bootstrap = await ref
          .read(bootstrapServiceProvider)
          .fetchBootstrap();
      final sessionId = _pickSessionId(
        bootstrap.sessions,
        state.currentSessionId,
        state.currentSessionId,
      );
      final nextConnection = state.connection.copyWith(
        currentSessionId: sessionId,
        latestEventId: bootstrap.eventStream.resume.latestEventId,
      );
      _apiClient.setConnection(nextConnection);
      await ref.read(connectServiceProvider).saveConnection(nextConnection);
      state = state.copyWith(
        connection: nextConnection,
        bootstrap: bootstrap,
        capabilities: bootstrap.capabilities,
        runtimeState: bootstrap.runtime,
        sessions: bootstrap.sessions,
        globalMessage: 'Workspace refreshed.',
      );
      await loadMessages();
      await loadSettings();
      await loadTasks();
      await loadEvents();
      await loadNotifications();
      await loadReminders();
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    }
  }

  Future<void> selectSession(String sessionId) async {
    final next = state.connection.copyWith(currentSessionId: sessionId);
    await ref.read(connectServiceProvider).saveConnection(next);
    state = state.copyWith(
      connection: next,
      globalMessage: 'Switched to ${_sessionTitleFor(sessionId)}.',
    );
    await loadMessages();
  }

  Future<void> loadSessions() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        sessions: _sortSessions(state.sessions),
        globalMessage: 'Demo conversations refreshed locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final sessions = await ref.read(chatServiceProvider).listSessions();
      final currentSessionId = _pickSessionId(
        sessions,
        state.currentSessionId,
        state.currentSessionId,
      );
      final nextConnection = state.connection.copyWith(
        currentSessionId: currentSessionId,
      );
      await ref.read(connectServiceProvider).saveConnection(nextConnection);
      state = state.copyWith(
        connection: nextConnection,
        sessions: sessions,
        globalMessage: sessions.isEmpty
            ? 'No conversations yet.'
            : 'Conversation list refreshed.',
      );
      if (currentSessionId.isNotEmpty) {
        await loadMessages();
      }
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    }
  }

  Future<void> createSession({String? title}) async {
    final sessionTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : 'New conversation';
    if (state.isDemoMode) {
      final now = DateTime.now().toIso8601String();
      final session = SessionModel(
        sessionId: 'app:demo-${DateTime.now().millisecondsSinceEpoch}',
        channel: 'app',
        title: sessionTitle,
        summary: 'Fresh local demo session.',
        lastMessageAt: now,
        messageCount: 0,
        pinned: false,
        archived: false,
      );
      final nextConnection = state.connection.copyWith(
        currentSessionId: session.sessionId,
      );
      await ref.read(connectServiceProvider).saveConnection(nextConnection);
      state = state.copyWith(
        connection: nextConnection,
        sessions: _sortSessions(<SessionModel>[session, ...state.sessions]),
        messagesBySession: <String, List<MessageModel>>{
          ...state.messagesBySession,
          session.sessionId: const <MessageModel>[],
        },
        globalMessage: 'Demo conversation created.',
      );
      return;
    }

    _apiClient.setConnection(state.connection);
    try {
      final session = await ref
          .read(chatServiceProvider)
          .createSession(title: sessionTitle);
      final nextConnection = state.connection.copyWith(
        currentSessionId: session.sessionId,
      );
      await ref.read(connectServiceProvider).saveConnection(nextConnection);
      state = state.copyWith(
        connection: nextConnection,
        sessions: _sortSessions(<SessionModel>[session, ...state.sessions]),
        messagesBySession: <String, List<MessageModel>>{
          ...state.messagesBySession,
          session.sessionId: const <MessageModel>[],
        },
        globalMessage: 'Conversation created.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    }
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
    final content = text.trim();
    if (content.isEmpty) {
      return;
    }
    if (state.currentSessionId.isEmpty) {
      await createSession(title: 'New conversation');
      if (state.currentSessionId.isEmpty) {
        return;
      }
    }
    if (state.currentSessionId.isEmpty) {
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
              text: content,
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
        sessions: _touchSession(
          state.sessions,
          state.currentSessionId,
          summary: content,
          lastMessageAt: now.toIso8601String(),
          incrementCount: true,
        ),
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final result = await ref
          .read(chatServiceProvider)
          .postMessage(
            state.currentSessionId,
            content: content,
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
        sessions: _touchSession(
          state.sessions,
          state.currentSessionId,
          summary: content,
          lastMessageAt: result.acceptedMessage.createdAt,
          incrementCount: true,
        ),
        globalMessage: null,
      );
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    }
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
    final deviceOnline = state.runtimeState.device.connected;
    final bridgeReady = state.runtimeState.voice.desktopBridgeReady;
    final backendReported = state.runtimeState.voice.reportedByBackend;

    final message = !deviceOnline
        ? 'Voice starts from the device. Bring the device online, then press and hold it to talk.'
        : !bridgeReady
        ? backendReported
              ? 'Device feedback is online, but the desktop microphone bridge is not ready yet. The app does not record directly.'
              : 'The app no longer records voice directly. Use press-to-talk on the device once the desktop microphone bridge reports ready.'
        : 'Press and hold the device to talk. Audio is captured by the desktop microphone bridge, and replies currently return as device text/status feedback.';

    state = state.copyWith(globalMessage: message);
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

  Future<void> testAiConnection({
    AppSettingsModel? draft,
    String? apiKey,
  }) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        settingsMessage: 'Demo mode does not call the backend test endpoint.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    final candidate = (draft ?? state.settings)?.toUpdate(llmApiKey: apiKey);
    final result = await ref
        .read(settingsServiceProvider)
        .testAiConnection(draft: candidate);
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

  Future<void> createTask(TaskModel task) async {
    if (state.isDemoMode) {
      final created = task.copyWith();
      state = state.copyWith(
        tasks: _sortTasks(<TaskModel>[created, ...state.tasks]),
        tasksMessage: 'Demo task created locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final created = await ref.read(tasksServiceProvider).createTask(task);
      state = state.copyWith(
        tasksStatus: FeatureStatus.ready,
        tasks: _sortTasks(<TaskModel>[created, ...state.tasks]),
        tasksMessage: 'Task created.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        tasksStatus: FeatureStatus.error,
        tasksMessage: error.message,
      );
    }
  }

  Future<void> updateTask(TaskModel task) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        tasks: _sortTasks(_replaceTask(state.tasks, task)),
        tasksMessage: 'Demo task updated locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final updated = await ref
          .read(tasksServiceProvider)
          .updateTask(task.id, task.toUpdateJson());
      state = state.copyWith(
        tasksStatus: FeatureStatus.ready,
        tasks: _sortTasks(_replaceTask(state.tasks, updated)),
        tasksMessage: 'Task updated.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        tasksStatus: FeatureStatus.error,
        tasksMessage: error.message,
      );
    }
  }

  Future<void> deleteTask(String taskId) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        tasks: state.tasks
            .where((TaskModel item) => item.id != taskId)
            .toList(),
        tasksMessage: 'Demo task deleted locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      await ref.read(tasksServiceProvider).deleteTask(taskId);
      final remaining = state.tasks
          .where((TaskModel item) => item.id != taskId)
          .toList();
      state = state.copyWith(
        tasksStatus: FeatureStatus.ready,
        tasks: remaining,
        tasksMessage: remaining.isEmpty ? 'No tasks yet.' : 'Task deleted.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        tasksStatus: FeatureStatus.error,
        tasksMessage: error.message,
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

  Future<void> createEvent(EventModel event) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        events: _sortEvents(<EventModel>[event, ...state.events]),
        eventsMessage: 'Demo event created locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final created = await ref.read(eventsServiceProvider).createEvent(event);
      state = state.copyWith(
        eventsStatus: FeatureStatus.ready,
        events: _sortEvents(<EventModel>[created, ...state.events]),
        eventsMessage: 'Event created.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        eventsStatus: FeatureStatus.error,
        eventsMessage: error.message,
      );
    }
  }

  Future<void> updateEvent(EventModel event) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        events: _sortEvents(_replaceEvent(state.events, event)),
        eventsMessage: 'Demo event updated locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final updated = await ref
          .read(eventsServiceProvider)
          .updateEvent(event.id, event.toUpdateJson());
      state = state.copyWith(
        eventsStatus: FeatureStatus.ready,
        events: _sortEvents(_replaceEvent(state.events, updated)),
        eventsMessage: 'Event updated.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        eventsStatus: FeatureStatus.error,
        eventsMessage: error.message,
      );
    }
  }

  Future<void> deleteEvent(String eventId) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        events: state.events
            .where((EventModel item) => item.id != eventId)
            .toList(),
        eventsMessage: 'Demo event deleted locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      await ref.read(eventsServiceProvider).deleteEvent(eventId);
      final remaining = state.events
          .where((EventModel item) => item.id != eventId)
          .toList();
      state = state.copyWith(
        eventsStatus: FeatureStatus.ready,
        events: remaining,
        eventsMessage: remaining.isEmpty
            ? 'No upcoming events.'
            : 'Event deleted.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        eventsStatus: FeatureStatus.error,
        eventsMessage: error.message,
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

  Future<void> markNotificationRead(
    String notificationId, {
    required bool read,
  }) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        notifications: _replaceNotification(
          state.notifications,
          state.notifications
              .firstWhere((NotificationModel item) => item.id == notificationId)
              .copyWith(read: read),
        ),
        notificationsMessage: read
            ? 'Demo notification marked read.'
            : 'Demo notification marked unread.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      await ref
          .read(notificationsServiceProvider)
          .markRead(notificationId, read: read);
      state = state.copyWith(
        notificationsStatus: FeatureStatus.ready,
        notifications: _replaceNotification(
          state.notifications,
          state.notifications
              .firstWhere((NotificationModel item) => item.id == notificationId)
              .copyWith(read: read),
        ),
        notificationsMessage: read
            ? 'Notification marked read.'
            : 'Notification marked unread.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        notificationsStatus: FeatureStatus.error,
        notificationsMessage: error.message,
      );
    }
  }

  Future<void> markAllNotificationsRead() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        notifications: state.notifications
            .map((NotificationModel item) => item.copyWith(read: true))
            .toList(),
        notificationsMessage: 'Demo notifications marked read.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      await ref.read(notificationsServiceProvider).markAllRead();
      state = state.copyWith(
        notificationsStatus: FeatureStatus.ready,
        notifications: state.notifications
            .map((NotificationModel item) => item.copyWith(read: true))
            .toList(),
        notificationsMessage: 'All notifications marked read.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        notificationsStatus: FeatureStatus.error,
        notificationsMessage: error.message,
      );
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    if (state.isDemoMode) {
      final remaining = state.notifications
          .where((NotificationModel item) => item.id != notificationId)
          .toList();
      state = state.copyWith(
        notifications: remaining,
        notificationsMessage: remaining.isEmpty
            ? 'No notifications.'
            : 'Demo notification deleted locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      await ref
          .read(notificationsServiceProvider)
          .deleteNotification(notificationId);
      final remaining = state.notifications
          .where((NotificationModel item) => item.id != notificationId)
          .toList();
      state = state.copyWith(
        notificationsStatus: FeatureStatus.ready,
        notifications: remaining,
        notificationsMessage: remaining.isEmpty
            ? 'No notifications.'
            : 'Notification deleted.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        notificationsStatus: FeatureStatus.error,
        notificationsMessage: error.message,
      );
    }
  }

  Future<void> clearNotifications() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        notifications: const <NotificationModel>[],
        notificationsMessage: 'Demo notifications cleared locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      await ref.read(notificationsServiceProvider).clearNotifications();
      state = state.copyWith(
        notificationsStatus: FeatureStatus.ready,
        notifications: const <NotificationModel>[],
        notificationsMessage: 'Notifications cleared.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        notificationsStatus: FeatureStatus.error,
        notificationsMessage: error.message,
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

  Future<void> createReminder(ReminderModel reminder) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        reminders: _sortReminders(<ReminderModel>[
          reminder,
          ...state.reminders,
        ]),
        remindersMessage: 'Demo reminder created locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final created = await ref
          .read(remindersServiceProvider)
          .createReminder(reminder);
      state = state.copyWith(
        remindersStatus: FeatureStatus.ready,
        reminders: _sortReminders(<ReminderModel>[created, ...state.reminders]),
        remindersMessage: 'Reminder created.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        remindersStatus: FeatureStatus.error,
        remindersMessage: error.message,
      );
    }
  }

  Future<void> updateReminder(ReminderModel reminder) async {
    if (state.isDemoMode) {
      state = state.copyWith(
        reminders: _sortReminders(_replaceReminder(state.reminders, reminder)),
        remindersMessage: 'Demo reminder updated locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final updated = await ref
          .read(remindersServiceProvider)
          .updateReminder(reminder.id, reminder.toUpdateJson());
      state = state.copyWith(
        remindersStatus: FeatureStatus.ready,
        reminders: _sortReminders(_replaceReminder(state.reminders, updated)),
        remindersMessage: 'Reminder updated.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        remindersStatus: FeatureStatus.error,
        remindersMessage: error.message,
      );
    }
  }

  Future<void> setReminderEnabled(String reminderId, bool enabled) async {
    final target = state.reminders.firstWhere(
      (ReminderModel item) => item.id == reminderId,
    );
    await updateReminder(target.copyWith(enabled: enabled));
  }

  Future<void> deleteReminder(String reminderId) async {
    if (state.isDemoMode) {
      final remaining = state.reminders
          .where((ReminderModel item) => item.id != reminderId)
          .toList();
      state = state.copyWith(
        reminders: remaining,
        remindersMessage: remaining.isEmpty
            ? 'No reminders.'
            : 'Demo reminder deleted locally.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      await ref.read(remindersServiceProvider).deleteReminder(reminderId);
      final remaining = state.reminders
          .where((ReminderModel item) => item.id != reminderId)
          .toList();
      state = state.copyWith(
        remindersStatus: FeatureStatus.ready,
        reminders: remaining,
        remindersMessage: remaining.isEmpty
            ? 'No reminders.'
            : 'Reminder deleted.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        remindersStatus: FeatureStatus.error,
        remindersMessage: error.message,
      );
    }
  }

  Future<void> sendDeviceCommand(
    String command, {
    Map<String, dynamic>? params,
  }) async {
    if (state.isDemoMode) {
      state = state.copyWith(globalMessage: 'Demo device accepted "$command".');
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final result = await ref
          .read(deviceServiceProvider)
          .sendCommand(
            command,
            params: params,
            clientCommandId: 'flutter_${DateTime.now().millisecondsSinceEpoch}',
          );
      state = state.copyWith(
        globalMessage:
            'Device command accepted: ${result['command'] ?? command}.',
      );
      await refreshRuntime();
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    }
  }

  String _sessionTitleFor(String sessionId) {
    final match = state.sessions.where(
      (SessionModel item) => item.sessionId == sessionId,
    );
    if (match.isEmpty) {
      return 'Conversation';
    }
    final title = match.first.title.trim();
    return title.isEmpty ? 'Conversation' : title;
  }

  List<SessionModel> _sortSessions(List<SessionModel> sessions) {
    final sorted = List<SessionModel>.from(sessions);
    sorted.sort((SessionModel left, SessionModel right) {
      if (left.pinned != right.pinned) {
        return left.pinned ? -1 : 1;
      }
      return (right.lastMessageAt ?? '').compareTo(left.lastMessageAt ?? '');
    });
    return sorted;
  }

  List<SessionModel> _touchSession(
    List<SessionModel> sessions,
    String sessionId, {
    required String summary,
    required String lastMessageAt,
    bool incrementCount = false,
  }) {
    return _sortSessions(
      sessions.map((SessionModel item) {
        if (item.sessionId != sessionId) {
          return item;
        }
        return item.copyWith(
          summary: summary,
          lastMessageAt: lastMessageAt,
          messageCount: incrementCount
              ? item.messageCount + 1
              : item.messageCount,
        );
      }).toList(),
    );
  }

  List<TaskModel> _sortTasks(List<TaskModel> tasks) {
    final sorted = List<TaskModel>.from(tasks);
    const order = <String, int>{'high': 0, 'medium': 1, 'low': 2};
    sorted.sort((TaskModel left, TaskModel right) {
      if (left.completed != right.completed) {
        return left.completed ? 1 : -1;
      }
      return (order[left.priority] ?? 9).compareTo(order[right.priority] ?? 9);
    });
    return sorted;
  }

  List<TaskModel> _replaceTask(List<TaskModel> tasks, TaskModel next) {
    return tasks
        .map((TaskModel item) => item.id == next.id ? next : item)
        .toList();
  }

  List<EventModel> _sortEvents(List<EventModel> events) {
    final sorted = List<EventModel>.from(events);
    sorted.sort(
      (EventModel left, EventModel right) =>
          left.startAt.compareTo(right.startAt),
    );
    return sorted;
  }

  List<EventModel> _replaceEvent(List<EventModel> events, EventModel next) {
    return events
        .map((EventModel item) => item.id == next.id ? next : item)
        .toList();
  }

  List<NotificationModel> _replaceNotification(
    List<NotificationModel> notifications,
    NotificationModel next,
  ) {
    return notifications
        .map((NotificationModel item) => item.id == next.id ? next : item)
        .toList();
  }

  List<ReminderModel> _sortReminders(List<ReminderModel> reminders) {
    final sorted = List<ReminderModel>.from(reminders);
    sorted.sort(
      (ReminderModel left, ReminderModel right) =>
          left.updatedAt.compareTo(right.updatedAt),
    );
    return sorted.reversed.toList();
  }

  List<ReminderModel> _replaceReminder(
    List<ReminderModel> reminders,
    ReminderModel next,
  ) {
    return reminders
        .map((ReminderModel item) => item.id == next.id ? next : item)
        .toList();
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
          final nextMessage = MessageModel.fromJson(raw);
          final existingMessages = List<MessageModel>.from(
            state.messagesBySession[sessionId] ?? const <MessageModel>[],
          );
          final alreadyPresent = existingMessages.any(
            (MessageModel item) => item.id == nextMessage.id,
          );
          final updated = _upsertMessage(existingMessages, nextMessage);
          state = state.copyWith(
            messagesBySession: <String, List<MessageModel>>{
              ...state.messagesBySession,
              sessionId: updated,
            },
            sessions: _touchSession(
              state.sessions,
              sessionId,
              summary: nextMessage.text,
              lastMessageAt: nextMessage.createdAt,
              incrementCount: !alreadyPresent,
            ),
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
      case 'task.created':
      case 'task.updated':
        final rawTask = event.payload['task'];
        if (rawTask is Map<String, dynamic>) {
          final task = TaskModel.fromJson(rawTask);
          final existing =
              state.tasks.any((TaskModel item) => item.id == task.id)
              ? _replaceTask(state.tasks, task)
              : <TaskModel>[task, ...state.tasks];
          state = state.copyWith(
            tasksStatus: FeatureStatus.ready,
            tasks: _sortTasks(existing),
            tasksMessage: null,
          );
        }
        break;
      case 'task.deleted':
        final rawTask = event.payload['task'];
        if (rawTask is Map<String, dynamic>) {
          final taskId =
              rawTask['task_id']?.toString() ?? rawTask['id']?.toString();
          if (taskId != null && taskId.isNotEmpty) {
            final remaining = state.tasks
                .where((TaskModel item) => item.id != taskId)
                .toList();
            state = state.copyWith(
              tasksStatus: FeatureStatus.ready,
              tasks: remaining,
              tasksMessage: remaining.isEmpty ? 'No tasks yet.' : null,
            );
          }
        }
        break;
      case 'event.created':
      case 'event.updated':
        final rawEvent = event.payload['event'];
        if (rawEvent is Map<String, dynamic>) {
          final nextEvent = EventModel.fromJson(rawEvent);
          final existing =
              state.events.any((EventModel item) => item.id == nextEvent.id)
              ? _replaceEvent(state.events, nextEvent)
              : <EventModel>[nextEvent, ...state.events];
          state = state.copyWith(
            eventsStatus: FeatureStatus.ready,
            events: _sortEvents(existing),
            eventsMessage: null,
          );
        }
        break;
      case 'event.deleted':
        final rawEvent = event.payload['event'];
        if (rawEvent is Map<String, dynamic>) {
          final eventId =
              rawEvent['event_id']?.toString() ?? rawEvent['id']?.toString();
          if (eventId != null && eventId.isNotEmpty) {
            final remaining = state.events
                .where((EventModel item) => item.id != eventId)
                .toList();
            state = state.copyWith(
              eventsStatus: FeatureStatus.ready,
              events: remaining,
              eventsMessage: remaining.isEmpty ? 'No upcoming events.' : null,
            );
          }
        }
        break;
      case 'notification.updated':
        final rawNotification = event.payload['notification'];
        if (rawNotification is Map<String, dynamic>) {
          final nextNotification = NotificationModel.fromJson(rawNotification);
          final existing =
              state.notifications.any(
                (NotificationModel item) => item.id == nextNotification.id,
              )
              ? _replaceNotification(state.notifications, nextNotification)
              : <NotificationModel>[nextNotification, ...state.notifications];
          state = state.copyWith(
            notificationsStatus: FeatureStatus.ready,
            notifications: existing,
            notificationsMessage: null,
          );
        }
        break;
      case 'notification.deleted':
        final rawNotification = event.payload['notification'];
        if (rawNotification is Map<String, dynamic>) {
          final notificationId = rawNotification['notification_id']?.toString();
          if (notificationId != null && notificationId.isNotEmpty) {
            final remaining = state.notifications
                .where((NotificationModel item) => item.id != notificationId)
                .toList();
            state = state.copyWith(
              notificationsStatus: FeatureStatus.ready,
              notifications: remaining,
              notificationsMessage: remaining.isEmpty
                  ? 'No notifications.'
                  : null,
            );
          }
        }
        break;
      case 'reminder.created':
      case 'reminder.updated':
        final rawReminder = event.payload['reminder'];
        if (rawReminder is Map<String, dynamic>) {
          final nextReminder = ReminderModel.fromJson(rawReminder);
          final existing =
              state.reminders.any(
                (ReminderModel item) => item.id == nextReminder.id,
              )
              ? _replaceReminder(state.reminders, nextReminder)
              : <ReminderModel>[nextReminder, ...state.reminders];
          state = state.copyWith(
            remindersStatus: FeatureStatus.ready,
            reminders: _sortReminders(existing),
            remindersMessage: null,
          );
        }
        break;
      case 'reminder.deleted':
        final rawReminder = event.payload['reminder'];
        if (rawReminder is Map<String, dynamic>) {
          final reminderId = rawReminder['reminder_id']?.toString();
          if (reminderId != null && reminderId.isNotEmpty) {
            final remaining = state.reminders
                .where((ReminderModel item) => item.id != reminderId)
                .toList();
            state = state.copyWith(
              remindersStatus: FeatureStatus.ready,
              reminders: remaining,
              remindersMessage: remaining.isEmpty ? 'No reminders.' : null,
            );
          }
        }
        break;
      case 'settings.updated':
        state = state.copyWith(
          settingsStatus: FeatureStatus.ready,
          settings: AppSettingsModel.fromJson(event.payload),
          settingsMessage: 'Settings refreshed from backend.',
        );
        break;
      case 'device.command.accepted':
        final command = event.payload['command']?.toString();
        state = state.copyWith(
          globalMessage: command == null || command.isEmpty
              ? 'Device command accepted.'
              : 'Device command accepted: $command.',
        );
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

class VoiceUiState {
  const VoiceUiState({
    required this.deviceOnline,
    required this.desktopBridgeReady,
    required this.deviceFeedbackReady,
    required this.backendReported,
    required this.ready,
    required this.inputModeLabel,
    required this.outputModeLabel,
    required this.primaryDescription,
    required this.bridgeDescription,
    this.statusMessage,
    this.errorMessage,
  });

  final bool deviceOnline;
  final bool desktopBridgeReady;
  final bool deviceFeedbackReady;
  final bool backendReported;
  final bool ready;
  final String inputModeLabel;
  final String outputModeLabel;
  final String primaryDescription;
  final String bridgeDescription;
  final String? statusMessage;
  final String? errorMessage;
}

final voiceUiStateProvider = Provider<VoiceUiState>((Ref ref) {
  final state = ref.watch(appControllerProvider);
  final voice = state.runtimeState.voice;
  final deviceOnline = state.runtimeState.device.connected;
  final bridgeReady = state.isDemoMode || voice.desktopBridgeReady;
  final deviceFeedbackReady = state.isDemoMode || deviceOnline;
  final ready = state.isDemoMode || (deviceOnline && bridgeReady);

  return VoiceUiState(
    deviceOnline: deviceOnline,
    desktopBridgeReady: bridgeReady,
    deviceFeedbackReady: deviceFeedbackReady,
    backendReported: voice.reportedByBackend,
    ready: ready,
    inputModeLabel:
        'Press and hold the device. Audio is captured by the desktop microphone bridge.',
    outputModeLabel:
        'Replies currently return as device text and state feedback. App direct recording is not used.',
    primaryDescription: ready
        ? 'Press-to-talk is available through the device.'
        : 'Press-to-talk is waiting for the full handoff path.',
    bridgeDescription: bridgeReady
        ? 'Desktop microphone bridge is ready.'
        : voice.reportedByBackend
        ? 'Desktop microphone bridge is reported as not ready.'
        : 'Desktop microphone bridge status has not been reported yet.',
    statusMessage: voice.statusMessage,
    errorMessage: voice.lastError,
  );
});

final voiceAvailableProvider = Provider<bool>((Ref ref) {
  return ref.watch(voiceUiStateProvider).ready;
});

final unreadNotificationsCountProvider = Provider<int>((Ref ref) {
  return ref
      .watch(appControllerProvider)
      .notifications
      .where((NotificationModel item) => !item.read)
      .length;
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
