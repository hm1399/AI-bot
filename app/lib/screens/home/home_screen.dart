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
    final planning = _HomePlanningSnapshot.fromSources(
      state: state,
      controller: controller,
    );

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
          _PlanningHighlightsPanel(snapshot: planning),
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
    final experience = state.currentExperience;
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
          const SizedBox(height: LinearSpacing.sm),
          _SummaryRow(
            title: 'Experience',
            value:
                '${experience.sceneLabel} · ${experience.personaLabel} · ${experience.physicalInteraction.readinessLabel}',
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

class _PlanningHighlightsPanel extends StatelessWidget {
  const _PlanningHighlightsPanel({required this.snapshot});

  final _HomePlanningSnapshot snapshot;

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
          Text(
            'Planning Highlights',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            snapshot.todaySummary,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          _SummaryRow(
            title: 'Next Timeline Item',
            value: snapshot.nextTimelineSummary,
          ),
          const SizedBox(height: LinearSpacing.sm),
          _SummaryRow(
            title: 'Reminders & Conflicts',
            value:
                '${snapshot.activeReminders} active reminders · ${snapshot.conflictCount} conflicts flagged',
          ),
          if (snapshot.highlights.isNotEmpty) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            Wrap(
              spacing: LinearSpacing.xs,
              runSpacing: LinearSpacing.xs,
              children: snapshot.highlights
                  .map(
                    (String item) => Chip(
                      label: Text(item),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomePlanningSnapshot {
  const _HomePlanningSnapshot({
    required this.todaySummary,
    required this.nextTimelineSummary,
    required this.activeReminders,
    required this.conflictCount,
    required this.highlights,
  });

  final String todaySummary;
  final String nextTimelineSummary;
  final int activeReminders;
  final int conflictCount;
  final List<String> highlights;

  factory _HomePlanningSnapshot.fromSources({
    required AppState state,
    required Object controller,
  }) {
    final overview = _coerceStringMap(
      _readPlanningProperty(
        state: state,
        controller: controller,
        name: 'planningOverview',
      ),
    );
    final timeline = _coerceList(
      _readPlanningProperty(
        state: state,
        controller: controller,
        name: 'planningTimeline',
      ),
    );
    final conflicts = _coerceList(
      _readPlanningProperty(
        state: state,
        controller: controller,
        name: 'planningConflicts',
      ),
    );
    final openTasks = state.tasks.where((item) => !item.completed).length;
    final dueToday = state.tasks.where((task) {
      if (task.completed || task.dueAt == null) {
        return false;
      }
      final dueAt = DateTime.tryParse(task.dueAt!);
      final now = DateTime.now();
      return dueAt != null &&
          dueAt.year == now.year &&
          dueAt.month == now.month &&
          dueAt.day == now.day;
    }).length;
    final activeReminders =
        _lookupInt(overview, <String>[
          'active_reminders',
          'activeReminderCount',
        ]) ??
        state.reminders.where((item) => item.enabled).length;
    final conflictCount =
        _lookupInt(overview, <String>['conflict_count', 'conflictCount']) ??
        conflicts.length;
    final nextLabel =
        _lookupString(overview, <String>[
          'next_item_title',
          'nextItemTitle',
          'next_event_title',
          'nextEventTitle',
        ]) ??
        _deriveNextTimelineLabel(timeline, state);
    final nextTime =
        _lookupString(overview, <String>[
          'next_item_time',
          'nextItemTime',
          'next_event_time',
          'nextEventTime',
        ]) ??
        _deriveNextTimelineTime(timeline, state);
    final highlights = _coerceList(overview['highlights'])
        .map((Object? item) => item?.toString().trim() ?? '')
        .where((String item) => item.isNotEmpty)
        .take(4)
        .toList();

    if (highlights.isEmpty) {
      highlights.add('Open tasks: $openTasks');
      highlights.add('Due today: $dueToday');
      if (nextLabel.isNotEmpty) {
        highlights.add('Next: $nextLabel');
      }
    }

    return _HomePlanningSnapshot(
      todaySummary:
          _lookupString(overview, <String>[
            'today_summary',
            'todaySummary',
            'summary',
            'headline',
          ]) ??
          'Derived summary: $openTasks open tasks, $dueToday due today, $activeReminders active reminders.',
      nextTimelineSummary: nextTime == null || nextTime.isEmpty
          ? nextLabel
          : '$nextLabel · $nextTime',
      activeReminders: activeReminders,
      conflictCount: conflictCount,
      highlights: highlights,
    );
  }
}

Object? _readPlanningProperty({
  required AppState state,
  required Object controller,
  required String name,
}) {
  Object? readFrom(Object target) {
    try {
      final dynamic dynamicTarget = target;
      switch (name) {
        case 'planningOverview':
          return dynamicTarget.planningOverview;
        case 'planningTimeline':
          return dynamicTarget.planningTimeline;
        case 'planningConflicts':
          return dynamicTarget.planningConflicts;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  return readFrom(state) ?? readFrom(controller);
}

Map<String, dynamic> _coerceStringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map<String, dynamic>(
      (Object? key, Object? item) => MapEntry(key.toString(), item),
    );
  }
  return <String, dynamic>{};
}

List<Object?> _coerceList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

String? _lookupString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num || value is bool) {
      return value.toString();
    }
  }
  return null;
}

int? _lookupInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

String _deriveNextTimelineLabel(List<Object?> timeline, AppState state) {
  for (final item in timeline) {
    final map = _coerceStringMap(item);
    final label = _lookupString(map, <String>['title', 'summary', 'label']);
    if (label != null && label.isNotEmpty) {
      return label;
    }
  }
  final upcomingEvents = state.events.toList()
    ..sort((a, b) => a.startAt.compareTo(b.startAt));
  return upcomingEvents.isEmpty
      ? 'No timeline items yet.'
      : upcomingEvents.first.title;
}

String? _deriveNextTimelineTime(List<Object?> timeline, AppState state) {
  for (final item in timeline) {
    final map = _coerceStringMap(item);
    final time = _lookupString(map, <String>[
      'time_label',
      'timeLabel',
      'display_time',
      'displayTime',
      'normalized_time',
      'normalizedTime',
      'scheduled_for',
      'scheduledFor',
    ]);
    if (time != null && time.isNotEmpty) {
      return time;
    }
  }
  if (state.events.isEmpty) {
    return null;
  }
  return state.events.first.startAt;
}
