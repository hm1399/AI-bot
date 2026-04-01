class ConnectionConfigModel {
  const ConnectionConfigModel({
    required this.host,
    required this.port,
    required this.token,
    required this.currentSessionId,
    required this.latestEventId,
  });

  final String host;
  final int port;
  final String token;
  final String currentSessionId;
  final String latestEventId;

  bool get hasServer => host.trim().isNotEmpty;

  ConnectionConfigModel copyWith({
    String? host,
    int? port,
    String? token,
    String? currentSessionId,
    String? latestEventId,
  }) {
    return ConnectionConfigModel(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      latestEventId: latestEventId ?? this.latestEventId,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'host': host,
      'port': port,
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
      token: json['token']?.toString() ?? '',
      currentSessionId: json['current_session_id']?.toString() ?? '',
      latestEventId: json['latest_event_id']?.toString() ?? '',
    );
  }

  factory ConnectionConfigModel.empty() {
    return const ConnectionConfigModel(
      host: '',
      port: 8000,
      token: '',
      currentSessionId: '',
      latestEventId: '',
    );
  }
}
