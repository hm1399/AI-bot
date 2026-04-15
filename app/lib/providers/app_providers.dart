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
import '../models/experience/experience_model.dart';
import '../models/events/event_model.dart';
import '../models/home/runtime_state_model.dart';
import '../models/notifications/notification_model.dart';
import '../models/planning/planning_conflict_model.dart';
import '../models/planning/planning_agenda_entry_model.dart';
import '../models/planning/planning_overview_model.dart';
import '../models/planning/planning_timeline_item_model.dart';
import '../models/reminders/reminder_model.dart';
import '../models/settings/settings_model.dart';
import '../models/tasks/task_model.dart';
import '../models/voice/voice_activity_model.dart';
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
import '../services/experience/experience_service.dart';
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

part 'app_controller.dart';
part 'app_controller_planning.dart';
part 'app_controller_realtime.dart';
part 'device_pairing_controller.dart';

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
final experienceServiceProvider = Provider<ExperienceService>(
  (Ref ref) => ExperienceService(ref.read(apiClientProvider)),
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
        sessionExperienceOverrides: _experienceOverridesFromSessions(
          bootstrap.sessions,
        ),
        voiceActivity: VoiceActivityModel.empty(),
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
        voiceActivity: VoiceActivityModel.empty(),
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

  Map<String, SessionExperienceOverrideModel> _storeSessionExperience(
    Map<String, SessionExperienceOverrideModel> current,
    String sessionId,
    SessionExperienceOverrideModel? override,
  ) {
    if (sessionId.trim().isEmpty) {
      return current;
    }
    final next = Map<String, SessionExperienceOverrideModel>.from(current);
    if (override == null || !override.hasOverrides) {
      next.remove(sessionId);
      return next;
    }
    next[sessionId] = override;
    return next;
  }

  SessionExperienceOverrideModel? _experienceOverrideFromSession(
    SessionModel? session,
  ) {
    final override = session?.experienceOverride;
    if (override == null || !override.hasOverrides) {
      return null;
    }
    return override;
  }

  Map<String, SessionExperienceOverrideModel> _experienceOverridesFromSessions(
    Iterable<SessionModel> sessions, {
    Map<String, SessionExperienceOverrideModel> seed =
        const <String, SessionExperienceOverrideModel>{},
  }) {
    var next = Map<String, SessionExperienceOverrideModel>.from(seed);
    for (final session in sessions) {
      next = _storeSessionExperience(
        next,
        session.sessionId,
        _experienceOverrideFromSession(session),
      );
    }
    return next;
  }

  Future<void> updateCurrentSessionExperience({
    String? sceneMode,
    PersonaPresetModel? personaPreset,
  }) async {
    final sessionId = state.currentSessionId.trim();
    if (sessionId.isEmpty) {
      state = state.copyWith(
        globalMessage: 'Create or select a conversation before changing scene.',
      );
      return;
    }

    final existing =
        state.experienceOverrideFor(sessionId) ??
        const SessionExperienceOverrideModel();
    final next = existing.copyWith(
      sceneMode: sceneMode ?? existing.sceneMode,
      personaProfileId: personaPreset?.id ?? existing.personaProfileId,
      persona: personaPreset?.profile ?? existing.persona,
      source: 'session_override',
      updatedAt: DateTime.now().toIso8601String(),
    );

    state = state.copyWith(
      sessionExperienceOverrides: _storeSessionExperience(
        state.sessionExperienceOverrides,
        sessionId,
        next,
      ),
      globalMessage: 'Conversation experience updated.',
    );

    if (state.isDemoMode) {
      return;
    }

    _apiClient.setConnection(state.connection);
    try {
      final synced = await ref
          .read(experienceServiceProvider)
          .patchSessionExperience(sessionId, next);
      state = state.copyWith(
        sessionExperienceOverrides: _storeSessionExperience(
          state.sessionExperienceOverrides,
          sessionId,
          synced.hasOverrides ? synced : next,
        ),
        globalMessage: 'Conversation experience synced.',
      );
    } on ApiError catch (error) {
      state = state.copyWith(
        globalMessage: error.isBackendNotReady
            ? 'Conversation experience updated locally. Backend sync is not ready yet.'
            : error.message,
      );
    }
  }

  Future<void> triggerPhysicalInteraction({
    required String kind,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    if (normalizedKind.isEmpty) {
      return;
    }
    if (state.physicalInteractionDebugPendingKey != null) {
      return;
    }
    if (state.isDemoMode) {
      state = state.copyWith(
        globalMessage: 'Demo mode does not trigger live physical interactions.',
      );
      return;
    }
    if (!state.isConnected) {
      state = state.copyWith(globalMessage: 'Connect to the backend first.');
      return;
    }

    final requestPayload = <String, dynamic>{
      if (state.currentSessionId.trim().startsWith('app:'))
        'app_session_id': state.currentSessionId.trim(),
      if (!payload.containsKey('source')) 'source': 'control_center_debug',
      ...payload,
    };
    final pendingKey = _physicalInteractionDebugKey(
      normalizedKind,
      requestPayload,
    );
    final refreshRuntimeFromBackend = !state.eventStreamConnected;
    final refreshComputerControl =
        normalizedKind == 'tap' && !state.eventStreamConnected;

    state = state.copyWith(physicalInteractionDebugPendingKey: pendingKey);
    _apiClient.setConnection(state.connection);
    try {
      final result = await ref
          .read(experienceServiceProvider)
          .triggerPhysicalInteraction(
            kind: normalizedKind,
            payload: requestPayload,
          );
      if (refreshRuntimeFromBackend) {
        try {
          await refreshRuntime();
        } on ApiError {
          // Keep the trigger result visible even if the follow-up runtime pull lags.
        }
      }
      if (refreshComputerControl) {
        unawaited(loadComputerControl(silent: true));
      }
      state = state.copyWith(
        globalMessage: _physicalInteractionTriggerMessage(result),
      );
    } on ApiError catch (error) {
      state = state.copyWith(globalMessage: error.message);
    } finally {
      state = state.copyWith(physicalInteractionDebugPendingKey: null);
    }
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
      sessionExperienceOverrides:
          const <String, SessionExperienceOverrideModel>{},
      voiceActivity: VoiceActivityModel.empty(),
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
        sessionExperienceOverrides:
            const <String, SessionExperienceOverrideModel>{},
        voiceActivity: VoiceActivityModel.empty(),
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
        sessionExperienceOverrides: _experienceOverridesFromSessions(
          bootstrap.sessions,
        ),
        voiceActivity: VoiceActivityModel.empty(),
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
        sessionExperienceOverrides: _experienceOverridesFromSessions(
          sessions,
          seed: state.sessionExperienceOverrides,
        ),
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

  Future<void> refreshRuntime() => _refreshRuntime(this);

  Future<void> loadPlanningOverview() => _loadPlanningOverview(this);

  Future<void> loadPlanningTimeline() => _loadPlanningTimeline(this);

  Future<void> loadPlanningConflicts() => _loadPlanningConflicts(this);

  Future<void> refreshPlanningWorkbench() => _refreshPlanningWorkbench(this);

  Future<void> stopCurrentTask() => _stopCurrentTask(this);

  Future<void> speakTestPhrase() => _speakTestPhrase(this);

  Future<void> triggerVoiceInput() => _triggerVoiceInput(this);

  Future<void> loadSettings() => _loadSettings(this);

  Future<void> saveSettings(AppSettingsModel draft, {String? apiKey}) =>
      _saveSettings(this, draft, apiKey: apiKey);

  Future<void> loadComputerControl({bool silent = false}) =>
      _loadComputerControl(this, silent: silent);

  Future<void> runComputerAction(ComputerActionRequest request) =>
      _runComputerAction(this, request);

  Future<void> confirmComputerAction(String actionId) =>
      _confirmComputerAction(this, actionId);

  Future<void> cancelComputerAction(String actionId) =>
      _cancelComputerAction(this, actionId);

  Future<void> testAiConnection({AppSettingsModel? draft, String? apiKey}) =>
      _testAiConnection(this, draft: draft, apiKey: apiKey);

  Future<void> loadTasks() => _loadTasks(this);

  Future<void> createTask(TaskModel task) => _createTask(this, task);

  Future<void> createPlanningBundle({
    List<TaskModel> tasks = const <TaskModel>[],
    List<EventModel> events = const <EventModel>[],
    List<ReminderModel> reminders = const <ReminderModel>[],
    String successMessage = 'Planning items created.',
  }) => _createPlanningBundle(
    this,
    tasks: tasks,
    events: events,
    reminders: reminders,
    successMessage: successMessage,
  );

  Future<void> updateTask(TaskModel task) => _updateTask(this, task);

  Future<void> deleteTask(String taskId) => _deleteTask(this, taskId);

  Future<void> loadEvents() => _loadEvents(this);

  Future<void> createEvent(EventModel event) => _createEvent(this, event);

  Future<void> updateEvent(EventModel event) => _updateEvent(this, event);

  Future<void> deleteEvent(String eventId) => _deleteEvent(this, eventId);

  Future<void> loadNotifications() => _loadNotifications(this);

  Future<void> markNotificationRead(
    String notificationId, {
    required bool read,
  }) => _markNotificationRead(this, notificationId, read: read);

  Future<void> markAllNotificationsRead() => _markAllNotificationsRead(this);

  Future<void> deleteNotification(String notificationId) =>
      _deleteNotification(this, notificationId);

  Future<void> clearNotifications() => _clearNotifications(this);

  Future<void> loadReminders() => _loadReminders(this);

  Future<void> createReminder(ReminderModel reminder) =>
      _createReminder(this, reminder);

  Future<void> updateReminder(ReminderModel reminder) =>
      _updateReminder(this, reminder);

  Future<void> setReminderEnabled(String reminderId, bool enabled) =>
      _setReminderEnabled(this, reminderId, enabled);

  Future<void> deleteReminder(String reminderId) =>
      _deleteReminder(this, reminderId);

  Future<void> sendDeviceCommand(
    String command, {
    Map<String, dynamic>? params,
  }) => _sendDeviceCommand(this, command, params: params);

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

  String _physicalInteractionDebugKey(
    String kind,
    Map<String, dynamic> payload,
  ) {
    if (kind == 'tap') {
      final tapCount = int.tryParse(
        '${payload['tap_count'] ?? payload['tapCount'] ?? ''}',
      );
      if (tapCount != null && tapCount > 0) {
        return 'tap:$tapCount';
      }
    }
    return kind;
  }

  String _physicalInteractionTriggerMessage(InteractionResultModel result) {
    final detail = result.displayText?.trim();
    if (detail != null && detail.isNotEmpty) {
      return detail;
    }
    final title = result.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
    return 'Physical interaction trigger sent to backend.';
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
      'default_scene_mode': SettingApplyResultModel(
        field: 'default_scene_mode',
        mode: 'config_only',
        status: 'saved_only',
      ),
      'persona_tone_style': SettingApplyResultModel(
        field: 'persona_tone_style',
        mode: 'config_only',
        status: 'saved_only',
      ),
      'persona_reply_length': SettingApplyResultModel(
        field: 'persona_reply_length',
        mode: 'config_only',
        status: 'saved_only',
      ),
      'persona_proactivity': SettingApplyResultModel(
        field: 'persona_proactivity',
        mode: 'config_only',
        status: 'saved_only',
      ),
      'persona_voice_style': SettingApplyResultModel(
        field: 'persona_voice_style',
        mode: 'config_only',
        status: 'saved_only',
      ),
      'physical_interaction_enabled': SettingApplyResultModel(
        field: 'physical_interaction_enabled',
        mode: 'config_only',
        status: 'saved_only',
      ),
      'shake_enabled': SettingApplyResultModel(
        field: 'shake_enabled',
        mode: 'config_only',
        status: 'saved_only',
      ),
      'tap_confirmation_enabled': SettingApplyResultModel(
        field: 'tap_confirmation_enabled',
        mode: 'config_only',
        status: 'saved_only',
      ),
    };
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

  void _handleRealtimeStatus(RealtimeConnectionStatus status) =>
      _handleAppControllerRealtimeStatus(this, status);

  void _handleEvent(AppEventModel event) =>
      _handleAppControllerEvent(this, event);

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

final voiceActivityProvider = Provider<VoiceActivityModel>((Ref ref) {
  return ref.watch(
    appControllerProvider.select((AppState state) => state.voiceActivity),
  );
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
