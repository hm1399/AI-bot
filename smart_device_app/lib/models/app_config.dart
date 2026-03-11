class AppConfig {
  final String serverIp;
  final int serverPort;
  final String llmApiKey;
  final String llmModel;
  final String ttsVoice;
  final double ttsSpeed;
  final int deviceVolume;
  final String ledMode;
  
  AppConfig({
    required this.serverIp,
    required this.serverPort,
    required this.llmApiKey,
    required this.llmModel,
    required this.ttsVoice,
    required this.ttsSpeed,
    required this.deviceVolume,
    required this.ledMode
  });
  
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      serverIp: json['serverIp'] as String,
      serverPort: json['serverPort'] as int,
      llmApiKey: json['llmApiKey'] as String,
      llmModel: json['llmModel'] as String,
      ttsVoice: json['ttsVoice'] as String,
      ttsSpeed: (json['ttsSpeed'] as num).toDouble(),
      deviceVolume: json['deviceVolume'] as int,
      ledMode: json['ledMode'] as String,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'serverIp': serverIp,
      'serverPort': serverPort,
      'llmApiKey': llmApiKey,
      'llmModel': llmModel,
      'ttsVoice': ttsVoice,
      'ttsSpeed': ttsSpeed,
      'deviceVolume': deviceVolume,
      'ledMode': ledMode,
    };
  }
  
  AppConfig copyWith({
    String? serverIp,
    int? serverPort,
    String? llmApiKey,
    String? llmModel,
    String? ttsVoice,
    double? ttsSpeed,
    int? deviceVolume,
    String? ledMode,
  }) {
    return AppConfig(
      serverIp: serverIp ?? this.serverIp,
      serverPort: serverPort ?? this.serverPort,
      llmApiKey: llmApiKey ?? this.llmApiKey,
      llmModel: llmModel ?? this.llmModel,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      deviceVolume: deviceVolume ?? this.deviceVolume,
      ledMode: ledMode ?? this.ledMode,
    );
  }
  
  // 获取脱敏后的API Key
  String get maskedApiKey {
    if (llmApiKey.length <= 8) {
      return '*' * llmApiKey.length;
    }
    final visibleChars = 4;
    final maskedChars = llmApiKey.length - (2 * visibleChars);
    return llmApiKey.substring(0, visibleChars) + 
           '*' * maskedChars + 
           llmApiKey.substring(llmApiKey.length - visibleChars);
  }
}