import '../connect/connection_config_model.dart';
import '../experience/experience_model.dart';

class SettingsConnectionDiagnosticsModel {
  const SettingsConnectionDiagnosticsModel({
    required this.status,
    required this.endpoint,
  });

  final String status;
  final String? endpoint;

  String get summary =>
      endpoint == null || endpoint!.isEmpty ? status : '$status · $endpoint';

  factory SettingsConnectionDiagnosticsModel.fromConnection(
    ConnectionConfigModel connection, {
    required bool connected,
    required bool demoMode,
  }) {
    final endpoint = connection.hasServer
        ? '${connection.secure ? 'https' : 'http'}://${connection.host.trim()}:${connection.port}'
        : null;
    if (demoMode) {
      return SettingsConnectionDiagnosticsModel(
        status: 'Demo backend',
        endpoint: endpoint,
      );
    }
    if (connected) {
      return SettingsConnectionDiagnosticsModel(
        status: 'Connected backend',
        endpoint: endpoint,
      );
    }
    if (connection.hasServer) {
      return SettingsConnectionDiagnosticsModel(
        status: 'Saved backend',
        endpoint: endpoint,
      );
    }
    return const SettingsConnectionDiagnosticsModel(
      status: 'Not connected',
      endpoint: null,
    );
  }
}

class AppSettingsModel {
  static const Object _unset = Object();

  const AppSettingsModel({
    required this.llmProvider,
    required this.llmModel,
    required this.llmApiKeyConfigured,
    required this.llmBaseUrl,
    required this.sttProvider,
    required this.sttModel,
    required this.sttLanguage,
    required this.ttsProvider,
    required this.ttsModel,
    required this.ttsVoice,
    required this.ttsSpeed,
    required this.deviceVolume,
    required this.ledEnabled,
    required this.ledBrightness,
    required this.ledMode,
    required this.ledColor,
    required this.wakeWord,
    required this.autoListen,
    this.defaultSceneMode = 'focus',
    this.personaToneStyle = 'clear',
    this.personaReplyLength = 'medium',
    this.personaProactivity = 'balanced',
    this.personaVoiceStyle = 'calm',
    this.physicalInteractionEnabled = true,
    this.shakeEnabled = true,
    this.tapConfirmationEnabled = true,
    this.applyResults = const <String, SettingApplyResultModel>{},
  });

  final String llmProvider;
  final String llmModel;
  final bool llmApiKeyConfigured;
  final String? llmBaseUrl;
  final String sttProvider;
  final String sttModel;
  final String sttLanguage;
  final String ttsProvider;
  final String ttsModel;
  final String ttsVoice;
  final double ttsSpeed;
  final int deviceVolume;
  final bool ledEnabled;
  final int ledBrightness;
  final String ledMode;
  final String ledColor;
  final String wakeWord;
  final bool autoListen;
  final String defaultSceneMode;
  final String personaToneStyle;
  final String personaReplyLength;
  final String personaProactivity;
  final String personaVoiceStyle;
  final bool physicalInteractionEnabled;
  final bool shakeEnabled;
  final bool tapConfirmationEnabled;
  final Map<String, SettingApplyResultModel> applyResults;

  bool get hasApplyResults => applyResults.isNotEmpty;

  ExperienceSettingsModel get experience => ExperienceSettingsModel(
    defaultSceneMode: defaultSceneMode,
    persona: PersonaProfileModel(
      toneStyle: personaToneStyle,
      replyLength: personaReplyLength,
      proactivity: personaProactivity,
      voiceStyle: personaVoiceStyle,
    ),
    physicalInteractionEnabled: physicalInteractionEnabled,
    shakeEnabled: shakeEnabled,
    tapConfirmationEnabled: tapConfirmationEnabled,
  );

  SettingApplyResultModel? applyResultFor(String field) {
    return applyResults[field] ??
        SettingApplyResultModel.defaultForField(field);
  }

