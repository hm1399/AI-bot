import '../../config/app_config.dart';
import '../../constants/api_constants.dart';
import '../../models/connect/connection_config_model.dart';
import '../api/api_client.dart';
import '../storage/auth_storage_service.dart';

class ConnectService {
  ConnectService(this._storage, this._apiClient);

  final AuthStorageService _storage;
  final ApiClient _apiClient;

  Future<void> saveConnection(ConnectionConfigModel config) {
    return _storage.saveConnection(config);
  }

  Future<ConnectionConfigModel?> loadConnection() {
    return _storage.loadConnection();
  }

  Future<Map<String, dynamic>> checkHealth(
    String host,
    int port,
    String token,
    bool secure,
  ) {
    _apiClient.setConnection(buildConnection(
      host: host,
      port: port,
      token: token,
      secure: secure,
    ));
    return _apiClient.getRaw(
      ApiConstants.healthPath,
      timeout: const Duration(seconds: 5),
    );
  }

  ConnectionConfigModel buildConnection({
    required String host,
    required int port,
    required String token,
    required bool secure,
    String currentSessionId = '',
    String latestEventId = '',
  }) {
    final endpoint = _parseEndpoint(host);
    return ConnectionConfigModel(
      host: endpoint.host,
      port: endpoint.port ?? (port <= 0 ? AppConfig.defaultPort : port),
      secure: endpoint.secure ?? secure,
      token: token.trim(),
      currentSessionId: currentSessionId,
      latestEventId: latestEventId,
    );
  }

  ({String host, int? port, bool? secure}) _parseEndpoint(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (host: '', port: null, secure: null);
    }

    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || parsed.host.isEmpty) {
      return (host: trimmed, port: null, secure: null);
    }

    final secure = switch (parsed.scheme) {
      'https' || 'wss' => true,
      'http' || 'ws' => false,
      _ => null,
    };

    return (
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      secure: secure,
    );
  }
}
