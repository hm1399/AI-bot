import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

class WSService {
  final String baseUrl;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;
  final Duration _initialReconnectDelay = const Duration(seconds: 1);
  
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectionStatusController = 
      StreamController<bool>.broadcast();
  
  WSService({required this.baseUrl});
  
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  
  bool get isConnected => _isConnected;
  
  // 连接WebSocket
  Future<void> connect() async {
    try {
      if (_channel != null) {
        await disconnect();
      }
      
      final wsUrl = 'ws://$baseUrl/ws/app';
      _channel = IOWebSocketChannel.connect(wsUrl);
      
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );
      
      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStatusController.add(true);
      _startHeartbeat();
      _setupLifecycleListener();
      
      print('WebSocket connected to $wsUrl');
    } catch (e) {
      print('WebSocket connection error: $e');
      _handleConnectionError();
    }
  }
  
  // 断开WebSocket
  Future<void> disconnect() async {
    _stopHeartbeat();
    _cancelReconnect();
    
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
    
    _isConnected = false;
    _connectionStatusController.add(false);
    print('WebSocket disconnected');
  }
  
  // 发送消息
  void sendMessage(Map<String, dynamic> message) {
    if (!_isConnected || _channel == null) {
      print('Cannot send message: WebSocket not connected');
      return;
    }
    
    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      print('Error sending message: $e');
      _handleConnectionError();
    }
  }
  
  // 处理接收到的消息
  void _handleMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message as String);
      
      // 处理心跳响应
      if (data['type'] == 'pong') {
        print('Received pong');
        return;
      }
      
      // 将消息分发给监听器
      _messageController.add(data);
    } catch (e) {
      print('Error processing message: $e');
    }
  }
  
  // 处理错误
  void _handleError(dynamic error) {
    print('WebSocket error: $error');
    _handleConnectionError();
  }
  
  // 处理连接关闭
  void _handleDone() {
    print('WebSocket connection closed');
    _isConnected = false;
    _connectionStatusController.add(false);
    _stopHeartbeat();
    _reconnect();
  }
  
  // 处理连接错误
  void _handleConnectionError() {
    if (_isConnected) {
      _isConnected = false;
      _connectionStatusController.add(false);
      _stopHeartbeat();
      _reconnect();
    }
  }
  
  // 心跳保活
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && _channel != null) {
        sendMessage({'type': 'ping'});
        print('Sent ping');
      }
    });
  }
  
  // 停止心跳
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  // 重连逻辑
  void _reconnect() {
    _cancelReconnect();
    
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Max reconnection attempts reached');
      return;
    }
    
    final delay = _initialReconnectDelay * (1 << _reconnectAttempts);
    _reconnectAttempts++;
    
    print('Attempting to reconnect in ${delay.inSeconds} seconds... (Attempt $_reconnectAttempts/$_maxReconnectAttempts)');
    
    _reconnectTimer = Timer(delay, () {
      print('Reconnecting...');
      connect();
    });
  }
  
  // 取消重连
  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
  
  // 监听App生命周期
  void _setupLifecycleListener() {
    WidgetsBinding.instance.addObserver(_LifecycleObserver(
      onResume: () {
        if (!_isConnected) {
          print('App resumed, reconnecting WebSocket...');
          connect();
        }
      },
      onPause: () {
        if (_isConnected) {
          print('App paused, disconnecting WebSocket...');
          disconnect();
        }
      },
    ));
  }
  
  void dispose() {
    disconnect();
    _messageController.close();
    _connectionStatusController.close();
    WidgetsBinding.instance.removeObserver(_LifecycleObserver(onResume: () {}, onPause: () {}));
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  final VoidCallback onPause;
  
  _LifecycleObserver({required this.onResume, required this.onPause});
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onResume();
        break;
      case AppLifecycleState.paused:
        onPause();
        break;
      default:
        break;
    }
  }
}