import '../chat/session_model.dart';
import '../home/runtime_state_model.dart';

class DesktopVoiceCapabilitiesModel {
  const DesktopVoiceCapabilitiesModel({
    required this.httpPath,
    required this.wsPath,
    required this.desktopClientReady,
    required this.captureSource,
    required this.deviceFeedbackAvailable,
    required this.localSpeakerOutput,
  });

  final String httpPath;
  final String wsPath;
  final bool desktopClientReady;
  final String captureSource;
  final bool deviceFeedbackAvailable;
  final bool localSpeakerOutput;

  factory DesktopVoiceCapabilitiesModel.fromJson(Map<String, dynamic> json) {
    return DesktopVoiceCapabilitiesModel(
      httpPath: json['http_path']?.toString() ?? '',
      wsPath: json['ws_path']?.toString() ?? '',
      desktopClientReady: json['desktop_client_ready'] == true,
      captureSource: json['capture_source']?.toString() ?? '',
      deviceFeedbackAvailable: json['device_feedback_available'] == true,
      localSpeakerOutput: json['local_speaker_output'] == true,
    );
  }

  factory DesktopVoiceCapabilitiesModel.empty() {
    return const DesktopVoiceCapabilitiesModel(
      httpPath: '',
      wsPath: '',
      desktopClientReady: false,
      captureSource: '',
      deviceFeedbackAvailable: false,
      localSpeakerOutput: false,
    );
  }
}

class CapabilitiesModel {
  const CapabilitiesModel({
    required this.chat,
    required this.deviceControl,
    required this.deviceCommands,
    required this.voicePipeline,
    required this.desktopVoice,
    required this.wakeWord,
    required this.autoListen,
    required this.whatsappBridge,
    required this.settings,
    required this.tasks,
    required this.events,
    required this.notifications,
    required this.reminders,
    required this.todoSummary,
    required this.calendarSummary,
    required this.appEvents,
    required this.eventReplay,
    required this.appAuthEnabled,
    this.planning = false,
    this.planningOverview = false,
    this.planningTimeline = false,
    this.planningConflicts = false,
  });

  final bool chat;
  final bool deviceControl;
  final bool deviceCommands;
  final bool voicePipeline;
  final DesktopVoiceCapabilitiesModel desktopVoice;
  final bool wakeWord;
  final bool autoListen;
  final bool whatsappBridge;
  final bool settings;
  final bool tasks;
  final bool events;
  final bool notifications;
  final bool reminders;
  final bool todoSummary;
  final bool calendarSummary;
  final bool appEvents;
  final bool eventReplay;
  final bool appAuthEnabled;
  final bool planning;
  final bool planningOverview;
  final bool planningTimeline;
  final bool planningConflicts;

