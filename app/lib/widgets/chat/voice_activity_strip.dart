import 'package:flutter/material.dart';

import '../../models/voice/voice_activity_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class VoiceActivityStrip extends StatelessWidget {
  const VoiceActivityStrip({
    required this.activity,
    this.embedded = true,
    super.key,
  });

  final VoiceActivityModel activity;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (!activity.shouldRenderStrip) {
      return const SizedBox.shrink();
    }

    final chrome = context.linear;
    final updatedLabel = _updatedLabel(activity.updatedDateTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.sm),
      decoration: BoxDecoration(
        color: embedded ? chrome.surface : chrome.panel,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: LinearSpacing.xs,
                  runSpacing: LinearSpacing.xs,
                  children: <Widget>[
                    StatusPill(
                      label: activity.displayStateLabel,
                      tone: _toneFor(activity),
                      icon: _iconFor(activity),
                    ),
                    if (activity.hasTranscript)
                      const StatusPill(
                        label: 'Transcript',
                        icon: Icons.hearing_outlined,
                      ),
                    if (activity.hasResponse)
                      const StatusPill(
                        label: 'Response',
                        icon: Icons.auto_awesome_outlined,
                      ),
                    if (activity.hasError)
                      const StatusPill(
                        label: 'Error',
                        tone: StatusPillTone.danger,
                        icon: Icons.error_outline,
                      ),
                  ],
                ),
              ),
              if (updatedLabel != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: LinearSpacing.sm,
                    top: 2,
                  ),
                  child: Text(
                    updatedLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: chrome.textQuaternary,
                    ),
                  ),
                ),
            ],
          ),
          if (activity.hasTranscript) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            _ActivitySnippet(label: 'Heard', text: activity.lastTranscript!),
          ],
          if (activity.hasResponse) ...<Widget>[
            const SizedBox(height: LinearSpacing.xs),
            _ActivitySnippet(label: 'Reply', text: activity.lastResponse!),
          ],
          if (activity.hasError) ...<Widget>[
            const SizedBox(height: LinearSpacing.xs),
            _ActivitySnippet(
              label: 'Error',
              text: activity.lastError!,
              accentColor: chrome.danger,
            ),
          ],
          if (activity.hasIdentifiers) ...<Widget>[
            const SizedBox(height: LinearSpacing.xs),
            Text(
              _buildContextLine(activity),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: chrome.textQuaternary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivitySnippet extends StatelessWidget {
  const _ActivitySnippet({
    required this.label,
    required this.text,
    this.accentColor,
  });

  final String label;
  final String text;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final tone = accentColor ?? chrome.textSecondary;

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '$label: ',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: chrome.textQuaternary),
          ),
          TextSpan(
            text: text.trim(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone),
          ),
        ],
      ),
    );
  }
}

StatusPillTone _toneFor(VoiceActivityModel activity) {
  if (activity.hasError) {
    return StatusPillTone.danger;
  }
  if (activity.isActive) {
    return StatusPillTone.accent;
  }
  if (activity.hasResponse) {
    return StatusPillTone.success;
  }
  return StatusPillTone.neutral;
}

IconData _iconFor(VoiceActivityModel activity) {
  if (activity.hasError) {
    return Icons.error_outline;
  }
  return switch (activity.state) {
    'capturing' || 'listening' => Icons.mic_none_rounded,
    'transcribing' => Icons.graphic_eq_rounded,
    'thinking' => Icons.hourglass_bottom_rounded,
    'responding' || 'speaking' => Icons.volume_up_outlined,
    _ => Icons.hearing_outlined,
  };
}

String? _updatedLabel(DateTime? updatedAt) {
  if (updatedAt == null) {
    return null;
  }
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(updatedAt.hour)}:${pad(updatedAt.minute)}:${pad(updatedAt.second)}';
}

String _buildContextLine(VoiceActivityModel activity) {
  final parts = <String>[
    if (activity.sessionId case final String sessionId
        when sessionId.trim().isNotEmpty)
      'session ${sessionId.trim()}',
    if (activity.taskId case final String taskId when taskId.trim().isNotEmpty)
      'task ${taskId.trim()}',
  ];
  return parts.join(' · ');
}
