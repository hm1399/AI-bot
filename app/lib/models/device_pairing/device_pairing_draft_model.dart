class DevicePairingDraftModel {
  const DevicePairingDraftModel({
    required this.portName,
    required this.wifiSsid,
    required this.wifiPassword,
    required this.host,
    required this.port,
    required this.path,
    required this.secure,
  });

  static const int defaultServerPort = 8765;
  static const String defaultServerPath = '/ws/device';

  final String portName;
  final String wifiSsid;
  final String wifiPassword;
  final String host;
  final int port;
  final String path;
  final bool secure;

  String get trimmedPortName => portName.trim();
  String get trimmedWifiSsid => wifiSsid.trim();
  String get trimmedWifiPassword => wifiPassword.trim();
  String get trimmedHost => host.trim();
  String get normalizedPath {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return defaultServerPath;
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  bool get hasSelectedPort => trimmedPortName.isNotEmpty;
  bool get hasWifiSsid => trimmedWifiSsid.isNotEmpty;
  bool get hasLanHost => trimmedHost.isNotEmpty && !isLoopbackHost(trimmedHost);
  bool get requiresExplicitLanHost =>
      trimmedHost.isEmpty || isLoopbackHost(trimmedHost);
  bool get canRequestBundle => hasLanHost;
  bool get canSubmit => hasSelectedPort && hasWifiSsid && hasLanHost;

  String get websocketSummary =>
      '${secure ? 'wss' : 'ws'}://$trimmedHost:${port <= 0 ? defaultServerPort : port}$normalizedPath';

  DevicePairingDraftModel copyWith({
    String? portName,
    String? wifiSsid,
    String? wifiPassword,
    String? host,
    int? port,
    String? path,
    bool? secure,
  }) {
    return DevicePairingDraftModel(
      portName: portName ?? this.portName,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      wifiPassword: wifiPassword ?? this.wifiPassword,
      host: host ?? this.host,
      port: port ?? this.port,
      path: path ?? this.path,
      secure: secure ?? this.secure,
    );
  }

  Map<String, dynamic> toStorageJson() {
    return <String, dynamic>{
      'port_name': trimmedPortName,
      'wifi_ssid': trimmedWifiSsid,
      'host': trimmedHost,
      'port': port <= 0 ? defaultServerPort : port,
      'path': normalizedPath,
      'secure': secure,
    };
  }

  factory DevicePairingDraftModel.fromStorageJson(Map<String, dynamic> json) {
    return DevicePairingDraftModel(
      portName: json['port_name']?.toString() ?? '',
      wifiSsid: json['wifi_ssid']?.toString() ?? '',
      wifiPassword: '',
      host: json['host']?.toString() ?? '',
      port: json['port'] is int
          ? json['port'] as int
          : int.tryParse(json['port']?.toString() ?? '') ?? defaultServerPort,
      path: json['path']?.toString() ?? defaultServerPath,
      secure: json['secure'] == true,
    );
  }

  factory DevicePairingDraftModel.empty() {
    return const DevicePairingDraftModel(
      portName: '',
      wifiSsid: '',
      wifiPassword: '',
      host: '',
      port: defaultServerPort,
      path: defaultServerPath,
      secure: false,
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
