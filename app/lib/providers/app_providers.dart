import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../constants/api_constants.dart';
import '../config/app_config.dart';
import '../models/api/api_error.dart';
import '../models/api/app_event_model.dart';
import '../models/chat/message_model.dart';
import '../models/chat/session_model.dart';
import '../models/connect/bootstrap_model.dart';
import '../models/connect/connection_config_model.dart';
import '../models/control/computer_action_model.dart';
import '../models/device_pairing/device_pairing_bundle_model.dart';
import '../models/device_pairing/device_pairing_draft_model.dart';
import '../models/device_pairing/device_pairing_state_model.dart';
import '../models/events/event_model.dart';
import '../models/notifications/notification_model.dart';
import '../models/planning/planning_conflict_model.dart';
import '../models/planning/planning_agenda_entry_model.dart';
import '../models/planning/planning_overview_model.dart';
import '../models/planning/planning_timeline_item_model.dart';
import '../models/reminders/reminder_model.dart';
import '../models/settings/settings_model.dart';
import '../models/tasks/task_model.dart';
import '../services/api/api_client.dart';
import '../services/bootstrap/bootstrap_service.dart';
import '../services/chat/chat_service.dart';
import '../services/chat/voice_capture_service.dart';
import '../services/connect/connect_service.dart';
import '../services/control/computer_control_service.dart';
import '../services/device_pairing/device_pairing_storage_service.dart';
import '../services/device_pairing/serial_pairing_service.dart';
import '../services/device_pairing/serial_pairing_service_base.dart';
import '../services/demo/demo_service_bundle.dart';
import '../services/events/events_service.dart';
import '../services/home/device_service.dart';
import '../services/home/runtime_service.dart';
import '../services/notifications/notifications_service.dart';
import '../services/planning/planning_service.dart';
import '../services/realtime/ws_reconnect_service.dart';
import '../services/realtime/ws_service.dart';
import '../services/reminders/reminders_service.dart';
import '../services/settings/settings_service.dart';
import '../services/storage/auth_storage_service.dart';
import '../services/storage/theme_preference_service.dart';
import '../services/tasks/tasks_service.dart';
import 'app_state.dart';

