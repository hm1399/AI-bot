class ConnectionConfigModel {
  const ConnectionConfigModel({
    required this.host,
    required this.port,
    required this.secure,
    required this.token,
    required this.currentSessionId,
    required this.latestEventId,
  });

  final String host;
  final int port;
  final bool secure;
  final String token;
  final String currentSessionId;
  final String latestEventId;

  bool get hasServer => host.trim().isNotEmpty;

  ConnectionConfigModel copyWith({
    String? host,
    int? port,
    bool? secure,
    String? token,
    String? currentSessionId,
    String? latestEventId,
  }) {
    return ConnectionConfigModel(
      host: host ?? this.host,
      port: port ?? this.port,
      secure: secure ?? this.secure,
      token: token ?? this.token,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      latestEventId: latestEventId ?? this.latestEventId,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'host': host,
      'port': port,
      'secure': secure,
      'token': token,
      'current_session_id': currentSessionId,
      'latest_event_id': latestEventId,
    };
  }

  factory ConnectionConfigModel.fromJson(Map<String, dynamic> json) {
    return ConnectionConfigModel(
      host: json['host']?.toString() ?? '',
      port: json['port'] is int
          ? json['port'] as int
          : int.tryParse(json['port']?.toString() ?? '') ?? 8000,
      secure: json['secure'] == true,
      token: json['token']?.toString() ?? '',
      currentSessionId: json['current_session_id']?.toString() ?? '',
      latestEventId: json['latest_event_id']?.toString() ?? '',
    );
  }

  factory ConnectionConfigModel.empty() {
    return const ConnectionConfigModel(
      host: '',
      port: 8000,
      secure: false,
      token: '',
      currentSessionId: '',
      latestEventId: '',
    );
  }
}