  String? get applySummary {
    if (applyResults.isEmpty) {
      return null;
    }
    final values = applyResults.values.toList();
    final failedCount = values
        .where((SettingApplyResultModel item) => item.isFailure)
        .length;
    final pendingCount = values
        .where((SettingApplyResultModel item) => item.isPending)
        .length;
    final configOnlyCount = values
        .where((SettingApplyResultModel item) => item.isConfigOnly)
        .length;
    final appliedCount = values
        .where(
          (SettingApplyResultModel item) =>
              item.isSuccessful && item.isLiveApply,
        )
        .length;
    final segments = <String>[];
    if (appliedCount > 0) {
      segments.add('$appliedCount live applied');
    }
    if (pendingCount > 0) {
      segments.add('$pendingCount pending');
    }
    if (configOnlyCount > 0) {
      segments.add('$configOnlyCount config only');
    }
    if (failedCount > 0) {
      segments.add('$failedCount failed');
    }
    return segments.isEmpty ? 'Settings saved.' : segments.join(' · ');
  }

  AppSettingsModel copyWith({
    String? llmProvider,
    String? llmModel,
    bool? llmApiKeyConfigured,
    Object? llmBaseUrl = _unset,
    String? sttLanguage,
    String? ttsVoice,
    double? ttsSpeed,
    int? deviceVolume,
    bool? ledEnabled,
    int? ledBrightness,
    String? ledMode,
    String? ledColor,
    String? wakeWord,
    bool? autoListen,
    String? defaultSceneMode,
    String? personaToneStyle,
    String? personaReplyLength,
    String? personaProactivity,
    String? personaVoiceStyle,
    bool? physicalInteractionEnabled,
    bool? shakeEnabled,
    bool? tapConfirmationEnabled,
    Object? applyResults = _unset,
  }) {
    return AppSettingsModel(
      llmProvider: llmProvider ?? this.llmProvider,
      llmModel: llmModel ?? this.llmModel,
      llmApiKeyConfigured: llmApiKeyConfigured ?? this.llmApiKeyConfigured,
      llmBaseUrl: identical(llmBaseUrl, _unset)
          ? this.llmBaseUrl
          : llmBaseUrl as String?,
      sttProvider: sttProvider,
      sttModel: sttModel,
      sttLanguage: sttLanguage ?? this.sttLanguage,
      ttsProvider: ttsProvider,
      ttsModel: ttsModel,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      deviceVolume: deviceVolume ?? this.deviceVolume,
      ledEnabled: ledEnabled ?? this.ledEnabled,
      ledBrightness: ledBrightness ?? this.ledBrightness,
      ledMode: ledMode ?? this.ledMode,
      ledColor: ledColor ?? this.ledColor,
      wakeWord: wakeWord ?? this.wakeWord,
      autoListen: autoListen ?? this.autoListen,
      defaultSceneMode: defaultSceneMode ?? this.defaultSceneMode,
      personaToneStyle: personaToneStyle ?? this.personaToneStyle,
      personaReplyLength: personaReplyLength ?? this.personaReplyLength,
      personaProactivity: personaProactivity ?? this.personaProactivity,
      personaVoiceStyle: personaVoiceStyle ?? this.personaVoiceStyle,
      physicalInteractionEnabled:
          physicalInteractionEnabled ?? this.physicalInteractionEnabled,
      shakeEnabled: shakeEnabled ?? this.shakeEnabled,
      tapConfirmationEnabled:
          tapConfirmationEnabled ?? this.tapConfirmationEnabled,
      applyResults: identical(applyResults, _unset)
          ? this.applyResults
          : applyResults as Map<String, SettingApplyResultModel>,
    );
  }