final storageServiceProvider = Provider<AuthStorageService>(
  (Ref ref) => AuthStorageService(),
);
final themePreferenceServiceProvider = Provider<ThemePreferenceService>(
  (Ref ref) => ThemePreferenceService(),
);
final devicePairingStorageServiceProvider =
    Provider<DevicePairingStorageService>(
      (Ref ref) => DevicePairingStorageService(),
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

enum ChatSessionListMode { active, archived }

final chatSessionListModeProvider = StateProvider<ChatSessionListMode>(
  (Ref ref) => ChatSessionListMode.active,
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
final serialPairingServiceProvider = Provider<SerialPairingService>((Ref ref) {
  final service = createSerialPairingService();
  ref.onDispose(service.dispose);
  return service;
});
final settingsServiceProvider = Provider<SettingsService>(
  (Ref ref) => SettingsService(ref.read(apiClientProvider)),
);
final computerControlServiceProvider = Provider<ComputerControlService>(
  (Ref ref) => ComputerControlService(ref.read(apiClientProvider)),
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
final planningServiceProvider = Provider<PlanningService>(
  (Ref ref) => PlanningService(ref.read(apiClientProvider)),
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
    Future<void>.microtask(() async {
      await _restoreThemeMode();
      await _restoreSavedConnection();
    });
  }

  final Ref ref;
  StreamSubscription<AppEventModel>? _eventSubscription;
  StreamSubscription<RealtimeConnectionStatus>? _statusSubscription;

  ApiClient get _apiClient => ref.read(apiClientProvider);

  Future<void> _restoreThemeMode() async {
    final saved = await ref
        .read(themePreferenceServiceProvider)
        .loadThemeMode();
    if (saved == null || saved == state.themeMode) {
      return;
    }
    state = state.copyWith(themeMode: saved);
  }

  Future<void> setThemeMode(ThemeMode themeMode) async {
    if (themeMode == state.themeMode) {
      return;
    }
    state = state.copyWith(themeMode: themeMode);
    await ref.read(themePreferenceServiceProvider).saveThemeMode(themeMode);
  }

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
      if (sessionId.isNotEmpty) {
        await _syncActiveSession(sessionId);
      }
      await loadMessages();
      await refreshPlanningWorkbench();
      await loadComputerControl(silent: true);
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
    final activeSessions = sessions.where((SessionModel item) => item.active);
    if (activeSessions.isNotEmpty) {
      return activeSessions.first.sessionId;
    }
    final unarchivedSessions = sessions.where(
      (SessionModel item) => !item.archived,
    );
    if (unarchivedSessions.isNotEmpty) {
      return unarchivedSessions.first.sessionId;
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
    final demoBootstrap = _demoBootstrap();
    state = state.copyWith(
      connection: demoConnection,
      isConnected: true,
      isDemoMode: true,
      eventStreamConnected: true,
      bootstrap: demoBootstrap,
      capabilities: demoBootstrap.capabilities,
      runtimeState: DemoServiceBundle.runtime,
      sessions: DemoServiceBundle.sessions,
      messagesBySession: DemoServiceBundle.messagesBySession,
      settingsStatus: FeatureStatus.demo,
      settings: _demoSettings(),
      tasksStatus: FeatureStatus.demo,
      tasks: DemoServiceBundle.tasks,
      eventsStatus: FeatureStatus.demo,
      events: DemoServiceBundle.events,
      notificationsStatus: FeatureStatus.demo,
      notifications: DemoServiceBundle.notifications,
      remindersStatus: FeatureStatus.demo,
      reminders: DemoServiceBundle.reminders,
      planningOverviewStatus: FeatureStatus.demo,
      planningOverview: null,
      planningOverviewMessage:
          'Demo planning is derived from local sample data.',
      planningTimelineStatus: FeatureStatus.demo,
      planningTimeline: const <PlanningTimelineItemModel>[],
      planningTimelineMessage:
          'Demo planning is derived from local sample data.',
      planningConflictsStatus: FeatureStatus.demo,
      planningConflicts: const <PlanningConflictModel>[],
      planningConflictsMessage:
          'Demo planning is derived from local sample data.',
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
    state = AppState.initial().copyWith(
      connection: keptConnection,
      themeMode: state.themeMode,
    );
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
      final demoBootstrap = _demoBootstrap();
      state = state.copyWith(
        connection: nextConnection,
        bootstrap: demoBootstrap,
        capabilities: demoBootstrap.capabilities,
        runtimeState: DemoServiceBundle.runtime,
        sessions: DemoServiceBundle.sessions,
        messagesBySession: DemoServiceBundle.messagesBySession,
        settingsStatus: FeatureStatus.demo,
        settings: _demoSettings(),
        tasksStatus: FeatureStatus.demo,
        tasks: DemoServiceBundle.tasks,
        eventsStatus: FeatureStatus.demo,
        events: DemoServiceBundle.events,
        notificationsStatus: FeatureStatus.demo,
        notifications: DemoServiceBundle.notifications,
        remindersStatus: FeatureStatus.demo,
        reminders: DemoServiceBundle.reminders,
        planningOverviewStatus: FeatureStatus.demo,
        planningOverview: null,
        planningOverviewMessage:
            'Demo planning is derived from local sample data.',
        planningTimelineStatus: FeatureStatus.demo,
        planningTimeline: const <PlanningTimelineItemModel>[],
        planningTimelineMessage:
            'Demo planning is derived from local sample data.',
        planningConflictsStatus: FeatureStatus.demo,
        planningConflicts: const <PlanningConflictModel>[],
        planningConflictsMessage:
            'Demo planning is derived from local sample data.',
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
      if (sessionId.isNotEmpty) {
        await _syncActiveSession(sessionId);
      }
      await loadMessages();
      await loadSettings();
      await loadTasks();
      await loadEvents();
      await loadNotifications();
      await loadReminders();
      await refreshPlanningWorkbench();
      await loadComputerControl(silent: true);
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    }
  }

  Future<void> selectSession(String sessionId) async {
    final selectedSession = state.sessions.where(
      (SessionModel item) => item.sessionId == sessionId,
    );
    final session = selectedSession.isEmpty ? null : selectedSession.first;
    final next = state.connection.copyWith(currentSessionId: sessionId);
    await ref.read(connectServiceProvider).saveConnection(next);
    state = state.copyWith(
      connection: next,
      globalMessage: session?.archived == true
          ? 'Viewing archived conversation.'
          : 'Switched to ${_sessionTitleFor(sessionId)}.',
    );
    if (session?.archived != true) {
      await _syncActiveSession(sessionId);
    }
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
        await _syncActiveSession(currentSessionId);
      }
      if (currentSessionId.isNotEmpty) {
        await loadMessages();
      }
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    }
  }

  Future<void> createSession({String? title}) async {
    final sessionTitle = title?.trim() ?? '';
    if (state.isDemoMode) {
      final now = DateTime.now().toIso8601String();
      final session = SessionModel(
        sessionId: 'app:demo-${DateTime.now().millisecondsSinceEpoch}',
        channel: 'app',
        title: sessionTitle.isEmpty ? 'New conversation' : sessionTitle,
        summary: 'Fresh local demo session.',
        lastMessageAt: now,
        messageCount: 0,
        pinned: false,
        archived: false,
        active: true,
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
      await _syncActiveSession(session.sessionId);
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    }
  }

  Future<void> _syncActiveSession(String sessionId) async {
    if (state.isDemoMode || sessionId.isEmpty) {
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      await ref.read(chatServiceProvider).setActiveSession(sessionId);
    } on ApiError catch (_) {
      // Keep local navigation responsive even if backend active-session sync lags.
    }
  }

  Future<void> renameSession(String sessionId, String title) async {
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) {
      return;
    }
    final session = state.sessions.firstWhere(
      (SessionModel item) => item.sessionId == sessionId,
    );
    final optimistic = session.copyWith(title: nextTitle);
    state = state.copyWith(
      sessions: _replaceSession(state.sessions, optimistic),
      globalMessage: 'Conversation renamed.',
    );
    if (state.isDemoMode) {
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final updated = await ref
          .read(chatServiceProvider)
          .patchSession(sessionId, title: nextTitle);
      state = state.copyWith(
        sessions: _replaceSession(state.sessions, updated),
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        sessions: _replaceSession(state.sessions, session),
        globalMessage: error.message,
      );
    }
  }

  Future<void> setSessionPinned(String sessionId, bool pinned) async {
    final session = state.sessions.firstWhere(
      (SessionModel item) => item.sessionId == sessionId,
    );
    final optimistic = session.copyWith(pinned: pinned);
    state = state.copyWith(
      sessions: _replaceSession(state.sessions, optimistic),
      globalMessage: pinned ? 'Conversation pinned.' : 'Conversation unpinned.',
    );
    if (state.isDemoMode) {
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final updated = await ref
          .read(chatServiceProvider)
          .patchSession(sessionId, pinned: pinned);
      state = state.copyWith(
        sessions: _replaceSession(state.sessions, updated),
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        sessions: _replaceSession(state.sessions, session),
        globalMessage: error.message,
      );
    }
  }

  Future<void> setSessionArchived(String sessionId, bool archived) async {
    final session = state.sessions.firstWhere(
      (SessionModel item) => item.sessionId == sessionId,
    );
    final originalConnection = state.connection;
    final optimistic = session.copyWith(archived: archived);
    var nextSessions = _replaceSession(state.sessions, optimistic);
    var nextConnection = state.connection;
    final currentFilter = ref.read(chatSessionListModeProvider);
    var switchedToFallback = false;
    if (archived &&
        sessionId == state.currentSessionId &&
        currentFilter == ChatSessionListMode.active) {
      SessionModel? fallback;
      for (final item in nextSessions) {
        if (!item.archived) {
          fallback = item;
          break;
        }
      }
      nextConnection = nextConnection.copyWith(
        currentSessionId: fallback?.sessionId ?? state.currentSessionId,
      );
      await ref.read(connectServiceProvider).saveConnection(nextConnection);
      if (fallback != null) {
        switchedToFallback = true;
        unawaited(_syncActiveSession(fallback.sessionId));
      }
    }
    state = state.copyWith(
      connection: nextConnection,
      sessions: nextSessions,
      globalMessage: archived
          ? 'Conversation archived.'
          : 'Conversation restored.',
    );
    if (switchedToFallback) {
      unawaited(loadMessages());
    }
    if (state.isDemoMode) {
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final updated = await ref
          .read(chatServiceProvider)
          .patchSession(sessionId, archived: archived);
      state = state.copyWith(
        sessions: _replaceSession(state.sessions, updated),
      );
    } on ApiError catch (error) {
      await ref.read(connectServiceProvider).saveConnection(originalConnection);
      state = state.copyWith(
        connection: originalConnection,
        sessions: _replaceSession(state.sessions, session),
        globalMessage: error.message,
      );
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
      await createSession();
      if (state.currentSessionId.isEmpty) {
        return;
      }
    }
    if (state.currentSessionId.isEmpty) {
      return;
    }
    final activeSession = state.sessions.where(
      (SessionModel item) => item.sessionId == state.currentSessionId,
    );
    if (activeSession.isNotEmpty && activeSession.first.archived) {
      state = state.copyWith(
        globalMessage: 'Restore this conversation before sending new messages.',
      );
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

  Future<void> loadPlanningOverview() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        planningOverviewStatus: FeatureStatus.demo,
        planningOverview: null,
        planningOverviewMessage:
            'Demo planning is derived from local sample data.',
      );
      return;
    }
    if (!_planningAvailable()) {
      state = state.copyWith(
        planningOverviewStatus: FeatureStatus.notReady,
        planningOverview: null,
        planningOverviewMessage: _planningUnavailableMessage,
      );
      return;
    }

    state = state.copyWith(planningOverviewStatus: FeatureStatus.loading);
    _apiClient.setConnection(state.connection);
    try {
      final overview = await ref.read(planningServiceProvider).fetchOverview();
      state = state.copyWith(
        planningOverviewStatus: FeatureStatus.ready,
        planningOverview: overview,
        planningOverviewMessage: null,
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        planningOverviewStatus: error.isBackendNotReady
            ? FeatureStatus.notReady
            : FeatureStatus.error,
        planningOverviewMessage: error.isBackendNotReady
            ? AppConfig.backendNotReadyMessage
            : error.message,
      );
    }
  }

  Future<void> loadPlanningTimeline() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        planningTimelineStatus: FeatureStatus.demo,
        planningTimeline: const <PlanningTimelineItemModel>[],
        planningTimelineMessage:
            'Demo planning is derived from local sample data.',
      );
      return;
    }
    if (!_planningAvailable()) {
      state = state.copyWith(
        planningTimelineStatus: FeatureStatus.notReady,
        planningTimeline: const <PlanningTimelineItemModel>[],
        planningTimelineMessage: _planningUnavailableMessage,
      );
      return;
    }

    state = state.copyWith(planningTimelineStatus: FeatureStatus.loading);
    _apiClient.setConnection(state.connection);
    try {
      final timeline = await ref.read(planningServiceProvider).fetchTimeline();
      state = state.copyWith(
        planningTimelineStatus: FeatureStatus.ready,
        planningTimeline: timeline,
        planningTimelineMessage: timeline.isEmpty
            ? 'No planning items are scheduled yet.'
            : null,
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        planningTimelineStatus: error.isBackendNotReady
            ? FeatureStatus.notReady
            : FeatureStatus.error,
        planningTimelineMessage: error.isBackendNotReady
            ? AppConfig.backendNotReadyMessage
            : error.message,
      );
    }
  }

  Future<void> loadPlanningConflicts() async {
    if (state.isDemoMode) {
      state = state.copyWith(
        planningConflictsStatus: FeatureStatus.demo,
        planningConflicts: const <PlanningConflictModel>[],
        planningConflictsMessage:
            'Demo planning is derived from local sample data.',
      );
      return;
    }
    if (!_planningAvailable()) {
      state = state.copyWith(
        planningConflictsStatus: FeatureStatus.notReady,
        planningConflicts: const <PlanningConflictModel>[],
        planningConflictsMessage: _planningUnavailableMessage,
      );
      return;
    }

    state = state.copyWith(planningConflictsStatus: FeatureStatus.loading);
    _apiClient.setConnection(state.connection);
    try {
      final conflicts = await ref
          .read(planningServiceProvider)
          .fetchConflicts();
      state = state.copyWith(
        planningConflictsStatus: FeatureStatus.ready,
        planningConflicts: conflicts,
        planningConflictsMessage: conflicts.isEmpty
            ? 'No conflicts detected right now.'
            : null,
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        planningConflictsStatus: error.isBackendNotReady
            ? FeatureStatus.notReady
            : FeatureStatus.error,
        planningConflictsMessage: error.isBackendNotReady
            ? AppConfig.backendNotReadyMessage
            : error.message,
      );
    }
  }

  Future<void> refreshPlanningWorkbench() async {
    if (!state.isConnected) {
      return;
    }
    await loadPlanningOverview();
    await loadPlanningTimeline();
    await loadPlanningConflicts();
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
    final selectedSession = state.sessions.where(
      (SessionModel item) => item.sessionId == state.currentSessionId,
    );
    if (selectedSession.isNotEmpty && selectedSession.first.archived) {
      state = state.copyWith(
        globalMessage:
            'Restore this conversation before continuing it with voice.',
      );
      return;
    }
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
        settings: _demoSettings(),
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
      final nextSettings = draft.copyWith(
        llmApiKeyConfigured:
            state.settings?.llmApiKeyConfigured == true ||
            (apiKey?.trim().isNotEmpty ?? false),
        applyResults: _demoApplyResults(),
      );
      state = state.copyWith(
        settings: nextSettings,
        settingsMessage:
            nextSettings.applySummary ?? 'Demo settings updated locally.',
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
      settingsMessage:
          next.applySummary ?? 'Settings saved through the backend.',
    );
  }

  Future<void> loadComputerControl({bool silent = false}) async {
    final bootstrap = state.bootstrap;
    if (bootstrap == null) {
      return;
    }

    final supportedActions = _computerControlSupportedActions();
    if (state.isDemoMode) {
      state = state.copyWith(
        bootstrap: _demoBootstrap(),
        globalMessage: silent
            ? state.globalMessage
            : 'Demo mode has no live computer control.',
      );
      return;
    }

    if (!_computerControlAvailable()) {
      state = state.copyWith(
        bootstrap: bootstrap.copyWith(
          computerControl: _computerControlSeed(
            statusMessage:
                'Structured computer actions are unavailable on this backend.',
          ),
        ),
      );
      return;
    }

    _apiClient.setConnection(state.connection);
    try {
      final snapshot = await ref
          .read(computerControlServiceProvider)
          .getState(fallbackSupportedActions: supportedActions);
      state = state.copyWith(
        bootstrap: bootstrap.copyWith(computerControl: snapshot),
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        bootstrap: bootstrap.copyWith(
          computerControl: _computerControlSeed(
            statusMessage: error.isBackendNotReady
                ? AppConfig.backendNotReadyMessage
                : error.message,
          ),
        ),
        globalMessage: silent ? state.globalMessage : error.message,
      );
    }
  }

  Future<void> runComputerAction(ComputerActionRequest request) async {
    if (!_computerControlAvailable()) {
      state = state.copyWith(
        globalMessage: 'Computer actions are not available on this backend.',
      );
      return;
    }
    if (state.isDemoMode) {
      state = state.copyWith(
        globalMessage: 'Demo mode does not execute live computer actions.',
      );
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final action = await ref
          .read(computerControlServiceProvider)
          .createAction(request);
      _storeComputerControl(
        _computerControlSeed(clearStatusMessage: true).upsertAction(action),
        globalMessage: _computerActionMessage(action),
      );
    } on ApiError catch (error) {
      _storeComputerControl(
        _computerControlSeed(statusMessage: error.message),
        globalMessage: error.message,
      );
    }
  }

  Future<void> confirmComputerAction(String actionId) async {
    if (actionId.trim().isEmpty || state.isDemoMode) {
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final action = await ref
          .read(computerControlServiceProvider)
          .confirmAction(actionId);
      _storeComputerControl(
        _computerControlSeed(clearStatusMessage: true).upsertAction(action),
        globalMessage: _computerActionMessage(action),
      );
    } on ApiError catch (error) {
      _storeComputerControl(
        _computerControlSeed(statusMessage: error.message),
        globalMessage: error.message,
      );
    }
  }

  Future<void> cancelComputerAction(String actionId) async {
    if (actionId.trim().isEmpty || state.isDemoMode) {
      return;
    }
    _apiClient.setConnection(state.connection);
    try {
      final action = await ref
          .read(computerControlServiceProvider)
          .cancelAction(actionId);
      _storeComputerControl(
        _computerControlSeed(clearStatusMessage: true).upsertAction(action),
        globalMessage: _computerActionMessage(action),
      );
    } on ApiError catch (error) {
      _storeComputerControl(
        _computerControlSeed(statusMessage: error.message),
        globalMessage: error.message,
      );
    }
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
      unawaited(refreshPlanningWorkbench());
    } on ApiError catch (error) {
      state = state.copyWith(
        tasksStatus: FeatureStatus.error,
        tasksMessage: error.message,
      );
    }
  }

  Future<void> createPlanningBundle({
    List<TaskModel> tasks = const <TaskModel>[],
    List<EventModel> events = const <EventModel>[],
    List<ReminderModel> reminders = const <ReminderModel>[],
    String successMessage = 'Planning items created.',
  }) async {
    if (tasks.isEmpty && events.isEmpty && reminders.isEmpty) {
      return;
    }

    if (state.isDemoMode) {
      state = state.copyWith(
        tasks: _sortTasks(_mergeTasks(state.tasks, tasks)),
        events: _sortEvents(_mergeEvents(state.events, events)),
        reminders: _sortReminders(_mergeReminders(state.reminders, reminders)),
        tasksStatus: FeatureStatus.demo,
        eventsStatus: FeatureStatus.demo,
        remindersStatus: FeatureStatus.demo,
        globalMessage: 'Demo planning bundle created locally.',
      );
      return;
    }

    _apiClient.setConnection(state.connection);
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
      final bundle = await ref.read(planningServiceProvider).createBundle(<
        String,
        dynamic
      >{
        if (firstBundleId?.isNotEmpty == true) 'bundle_id': firstBundleId,
        if (createdVia?.isNotEmpty == true) 'created_via': createdVia,
        if (sourceChannel?.isNotEmpty == true) 'source_channel': sourceChannel,
        if (sourceSessionId?.isNotEmpty == true)
          'source_session_id': sourceSessionId,
        if (sourceMessageId?.isNotEmpty == true)
          'source_message_id': sourceMessageId,
        if (tasks.isNotEmpty)
          'tasks': tasks.map((TaskModel item) => item.toCreateJson()).toList(),
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

      state = state.copyWith(
        tasksStatus: FeatureStatus.ready,
        tasks: _sortTasks(_mergeTasks(state.tasks, createdTasks)),
        tasksMessage: createdTasks.isEmpty ? state.tasksMessage : null,
        eventsStatus: FeatureStatus.ready,
        events: _sortEvents(_mergeEvents(state.events, createdEvents)),
        eventsMessage: createdEvents.isEmpty ? state.eventsMessage : null,
        remindersStatus: FeatureStatus.ready,
        reminders: _sortReminders(
          _mergeReminders(state.reminders, createdReminders),
        ),
        remindersMessage: createdReminders.isEmpty
            ? state.remindersMessage
            : null,
        notificationsStatus: createdNotifications.isEmpty
            ? state.notificationsStatus
            : FeatureStatus.ready,
        notifications: createdNotifications.isEmpty
            ? state.notifications
            : _mergeNotifications(state.notifications, createdNotifications),
        notificationsMessage: createdNotifications.isEmpty
            ? state.notificationsMessage
            : null,
        globalMessage: successMessage,
      );
      unawaited(refreshPlanningWorkbench());
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      unawaited(refreshPlanningWorkbench());
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
      final clientCommandId =
          'flutter_${DateTime.now().millisecondsSinceEpoch}';
      final result = await ref
          .read(deviceServiceProvider)
          .sendCommand(
            command,
            params: params,
            clientCommandId: clientCommandId,
          );
      final acceptedCommand = result['command']?.toString() ?? command;
      final acceptedStatus = result['status']?.toString() ?? 'pending';
      state = state.copyWith(
        globalMessage: acceptedStatus == 'pending'
            ? 'Device command pending: $acceptedCommand.'
            : 'Device command accepted: $acceptedCommand.',
      );
      await refreshRuntime();
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    }
  }

  bool _computerControlAvailable() {
    final bootstrap = state.bootstrap;
    if (bootstrap == null) {
      return false;
    }
    return state.capabilities.computerControl ||
        state.capabilities.computerActions.isNotEmpty ||
        bootstrap.computerControl.hasStructuredActions;
  }

  List<String> _computerControlSupportedActions() {
    final capabilityActions = state.capabilities.computerActions;
    if (capabilityActions.isNotEmpty) {
      return capabilityActions;
    }
    return state.bootstrap?.computerControl.supportedActions ??
        const <String>[];
  }

  ComputerControlStateModel _computerControlSeed({
    String? statusMessage,
    bool clearStatusMessage = false,
  }) {
    final current =
        state.bootstrap?.computerControl ?? const ComputerControlStateModel();
    return current.copyWith(
      available: current.available || state.capabilities.computerControl,
      supportedActions: _computerControlSupportedActions(),
      statusMessage: clearStatusMessage
          ? null
          : statusMessage ?? current.statusMessage,
    );
  }

  void _storeComputerControl(
    ComputerControlStateModel computerControl, {
    String? globalMessage,
  }) {
    final bootstrap = state.bootstrap;
    if (bootstrap == null) {
      if (globalMessage != null) {
        state = state.copyWith(globalMessage: globalMessage);
      }
      return;
    }
    state = state.copyWith(
      bootstrap: bootstrap.copyWith(computerControl: computerControl),
      globalMessage: globalMessage ?? state.globalMessage,
    );
  }

  ComputerActionModel? _actionFromEvent(AppEventModel event) {
    final raw = event.payload['action'];
    if (raw is Map<String, dynamic>) {
      return ComputerActionModel.fromJson(raw);
    }
    if (event.payload.containsKey('action_id') ||
        event.payload.containsKey('kind') ||
        event.payload.containsKey('action')) {
      return ComputerActionModel.fromJson(event.payload);
    }
    return null;
  }

  String _computerActionMessage(ComputerActionModel action) {
    final summary = action.displaySummary;
    if (action.isAwaitingConfirmation) {
      return 'Computer action needs approval: $summary.';
    }
    if (action.isSuccessful) {
      return 'Computer action completed: $summary.';
    }
    if (action.isFailed) {
      final detail = action.outputSummary;
      return detail == null || detail.isEmpty
          ? 'Computer action failed: $summary.'
          : 'Computer action failed: $summary ($detail).';
    }
    return 'Computer action requested: $summary.';
  }

  String? _deviceCommandFailureDetail(String? error) {
    return switch (error) {
      'command_timeout' => 'timed out before the device confirmed it',
      'device_offline' => 'device is offline',
      'unsupported_command' => 'firmware does not support this command yet',
      'invalid_argument' => 'firmware rejected the command parameters',
      'apply_failed' => 'device did not confirm the apply result',
      _ => error?.trim().isNotEmpty == true ? error!.trim() : null,
    };
  }

  BootstrapModel _demoBootstrap() {
    return DemoServiceBundle.bootstrap.copyWith(
      computerControl: const ComputerControlStateModel(
        statusMessage: 'Structured computer actions require a live backend.',
      ),
    );
  }

  AppSettingsModel _demoSettings() {
    return DemoServiceBundle.settings.copyWith(
      applyResults: _demoApplyResults(),
    );
  }

  Map<String, SettingApplyResultModel> _demoApplyResults() {
    return const <String, SettingApplyResultModel>{
      'device_volume': SettingApplyResultModel(
        field: 'device_volume',
        mode: 'save_and_apply',
        status: 'pending',
      ),
      'led_enabled': SettingApplyResultModel(
        field: 'led_enabled',
        mode: 'save_and_apply',
        status: 'pending',
      ),
      'led_brightness': SettingApplyResultModel(
        field: 'led_brightness',
        mode: 'save_and_apply',
        status: 'pending',
      ),
      'led_color': SettingApplyResultModel(
        field: 'led_color',
        mode: 'save_and_apply',
        status: 'pending',
      ),
      'led_mode': SettingApplyResultModel(
        field: 'led_mode',
        mode: 'config_only',
        status: 'saved_only',
      ),
      'wake_word': SettingApplyResultModel(
        field: 'wake_word',
        mode: 'config_only',
        status: 'saved_only',
      ),
      'auto_listen': SettingApplyResultModel(
        field: 'auto_listen',
        mode: 'config_only',
        status: 'saved_only',
      ),
    };
  }

  bool _planningAvailable() {
    final bootstrapPlanning =
        state.bootstrap?.planning ?? const <String, dynamic>{};
    return state.capabilities.planning ||
        state.capabilities.planningOverview ||
        state.capabilities.planningTimeline ||
        state.capabilities.planningConflicts ||
        bootstrapPlanning.isNotEmpty;
  }

  static const String _planningUnavailableMessage =
      'Planning workbench is not available on this backend.';

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

  List<SessionModel> _replaceSession(
    List<SessionModel> sessions,
    SessionModel session,
  ) {
    final replaced = sessions.map((SessionModel item) {
      if (item.sessionId != session.sessionId) {
        return item;
      }
      return session;
    }).toList();
    final exists = sessions.any(
      (SessionModel item) => item.sessionId == session.sessionId,
    );
    return _sortSessions(
      exists ? replaced : <SessionModel>[session, ...sessions],
    );
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

  List<TaskModel> _mergeTasks(
    List<TaskModel> current,
    List<TaskModel> nextItems,
  ) {
    final merged = List<TaskModel>.from(current);
    for (final item in nextItems) {
      final index = merged.indexWhere(
        (TaskModel current) => current.id == item.id,
      );
      if (index == -1) {
        merged.add(item);
      } else {
        merged[index] = item;
      }
    }
    return merged;
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

  List<EventModel> _mergeEvents(
    List<EventModel> current,
    List<EventModel> nextItems,
  ) {
    final merged = List<EventModel>.from(current);
    for (final item in nextItems) {
      final index = merged.indexWhere(
        (EventModel current) => current.id == item.id,
      );
      if (index == -1) {
        merged.add(item);
      } else {
        merged[index] = item;
      }
    }
    return merged;
  }

  List<NotificationModel> _replaceNotification(
    List<NotificationModel> notifications,
    NotificationModel next,
  ) {
    return notifications
        .map((NotificationModel item) => item.id == next.id ? next : item)
        .toList();
  }

  List<NotificationModel> _mergeNotifications(
    List<NotificationModel> current,
    List<NotificationModel> nextItems,
  ) {
    final merged = List<NotificationModel>.from(current);
    for (final item in nextItems) {
      final index = merged.indexWhere(
        (NotificationModel current) => current.id == item.id,
      );
      if (index == -1) {
        merged.add(item);
      } else {
        merged[index] = item;
      }
    }
    return merged;
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

  List<ReminderModel> _mergeReminders(
    List<ReminderModel> current,
    List<ReminderModel> nextItems,
  ) {
    final merged = List<ReminderModel>.from(current);
    for (final item in nextItems) {
      final index = merged.indexWhere(
        (ReminderModel current) => current.id == item.id,
      );
      if (index == -1) {
        merged.add(item);
      } else {
        merged[index] = item;
      }
    }
    return merged;
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
          unawaited(refreshAll());
        }
        break;
      case 'runtime.task.current_changed':
      case 'runtime.task.queue_changed':
      case 'device.state.changed':
      case 'device.status.updated':
      case 'todo.summary.changed':
      case 'calendar.summary.changed':
        unawaited(refreshRuntime());
        break;
      case 'device.connection.changed':
        final connected = event.payload['connected'] == true;
        state = state.copyWith(
          globalMessage: connected
              ? 'Device online.'
              : 'Device offline. Waiting for reconnect.',
        );
        unawaited(refreshRuntime());
        break;
      case 'planning.changed':
        unawaited(refreshPlanningWorkbench());
        break;
      case 'computer.action.created':
      case 'computer.action.updated':
      case 'computer.action.completed':
      case 'computer.action.cancelled':
      case 'computer.action.requires_confirmation':
        final action = _actionFromEvent(event);
        if (action == null) {
          unawaited(loadComputerControl(silent: true));
          break;
        }
        _storeComputerControl(
          _computerControlSeed(clearStatusMessage: true).upsertAction(action),
          globalMessage: _computerActionMessage(action),
        );
        break;
      case 'session.updated':
        final rawSession = event.payload['session'];
        if (rawSession is Map<String, dynamic>) {
          final nextSession = SessionModel.fromJson(rawSession);
          state = state.copyWith(
            sessions: _replaceSession(state.sessions, nextSession),
          );
        }
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
          metadata: event.payload['metadata'] is Map<String, dynamic>
              ? event.payload['metadata'] as Map<String, dynamic>
              : const <String, dynamic>{},
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
          unawaited(refreshPlanningWorkbench());
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
            unawaited(refreshPlanningWorkbench());
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
          unawaited(refreshPlanningWorkbench());
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
            unawaited(refreshPlanningWorkbench());
          }
        }
        break;
      case 'notification.created':
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
          unawaited(refreshPlanningWorkbench());
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
            unawaited(refreshPlanningWorkbench());
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
        unawaited(refreshPlanningWorkbench());
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
            unawaited(refreshPlanningWorkbench());
          }
        }
        break;
      case 'settings.updated':
        final settings = AppSettingsModel.fromJson(event.payload);
        state = state.copyWith(
          settingsStatus: FeatureStatus.ready,
          settings: settings,
          settingsMessage:
              settings.applySummary ?? 'Settings refreshed from backend.',
        );
        break;
      case 'device.command.accepted':
        final command = event.payload['command']?.toString();
        state = state.copyWith(
          globalMessage: command == null || command.isEmpty
              ? 'Device command pending.'
              : 'Device command pending: $command.',
        );
        unawaited(refreshRuntime());
        break;
      case 'device.command.updated':
        final command = event.payload['command']?.toString();
        final ok = event.payload['ok'] == true;
        final error = event.payload['error']?.toString().trim();
        final failureDetail = _deviceCommandFailureDetail(error);
        state = state.copyWith(
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
        unawaited(refreshRuntime());
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

class DevicePairingController extends StateNotifier<DevicePairingStateModel> {
  DevicePairingController(this.ref, this._storage, this._serial)
    : super(
        DevicePairingStateModel.initial(platformSupported: _serial.isSupported),
      ) {
    _serialSubscription = _serial.events.listen(_handleSerialEvent);
    final appState = ref.read(appControllerProvider);
    state = state.copyWith(
      deviceOnline: appState.runtimeState.device.connected,
    );
    Future<void>.microtask(() async {
      await _restoreDraft();
      syncConnectionDefaults(appState.connection);
      if (_serial.isSupported) {
        await refreshPorts(silent: true);
      }
    });
  }

  final Ref ref;
  final DevicePairingStorageService _storage;
  final SerialPairingService _serial;

  StreamSubscription<SerialPairingTransportEvent>? _serialSubscription;
  Timer? _devicePollTimer;
  Completer<Map<String, dynamic>>? _pendingApplyResult;
  int _devicePollAttempts = 0;

  Future<void> _restoreDraft() async {
    final saved = await _storage.loadDraft();
    if (saved == null) {
      return;
    }
    state = state.copyWith(draft: saved);
  }

  Future<void> _persistDraft(DevicePairingDraftModel draft) {
    return _storage.saveDraft(draft.copyWith(wifiPassword: ''));
  }

  void syncConnectionDefaults(ConnectionConfigModel connection) {
    if (!connection.hasServer) {
      return;
    }
    final existingHost = state.draft.trimmedHost;
    final canOverwriteHost =
        existingHost.isEmpty ||
        DevicePairingDraftModel.isLoopbackHost(existingHost);
    if (!canOverwriteHost) {
      return;
    }
    final candidate = connection.host.trim();
    if (candidate.isEmpty ||
        DevicePairingDraftModel.isLoopbackHost(candidate)) {
      return;
    }
    final nextDraft = state.draft.copyWith(host: candidate);
    state = state.copyWith(draft: nextDraft);
    unawaited(_persistDraft(nextDraft));
  }

  void onDeviceOnlineChanged(bool online) {
    state = state.copyWith(deviceOnline: online);
    if (online &&
        (state.stage == DevicePairingStage.awaitingOnline ||
            state.stage == DevicePairingStage.sending)) {
      _completePairing('Device online. Pairing complete.');
    }
  }

  Future<void> refreshPorts({bool silent = false}) async {
    if (!_serial.isSupported) {
      state = state.copyWith(
        stage: DevicePairingStage.unavailable,
        statusMessage: 'Pairing unavailable on this platform.',
        errorMessage: null,
      );
      return;
    }

    if (!silent) {
      state = state.copyWith(
        stage: DevicePairingStage.refreshingPorts,
        statusMessage: 'Refreshing serial devices...',
        errorMessage: null,
      );
    }

    try {
      final ports = await _serial.listPorts();
      final selectedPort = ports.contains(state.draft.trimmedPortName)
          ? state.draft.trimmedPortName
          : '';
      final nextDraft = selectedPort == state.draft.trimmedPortName
          ? state.draft
          : state.draft.copyWith(portName: selectedPort);
      final nextStage = _stageAfterTransportRefresh(nextDraft);
      state = state.copyWith(
        availablePorts: ports,
        draft: nextDraft,
        stage: nextStage,
        statusMessage: ports.isEmpty
            ? 'No USB serial devices detected yet.'
            : 'USB serial devices refreshed.',
        errorMessage: null,
      );
      await _persistDraft(nextDraft);
    } catch (error) {
      _setFailure('Unable to list USB serial devices.', error.toString());
    }
  }

  DevicePairingStage _stageAfterTransportRefresh(
    DevicePairingDraftModel draft,
  ) {
    if (state.stage == DevicePairingStage.awaitingOnline) {
      return DevicePairingStage.awaitingOnline;
    }
    if (state.stage == DevicePairingStage.paired) {
      return DevicePairingStage.paired;
    }
    if (state.transportState == 'armed') {
      return DevicePairingStage.armed;
    }
    if (state.connectedPortName.isNotEmpty) {
      return DevicePairingStage.usbLinked;
    }
    return draft.hasSelectedPort
        ? DevicePairingStage.portReady
        : DevicePairingStage.idle;
  }

  Future<void> selectPort(String portName) async {
    final trimmed = portName.trim();
    if (trimmed == state.draft.trimmedPortName) {
      return;
    }
    if (state.connectedPortName.isNotEmpty &&
        state.connectedPortName != trimmed) {
      await closePort();
    }
    final nextDraft = state.draft.copyWith(portName: trimmed);
    state = state.copyWith(
      draft: nextDraft,
      stage: trimmed.isEmpty
          ? DevicePairingStage.idle
          : DevicePairingStage.portReady,
      statusMessage: trimmed.isEmpty
          ? 'Select a USB serial device to start pairing.'
          : 'USB serial selected. Open the port, then long-press the robot touch pad.',
      errorMessage: null,
    );
    await _persistDraft(nextDraft);
  }

  Future<void> openSelectedPort() async {
    if (!_serial.isSupported) {
      state = state.copyWith(
        stage: DevicePairingStage.unavailable,
        statusMessage: 'Pairing unavailable on this platform.',
        errorMessage: null,
      );
      return;
    }
    if (!state.draft.hasSelectedPort) {
      _setFailure('Select a USB serial device first.', null);
      return;
    }

    try {
      await _serial.connect(state.draft.trimmedPortName);
      state = state.copyWith(
        connectedPortName: state.draft.trimmedPortName,
        stage: DevicePairingStage.usbLinked,
        transportState: 'idle',
        transportReason: 'Hold the robot touch pad to arm pairing.',
        statusMessage:
            'USB linked. Hold the touch pad until the device reports pairing armed.',
        errorMessage: null,
      );
    } catch (error) {
      _setFailure(
        'Unable to open the selected USB serial device.',
        error.toString(),
      );
    }
  }

  Future<void> closePort() async {
    _cancelDevicePolling();
    _pendingApplyResult = null;
    await _serial.disconnect();
    final nextStage = state.draft.hasSelectedPort
        ? DevicePairingStage.portReady
        : DevicePairingStage.idle;
    state = state.copyWith(
      connectedPortName: '',
      transportState: 'idle',
      transportReason: state.draft.hasSelectedPort
          ? 'Open USB again to listen for pairing status.'
          : 'Select a USB serial device to start pairing.',
      stage: nextStage,
      statusMessage: state.draft.hasSelectedPort
          ? 'USB released.'
          : 'Select a USB serial device to start pairing.',
      errorMessage: null,
    );
  }

  Future<void> updateWifiSsid(String value) async {
    final nextDraft = state.draft.copyWith(wifiSsid: value);
    state = state.copyWith(draft: nextDraft, errorMessage: null);
    await _persistDraft(nextDraft);
  }

  void updateWifiPassword(String value) {
    final nextDraft = state.draft.copyWith(wifiPassword: value);
    state = state.copyWith(draft: nextDraft, errorMessage: null);
  }

  Future<void> updateHost(String value) async {
    final nextDraft = state.draft.copyWith(host: value);
    state = state.copyWith(draft: nextDraft, errorMessage: null);
    await _persistDraft(nextDraft);
  }

  Future<void> submitPairing() async {
    final appState = ref.read(appControllerProvider);
    if (!appState.isConnected || appState.isDemoMode) {
      _setFailure(
        'Connect the live backend before starting robot pairing.',
        null,
      );
      return;
    }
    if (!state.draft.hasSelectedPort) {
      _setFailure('Select and open a USB serial device first.', null);
      return;
    }
    if (state.connectedPortName.isEmpty) {
      _setFailure('Open the USB serial device first.', null);
      return;
    }
    if (!state.isArmed) {
      _setFailure(
        'Long-press the robot touch pad until pairing is armed before sending.',
        null,
      );
      return;
    }
    if (!state.draft.hasWifiSsid) {
      _setFailure('Enter the robot WiFi SSID first.', null);
      return;
    }
    if (state.draft.requiresExplicitLanHost) {
      _setFailure(
        'Use a LAN IPv4 host for the device endpoint. localhost and loopback addresses will not work on the robot.',
        null,
      );
      return;
    }

    _cancelDevicePolling();
    state = state.copyWith(
      stage: DevicePairingStage.sending,
      statusMessage: 'Requesting pairing bundle from the backend...',
      errorMessage: null,
      deviceOnline: false,
    );

    try {
      final bundle = await _requestBundle(host: state.draft.trimmedHost);
      final nextDraft = state.draft.copyWith(
        host: bundle.server.host,
        port: bundle.server.port,
        path: bundle.server.path,
        secure: bundle.server.secure,
      );
      state = state.copyWith(
        draft: nextDraft,
        bundle: bundle,
        statusMessage: 'Sending pairing bundle over USB...',
        errorMessage: null,
      );
      await _persistDraft(nextDraft);

      final completer = Completer<Map<String, dynamic>>();
      _pendingApplyResult = completer;
      await _serial.sendJson(
        bundle.toPairingApplyEnvelope(
          wifiSsid: nextDraft.trimmedWifiSsid,
          wifiPassword: nextDraft.wifiPassword,
        ),
      );

      final result = await completer.future.timeout(
        const Duration(seconds: 18),
        onTimeout: () => throw StateError(
          'Timed out waiting for pairing.result from the device.',
        ),
      );

      if (result['ok'] != true) {
        final detail =
            result['reason']?.toString() ??
            result['message']?.toString() ??
            'Device rejected the pairing payload.';
        _setFailure('Device did not accept the pairing payload.', detail);
        return;
      }

      _pendingApplyResult = null;
      _beginAwaitDeviceOnline();
    } on ApiError catch (error) {
      final message = error.isBackendNotReady
          ? 'Pairing bundle endpoint is not ready on the backend yet. The frontend contract is wired and waiting for server support.'
          : error.message;
      _setFailure('Unable to fetch the pairing bundle.', message);
    } catch (error) {
      _setFailure(
        'Unable to send the pairing payload over USB.',
        error.toString(),
      );
    }
  }

  Future<DevicePairingBundleModel> _requestBundle({
    required String host,
  }) async {
    final appState = ref.read(appControllerProvider);
    final apiClient = ref.read(apiClientProvider);
    apiClient.setConnection(appState.connection);
    return apiClient.post(
      ApiConstants.devicePairingBundlePath,
      body: <String, dynamic>{'host': host},
      parser: (dynamic data) => DevicePairingBundleModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  void _beginAwaitDeviceOnline() {
    state = state.copyWith(
      stage: DevicePairingStage.awaitingOnline,
      statusMessage:
          'Config written. Waiting for the device to reconnect over WiFi and /ws/device.',
      errorMessage: null,
    );

    if (ref.read(appControllerProvider).runtimeState.device.connected) {
      _completePairing('Device online. Pairing complete.');
      return;
    }

    _devicePollAttempts = 0;
    _devicePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollDeviceOnline());
    });
    unawaited(_pollDeviceOnline());
  }

  Future<void> _pollDeviceOnline() async {
    if (state.stage != DevicePairingStage.awaitingOnline) {
      return;
    }
    _devicePollAttempts += 1;
    try {
      await ref.read(appControllerProvider.notifier).refreshRuntime();
      if (ref.read(appControllerProvider).runtimeState.device.connected) {
        _completePairing('Device online. Pairing complete.');
        return;
      }
    } catch (_) {
      // Keep waiting. The realtime stream may still report the device state.
    }

    if (_devicePollAttempts >= 20) {
      _setFailure(
        'The device did not come online yet.',
        'Check WiFi credentials, LAN host reachability, and device power, then retry pairing.',
      );
    }
  }

  void _handleSerialEvent(SerialPairingTransportEvent event) {
    switch (event.type) {
      case 'pairing.status':
        final nextTransportState =
            event.data['state']?.toString().trim().toLowerCase() ?? 'idle';
        final reason = event.data['reason']?.toString();
        final nextStage = switch (nextTransportState) {
          'armed' => DevicePairingStage.armed,
          'applying' => DevicePairingStage.sending,
          'restarting' => DevicePairingStage.awaitingOnline,
          _ =>
            state.connectedPortName.isNotEmpty
                ? DevicePairingStage.usbLinked
                : state.stage,
        };
        state = state.copyWith(
          stage: nextStage,
          transportState: nextTransportState,
          transportReason: reason,
          deviceId: event.data['device_id']?.toString(),
          firmwareVersion: event.data['firmware']?.toString(),
          statusMessage: _transportStatusMessage(nextTransportState, reason),
          errorMessage: null,
        );
        break;
      case 'pairing.result':
        final resultData = <String, dynamic>{...event.data};
        if (!(_pendingApplyResult?.isCompleted ?? true)) {
          _pendingApplyResult?.complete(resultData);
        }
        break;
      case 'serial.closed':
        if (state.stage == DevicePairingStage.awaitingOnline) {
          state = state.copyWith(
            connectedPortName: '',
            transportState: 'restarting',
            transportReason: 'Device rebooted after pairing apply.',
            stage: DevicePairingStage.awaitingOnline,
            statusMessage:
                'Device rebooted after pairing. Waiting for WiFi and /ws/device reconnect.',
            errorMessage: null,
          );
          break;
        }
        final nextStage = state.draft.hasSelectedPort
            ? DevicePairingStage.portReady
            : DevicePairingStage.idle;
        state = state.copyWith(
          connectedPortName: '',
          transportState: 'idle',
          transportReason: 'USB serial connection closed.',
          stage: nextStage,
          statusMessage: 'USB serial connection closed.',
          errorMessage: null,
        );
        break;
      case 'serial.error':
        _setFailure(
          'USB serial transport reported an error.',
          event.data['message']?.toString(),
        );
        break;
      case 'serial.raw':
        state = state.copyWith(
          statusMessage: event.data['line']?.toString() ?? state.statusMessage,
        );
        break;
    }
  }

  String _transportStatusMessage(String transportState, String? reason) {
    return switch (transportState) {
      'armed' => 'Device armed. Send the pairing bundle now.',
      'applying' => 'Device is applying the pairing payload.',
      'restarting' =>
        'Device acknowledged pairing. Waiting for WiFi and runtime reconnect.',
      _ =>
        reason == null || reason.trim().isEmpty
            ? 'USB linked. Hold the touch pad until the device reports pairing armed.'
            : 'USB linked: $reason',
    };
  }

  void _completePairing(String message) {
    _cancelDevicePolling();
    _pendingApplyResult = null;
    state = state.copyWith(
      stage: DevicePairingStage.paired,
      deviceOnline: true,
      statusMessage: message,
      errorMessage: null,
    );
  }

  void _cancelDevicePolling() {
    _devicePollTimer?.cancel();
    _devicePollTimer = null;
    _devicePollAttempts = 0;
  }

  void _setFailure(String message, String? detail) {
    _cancelDevicePolling();
    if (!(_pendingApplyResult?.isCompleted ?? true)) {
      _pendingApplyResult?.complete(<String, dynamic>{
        'ok': false,
        if (detail != null && detail.trim().isNotEmpty) 'message': detail,
      });
    }
    _pendingApplyResult = null;
    state = state.copyWith(
      stage: DevicePairingStage.failed,
      statusMessage: message,
      errorMessage: detail,
    );
  }

  @override
  void dispose() {
    _cancelDevicePolling();
    _serialSubscription?.cancel();
    super.dispose();
  }
}

