enum MessageSender { device, app }

class Message {
  final String id;
  final String text;
  final MessageSender sender;
  final DateTime timestamp;
  final Map<String, dynamic>? toolResult;

  Message({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.toolResult,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      text: json['text'],
      sender: json['sender'] == 'device' ? MessageSender.device : MessageSender.app,
      timestamp: DateTime.parse(json['timestamp']),
      toolResult: json['toolResult'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'sender': sender == MessageSender.device ? 'device' : 'app',
      'timestamp': timestamp.toIso8601String(),
      'toolResult': toolResult,
    };
  }
}