  AppSettingsUpdate toUpdate({String? llmApiKey}) {
    return AppSettingsUpdate(
      llmProvider: llmProvider,
      llmModel: llmModel,
      llmApiKey: llmApiKey,
      llmBaseUrl: llmBaseUrl,
      sttLanguage: sttLanguage,
      ttsVoice: ttsVoice,
      ttsSpeed: ttsSpeed,
      deviceVolume: deviceVolume,
      ledEnabled: ledEnabled,
      ledBrightness: ledBrightness,
      ledMode: ledMode,
      ledColor: ledColor,
      wakeWord: wakeWord,
      autoListen: autoListen,
      defaultSceneMode: defaultSceneMode,
      personaToneStyle: personaToneStyle,
      personaReplyLength: personaReplyLength,
      personaProactivity: personaProactivity,
      personaVoiceStyle: personaVoiceStyle,
      physicalInteractionEnabled: physicalInteractionEnabled,
      shakeEnabled: shakeEnabled,
      tapConfirmationEnabled: tapConfirmationEnabled,
    );
  }

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) {
    final payload = _extractSettingsPayload(json);
    return AppSettingsModel(
      llmProvider: payload['llm_provider']?.toString() ?? 'server-managed',
      llmModel: payload['llm_model']?.toString() ?? '',
      llmApiKeyConfigured: payload['llm_api_key_configured'] == true,
      llmBaseUrl: payload['llm_base_url']?.toString(),
      sttProvider: payload['stt_provider']?.toString() ?? 'server-managed',
      sttModel: payload['stt_model']?.toString() ?? '',
      sttLanguage: payload['stt_language']?.toString() ?? 'en-US',
      ttsProvider: payload['tts_provider']?.toString() ?? 'server-managed',
      ttsModel: payload['tts_model']?.toString() ?? '',
      ttsVoice: payload['tts_voice']?.toString() ?? 'en-US-AriaNeural',
      ttsSpeed: payload['tts_speed'] is num
          ? (payload['tts_speed'] as num).toDouble()
          : double.tryParse(payload['tts_speed']?.toString() ?? '') ?? 1.0,
      deviceVolume: payload['device_volume'] is int
          ? payload['device_volume'] as int
          : int.tryParse(payload['device_volume']?.toString() ?? '') ?? 70,
      ledEnabled: payload['led_enabled'] == true,
      ledBrightness: payload['led_brightness'] is int
          ? payload['led_brightness'] as int
          : int.tryParse(payload['led_brightness']?.toString() ?? '') ?? 50,
      ledMode: payload['led_mode']?.toString() ?? 'breathing',
      ledColor: payload['led_color']?.toString() ?? '#2563eb',
      wakeWord: payload['wake_word']?.toString() ?? 'Hey Assistant',
      autoListen: payload['auto_listen'] == true,
      defaultSceneMode: payload['default_scene_mode']?.toString() ?? 'focus',
      personaToneStyle: payload['persona_tone_style']?.toString() ?? 'clear',
      personaReplyLength:
          payload['persona_reply_length']?.toString() ?? 'medium',
      personaProactivity:
          payload['persona_proactivity']?.toString() ?? 'balanced',
      personaVoiceStyle: payload['persona_voice_style']?.toString() ?? 'calm',
      physicalInteractionEnabled:
          payload['physical_interaction_enabled'] != false,
      shakeEnabled: payload['shake_enabled'] != false,
      tapConfirmationEnabled: payload['tap_confirmation_enabled'] != false,
      applyResults: _extractApplyResults(json),
    );
  }
}

class SettingsSaveResultModel {
  const SettingsSaveResultModel({
    required this.settings,
    required this.applyResults,
  });

  final AppSettingsModel settings;
  final Map<String, SettingApplyResultModel> applyResults;

  String? get summary => settings.applySummary;

  factory SettingsSaveResultModel.fromJson(Map<String, dynamic> json) {
    final settings = AppSettingsModel.fromJson(json);
    return SettingsSaveResultModel(
      settings: settings,
      applyResults: settings.applyResults,
    );
  }
}

class SettingApplyResultModel {
  const SettingApplyResultModel({
    required this.field,
    required this.mode,
    required this.status,
    this.message,
    this.errorCode,
    this.updatedAt,
  });

  final String field;
  final String mode;
  final String status;
  final String? message;
  final String? errorCode;
  final String? updatedAt;

  String get effectiveMode {
    if (_isPhysicalInteractionApplyField(field) &&
        (mode == 'config_only' || mode == 'save_only')) {
      return 'runtime_applied';
    }
    return mode;
  }

