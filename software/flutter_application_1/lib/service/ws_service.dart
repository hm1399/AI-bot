import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:connectivity_plus/connectivity_plus.dart';

typedef MessageHandler = void Function(Map<String, dynamic> message);

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  String? _serverUrl;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  final List<MessageHandler> _handlers = [];

  // 连接状态流
  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  // 网络状态监听
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  void init() {
    // 监听网络变化
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none && _channel == null && _serverUrl != null) {
        // 网络恢复且当前未连接，尝试重连
        connect(_serverUrl!);
      }
    });
  }

  void addHandler(MessageHandler handler) {
    _handlers.add(handler);
  }

  void removeHandler(MessageHandler handler) {
    _handlers.remove(handler);
  }

  Future<void> connect(String serverUrl) async {
    if (_isConnecting) return;
    _isConnecting = true;
    _serverUrl = serverUrl;

    try {
      final wsUrl = 'ws://$serverUrl/ws/app'; // 假设 WebSocket 路径
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // 监听消息
      _channel!.stream.listen(
        (message) {
          // 假设服务端发送 JSON 字符串
          final data = message is String ? jsonDecode(message) : message;
          _handleIncoming(data);
        },
        onError: (error) {
          print('WebSocket error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          print('WebSocket closed');
          _connectionController.add(false);
          _scheduleReconnect();
        },
      );

      _startHeartbeat();
      _connectionController.add(true);
      _isConnecting = false;
    } catch (e) {
      print('WebSocket connection failed: $e');
      _connectionController.add(false);
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void _handleIncoming(Map<String, dynamic> message) {
    for (var handler in _handlers) {
      handler(message);
    }
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    } else {
      print('WebSocket not connected');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_channel != null) {
        // 发送 ping 帧（或自定义心跳消息）
        _channel!.sink.add('ping');
      } else {
        timer.cancel();
      }
    });
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _channel = null;

    if (_reconnectTimer != null) return;
    _reconnectTimer = Timer(Duration(seconds: 5), () {
      _reconnectTimer = null;
      if (_serverUrl != null) {
        connect(_serverUrl!);
      }
    });
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _channel = null;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _connectivitySubscription.cancel();
    _connectionController.close();
  }
}