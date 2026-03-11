enum DeviceState {
  standby,
  recording,
  playing
}

class DeviceStatus {
  final bool isOnline;
  final int batteryLevel;
  final int wifiSignalStrength;
  final DeviceState state;
  final DateTime lastUpdated;
  
  DeviceStatus({
    required this.isOnline,
    required this.batteryLevel,
    required this.wifiSignalStrength,
    required this.state,
    required this.lastUpdated
  });
  
  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      isOnline: json['isOnline'] as bool,
      batteryLevel: json['batteryLevel'] as int,
      wifiSignalStrength: json['wifiSignalStrength'] as int,
      state: _parseDeviceState(json['state'] as String),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'isOnline': isOnline,
      'batteryLevel': batteryLevel,
      'wifiSignalStrength': wifiSignalStrength,
      'state': _deviceStateToString(state),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
  
  static DeviceState _parseDeviceState(String state) {
    switch (state) {
      case 'standby':
        return DeviceState.standby;
      case 'recording':
        return DeviceState.recording;
      case 'playing':
        return DeviceState.playing;
      default:
        return DeviceState.standby;
    }
  }
  
  static String _deviceStateToString(DeviceState state) {
    switch (state) {
      case DeviceState.standby:
        return 'standby';
      case DeviceState.recording:
        return 'recording';
      case DeviceState.playing:
        return 'playing';
    }
  }
}