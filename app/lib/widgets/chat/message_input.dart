import 'package:flutter/material.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({
    required this.onSend,
    required this.onVoiceTap,
    required this.voiceReady,
    required this.voiceTooltip,
    super.key,
  });

  final Future<void> Function(String text) onSend;
  final Future<void> Function() onVoiceTap;
  final bool voiceReady;
  final String voiceTooltip;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _controller.clear();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Send a backend-driven message',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: widget.voiceTooltip,
              onPressed: widget.onVoiceTap,
              icon: Icon(
                widget.voiceReady
                    ? Icons.mic_external_on_outlined
                    : Icons.info_outline,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
