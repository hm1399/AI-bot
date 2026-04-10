import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/planning/planning_agenda_entry_model.dart';
import '../../models/planning/planning_editor_models.dart';
import '../../providers/app_providers.dart';
import '../../theme/linear_tokens.dart';
import '../../widgets/planning/planning_day_schedule.dart';
import '../../widgets/planning/planning_editor_dialog.dart';
import '../../widgets/planning/planning_month_calendar.dart';

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  late DateTime _selectedDay;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _visibleMonth = DateTime(now.year, now.month, 1);
    Future<void>.microtask(_refreshAgenda);
  }

  Future<void> _refreshAgenda() async {
    final controller = ref.read(appControllerProvider.notifier);
    await controller.loadTasks();
    await controller.loadEvents();
    await controller.loadReminders();
    await controller.refreshPlanningWorkbench();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final dataset = ref.watch(planningAgendaDatasetProvider);
    final chrome = context.linear;
    final dayEntries = dataset.entriesForDay(_selectedDay);

    return RefreshIndicator(
      onRefresh: _refreshAgenda,
      child: ListView(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Agenda',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton.filledTonal(
                onPressed: _refreshAgenda,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.sm),
          Text(
            'Review the month at a glance, then drill into the selected day for events, reminders, and due tasks.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.lg),
          Wrap(
            spacing: LinearSpacing.sm,
            runSpacing: LinearSpacing.sm,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => showPlanningEditorDialog(
                  context,
                  kind: PlanningEditorKind.task,
                  origin: 'agenda_manual',
                ),
                icon: const Icon(Icons.add_task_outlined),
                label: const Text('Add Task'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showPlanningEditorDialog(
                  context,
                  kind: PlanningEditorKind.event,
                  origin: 'agenda_manual',
                ),
                icon: const Icon(Icons.event_outlined),
                label: const Text('Add Event'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showPlanningEditorDialog(
                  context,
                  kind: PlanningEditorKind.reminder,
                  origin: 'agenda_manual',
                ),
                icon: const Icon(Icons.alarm_add_outlined),
                label: const Text('Add Reminder'),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.lg),
          Container(
            padding: const EdgeInsets.all(LinearSpacing.md),
            decoration: BoxDecoration(
              color: chrome.surface,
              borderRadius: LinearRadius.card,
              border: Border.all(color: chrome.borderStandard),
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final calendarWidth = _calendarWidthFor(constraints.maxWidth);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: LinearSpacing.sm,
                      runSpacing: LinearSpacing.sm,
                      children: <Widget>[
                        _SummaryPill(
                          label: 'Selected Day',
                          value: '${dayEntries.length} item(s)',
                        ),
                        _SummaryPill(
                          label: 'This Month',
                          value: '${_countMonthEntries(dataset)} scheduled',
                        ),
                        _SummaryPill(
                          label: 'Timeline',
                          value: dataset.planningReady
                              ? 'Synced'
                              : dataset.timelineStatus.name,
                        ),
                      ],
                    ),
                    const SizedBox(height: LinearSpacing.md),
                    Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: calendarWidth,
                        child: PlanningMonthCalendar(
                          visibleMonth: _visibleMonth,
                          selectedDay: _selectedDay,
                          entries: dataset.entries,
                          onMonthChanged: (DateTime value) {
                            setState(() {
                              _visibleMonth = DateTime(
                                value.year,
                                value.month,
                                1,
                              );
                            });
                          },
                          onDaySelected: (DateTime value) {
                            setState(() {
                              _selectedDay = DateTime(
                                value.year,
                                value.month,
                                value.day,
                              );
                              _visibleMonth = DateTime(
                                value.year,
                                value.month,
                                1,
                              );
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: LinearSpacing.md),
          PlanningDaySchedule(
            selectedDay: _selectedDay,
            entries: dayEntries,
            hiddenReminders: dataset.hiddenReminders,
            timelineStatus: dataset.timelineStatus,
            timelineMessage: dataset.timelineMessage,
            degraded: dataset.degraded,
            onEditEntry: _openEditorForEntry,
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

  Future<void> _openEditorForEntry(PlanningAgendaEntryModel entry) {
    switch (entry.kind) {
      case PlanningAgendaEntryKind.task:
        if (entry.task == null) {
          return Future<void>.value();
        }
        return showPlanningEditorDialog(
          context,
          kind: PlanningEditorKind.task,
          origin: 'agenda_manual',
          task: entry.task,
        );
      case PlanningAgendaEntryKind.event:
        if (entry.event == null) {
          return Future<void>.value();
        }
        return showPlanningEditorDialog(
          context,
          kind: PlanningEditorKind.event,
          origin: 'agenda_manual',
          event: entry.event,
        );
      case PlanningAgendaEntryKind.reminder:
        if (entry.reminder == null) {
          return Future<void>.value();
        }
        return showPlanningEditorDialog(
          context,
          kind: PlanningEditorKind.reminder,
          origin: 'agenda_manual',
          reminder: entry.reminder,
        );
    }
  }

  int _countMonthEntries(PlanningAgendaDataset dataset) {
    return dataset.entries.where((PlanningAgendaEntryModel entry) {
      return entry.scheduledAt.year == _visibleMonth.year &&
          entry.scheduledAt.month == _visibleMonth.month;
    }).length;
  }

  double _calendarWidthFor(double availableWidth) {
    if (availableWidth >= 900) {
      return availableWidth * 0.58;
    }
    if (availableWidth >= 720) {
      return availableWidth * 0.74;
    }
    return availableWidth;
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.control,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
