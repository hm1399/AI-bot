class DevicePairingBundleModel {
  const DevicePairingBundleModel({
    required this.transport,
    required this.server,
    required this.auth,
  });

  final String transport;
  final DevicePairingServerBundleModel server;
  final DevicePairingAuthBundleModel auth;

  bool get requiresDeviceToken =>
      auth.required || auth.deviceToken.trim().isNotEmpty;

  Map<String, dynamic> toPairingApplyEnvelope({
    required String wifiSsid,
    required String wifiPassword,
  }) {
    return <String, dynamic>{
      'type': 'pairing.apply',
      'data': <String, dynamic>{
        'schema_version': 1,
        'wifi': <String, dynamic>{
          'ssid': wifiSsid.trim(),
          'password': wifiPassword,
        },
        'server': server.toJson(),
        if (requiresDeviceToken)
          'auth': <String, dynamic>{
            if (auth.deviceToken.trim().isNotEmpty)
              'device_token': auth.deviceToken.trim(),
          },
      },
    };
  }

  factory DevicePairingBundleModel.fromJson(Map<String, dynamic> json) {
    final payload = json['bundle'] is Map<String, dynamic>
        ? json['bundle'] as Map<String, dynamic>
        : json;
    return DevicePairingBundleModel(
      transport: json['transport']?.toString() ?? 'serial',
      server: DevicePairingServerBundleModel.fromJson(
        payload['server'] is Map<String, dynamic>
            ? payload['server'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      auth: DevicePairingAuthBundleModel.fromJson(
        payload['auth'] is Map<String, dynamic>
            ? payload['auth'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
    );
  }
}

class DevicePairingServerBundleModel {
  const DevicePairingServerBundleModel({
    required this.host,
    required this.port,
    required this.path,
    required this.secure,
  });

  final String host;
  final int port;
  final String path;
  final bool secure;

  String get normalizedPath {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '/ws/device';
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  String get summary =>
      '${secure ? 'wss' : 'ws'}://${host.trim()}:${port <= 0 ? 8765 : port}$normalizedPath';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'host': host.trim(),
      'port': port <= 0 ? 8765 : port,
      'path': normalizedPath,
      'secure': secure,
    };
  }

  factory DevicePairingServerBundleModel.fromJson(Map<String, dynamic> json) {
    return DevicePairingServerBundleModel(
      host: json['host']?.toString() ?? '',
      port: json['port'] is int
          ? json['port'] as int
          : int.tryParse(json['port']?.toString() ?? '') ?? 8765,
      path: json['path']?.toString() ?? '/ws/device',
      secure: json['secure'] == true,
    );
  }
}

class DevicePairingAuthBundleModel {
  const DevicePairingAuthBundleModel({
    required this.deviceToken,
    required this.required,
  });

  final String deviceToken;
  final bool required;

  factory DevicePairingAuthBundleModel.fromJson(Map<String, dynamic> json) {
    return DevicePairingAuthBundleModel(
      deviceToken: json['device_token']?.toString() ?? '',
      required: json['required'] == true,
    );
  }
}
