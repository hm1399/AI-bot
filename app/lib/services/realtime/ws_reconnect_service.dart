import '../../models/connect/connection_config_model.dart';
import 'ws_service.dart';

class WsReconnectService {
  WsReconnectService(this._wsService);

  final WebSocketService _wsService;

  Future<void> connect({
    required ConnectionConfigModel connection,
    required String path,
    required int replayLimit,
  }) {
    return _wsService.connect(
      connection: connection,
      path: path,
      replayLimit: replayLimit,
    );
  }

  void disconnect() {
    _wsService.disconnect();
  }
}
