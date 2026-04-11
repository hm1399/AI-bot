import 'package:flutter/material.dart';

import '../../theme/linear_tokens.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({
    required this.onSend,
    required this.onVoiceTap,
    required this.enabled,
    required this.voiceReady,
    required this.voiceTooltip,
    this.embedded = false,
    super.key,
  });

  final Future<void> Function(String text) onSend;
  final Future<void> Function() onVoiceTap;
  final bool enabled;
  final bool voiceReady;
  final String voiceTooltip;
  final bool embedded;

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
    if (!widget.enabled || text.isEmpty || _sending) {
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
    final disabledHint =
        'This conversation is archived. Restore it from Sessions to continue.';
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(top: widget.embedded ? 0 : LinearSpacing.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: chrome.surface,
            borderRadius: widget.embedded
                ? BorderRadius.zero
                : LinearRadius.card,
            border: widget.embedded
                ? null
                : Border.all(color: chrome.borderStandard),
          ),
          child: Padding(
            padding: const EdgeInsets.all(LinearSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!widget.enabled) ...<Widget>[
                  Text(
                    disabledHint,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: chrome.warning),
                  ),
                  const SizedBox(height: LinearSpacing.sm),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        enabled: widget.enabled,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: widget.enabled
                              ? 'Ask, plan, or schedule something'
                              : 'Restore archived conversation to reply',
                          border: const OutlineInputBorder(
                            borderRadius: LinearRadius.control,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: LinearSpacing.sm,
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(width: LinearSpacing.sm),
                    Tooltip(
                      message: widget.voiceTooltip,
                      child: OutlinedButton.icon(
                        onPressed: widget.enabled ? widget.onVoiceTap : null,
                        icon: Icon(
                          widget.enabled && widget.voiceReady
                              ? Icons.mic_external_on_outlined
                              : Icons.info_outline,
                          size: 16,
                        ),
                        label: Text(widget.voiceReady ? 'Voice' : 'Status'),
                      ),
                    ),
                    const SizedBox(width: LinearSpacing.xs),
                    FilledButton.icon(
                      onPressed: !widget.enabled || _sending ? null : _submit,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward, size: 16),
                      label: const Text('Send'),
                    ),
                  ],
                ),
                const SizedBox(height: LinearSpacing.xs),
                Text(
                  widget.voiceReady
                      ? 'Voice stays device-first. Use the microphone shortcut when you need a spoken turn.'
                      : widget.voiceTooltip,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: chrome.textQuaternary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
