import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../../widgets/common/status_pill.dart';
import '../../widgets/home/device_card.dart';
import '../../widgets/home/overview_stat_card.dart';
import '../../widgets/home/runtime_queue_panel.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final runtime = state.runtimeState;
    final unreadNotifications = state.notifications
        .where((item) => !item.read)
        .length;
    final chrome = context.linear;

    return RefreshIndicator(
      onRefresh: controller.refreshAll,
      child: ListView(
        children: <Widget>[
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: runtime.device.connected
                    ? 'Device Ready'
                    : 'Device Offline',
                tone: runtime.device.connected
                    ? StatusPillTone.success
                    : StatusPillTone.danger,
              ),
              StatusPill(
                label: state.capabilities.voicePipeline
                    ? 'Voice Pipeline Ready'
                    : 'Voice Pipeline Partial',
                tone: state.capabilities.voicePipeline
                    ? StatusPillTone.success
                    : StatusPillTone.warning,
              ),
              StatusPill(
                label: state.capabilities.appEvents
                    ? 'App Events Enabled'
                    : 'App Events Missing',
                tone: state.capabilities.appEvents
                    ? StatusPillTone.accent
                    : StatusPillTone.warning,
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.lg),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final stacked = constraints.maxWidth < 920;
              final quickActions = Container(
                padding: const EdgeInsets.all(LinearSpacing.md),
                decoration: BoxDecoration(
                  color: chrome.surface,
                  borderRadius: LinearRadius.card,
                  border: Border.all(color: chrome.borderStandard),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Preserve the current runtime controls, but surface them more clearly.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textTertiary,
                      ),
                    ),
                    const SizedBox(height: LinearSpacing.md),
                    Wrap(
                      spacing: LinearSpacing.sm,
                      runSpacing: LinearSpacing.sm,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: controller.speakTestPhrase,
                          icon: const Icon(Icons.volume_up_outlined, size: 16),
                          label: const Text('Speak'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: controller.stopCurrentTask,
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            size: 16,
                          ),
                          label: const Text('Stop'),
                        ),
                        OutlinedButton.icon(
                          onPressed: controller.refreshAll,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh Runtime'),
                        ),
                      ],
                    ),
                  ],
                ),
              );

              final queuePanel = RuntimeQueuePanel(
                currentTask: runtime.currentTask,
                queue: runtime.taskQueue,
              );

              if (stacked) {
                return Column(
                  children: <Widget>[
                    quickActions,
                    const SizedBox(height: LinearSpacing.md),
                    queuePanel,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 5, child: quickActions),
                  const SizedBox(width: LinearSpacing.md),
                  Expanded(flex: 4, child: queuePanel),
                ],
              );
            },
          ),
          const SizedBox(height: LinearSpacing.lg),
          Wrap(
            spacing: LinearSpacing.md,
            runSpacing: LinearSpacing.md,
            children: <Widget>[
              OverviewStatCard(
                label: 'Server',
                value: state.bootstrap?.serverVersion.isNotEmpty == true
                    ? state.bootstrap!.serverVersion
                    : 'Unknown',
                detail: state.connection.hasServer
                    ? '${state.connection.host}:${state.connection.port}'
                    : 'Not connected',
                icon: Icons.hub_outlined,
                highlight: true,
              ),
              OverviewStatCard(
                label: 'Current Task',
                value: runtime.currentTask == null
                    ? 'Idle'
                    : runtime.currentTask!.stage,
                detail:
                    runtime.currentTask?.summary ?? 'No active runtime task.',
                icon: Icons.bolt_outlined,
              ),
              OverviewStatCard(
                label: 'Notifications',
                value: '$unreadNotifications unread',
                detail:
                    'Total ${state.notifications.length} notifications in workspace.',
                icon: Icons.notifications_outlined,
              ),
              OverviewStatCard(
                label: 'Reminders',
                value:
                    '${state.reminders.where((item) => item.enabled).length} active',
                detail: 'Total ${state.reminders.length} reminders loaded.',
                icon: Icons.alarm_outlined,
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.lg),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final stacked = constraints.maxWidth < 980;
              final summaryPanel = _SummaryPanel(state: state);
              if (stacked) {
                return Column(
                  children: <Widget>[
                    DeviceCard(status: runtime.device),
                    const SizedBox(height: LinearSpacing.md),
                    summaryPanel,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: DeviceCard(status: runtime.device)),
                  const SizedBox(width: LinearSpacing.md),
                  Expanded(child: summaryPanel),
                ],
              );
            },
          ),
          if (state.globalMessage != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.lg),
            Container(
              padding: const EdgeInsets.all(LinearSpacing.md),
              decoration: BoxDecoration(
                color: chrome.panel,
                borderRadius: LinearRadius.card,
                border: Border.all(color: chrome.borderSubtle),
              ),
              child: Text(
                state.globalMessage!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final runtime = state.runtimeState;
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
          Text(
            'Workspace Summary',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: LinearSpacing.md),
          _SummaryRow(
            title: 'Todo Summary',
            value: runtime.todoSummary.enabled
                ? 'Pending ${runtime.todoSummary.pendingCount} · Overdue ${runtime.todoSummary.overdueCount}'
                : 'Todo summary is not enabled on the backend.',
          ),
          const SizedBox(height: LinearSpacing.sm),
          _SummaryRow(
            title: 'Calendar Summary',
            value: runtime.calendarSummary.enabled
                ? 'Today ${runtime.calendarSummary.todayCount} · Next ${runtime.calendarSummary.nextEventTitle ?? 'Not set'}'
                : 'Calendar summary is not enabled on the backend.',
          ),
          const SizedBox(height: LinearSpacing.sm),
          _SummaryRow(
            title: 'Capabilities',
            value:
                'Chat ${state.capabilities.chat ? 'on' : 'off'} · Device ${state.capabilities.deviceControl ? 'on' : 'off'} · Tasks ${state.capabilities.tasks ? 'on' : 'off'} · Settings ${state.capabilities.settings ? 'on' : 'off'}',
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.sm),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.control,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: chrome.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
        ],
      ),
    );
  }
}
