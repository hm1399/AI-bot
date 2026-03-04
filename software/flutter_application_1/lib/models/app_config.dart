class AppConfig {
  final String serverIp;
  final int serverPort;
  final String? llmApiKey;      // 脱敏显示
  final String? ttsVoice;
  final double ttsSpeed;
  final int deviceVolume;

  AppConfig({
    required this.serverIp,
    required this.serverPort,
    this.llmApiKey,
    this.ttsVoice,
    required this.ttsSpeed,
    required this.deviceVolume,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      serverIp: json['serverIp'] as String,
      serverPort: json['serverPort'] as int,
      llmApiKey: json['llmApiKey'] as String?,
      ttsVoice: json['ttsVoice'] as String?,
      ttsSpeed: json['ttsSpeed'] as double,
      deviceVolume: json['deviceVolume'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverIp': serverIp,
      'serverPort': serverPort,
      'llmApiKey': llmApiKey,
      'ttsVoice': ttsVoice,
      'ttsSpeed': ttsSpeed,
      'deviceVolume': deviceVolume,
    };
  }
}