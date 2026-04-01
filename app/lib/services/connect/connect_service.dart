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
  ) {
    _apiClient.setConnection(
      ConnectionConfigModel(
        host: host,
        port: port,
        token: token,
        currentSessionId: '',
        latestEventId: '',
      ),
    );
    return _apiClient.getRaw(
      ApiConstants.healthPath,
      timeout: const Duration(seconds: 5),
    );
  }

  ConnectionConfigModel buildConnection({
    required String host,
    required int port,
    required String token,
    String currentSessionId = '',
    String latestEventId = '',
  }) {
    return ConnectionConfigModel(
      host: host.trim(),
      port: port <= 0 ? AppConfig.defaultPort : port,
      token: token.trim(),
      currentSessionId: currentSessionId,
      latestEventId: latestEventId,
    );
  }
}