  String get effectiveStatus {
    if (_isPhysicalInteractionApplyField(field) && status == 'saved_only') {
      return 'applied';
    }
    return status;
  }

  bool get isRuntimeApplied => effectiveMode == 'runtime_applied';
  bool get isLiveApply =>
      effectiveMode == 'save_and_apply' ||
      effectiveMode == 'live_apply' ||
      effectiveMode == 'runtime_applied';
  bool get isConfigOnly =>
      effectiveMode == 'config_only' || effectiveMode == 'save_only';
  bool get isPending =>
      effectiveStatus == 'pending' || effectiveStatus == 'queued';
  bool get isSuccessful =>
      effectiveStatus == 'applied' ||
      effectiveStatus == 'completed' ||
      effectiveStatus == 'succeeded' ||
      effectiveStatus == 'saved_only';
  bool get isFailure =>
      effectiveStatus == 'failed' || effectiveStatus == 'error';

  String get modeLabel => switch (effectiveMode) {
    'runtime_applied' => 'Runtime Applied',
    'config_only' || 'save_only' => 'Config Only',
    'save_and_apply' || 'live_apply' => 'Live Apply',
    _ => 'Unknown Mode',
  };

  String get statusLabel => switch (effectiveStatus) {
    'saved_only' => 'Saved Only',
    'applied' || 'completed' || 'succeeded' => 'Applied',
    'pending' || 'queued' => 'Pending',
    'failed' || 'error' => 'Failed',
    'skipped' => 'Skipped',
    'idle' => 'Idle',
    _ => effectiveStatus.replaceAll('_', ' '),
  };

  factory SettingApplyResultModel.fromJson(
    String field,
    Map<String, dynamic> json,
  ) {
    final reason = json['reason']?.toString();
    return SettingApplyResultModel(
      field: field,
      mode: json['mode']?.toString() ?? _defaultApplyMode(field) ?? 'unknown',
      status: json['status']?.toString() ?? 'idle',
      message:
          json['message']?.toString() ??
          _asMap(json['error'])['message']?.toString() ??
          _applyReasonMessage(field, reason),
      errorCode:
          json['error_code']?.toString() ??
          _asMap(json['error'])['code']?.toString() ??
          reason,
      updatedAt: json['updated_at']?.toString(),
    );
  }

  static SettingApplyResultModel? defaultForField(String field) {
    final mode = _defaultApplyMode(field);
    if (mode == null) {
      return null;
    }
    return SettingApplyResultModel(field: field, mode: mode, status: 'idle');
  }
}

class AppSettingsUpdate {
  const AppSettingsUpdate({
    required this.llmProvider,
    required this.llmModel,
    required this.llmApiKey,
    required this.llmBaseUrl,
    required this.sttLanguage,
    required this.ttsVoice,
    required this.ttsSpeed,
    required this.deviceVolume,
    required this.ledEnabled,
    required this.ledBrightness,
    required this.ledMode,
    required this.ledColor,
    required this.wakeWord,
    required this.autoListen,
    required this.defaultSceneMode,
    required this.personaToneStyle,
    required this.personaReplyLength,
    required this.personaProactivity,
    required this.personaVoiceStyle,
    required this.physicalInteractionEnabled,
    required this.shakeEnabled,
    required this.tapConfirmationEnabled,
  });

