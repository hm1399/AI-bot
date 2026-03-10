import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/ws_service.dart';
import '../services/api_service.dart';

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final wsService = ref.watch(wsServiceProvider);
  final apiService = ref.watch(apiServiceProvider);
  return ChatNotifier(wsService, apiService);
});

class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  
  ChatState({
    required this.messages,
    this.isLoading = false,
    this.error
  });
  
  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final WSService _wsService;
  final ApiService _apiService;
  final _uuid = Uuid();
  
  ChatNotifier(this._wsService, this._apiService) 
    : super(ChatState(messages: [])) {
    _loadHistory();
    _setupListeners();
  }
  
  // 加载历史消息
  Future<void> _loadHistory() async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final messages = await _apiService.getHistory();
      state = state.copyWith(messages: messages, isLoading: false);
    } catch (e) {
      print('Error loading chat history: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to load history');
    }
  }
  
  // 发送消息
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    
    try {
      // 创建本地消息
      final message = Message(
        id: _uuid.v4(),
        content: content,
        type: MessageType.text,
        source: MessageSource.app,
        timestamp: DateTime.now(),
      );
      
      // 立即添加到UI
      state = state.copyWith(
        messages: [...state.messages, message],
        error: null,
      );
      
      // 发送到服务器
      await _apiService.sendChatMessage(content);
      
      // 也通过WebSocket发送
      _wsService.sendMessage({
        'type': 'chat',
        'content': content,
        'messageId': message.id,
      });
    } catch (e) {
      print('Error sending message: $e');
      state = state.copyWith(error: 'Failed to send message');
      
      // 移除失败的消息
      final updatedMessages = state.messages.where((m) => 
        m.source != MessageSource.app || m.timestamp != DateTime.now()
      ).toList();
      state = state.copyWith(messages: updatedMessages);
    }
  }
  
  // 添加消息
  void addMessage(Message message) {
    // 检查消息是否已存在
    final exists = state.messages.any((m) => m.id == message.id);
    if (!exists) {
      state = state.copyWith(
        messages: [...state.messages, message],
        error: null,
      );
    }
  }
  
  // 清除消息
  void clearMessages() {
    state = state.copyWith(messages: []);
  }
  
  // 设置WebSocket监听器
  void _setupListeners() {
    _wsService.messageStream.listen((data) {
      if (data['type'] == 'chat' || data['type'] == 'system' || 
          data['type'] == 'toolResult' || data['type'] == 'error') {
        final message = Message(
          id: data['id'] ?? _uuid.v4(),
          content: data['content'] as String,
          type: _parseMessageType(data['type'] as String),
          source: MessageSource.device,
          timestamp: DateTime.now(),
        );
        addMessage(message);
      }
    });
  }
  
  // 解析消息类型
  MessageType _parseMessageType(String type) {
    switch (type) {
      case 'text':
        return MessageType.text;
      case 'system':
        return MessageType.system;
      case 'toolResult':
        return MessageType.toolResult;
      case 'error':
        return MessageType.error;
      default:
        return MessageType.text;
    }
  }
}

// 服务提供者
final wsServiceProvider = Provider<WSService>((ref) {
  final config = ref.watch(configProvider);
  return WSService(baseUrl: '${config.serverIp}:${config.serverPort}');
});

final apiServiceProvider = Provider<ApiService>((ref) {
  final config = ref.watch(configProvider);
  return ApiService(baseUrl: '${config.serverIp}:${config.serverPort}');
});