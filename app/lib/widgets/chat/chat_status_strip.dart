import 'package:flutter/material.dart';

import '../../models/chat/session_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class ChatStatusStrip extends StatelessWidget {
  const ChatStatusStrip({
    required this.state,
    required this.voice,
    required this.activeSession,
    this.embedded = false,
    super.key,
  });

  final AppState state;
  final VoiceUiState voice;
  final SessionModel? activeSession;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: embedded ? Colors.transparent : chrome.panel,
        borderRadius: embedded ? BorderRadius.zero : LinearRadius.card,
        border: embedded ? null : Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: state.isDemoMode
                    ? 'Demo Mode'
                    : state.eventStreamConnected
                    ? 'Events Live'
                    : 'Events Reconnecting',
                tone: state.isDemoMode
                    ? StatusPillTone.accent
                    : state.eventStreamConnected
                    ? StatusPillTone.success
                    : StatusPillTone.warning,
              ),
              if (activeSession != null)
                StatusPill(
                  label: '${activeSession!.messageCount} messages',
                  icon: Icons.chat_bubble_outline,
                ),
              StatusPill(
                label: voice.deviceOnline ? 'Device Online' : 'Device Offline',
                tone: voice.deviceOnline
                    ? StatusPillTone.success
                    : StatusPillTone.danger,
              ),
              StatusPill(
                label: voice.desktopBridgeReady
                    ? 'Bridge Ready'
                    : 'Bridge Waiting',
                tone: voice.desktopBridgeReady
                    ? StatusPillTone.success
                    : StatusPillTone.warning,
              ),
              if (activeSession?.archived == true)
                const StatusPill(
                  label: 'Archived',
                  tone: StatusPillTone.warning,
                  icon: Icons.archive_outlined,
                ),
            ],
          ),
          const SizedBox(height: LinearSpacing.sm),
          Text(
            voice.primaryDescription,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            voice.statusMessage ?? voice.bridgeDescription,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: chrome.textQuaternary),
          ),
          if (voice.errorMessage != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              voice.errorMessage!,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: chrome.danger),
            ),
          ],
        ],
      ),
    );
  }
}