  final String llmProvider;
  final String llmModel;
  final String? llmApiKey;
  final String? llmBaseUrl;
  final String sttLanguage;
  final String ttsVoice;
  final double ttsSpeed;
  final int deviceVolume;
  final bool ledEnabled;
  final int ledBrightness;
  final String ledMode;
  final String ledColor;
  final String wakeWord;
  final bool autoListen;
  final String defaultSceneMode;
  final String personaToneStyle;
  final String personaReplyLength;
  final String personaProactivity;
  final String personaVoiceStyle;
  final bool physicalInteractionEnabled;
  final bool shakeEnabled;
  final bool tapConfirmationEnabled;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'llm_provider': llmProvider,
      'llm_model': llmModel,
      if (llmApiKey != null && llmApiKey!.trim().isNotEmpty)
        'llm_api_key': llmApiKey,
      'llm_base_url': llmBaseUrl,
      'stt_language': sttLanguage,
      'tts_voice': ttsVoice,
      'tts_speed': ttsSpeed,
      'device_volume': deviceVolume,
      'led_enabled': ledEnabled,
      'led_brightness': ledBrightness,
      'wake_word': wakeWord,
      'auto_listen': autoListen,
      'default_scene_mode': defaultSceneMode,
      'persona_tone_style': personaToneStyle,
      'persona_reply_length': personaReplyLength,
      'persona_proactivity': personaProactivity,
      'persona_voice_style': personaVoiceStyle,
      'physical_interaction_enabled': physicalInteractionEnabled,
      'shake_enabled': shakeEnabled,
      'tap_confirmation_enabled': tapConfirmationEnabled,
    };
  }
}

class AiConnectionTestModel {
  const AiConnectionTestModel({
    required this.success,
    required this.provider,
    required this.model,
    required this.message,
  });

  final bool success;
  final String provider;
  final String model;
  final String message;

  factory AiConnectionTestModel.fromJson(Map<String, dynamic> json) {
    return AiConnectionTestModel(
      success: json['success'] == true,
      provider: json['provider']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
    );
  }
}

Map<String, dynamic> _extractSettingsPayload(Map<String, dynamic> json) {
  final nested = json['settings'];
  if (nested is Map<String, dynamic>) {
    return nested;
  }
  return json;
}

Map<String, SettingApplyResultModel> _extractApplyResults(
  Map<String, dynamic> json,
) {
  final root = _coerceApplyResultPayload(json['apply_results']);
  if (root.isNotEmpty) {
    return root;
  }
  final settings = _extractSettingsPayload(json);
  return _coerceApplyResultPayload(settings['apply_results']);
}

Map<String, SettingApplyResultModel> _coerceApplyResultPayload(dynamic value) {
  if (value is! Map<String, dynamic>) {
    return const <String, SettingApplyResultModel>{};
  }
  final next = <String, SettingApplyResultModel>{};
  for (final entry in value.entries) {
    final field = entry.key.trim();
    final payload = entry.value;
    if (field.isEmpty || payload is! Map<String, dynamic>) {
      continue;
    }
    next[field] = SettingApplyResultModel.fromJson(field, payload);
  }
  return next;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

String? _defaultApplyMode(String field) {
  return switch (field) {
    'device_volume' || 'led_enabled' || 'led_brightness' => 'save_and_apply',
    'led_mode' ||
    'led_color' ||
    'wake_word' ||
    'auto_listen' ||
    'default_scene_mode' ||
    'persona_tone_style' ||
    'persona_reply_length' ||
    'persona_proactivity' ||
    'persona_voice_style' => 'config_only',
    'physical_interaction_enabled' ||
    'shake_enabled' ||
    'tap_confirmation_enabled' => 'runtime_applied',
    _ => null,
  };
}

String? _applyReasonMessage(String field, String? reason) {
  switch (reason) {
    case 'device_offline':
      return 'Device is offline. $field was saved but not applied live.';
    case 'command_timeout':
      return 'Device command timed out before the hardware confirmed it.';
    case 'unsupported_command':
      return 'Device firmware does not support this setting yet.';
    case 'invalid_argument':
      return 'Device rejected the runtime payload for this setting.';
    case 'config_saved_but_not_runtime_applied':
      if (_isPhysicalInteractionApplyField(field)) {
        return 'Saved and mirrored into the current runtime state.';
      }
      return 'Saved as config only. Runtime effect is not guaranteed yet.';
    case 'apply_failed':
      return 'Saved, but the device did not confirm runtime apply.';
    default:
      return null;
  }
}

bool _isPhysicalInteractionApplyField(String field) {
  return field == 'physical_interaction_enabled' ||
      field == 'shake_enabled' ||
      field == 'tap_confirmation_enabled';
}
