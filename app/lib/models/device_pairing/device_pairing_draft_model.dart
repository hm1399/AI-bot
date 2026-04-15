class DevicePairingDraftModel {
  const DevicePairingDraftModel({
    required this.portName,
    required this.wifiSsid,
    required this.wifiPassword,
    required this.host,
  });

  static const String defaultServerPath = '/ws/device';

  final String portName;
  final String wifiSsid;
  final String wifiPassword;
  final String host;

  String get trimmedPortName => portName.trim();
  String get trimmedWifiSsid => wifiSsid.trim();
  String get trimmedWifiPassword => wifiPassword.trim();
  String get trimmedHost => host.trim();

  bool get hasSelectedPort => trimmedPortName.isNotEmpty;
  bool get hasWifiSsid => trimmedWifiSsid.isNotEmpty;
  bool get hasLanHost => trimmedHost.isNotEmpty && !isLoopbackHost(trimmedHost);
  bool get requiresExplicitLanHost =>
      trimmedHost.isEmpty || isLoopbackHost(trimmedHost);
  bool get canSubmit => hasSelectedPort && hasWifiSsid && hasLanHost;

  DevicePairingDraftModel copyWith({
    String? portName,
    String? wifiSsid,
    String? wifiPassword,
    String? host,
  }) {
    return DevicePairingDraftModel(
      portName: portName ?? this.portName,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      wifiPassword: wifiPassword ?? this.wifiPassword,
      host: host ?? this.host,
    );
  }

  Map<String, dynamic> toStorageJson() {
    return <String, dynamic>{
      'port_name': trimmedPortName,
      'wifi_ssid': trimmedWifiSsid,
      'host': trimmedHost,
    };
  }

  factory DevicePairingDraftModel.fromStorageJson(Map<String, dynamic> json) {
    return DevicePairingDraftModel(
      portName: json['port_name']?.toString() ?? '',
      wifiSsid: json['wifi_ssid']?.toString() ?? '',
      wifiPassword: '',
      host: json['host']?.toString() ?? '',
    );
  }

  factory DevicePairingDraftModel.empty() {
    return const DevicePairingDraftModel(
      portName: '',
      wifiSsid: '',
      wifiPassword: '',
      host: '',
    );
  }

  static bool isLoopbackHost(String rawHost) {
    final host = rawHost.trim().toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host == '[::1]';
  }
}
