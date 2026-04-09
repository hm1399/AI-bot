class AppSettingsModel {
  static const Object _unset = Object();

  const AppSettingsModel({
    required this.serverUrl,
    required this.serverPort,
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
  });

  final String serverUrl;
  final int serverPort;
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
  }) {
    return AppSettingsModel(
      serverUrl: serverUrl,
      serverPort: serverPort,
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
    );
  }

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) {
    return AppSettingsModel(
      serverUrl: json['server_url']?.toString() ?? '',
      serverPort: json['server_port'] is int
          ? json['server_port'] as int
          : int.tryParse(json['server_port']?.toString() ?? '') ?? 8000,
      llmProvider: json['llm_provider']?.toString() ?? 'server-managed',
      llmModel: json['llm_model']?.toString() ?? '',
      llmApiKeyConfigured: json['llm_api_key_configured'] == true,
      llmBaseUrl: json['llm_base_url']?.toString(),
      sttProvider: json['stt_provider']?.toString() ?? 'server-managed',
      sttModel: json['stt_model']?.toString() ?? '',
      sttLanguage: json['stt_language']?.toString() ?? 'en-US',
      ttsProvider: json['tts_provider']?.toString() ?? 'server-managed',
      ttsModel: json['tts_model']?.toString() ?? '',
      ttsVoice: json['tts_voice']?.toString() ?? 'alloy',
      ttsSpeed: json['tts_speed'] is num
          ? (json['tts_speed'] as num).toDouble()
          : double.tryParse(json['tts_speed']?.toString() ?? '') ?? 1.0,
      deviceVolume: json['device_volume'] is int
          ? json['device_volume'] as int
          : int.tryParse(json['device_volume']?.toString() ?? '') ?? 70,
      ledEnabled: json['led_enabled'] == true,
      ledBrightness: json['led_brightness'] is int
          ? json['led_brightness'] as int
          : int.tryParse(json['led_brightness']?.toString() ?? '') ?? 50,
      ledMode: json['led_mode']?.toString() ?? 'breathing',
      ledColor: json['led_color']?.toString() ?? '#2563eb',
      wakeWord: json['wake_word']?.toString() ?? 'Hey Assistant',
      autoListen: json['auto_listen'] == true,
    );
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
      'led_mode': ledMode,
      'led_color': ledColor,
      'wake_word': wakeWord,
      'auto_listen': autoListen,
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
