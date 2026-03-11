import 'package:flutter/material.dart';

class MessageInput extends StatefulWidget {
  final Function(String) onSend;
  final bool isVoiceEnabled;
  final Function()? onVoiceButtonPressed;
  
  const MessageInput({
    Key? key,
    required this.onSend,
    this.isVoiceEnabled = false,
    this.onVoiceButtonPressed,
  }) : super(key: key);
  
  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _textController = TextEditingController();
  bool _isComposing = false;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          if (widget.isVoiceEnabled)
            IconButton(
              icon: const Icon(Icons.mic),
              onPressed: widget.onVoiceButtonPressed,
              color: Theme.of(context).colorScheme.primary,
            ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20.0),
              ),
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: '输入消息...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 10.0,
                  ),
                ),
                onChanged: (text) {
                  setState(() {
                    _isComposing = text.trim().isNotEmpty;
                  });
                },
                onSubmitted: _isComposing ? _handleSend : null,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _isComposing ? _handleSend : null,
            color: _isComposing
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
          ),
        ],
      ),
    );
  }
  
  void _handleSend([String? text]) {
    final messageText = text ?? _textController.text;
    if (messageText.trim().isNotEmpty) {
      widget.onSend(messageText.trim());
      _textController.clear();
      setState(() {
        _isComposing = false;
      });
    }
  }
  
  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}