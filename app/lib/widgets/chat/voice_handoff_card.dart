import 'package:flutter/material.dart';

import '../../providers/app_providers.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class VoiceHandoffCard extends StatelessWidget {
  const VoiceHandoffCard({required this.voice, super.key});

  final VoiceUiState voice;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Voice Handoff', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: LinearSpacing.sm),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: voice.deviceOnline ? 'Device Online' : 'Device Offline',
                tone: voice.deviceOnline
                    ? StatusPillTone.success
                    : StatusPillTone.danger,
              ),
              StatusPill(
                label: voice.desktopBridgeReady
                    ? 'Desktop Bridge Ready'
                    : 'Desktop Bridge Waiting',
                tone: voice.desktopBridgeReady
                    ? StatusPillTone.success
                    : StatusPillTone.warning,
              ),
              StatusPill(
                label: voice.deviceFeedbackReady
                    ? 'Device Feedback Ready'
                    : 'Device Feedback Missing',
                tone: voice.deviceFeedbackReady
                    ? StatusPillTone.success
                    : StatusPillTone.warning,
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.md),
          Text(voice.primaryDescription),
          const SizedBox(height: 8),
          Text(
            voice.inputModeLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: 6),
          Text(
            voice.outputModeLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          if (voice.statusMessage != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            Text(
              voice.statusMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
            ),
          ],
          if (voice.errorMessage != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            Text(
              voice.errorMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.danger),
            ),
          ],
        ],
      ),
    );
  }
}