  factory CapabilitiesModel.fromJson(Map<String, dynamic> json) {
    final planning = _asMap(json['planning']);
    return CapabilitiesModel(
      chat: json['chat'] == true,
      deviceControl: json['device_control'] == true,
      deviceCommands: json['device_commands'] == true,
      voicePipeline: json['voice_pipeline'] == true,
      desktopVoice: DesktopVoiceCapabilitiesModel.fromJson(
        json['desktop_voice'] is Map<String, dynamic>
            ? json['desktop_voice'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      wakeWord: json['wake_word'] == true,
      autoListen: json['auto_listen'] == true,
      whatsappBridge: json['whatsapp_bridge'] == true,
      settings: json['settings'] == true,
      tasks: json['tasks'] == true,
      events: json['events'] == true,
      notifications: json['notifications'] == true,
      reminders: json['reminders'] == true,
      todoSummary: json['todo_summary'] == true,
      calendarSummary: json['calendar_summary'] == true,
      appEvents: json['app_events'] == true,
      eventReplay: json['event_replay'] == true,
      appAuthEnabled: json['app_auth_enabled'] == true,
      planning:
          _readBool(json, const <String>['planning']) || planning.isNotEmpty,
      planningOverview:
          _readBool(json, const <String>['planning_overview']) ||
          _readBool(planning, const <String>['overview', 'overview_enabled']) ||
          planning['overview_path'] != null,
      planningTimeline:
          _readBool(json, const <String>['planning_timeline']) ||
          _readBool(planning, const <String>['timeline', 'timeline_enabled']) ||
          planning['timeline_path'] != null,
      planningConflicts:
          _readBool(json, const <String>['planning_conflicts']) ||
          _readBool(planning, const <String>[
            'conflicts',
            'conflicts_enabled',
          ]) ||
          planning['conflicts_path'] != null,
    );
  }

  factory CapabilitiesModel.empty() {
    return CapabilitiesModel(
      chat: false,
      deviceControl: false,
      deviceCommands: false,
      voicePipeline: false,
      desktopVoice: DesktopVoiceCapabilitiesModel.empty(),
      wakeWord: false,
      autoListen: false,
      whatsappBridge: false,
      settings: false,
      tasks: false,
      events: false,
      notifications: false,
      reminders: false,
      todoSummary: false,
      calendarSummary: false,
      appEvents: false,
      eventReplay: false,
      appAuthEnabled: false,
      planning: false,
      planningOverview: false,
      planningTimeline: false,
      planningConflicts: false,
    );
  }
}

class EventResumeModel {
  const EventResumeModel({
    required this.query,
    required this.replayLimit,
    required this.latestEventId,
  });

  final String query;
  final int replayLimit;
  final String latestEventId;

  factory EventResumeModel.fromJson(Map<String, dynamic> json) {
    return EventResumeModel(
      query: json['query']?.toString() ?? 'last_event_id',
      replayLimit: json['replay_limit'] is int
          ? json['replay_limit'] as int
          : int.tryParse(json['replay_limit']?.toString() ?? '') ?? 200,
      latestEventId: json['latest_event_id']?.toString() ?? '',
    );
  }
}

class EventStreamModel {
  const EventStreamModel({
    required this.type,
    required this.path,
    required this.resume,
  });

  final String type;
  final String path;
  final EventResumeModel resume;

  factory EventStreamModel.fromJson(Map<String, dynamic> json) {
    return EventStreamModel(
      type: json['type']?.toString() ?? 'websocket',
      path: json['path']?.toString() ?? '/ws/app/v1/events',
      resume: EventResumeModel.fromJson(
        json['resume'] is Map<String, dynamic>
            ? json['resume'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
    );
  }
}

class BootstrapModel {
  const BootstrapModel({
    required this.serverVersion,
    required this.capabilities,
    required this.runtime,
    required this.sessions,
    required this.eventStream,
    this.planning = const <String, dynamic>{},
  });

  final String serverVersion;
  final CapabilitiesModel capabilities;
  final RuntimeStateModel runtime;
  final List<SessionModel> sessions;
  final EventStreamModel eventStream;
  final Map<String, dynamic> planning;

  factory BootstrapModel.fromJson(Map<String, dynamic> json) {
    final rawSessions = json['sessions'] is List
        ? json['sessions'] as List<dynamic>
        : const <dynamic>[];

    return BootstrapModel(
      serverVersion: json['server_version']?.toString() ?? '',
      capabilities: CapabilitiesModel.fromJson(
        json['capabilities'] is Map<String, dynamic>
            ? json['capabilities'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      runtime: RuntimeStateModel.fromJson(
        json['runtime'] is Map<String, dynamic>
            ? json['runtime'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      sessions: rawSessions
          .map(
            (dynamic item) => SessionModel.fromJson(
              item is Map<String, dynamic> ? item : <String, dynamic>{},
            ),
          )
          .toList(),
      eventStream: EventStreamModel.fromJson(
        json['event_stream'] is Map<String, dynamic>
            ? json['event_stream'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      planning: _extractBootstrapPlanning(json),
    );
  }
}

Map<String, dynamic> _extractBootstrapPlanning(Map<String, dynamic> json) {
  final planning = <String, dynamic>{};
  final planningPayload = _asMap(json['planning']);
  if (planningPayload.isNotEmpty) {
    planning.addAll(planningPayload);
  }

  final planningRoutes = _asMap(json['planning_routes']);
  if (planningRoutes.isNotEmpty) {
    planning['routes'] = planningRoutes;
  }

  for (final key in const <String>[
    'planning_overview_path',
    'planning_timeline_path',
    'planning_conflicts_path',
  ]) {
    if (json.containsKey(key)) {
      planning[key] = json[key];
    }
  }

  return planning;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

bool _readBool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return false;
}