final appControllerProvider = StateNotifierProvider<AppController, AppState>((
  Ref ref,
) {
  return AppController(ref);
});

final devicePairingControllerProvider =
    StateNotifierProvider<DevicePairingController, DevicePairingStateModel>((
      Ref ref,
    ) {
      final controller = DevicePairingController(
        ref,
        ref.read(devicePairingStorageServiceProvider),
        ref.read(serialPairingServiceProvider),
      );
      ref.listen<ConnectionConfigModel>(
        appControllerProvider.select((AppState state) => state.connection),
        (_, ConnectionConfigModel next) {
          controller.syncConnectionDefaults(next);
        },
      );
      ref.listen<bool>(
        appControllerProvider.select(
          (AppState state) => state.runtimeState.device.connected,
        ),
        (_, bool next) {
          controller.onDeviceOnlineChanged(next);
        },
      );
      return controller;
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

final planningOverviewProvider = Provider<PlanningOverviewModel?>((Ref ref) {
  return ref.watch(appControllerProvider).planningOverview;
});

final planningTimelineProvider = Provider<List<PlanningTimelineItemModel>>((
  Ref ref,
) {
  return ref.watch(appControllerProvider).planningTimeline;
});

final planningConflictsProvider = Provider<List<PlanningConflictModel>>((
  Ref ref,
) {
  return ref.watch(appControllerProvider).planningConflicts;
});

final planningAgendaDatasetProvider = Provider<PlanningAgendaDataset>((
  Ref ref,
) {
  final state = ref.watch(appControllerProvider);
  return PlanningAgendaDataset.fromState(state);
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

List<TaskModel> _decodeTasksFromBundle(Map<String, dynamic> bundle) {
  final rawItems = bundle['tasks'];
  if (rawItems is! List) {
    return const <TaskModel>[];
  }
  return rawItems.map((dynamic item) {
    return TaskModel.fromJson(
      item is Map<String, dynamic> ? item : <String, dynamic>{},
    );
  }).toList();
}

List<EventModel> _decodeEventsFromBundle(Map<String, dynamic> bundle) {
  final rawItems = bundle['events'];
  if (rawItems is! List) {
    return const <EventModel>[];
  }
  return rawItems.map((dynamic item) {
    return EventModel.fromJson(
      item is Map<String, dynamic> ? item : <String, dynamic>{},
    );
  }).toList();
}

List<ReminderModel> _decodeRemindersFromBundle(Map<String, dynamic> bundle) {
  final rawItems = bundle['reminders'];
  if (rawItems is! List) {
    return const <ReminderModel>[];
  }
  return rawItems.map((dynamic item) {
    return ReminderModel.fromJson(
      item is Map<String, dynamic> ? item : <String, dynamic>{},
    );
  }).toList();
}

List<NotificationModel> _decodeNotificationsFromBundle(
  Map<String, dynamic> bundle,
) {
  final rawItems = bundle['notifications'];
  if (rawItems is! List) {
    return const <NotificationModel>[];
  }
  return rawItems.map((dynamic item) {
    return NotificationModel.fromJson(
      item is Map<String, dynamic> ? item : <String, dynamic>{},
    );
  }).toList();
}

T? _firstDefined<T>(List<T?> values) {
  for (final value in values) {
    if (value != null) {
      return value;
    }
  }
  return null;
}
