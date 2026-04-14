import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/events/event_model.dart';
import '../../models/planning/planning_agenda_entry_model.dart';
import '../../models/planning/planning_conflict_model.dart';
import '../../models/planning/planning_editor_models.dart';
import '../../models/reminders/reminder_model.dart';
import '../../models/tasks/task_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../../widgets/planning/planning_editor_dialog.dart';
import '../../widgets/tasks/task_filter_bar.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool showCompletedTasks = true;
  bool showDueSoonOnly = false;
  String taskPriorityFilter = 'all';
  bool showTodayEventsOnly = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    Future<void>.microtask(_refreshWorkbench);
  }

  Future<void> _refreshWorkbench() async {
    final controller = ref.read(appControllerProvider.notifier);
    await controller.loadTasks();
    await controller.loadEvents();
    await controller.loadReminders();
    await controller.refreshPlanningWorkbench();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final agendaDataset = ref.watch(planningAgendaDatasetProvider);
    final chrome = context.linear;
    final filteredTasks = _filterTasks(state.tasks);
    final filteredEvents = _filterEvents(state.events);
    final filteredReminders = _filterReminders(state.reminders);
    final workbench = _PlanningWorkbenchSnapshot.fromSources(
      state: state,
      agendaDataset: agendaDataset,
      visibleTasks: filteredTasks,
      visibleEvents: filteredEvents,
      visibleReminders: filteredReminders,
      showTodayOnly: showTodayEventsOnly,
    );

    return RefreshIndicator(
      onRefresh: _refreshWorkbench,
      child: ListView(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Planning Workbench',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton.filledTonal(
                onPressed: _refreshWorkbench,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.sm),
          Text(
            'Keep AI follow-up tasks editable here, while the calendar lane stays focused on agenda-facing events and reminder movement.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.lg),
          _TodayOverviewPanel(snapshot: workbench),
          const SizedBox(height: LinearSpacing.lg),
          TaskFilterBar(
            searchController: _searchController,
            chips: _buildWorkbenchChips(),
          ),
          const SizedBox(height: LinearSpacing.md),
          Wrap(
            spacing: LinearSpacing.sm,
            runSpacing: LinearSpacing.sm,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => showPlanningEditorDialog(
                  context,
                  kind: PlanningEditorKind.task,
                  origin: 'tasks_manual',
                ),
                icon: const Icon(Icons.add_task_outlined),
                label: const Text('Add Task'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showPlanningEditorDialog(
                  context,
                  kind: PlanningEditorKind.event,
                  origin: 'tasks_manual',
                ),
                icon: const Icon(Icons.event_outlined),
                label: const Text('Add Event'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showPlanningEditorDialog(
                  context,
                  kind: PlanningEditorKind.reminder,
                  origin: 'tasks_manual',
                ),
                icon: const Icon(Icons.alarm_add_outlined),
                label: const Text('Add Reminder'),
              ),
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.layers_clear_outlined),
                label: const Text('Clear Filters'),
              ),
            ],
          ),
          ..._buildStatusPanels(state),
          const SizedBox(height: LinearSpacing.lg),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final stacked = constraints.maxWidth < 1080;
              final taskPanel = _TaskWorkbenchPanel(
                tasks: filteredTasks,
                status: state.tasksStatus,
                onEdit: (TaskModel task) => showPlanningEditorDialog(
                  context,
                  kind: PlanningEditorKind.task,
                  origin: 'tasks_manual',
                  task: task,
                ),
                onToggleComplete: (TaskModel task) => controller.updateTask(
                  task.copyWith(completed: !task.completed),
                ),
                onDelete: (TaskModel task) => _confirmDelete(
                  context,
                  title: 'Delete task?',
                  onConfirm: () => controller.deleteTask(task.id),
                ),
              );
              final timelinePanel = _TimelinePanel(
                entries: workbench.timelineEntries,
                status: workbench.planningStatus,
                message: workbench.planningMessage,
                onEditEntry: (_TimelineEntry entry) =>
                    _openTimelineEntryEditor(context, entry),
                onDeleteEntry: (_TimelineEntry entry) =>
                    _deleteTimelineEntry(context, entry),
              );
              final sideColumn = Column(
                children: <Widget>[
                  timelinePanel,
                  const SizedBox(height: LinearSpacing.md),
                  _RemindersAndConflictsPanel(
                    reminders: filteredReminders,
                    conflicts: workbench.conflicts,
                    planningStatus: workbench.planningStatus,
                    planningMessage: workbench.planningMessage,
                    degraded: workbench.degraded,
                    hiddenReminderCount: workbench.hiddenReminderCount,
                    onAddReminder: () => showPlanningEditorDialog(
                      context,
                      kind: PlanningEditorKind.reminder,
                      origin: 'tasks_manual',
                    ),
                    onEditReminder: (ReminderModel reminder) =>
                        showPlanningEditorDialog(
                          context,
                          kind: PlanningEditorKind.reminder,
                          origin: 'tasks_manual',
                          reminder: reminder,
                        ),
                    onDeleteReminder: (ReminderModel reminder) =>
                        _confirmDelete(
                          context,
                          title: 'Delete reminder?',
                          onConfirm: () =>
                              controller.deleteReminder(reminder.id),
                        ),
                    onOpenConflictParticipant:
                        (PlanningConflictParticipantModel participant) =>
                            _openConflictParticipantEditor(
                              context,
                              participant,
                            ),
                  ),
                ],
              );

              if (stacked) {
                return Column(
                  children: <Widget>[
                    taskPanel,
                    const SizedBox(height: LinearSpacing.md),
                    sideColumn,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 6, child: taskPanel),
                  const SizedBox(width: LinearSpacing.md),
                  Expanded(flex: 5, child: sideColumn),
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

  void _clearFilters() {
    setState(() {
      showCompletedTasks = true;
      showDueSoonOnly = false;
      taskPriorityFilter = 'all';
      showTodayEventsOnly = false;
      _searchController.clear();
    });
  }

  List<TaskModel> _filterTasks(List<TaskModel> tasks) {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    return tasks.where((TaskModel task) {
      if (!showCompletedTasks && task.completed) {
        return false;
      }
      if (taskPriorityFilter != 'all' && task.priority != taskPriorityFilter) {
        return false;
      }
      if (showDueSoonOnly) {
        final due = task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
        if (due == null || due.isAfter(now.add(const Duration(days: 2)))) {
          return false;
        }
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack =
          '${task.title} ${task.description ?? ''} ${task.priority}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  List<EventModel> _filterEvents(List<EventModel> events) {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    return events.where((EventModel event) {
      if (showTodayEventsOnly) {
        final start = DateTime.tryParse(event.startAt);
        if (start == null || !_sameDay(start, now)) {
          return false;
        }
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack =
          '${event.title} ${event.description ?? ''} ${event.location ?? ''}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  List<ReminderModel> _filterReminders(List<ReminderModel> reminders) {
    final query = _searchController.text.trim().toLowerCase();
    return reminders.where((ReminderModel reminder) {
      if (query.isEmpty) {
        return true;
      }
      final haystack =
          '${reminder.title} ${reminder.message} ${reminder.time} ${reminder.repeat}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  List<Widget> _buildWorkbenchChips() {
    return <Widget>[
      FilterChip(
        label: const Text('Show Completed'),
        selected: showCompletedTasks,
        onSelected: (bool value) {
          setState(() => showCompletedTasks = value);
        },
      ),
      FilterChip(
        label: const Text('Due Soon'),
        selected: showDueSoonOnly,
        onSelected: (bool value) {
          setState(() => showDueSoonOnly = value);
        },
      ),
      FilterChip(
        label: const Text('Timeline Today Only'),
        selected: showTodayEventsOnly,
        onSelected: (bool value) {
          setState(() => showTodayEventsOnly = value);
        },
      ),
      ChoiceChip(
        label: const Text('All Priority'),
        selected: taskPriorityFilter == 'all',
        onSelected: (_) => setState(() => taskPriorityFilter = 'all'),
      ),
      ChoiceChip(
        label: const Text('High'),
        selected: taskPriorityFilter == 'high',
        onSelected: (_) => setState(() => taskPriorityFilter = 'high'),
      ),
      ChoiceChip(
        label: const Text('Medium'),
        selected: taskPriorityFilter == 'medium',
        onSelected: (_) => setState(() => taskPriorityFilter = 'medium'),
      ),
      ChoiceChip(
        label: const Text('Low'),
        selected: taskPriorityFilter == 'low',
        onSelected: (_) => setState(() => taskPriorityFilter = 'low'),
      ),
    ];
  }

  List<Widget> _buildStatusPanels(AppState state) {
    final widgets = <Widget>[];
    if (state.tasksMessage != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: LinearSpacing.md),
          child: _StatusPanel(
            title: 'Tasks',
            status: state.tasksStatus,
            message: state.tasksMessage!,
          ),
        ),
      );
    }
    if (state.eventsMessage != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: LinearSpacing.md),
          child: _StatusPanel(
            title: 'Events',
            status: state.eventsStatus,
            message: state.eventsMessage!,
          ),
        ),
      );
    }
    if (state.remindersMessage != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: LinearSpacing.md),
          child: _StatusPanel(
            title: 'Reminders',
            status: state.remindersStatus,
            message: state.remindersMessage!,
          ),
        ),
      );
    }
    if (state.planningWorkbenchMessage != null &&
        state.planningWorkbenchStatus != FeatureStatus.ready &&
        state.planningWorkbenchStatus != FeatureStatus.demo) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: LinearSpacing.md),
          child: _StatusPanel(
            title: 'Planning',
            status: state.planningWorkbenchStatus,
            message: state.planningWorkbenchMessage!,
          ),
        ),
      );
    }
    return widgets;
  }

  Future<void> _openTimelineEntryEditor(
    BuildContext context,
    _TimelineEntry entry,
  ) {
    switch (entry.kind) {
      case PlanningAgendaEntryKind.task:
        if (entry.task == null) {
          return Future<void>.value();
        }
        return showPlanningEditorDialog(
          context,
          kind: PlanningEditorKind.task,
          origin: 'tasks_manual',
          task: entry.task,
        );
      case PlanningAgendaEntryKind.event:
        if (entry.event == null) {
          return Future<void>.value();
        }
        return showPlanningEditorDialog(
          context,
          kind: PlanningEditorKind.event,
          origin: 'tasks_manual',
          event: entry.event,
        );
      case PlanningAgendaEntryKind.reminder:
        if (entry.reminder == null) {
          return Future<void>.value();
        }
        return showPlanningEditorDialog(
          context,
          kind: PlanningEditorKind.reminder,
          origin: 'tasks_manual',
          reminder: entry.reminder,
        );
    }
  }

  Future<void> _deleteTimelineEntry(
    BuildContext context,
    _TimelineEntry entry,
  ) {
    final controller = ref.read(appControllerProvider.notifier);
    switch (entry.kind) {
      case PlanningAgendaEntryKind.task:
        if (entry.task == null) {
          return Future<void>.value();
        }
        return _confirmDelete(
          context,
          title: 'Delete task?',
          onConfirm: () => controller.deleteTask(entry.task!.id),
        );
      case PlanningAgendaEntryKind.event:
        if (entry.event == null) {
          return Future<void>.value();
        }
        return _confirmDelete(
          context,
          title: 'Delete event?',
          onConfirm: () => controller.deleteEvent(entry.event!.id),
        );
      case PlanningAgendaEntryKind.reminder:
        if (entry.reminder == null) {
          return Future<void>.value();
        }
        return _confirmDelete(
          context,
          title: 'Delete reminder?',
          onConfirm: () => controller.deleteReminder(entry.reminder!.id),
        );
    }
  }

  Future<void> _openConflictParticipantEditor(
    BuildContext context,
    PlanningConflictParticipantModel participant,
  ) {
    switch (participant.kind) {
      case 'task':
        final task = _taskById(participant.id);
        if (task == null) {
          return Future<void>.value();
        }
        return showPlanningEditorDialog(
          context,
          kind: PlanningEditorKind.task,
          origin: 'tasks_manual',
          task: task,
        );
      case 'event':
        final event = _eventById(participant.id);
        if (event == null) {
          return Future<void>.value();
        }
        return showPlanningEditorDialog(
          context,
          kind: PlanningEditorKind.event,
          origin: 'tasks_manual',
          event: event,
        );
      case 'reminder':
        final reminder = _reminderById(participant.id);
        if (reminder == null) {
          return Future<void>.value();
        }
        return showPlanningEditorDialog(
          context,
          kind: PlanningEditorKind.reminder,
          origin: 'tasks_manual',
          reminder: reminder,
        );
      default:
        return Future<void>.value();
    }
  }

  TaskModel? _taskById(String id) {
    for (final item in ref.read(appControllerProvider).tasks) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  EventModel? _eventById(String id) {
    for (final item in ref.read(appControllerProvider).events) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  ReminderModel? _reminderById(String id) {
    for (final item in ref.read(appControllerProvider).reminders) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<void> _confirmDelete(
    BuildContext context, {
    required String title,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await onConfirm();
    }
  }
}

class _TodayOverviewPanel extends StatelessWidget {
  const _TodayOverviewPanel({required this.snapshot});

  final _PlanningWorkbenchSnapshot snapshot;

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
            'Today Overview',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            snapshot.headline,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          Wrap(
            spacing: LinearSpacing.md,
            runSpacing: LinearSpacing.md,
            children: <Widget>[
              _OverviewMetric(
                label: 'Open Tasks',
                value: '${snapshot.openTasks}',
                detail: '${snapshot.completedTasks} completed',
              ),
              _OverviewMetric(
                label: 'Due Today',
                value: '${snapshot.dueToday}',
                detail: snapshot.nextTimelineTime ?? 'No time locked yet',
              ),
              _OverviewMetric(
                label: 'Next Timeline',
                value: snapshot.nextTimelineLabel,
                detail: snapshot.nextTimelineTime ?? 'No timeline items',
              ),
              _OverviewMetric(
                label: 'Reminders & Conflicts',
                value:
                    '${snapshot.activeReminders} reminders · ${snapshot.conflictCount} conflicts',
                detail: snapshot.degraded
                    ? 'Planning is degraded; some reminder slots may be withheld until next trigger data arrives.'
                    : 'Shared editor is available from Tasks and Agenda.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.all(LinearSpacing.md),
        decoration: BoxDecoration(
          color: chrome.panel,
          borderRadius: LinearRadius.card,
          border: Border.all(color: chrome.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: chrome.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              detail,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskWorkbenchPanel extends StatelessWidget {
  const _TaskWorkbenchPanel({
    required this.tasks,
    required this.status,
    required this.onEdit,
    required this.onToggleComplete,
    required this.onDelete,
  });

  final List<TaskModel> tasks;
  final FeatureStatus status;
  final ValueChanged<TaskModel> onEdit;
  final ValueChanged<TaskModel> onToggleComplete;
  final ValueChanged<TaskModel> onDelete;

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
          Text('Tasks', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Keep the editable task list visible while the rest of the workbench shows supporting planning context.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          if (tasks.any((TaskModel task) => task.isAssistantOwned)) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _MetaTag(
                  label:
                      '${tasks.where((TaskModel task) => task.isAssistantOwned).length} AI task(s)',
                ),
                const _MetaTag(label: 'Assistant-owned items stay in Tasks'),
              ],
            ),
          ],
          const SizedBox(height: LinearSpacing.md),
          _TaskList(
            status: status,
            tasks: tasks,
            onEdit: onEdit,
            onToggleComplete: onToggleComplete,
            onDelete: onDelete,
          ),
        ],
      ),
    );
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({
    required this.entries,
    required this.status,
    required this.message,
    required this.onEditEntry,
    required this.onDeleteEntry,
  });

  final List<_TimelineEntry> entries;
  final FeatureStatus status;
  final String? message;
  final ValueChanged<_TimelineEntry> onEditEntry;
  final ValueChanged<_TimelineEntry> onDeleteEntry;

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
            'Calendar & Timeline',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'This lane stays focused on agenda-facing events and visible reminder slots instead of every assistant follow-up task.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          if (message != null &&
              status != FeatureStatus.ready &&
              status != FeatureStatus.demo) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _StatusPanel(title: 'Planning', status: status, message: message!),
          ],
          const SizedBox(height: LinearSpacing.md),
          if (entries.isEmpty)
            _EmptyPanel(
              message: status == FeatureStatus.notReady
                  ? 'Planning timeline is not ready yet. Dated local items will appear once available.'
                  : 'No timeline items match the current filters.',
            )
          else
            Column(
              children: entries.map((_TimelineEntry entry) {
                return _TimelineEntryCard(
                  entry: entry,
                  onEdit: () => onEditEntry(entry),
                  onDelete: () => onDeleteEntry(entry),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _TimelineEntryCard extends StatelessWidget {
  const _TimelineEntryCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final _TimelineEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      margin: const EdgeInsets.only(bottom: LinearSpacing.sm),
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(entry.icon, size: 18, color: chrome.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Edit ${entry.kindLabel.toLowerCase()}',
                onPressed: entry.canEdit ? onEdit : null,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete ${entry.kindLabel.toLowerCase()}',
                onPressed: entry.canEdit ? onDelete : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _MetaTag(label: entry.kindLabel),
              _MetaTag(label: entry.timeLabel),
              if (entry.secondaryLabel?.isNotEmpty == true)
                _MetaTag(label: entry.secondaryLabel!),
              if (entry.sourceLabel?.isNotEmpty == true)
                _MetaTag(label: entry.sourceLabel!),
              if (entry.bundleLabel?.isNotEmpty == true)
                _MetaTag(label: 'Bundle ${entry.bundleLabel!}'),
            ],
          ),
          if (entry.description?.isNotEmpty == true) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              entry.description!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemindersAndConflictsPanel extends StatelessWidget {
  const _RemindersAndConflictsPanel({
    required this.reminders,
    required this.conflicts,
    required this.planningStatus,
    required this.planningMessage,
    required this.degraded,
    required this.hiddenReminderCount,
    required this.onAddReminder,
    required this.onEditReminder,
    required this.onDeleteReminder,
    required this.onOpenConflictParticipant,
  });

  final List<ReminderModel> reminders;
  final List<_ConflictItem> conflicts;
  final FeatureStatus planningStatus;
  final String? planningMessage;
  final bool degraded;
  final int hiddenReminderCount;
  final VoidCallback onAddReminder;
  final ValueChanged<ReminderModel> onEditReminder;
  final ValueChanged<ReminderModel> onDeleteReminder;
  final ValueChanged<PlanningConflictParticipantModel>
  onOpenConflictParticipant;

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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Reminders & Conflicts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onAddReminder,
                icon: const Icon(Icons.alarm_add_outlined, size: 16),
                label: const Text('Add Reminder'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Reminder editing now uses the shared planning dialog, while conflicts continue to reflect backend planning when available.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          if (planningMessage != null &&
              planningStatus != FeatureStatus.ready &&
              planningStatus != FeatureStatus.demo) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _StatusPanel(
              title: 'Planning',
              status: planningStatus,
              message: planningMessage!,
            ),
          ],
          if (degraded || hiddenReminderCount > 0) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _StatusPanel(
              title: 'Reminder Visibility',
              status: FeatureStatus.notReady,
              message: hiddenReminderCount > 0
                  ? '$hiddenReminderCount reminder(s) stay out of Agenda because they are hidden delivery reminders or still lack a reliable next trigger day.'
                  : 'Planning timeline is degraded. Reminder slots may be incomplete.',
            ),
          ],
          const SizedBox(height: LinearSpacing.md),
          Text('Reminders', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (reminders.isEmpty)
            const _EmptyPanel(
              message: 'No reminders match the current filters.',
            )
          else
            Column(children: reminders.map((_buildReminderCard)).toList()),
          const SizedBox(height: LinearSpacing.md),
          Text('Conflicts', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (conflicts.isEmpty)
            const _EmptyPanel(message: 'No conflicts detected right now.')
          else
            Column(children: conflicts.map((_buildConflictCard)).toList()),
        ],
      ),
    );
  }

  Widget _buildReminderCard(ReminderModel reminder) {
    return Builder(
      builder: (BuildContext context) {
        final chrome = context.linear;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: LinearSpacing.sm),
          padding: const EdgeInsets.all(LinearSpacing.md),
          decoration: BoxDecoration(
            color: chrome.panel,
            borderRadius: LinearRadius.card,
            border: Border.all(color: chrome.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      reminder.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  _MetaTag(label: reminder.enabled ? 'Enabled' : 'Paused'),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _MetaTag(label: reminder.time),
                  _MetaTag(label: reminder.repeat),
                  if (reminder.status != null && reminder.status!.isNotEmpty)
                    _MetaTag(label: reminder.status!),
                  if (reminder.nextTriggerAt != null)
                    _MetaTag(label: 'Next ${reminder.nextTriggerAt!}'),
                  if (reminder.snoozedUntil != null)
                    _MetaTag(label: 'Snoozed ${reminder.snoozedUntil!}'),
                  if (_planningSourceLabel(
                        createdVia: reminder.createdVia,
                        sourceChannel: reminder.sourceChannel,
                      )
                      case final String sourceLabel)
                    _MetaTag(label: sourceLabel),
                  if (reminder.bundleId?.isNotEmpty == true)
                    _MetaTag(label: 'Bundle ${reminder.bundleId!}'),
                ],
              ),
              if (reminder.message.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  reminder.message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: () => onEditReminder(reminder),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    onPressed: () => onDeleteReminder(reminder),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConflictCard(_ConflictItem conflict) {
    return Builder(
      builder: (BuildContext context) {
        final chrome = context.linear;
        final borderColor = conflict.severity == 'danger'
            ? chrome.danger
            : chrome.warning;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: LinearSpacing.sm),
          padding: const EdgeInsets.all(LinearSpacing.md),
          decoration: BoxDecoration(
            color: borderColor.withValues(alpha: 0.08),
            borderRadius: LinearRadius.card,
            border: Border.all(color: borderColor.withValues(alpha: 0.36)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                conflict.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (conflict.detail?.isNotEmpty == true) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  conflict.detail!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
                ),
              ],
              if (conflict.participants.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: conflict.participants.map((
                    PlanningConflictParticipantModel participant,
                  ) {
                    return TextButton.icon(
                      onPressed: () => onOpenConflictParticipant(participant),
                      icon: Icon(_iconForEntryType(participant.kind), size: 16),
                      label: Text('Open ${participant.title}'),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.title,
    required this.status,
    required this.message,
  });

  final String title;
  final FeatureStatus status;
  final String message;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final color = status == FeatureStatus.notReady
        ? chrome.warning.withValues(alpha: 0.08)
        : status == FeatureStatus.error
        ? chrome.danger.withValues(alpha: 0.08)
        : chrome.panel;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: color,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(message),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.status,
    required this.tasks,
    required this.onEdit,
    required this.onToggleComplete,
    required this.onDelete,
  });

  final FeatureStatus status;
  final List<TaskModel> tasks;
  final ValueChanged<TaskModel> onEdit;
  final ValueChanged<TaskModel> onToggleComplete;
  final ValueChanged<TaskModel> onDelete;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return _EmptyPanel(
        message: status == FeatureStatus.notReady
            ? 'The backend task endpoint is not ready yet.'
            : 'No tasks match the current filters.',
      );
    }
    return Column(
      children: tasks.map((TaskModel task) {
        return _TaskRow(
          task: task,
          onEdit: () => onEdit(task),
          onToggleComplete: () => onToggleComplete(task),
          onDelete: () => onDelete(task),
        );
      }).toList(),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onEdit,
    required this.onToggleComplete,
    required this.onDelete,
  });

  final TaskModel task;
  final VoidCallback onEdit;
  final VoidCallback onToggleComplete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      margin: const EdgeInsets.only(bottom: LinearSpacing.sm),
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (task.isAssistantOwned) ...<Widget>[
                const SizedBox(width: 8),
                const Chip(label: Text('AI Task')),
              ],
              Chip(label: Text(task.priority)),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Edit task',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: task.completed ? 'Mark incomplete' : 'Mark complete',
                onPressed: onToggleComplete,
                icon: Icon(
                  task.completed
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                ),
              ),
              IconButton(
                tooltip: 'Delete task',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            task.description?.isEmpty == false
                ? task.description!
                : 'No description',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _MetaTag(label: task.completed ? 'Completed' : 'Open'),
              if (task.dueAt?.isNotEmpty == true)
                _MetaTag(label: 'Due ${_formatDateTime(task.dueDateTime)}'),
              _MetaTag(label: task.ownerLabel),
              _MetaTag(label: task.planningSurfaceLabel),
              if (task.deliveryModeLabel != null)
                _MetaTag(label: task.deliveryModeLabel!),
              if (_planningSourceLabel(
                    createdVia: task.createdVia,
                    sourceChannel: task.sourceChannel,
                  )
                  case final String sourceLabel)
                _MetaTag(label: sourceLabel),
              if (task.bundleId?.isNotEmpty == true)
                _MetaTag(label: 'Bundle ${task.bundleId!}'),
              _MetaTag(
                label: 'Updated ${_formatDateTime(task.updatedDateTime)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.pill,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: chrome.textTertiary),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.xl),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: chrome.textTertiary),
      ),
    );
  }
}

class _PlanningWorkbenchSnapshot {
  const _PlanningWorkbenchSnapshot({
    required this.headline,
    required this.openTasks,
    required this.completedTasks,
    required this.dueToday,
    required this.activeReminders,
    required this.conflictCount,
    required this.nextTimelineLabel,
    required this.nextTimelineTime,
    required this.timelineEntries,
    required this.conflicts,
    required this.planningStatus,
    required this.planningMessage,
    required this.degraded,
    required this.hiddenReminderCount,
  });

  final String headline;
  final int openTasks;
  final int completedTasks;
  final int dueToday;
  final int activeReminders;
  final int conflictCount;
  final String nextTimelineLabel;
  final String? nextTimelineTime;
  final List<_TimelineEntry> timelineEntries;
  final List<_ConflictItem> conflicts;
  final FeatureStatus planningStatus;
  final String? planningMessage;
  final bool degraded;
  final int hiddenReminderCount;

  factory _PlanningWorkbenchSnapshot.fromSources({
    required AppState state,
    required PlanningAgendaDataset agendaDataset,
    required List<TaskModel> visibleTasks,
    required List<EventModel> visibleEvents,
    required List<ReminderModel> visibleReminders,
    required bool showTodayOnly,
  }) {
    final overview = state.planningOverview;
    final now = DateTime.now();
    final visibleTaskIds = visibleTasks
        .map((TaskModel item) => item.id)
        .toSet();
    final visibleEventIds = visibleEvents
        .map((EventModel item) => item.id)
        .toSet();
    final visibleReminderIds = visibleReminders
        .map((ReminderModel item) => item.id)
        .toSet();

    final timelineEntries = agendaDataset.entries
        .where((PlanningAgendaEntryModel entry) {
          final matchesFilter = switch (entry.kind) {
            PlanningAgendaEntryKind.task => visibleTaskIds.contains(
              entry.resourceId,
            ),
            PlanningAgendaEntryKind.event => visibleEventIds.contains(
              entry.resourceId,
            ),
            PlanningAgendaEntryKind.reminder => visibleReminderIds.contains(
              entry.resourceId,
            ),
          };
          if (!matchesFilter) {
            return false;
          }
          if (showTodayOnly && !_sameDay(entry.scheduledAt, now)) {
            return false;
          }
          return true;
        })
        .map(_TimelineEntry.fromAgendaEntry)
        .toList();
    timelineEntries.sort(_sortTimelineEntries);

    final conflicts = state.planningConflicts
        .map(_ConflictItem.fromModel)
        .toList();

    final nextEntry = timelineEntries.isEmpty ? null : timelineEntries.first;
    final openTaskFallback = state.tasks
        .where((TaskModel item) => !item.completed)
        .length;
    final completedTaskFallback = state.tasks
        .where((TaskModel item) => item.completed)
        .length;
    final dueTodayFallback = state.tasks.where((TaskModel task) {
      if (task.completed || task.dueAt == null) {
        return false;
      }
      final dueAt = DateTime.tryParse(task.dueAt!);
      return dueAt != null && _sameDay(dueAt, DateTime.now());
    }).length;
    final activeReminderFallback = state.reminders
        .where((ReminderModel item) => item.enabled)
        .length;

    return _PlanningWorkbenchSnapshot(
      headline: state.planningTimelineReady
          ? overview?.nextItemTitle != null
                ? 'Backend planning is synced. Next up: ${overview!.nextItemTitle}.'
                : 'Backend planning is synced and ready for editing.'
          : state.planningWorkbenchStatus == FeatureStatus.notReady
          ? 'Planning timeline is not ready on this backend. The workbench is explicitly degraded instead of faking planning results.'
          : 'Planning timeline is still partial. Only dated local resources are shown until backend planning arrives.',
      openTasks: overview?.pendingTaskCount ?? openTaskFallback,
      completedTasks: overview?.completedTaskCount ?? completedTaskFallback,
      dueToday: dueTodayFallback,
      activeReminders: overview?.activeReminderCount ?? activeReminderFallback,
      conflictCount: overview?.conflictCount ?? conflicts.length,
      nextTimelineLabel:
          overview?.nextItemTitle ??
          nextEntry?.title ??
          (agendaDataset.degraded
              ? 'Planning timeline unavailable'
              : 'No timeline items yet.'),
      nextTimelineTime: overview?.nextItemAt == null
          ? nextEntry?.timeLabel
          : _formatDateTime(DateTime.tryParse(overview!.nextItemAt!)),
      timelineEntries: timelineEntries.take(12).toList(),
      conflicts: conflicts.take(8).toList(),
      planningStatus: state.planningWorkbenchStatus,
      planningMessage: state.planningWorkbenchMessage,
      degraded: agendaDataset.degraded,
      hiddenReminderCount: agendaDataset.hiddenReminders.length,
    );
  }
}

class _TimelineEntry {
  const _TimelineEntry({
    required this.id,
    required this.kind,
    required this.kindLabel,
    required this.title,
    required this.timeLabel,
    required this.icon,
    required this.sortAt,
    this.description,
    this.secondaryLabel,
    this.sourceLabel,
    this.bundleLabel,
    this.task,
    this.event,
    this.reminder,
  });

  final String id;
  final PlanningAgendaEntryKind kind;
  final String kindLabel;
  final String title;
  final String timeLabel;
  final String? description;
  final String? secondaryLabel;
  final String? sourceLabel;
  final String? bundleLabel;
  final IconData icon;
  final DateTime? sortAt;
  final TaskModel? task;
  final EventModel? event;
  final ReminderModel? reminder;

  bool get canEdit => task != null || event != null || reminder != null;

  factory _TimelineEntry.fromAgendaEntry(PlanningAgendaEntryModel entry) {
    return _TimelineEntry(
      id: entry.id,
      kind: entry.kind,
      kindLabel: _titleCase(entry.kind.name),
      title: entry.title,
      timeLabel: switch (entry.kind) {
        PlanningAgendaEntryKind.event => _formatTimeRange(
          entry.scheduledAt,
          entry.endsAt,
        ),
        PlanningAgendaEntryKind.task =>
          'Due ${_formatDateTime(entry.scheduledAt)}',
        PlanningAgendaEntryKind.reminder =>
          'Reminder ${_formatDateTime(entry.scheduledAt)}',
      },
      description: entry.description,
      secondaryLabel: _mergeLabels(<String?>[
        entry.location,
        entry.priority,
        entry.repeat,
      ]),
      sourceLabel: _planningSourceLabel(
        createdVia: entry.createdVia,
        sourceChannel: entry.sourceChannel,
      ),
      bundleLabel: entry.bundleId,
      icon: _iconForEntryType(entry.kind.name),
      sortAt: entry.scheduledAt,
      task: entry.task,
      event: entry.event,
      reminder: entry.reminder,
    );
  }
}

class _ConflictItem {
  const _ConflictItem({
    required this.title,
    required this.detail,
    required this.severity,
    required this.participants,
  });

  final String title;
  final String? detail;
  final String severity;
  final List<PlanningConflictParticipantModel> participants;

  static _ConflictItem fromModel(PlanningConflictModel conflict) {
    final detail =
        conflict.summary ??
        (conflict.participants.isEmpty
            ? null
            : conflict.participants.map((item) => item.title).join(' · '));
    return _ConflictItem(
      title: conflict.title,
      detail: detail,
      severity: conflict.severity,
      participants: conflict.participants,
    );
  }
}

int _sortTimelineEntries(_TimelineEntry a, _TimelineEntry b) {
  final aSort = a.sortAt;
  final bSort = b.sortAt;
  if (aSort == null && bSort == null) {
    return a.title.compareTo(b.title);
  }
  if (aSort == null) {
    return 1;
  }
  if (bSort == null) {
    return -1;
  }
  return aSort.compareTo(bSort);
}

IconData _iconForEntryType(String? type) {
  switch (type) {
    case 'event':
      return Icons.event_outlined;
    case 'task':
      return Icons.task_alt_outlined;
    case 'reminder':
      return Icons.alarm_outlined;
    default:
      return Icons.timeline_outlined;
  }
}

bool _sameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _formatTimeRange(DateTime? startAt, DateTime? endAt) {
  if (startAt == null && endAt == null) {
    return 'Time not set';
  }
  if (startAt == null) {
    return 'Ends ${_formatDateTime(endAt)}';
  }
  if (endAt == null) {
    return _formatDateTime(startAt);
  }
  final sameDay = _sameDay(startAt, endAt);
  final endText = sameDay ? _formatClock(endAt) : _formatDateTime(endAt);
  return '${_formatDateTime(startAt)} → $endText';
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'Unscheduled';
  }
  final monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${monthNames[value.month - 1]} ${value.day} · ${_formatClock(value)}';
}

String _formatClock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String? _planningSourceLabel({
  required String? createdVia,
  required String? sourceChannel,
}) {
  final via = createdVia?.trim();
  if (via != null && via.isNotEmpty) {
    return switch (via.toLowerCase()) {
      'voice' => 'Voice',
      'manual' => 'Manual',
      'chat' => 'Chat',
      _ => _titleCase(via),
    };
  }

  final channel = sourceChannel?.trim();
  if (channel == null || channel.isEmpty) {
    return null;
  }
  return switch (channel.toLowerCase()) {
    'desktop_voice' => 'Voice',
    'app' => 'App',
    'whatsapp' => 'WhatsApp',
    _ => _titleCase(channel),
  };
}

String? _mergeLabels(List<String?> values) {
  final filtered = values
      .map((String? value) => value?.trim())
      .where((String? value) => value != null && value.isNotEmpty)
      .cast<String>()
      .toList();
  if (filtered.isEmpty) {
    return null;
  }
  return filtered.join(' · ');
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}
