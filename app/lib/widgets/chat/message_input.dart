import 'package:flutter/material.dart';

import '../../theme/linear_tokens.dart';

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
    final chrome = context.linear;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(top: LinearSpacing.md),
        child: Container(
          padding: const EdgeInsets.all(LinearSpacing.md),
          decoration: BoxDecoration(
            color: chrome.surface,
            borderRadius: LinearRadius.card,
            border: Border.all(color: chrome.borderStandard),
          ),
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
              const SizedBox(width: LinearSpacing.sm),
              IconButton.filledTonal(
                tooltip: widget.voiceTooltip,
                onPressed: widget.onVoiceTap,
                icon: Icon(
                  widget.voiceReady
                      ? Icons.mic_external_on_outlined
                      : Icons.info_outline,
                ),
              ),
              const SizedBox(width: LinearSpacing.xs),
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
      ),
    );
  }
}
