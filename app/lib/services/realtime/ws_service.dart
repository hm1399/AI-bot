import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/app_config.dart';
import '../../constants/api_constants.dart';
import '../../models/api/app_event_model.dart';
import '../../models/connect/connection_config_model.dart';

enum RealtimeConnectionStatus { disconnected, connecting, connected }

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<AppEventModel> _eventsController =
      StreamController<AppEventModel>.broadcast();
  final StreamController<RealtimeConnectionStatus> _statusController =
      StreamController<RealtimeConnectionStatus>.broadcast();

  ConnectionConfigModel _connection = ConnectionConfigModel.empty();
  String _path = ApiConstants.wsEventsPath;
  int _replayLimit = AppConfig.defaultReplayLimit;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _manualDisconnect = false;

  Stream<AppEventModel> get events => _eventsController.stream;
  Stream<RealtimeConnectionStatus> get status => _statusController.stream;

  void setLatestEventId(String latestEventId) {
    _connection = _connection.copyWith(latestEventId: latestEventId);
  }

  Future<void> connect({
    required ConnectionConfigModel connection,
    required String path,
    required int replayLimit,
  }) async {
    _manualDisconnect = false;
    _connection = connection;
    _path = path;
    _replayLimit = replayLimit;
    _open();
  }

  void _open() {
    if (!_connection.hasServer) {
      return;
    }
    _statusController.add(RealtimeConnectionStatus.connecting);
    final uri = Uri(
      scheme: _connection.secure ? 'wss' : 'ws',
      host: _connection.host,
      port: _connection.port,
      path: _path,
      queryParameters: <String, String>{
        if (_connection.token.trim().isNotEmpty) 'token': _connection.token,
        if (_connection.latestEventId.trim().isNotEmpty)
          'last_event_id': _connection.latestEventId,
        'replay_limit': '$_replayLimit',
      },
    );

    _subscription?.cancel();
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(uri);
    _subscription = _channel!.stream.listen(
      _handleMessage,
      onDone: _handleClose,
      onError: (_) => _handleClose(),
    );
    _statusController.add(RealtimeConnectionStatus.connected);
  }

  void _handleMessage(dynamic raw) {
    final decoded = jsonDecode(raw as String);
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    _eventsController.add(AppEventModel.fromJson(decoded));
  }

  void _handleClose() {
    _statusController.add(RealtimeConnectionStatus.disconnected);
    if (_manualDisconnect) {
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delaySeconds = 1 << (_reconnectAttempt > 5 ? 5 : _reconnectAttempt);
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), _open);
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _statusController.add(RealtimeConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _eventsController.close();
    _statusController.close();
  }
}
