enum DeviceMode { standby, recording, playing }

class DeviceStatus {
  final bool isOnline;
  final int batteryLevel;
  final int wifiStrength;
  final DeviceMode mode;
  final bool isMuted;
  final bool ledOn;

  DeviceStatus({
    required this.isOnline,
    required this.batteryLevel,
    required this.wifiStrength,
    required this.mode,
    required this.isMuted,
    required this.ledOn,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      isOnline: json['isOnline'] ?? false,
      batteryLevel: json['batteryLevel'] ?? 0,
      wifiStrength: json['wifiStrength'] ?? 0,
      mode: DeviceMode.values.firstWhere(
        (e) => e.toString().split('.').last == json['mode'],
        orElse: () => DeviceMode.standby,
      ),
      isMuted: json['isMuted'] ?? false,
      ledOn: json['ledOn'] ?? false,
    );
  }
}