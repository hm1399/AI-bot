enum MessageType {
  text,
  system,
  toolResult,
  error
}

enum MessageSource {
  device,
  app
}

class Message {
  final String id;
  final String content;
  final MessageType type;
  final MessageSource source;
  final DateTime timestamp;
  
  Message({
    required this.id,
    required this.content,
    required this.type,
    required this.source,
    required this.timestamp
  });
  
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      content: json['content'] as String,
      type: _parseMessageType(json['type'] as String),
      source: _parseMessageSource(json['source'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'type': _messageTypeToString(type),
      'source': _messageSourceToString(source),
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  static MessageType _parseMessageType(String type) {
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
  
  static String _messageTypeToString(MessageType type) {
    switch (type) {
      case MessageType.text:
        return 'text';
      case MessageType.system:
        return 'system';
      case MessageType.toolResult:
        return 'toolResult';
      case MessageType.error:
        return 'error';
    }
  }
  
  static MessageSource _parseMessageSource(String source) {
    return source == 'device' ? MessageSource.device : MessageSource.app;
  }
  
  static String _messageSourceToString(MessageSource source) {
    return source == MessageSource.device ? 'device' : 'app';
  }
}