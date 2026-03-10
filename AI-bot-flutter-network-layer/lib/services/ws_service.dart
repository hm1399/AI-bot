import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:provider/provider.dart';  // 假設有 Providers 如 ChatProvider
import 'package:flutter/material.dart';  // 為了 AppLifecycleState

class WsService with WidgetsBindingObserver {
  IOWebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  String? _serverUrl;  // 例如 'ws://192.168.1.100:8765/ws/app'
  bool _isConnected = false;
  bool _isBackground = false;

  // 初始化並連接
  void init(String serverUrl) {
    _serverUrl = serverUrl;
    connect();
    WidgetsBinding.instance.addObserver(this);
  }

  // 連接 WebSocket
  void connect() {
    if (_channel != null || _isBackground) return;
    try {
      _channel = IOWebSocketChannel.connect(_serverUrl!);
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          _dispatchMessage(data);  // 分發訊息
          if (data['type'] == 'pong') {
            print('Received pong');
          }
        },
        onError: (error) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
      );
      _isConnected = true;
      _startHeartbeat();
    } catch (e) {
      _handleDisconnect();
    }
  }

  // 分發訊息給 Provider
  void _dispatchMessage(Map<String, dynamic> data) {
    final type = data['type'];
    // 假設有不同 Provider，例如 ChatProvider、StatusProvider
    if (type == 'chat_response') {
      // Provider.of<ChatProvider>(context, listen: false).updateChat(data);
      // 或使用 GlobalKey / EventBus 分發
      print('Dispatching chat response: ${data['content']}');
    } else if (type == 'status_update') {
      // Provider.of<StatusProvider>(context, listen: false).updateStatus(data);
      print('Dispatching status update');
    }
    // 根據 type 擴展更多
  }

  // 心跳保活
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      } else {
        timer.cancel();
      }
    });
  }

  // 處理斷線並重連
  void _handleDisconnect() {
    _isConnected = false;
    _channel?.sink.close();
    _channel = null;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    if (!_isBackground) {
      _reconnectTimer = Timer(const Duration(seconds: 5), connect);
    }
  }

  // 送出訊息
  void sendMessage(Map<String, dynamic> data) {
    if (_isConnected) {
      _channel?.sink.add(jsonEncode(data));
    }
  }

  // App 生命週期監聽
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {  // 進入背景
      _isBackground = true;
      _handleDisconnect();
    } else if (state == AppLifecycleState.resumed) {  // 回到前台
      _isBackground = false;
      connect();
    }
  }

  // 清理
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _handleDisconnect();
  }
}
