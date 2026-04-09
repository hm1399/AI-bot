import 'package:flutter/material.dart';

import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import 'status_pill.dart';

class AppShellHeader extends StatelessWidget {
  const AppShellHeader({
    required this.pageTitle,
    required this.state,
    required this.unreadNotifications,
    required this.onRefreshAll,
    required this.onDisconnect,
    required this.onShowConnection,
    super.key,
  });

  final String pageTitle;
  final AppState state;
  final int unreadNotifications;
  final Future<void> Function() onRefreshAll;
  final Future<void> Function() onDisconnect;
  final VoidCallback onShowConnection;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      decoration: BoxDecoration(
        color: chrome.canvas,
        border: Border(bottom: BorderSide(color: chrome.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(
        LinearSpacing.lg,
        LinearSpacing.md,
        LinearSpacing.lg,
        LinearSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final compact = constraints.maxWidth < 860;
          final content = <Widget>[
            _TitleBlock(pageTitle: pageTitle, state: state),
            const SizedBox(height: LinearSpacing.md),
            Wrap(
              spacing: LinearSpacing.xs,
              runSpacing: LinearSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _connectionPill(state),
                _eventsPill(state),
                if (state.connection.hasServer)
                  StatusPill(
                    label:
                        '${state.connection.secure ? 'https' : 'http'}://${state.connection.host}:${state.connection.port}',
                    icon: Icons.dns_outlined,
                  ),
                if (unreadNotifications > 0)
                  StatusPill(
                    label: '$unreadNotifications unread',
                    tone: StatusPillTone.warning,
                    icon: Icons.notifications_active_outlined,
                  ),
              ],
            ),
          ];

          final actions = Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            alignment: WrapAlignment.end,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onShowConnection,
                icon: const Icon(Icons.link_outlined, size: 16),
                label: const Text('Connection'),
              ),
              OutlinedButton.icon(
                onPressed: onRefreshAll,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh All'),
              ),
              OutlinedButton.icon(
                onPressed: state.isConnected ? onDisconnect : null,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Disconnect'),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ...content,
                const SizedBox(height: LinearSpacing.md),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content,
                ),
              ),
              const SizedBox(width: LinearSpacing.lg),
              actions,
            ],
          );
        },
      ),
    );
  }

  StatusPill _connectionPill(AppState state) {
    if (state.isDemoMode) {
      return const StatusPill(
        label: 'Demo Mode',
        tone: StatusPillTone.accent,
        icon: Icons.bolt_outlined,
      );
    }
    if (state.isConnected && state.eventStreamConnected) {
      return const StatusPill(
        label: 'Connected',
        tone: StatusPillTone.success,
        icon: Icons.check_circle_outline,
      );
    }
    if (state.isConnected) {
      return const StatusPill(
        label: 'Backend Live',
        tone: StatusPillTone.warning,
        icon: Icons.sync_problem_outlined,
      );
    }
    return const StatusPill(
      label: 'Disconnected',
      tone: StatusPillTone.danger,
      icon: Icons.portable_wifi_off_outlined,
    );
  }

  StatusPill _eventsPill(AppState state) {
    if (state.isDemoMode) {
      return const StatusPill(
        label: 'Local Demo Events',
        tone: StatusPillTone.accent,
        icon: Icons.stream_outlined,
      );
    }
    if (state.eventStreamConnected) {
      return const StatusPill(
        label: 'Events Live',
        tone: StatusPillTone.success,
        icon: Icons.wifi_tethering_outlined,
      );
    }
    return const StatusPill(
      label: 'Events Reconnecting',
      tone: StatusPillTone.warning,
      icon: Icons.wifi_find_outlined,
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.pageTitle, required this.state});

  final String pageTitle;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = context.linear;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          pageTitle,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 26,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          state.globalMessage ??
              'Operator workspace for runtime state, chat, tasks, control and backend settings.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: chrome.textTertiary,
          ),
        ),
      ],
    );
  }
}
