import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/events/event_model.dart';
import '../../models/reminders/reminder_model.dart';
import '../../models/tasks/task_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
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
    final chrome = context.linear;
    final filteredTasks = _filterTasks(state.tasks);
    final filteredEvents = _filterEvents(state.events);
    final filteredReminders = _filterReminders(state.reminders);
    final workbench = _PlanningWorkbenchSnapshot.fromSources(
      state: state,
      controller: controller,
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
            'Keep task and event maintenance in one place, while surfacing today focus, timeline movement, reminders, and conflicts.',
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
                onPressed: () => _openTaskEditor(context),
                icon: const Icon(Icons.add_task_outlined),
                label: const Text('Add Task'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openEventEditor(context),
                icon: const Icon(Icons.event_outlined),
                label: const Text('Add Event'),
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
                onEdit: (TaskModel task) =>
                    _openTaskEditor(context, existing: task),
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
                status: state.eventsStatus,
                onEditEvent: (EventModel event) =>
                    _openEventEditor(context, existing: event),
                onDeleteEvent: (EventModel event) => _confirmDelete(
                  context,
                  title: 'Delete event?',
                  onConfirm: () => controller.deleteEvent(event.id),
                ),
              );
              final sideColumn = Column(
                children: <Widget>[
                  timelinePanel,
                  const SizedBox(height: LinearSpacing.md),
                  _RemindersAndConflictsPanel(
                    reminders: filteredReminders,
                    conflicts: workbench.conflicts,
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
    return widgets;
  }

  Future<void> _openTaskEditor(
    BuildContext context, {
    TaskModel? existing,
  }) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final dueAtController = TextEditingController(text: existing?.dueAt ?? '');
    var priority = existing?.priority ?? 'medium';
    var completed = existing?.completed ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Task' : 'Edit Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: titleController,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: priority,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem(value: 'high', child: Text('High')),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('Medium'),
                        ),
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                      ],
                      onChanged: (String? value) {
                        if (value != null) {
                          setState(() => priority = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dueAtController,
                      decoration: const InputDecoration(
                        labelText: 'Due At',
                        hintText: '2026-04-06T09:00:00',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: completed,
                      onChanged: (bool value) {
                        setState(() => completed = value);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Completed'),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      final task = TaskModel(
        id:
            existing?.id ??
            'task_local_${DateTime.now().millisecondsSinceEpoch}',
        title: titleController.text.trim(),
        description: descriptionController.text.trim().isEmpty
            ? null
            : descriptionController.text.trim(),
        priority: priority,
        completed: completed,
        dueAt: dueAtController.text.trim().isEmpty
            ? null
            : dueAtController.text.trim(),
        createdAt: existing?.createdAt ?? DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      if (existing == null) {
        await ref.read(appControllerProvider.notifier).createTask(task);
      } else {
        await ref.read(appControllerProvider.notifier).updateTask(task);
      }
    }

    titleController.dispose();
    descriptionController.dispose();
    dueAtController.dispose();
  }

  Future<void> _openEventEditor(
    BuildContext context, {
    EventModel? existing,
  }) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final startAtController = TextEditingController(
      text: existing?.startAt ?? '',
    );
    final endAtController = TextEditingController(text: existing?.endAt ?? '');
    final locationController = TextEditingController(
      text: existing?.location ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(existing == null ? 'Add Event' : 'Edit Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: startAtController,
                  decoration: const InputDecoration(
                    labelText: 'Start At',
                    hintText: '2026-04-06T09:00:00',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endAtController,
                  decoration: const InputDecoration(
                    labelText: 'End At',
                    hintText: '2026-04-06T10:00:00',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved == true) {
      final event = EventModel(
        id:
            existing?.id ??
            'event_local_${DateTime.now().millisecondsSinceEpoch}',
        title: titleController.text.trim(),
        description: descriptionController.text.trim().isEmpty
            ? null
            : descriptionController.text.trim(),
        startAt: startAtController.text.trim(),
        endAt: endAtController.text.trim(),
        location: locationController.text.trim().isEmpty
            ? null
            : locationController.text.trim(),
        createdAt: existing?.createdAt ?? DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      if (existing == null) {
        await ref.read(appControllerProvider.notifier).createEvent(event);
      } else {
        await ref.read(appControllerProvider.notifier).updateEvent(event);
      }
    }

    titleController.dispose();
    descriptionController.dispose();
    startAtController.dispose();
    endAtController.dispose();
    locationController.dispose();
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
                detail: 'Reminders stay editable in Control Center.',
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
    required this.onEditEvent,
    required this.onDeleteEvent,
  });

  final List<_TimelineEntry> entries;
  final FeatureStatus status;
  final ValueChanged<EventModel> onEditEvent;
  final ValueChanged<EventModel> onDeleteEvent;

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
            'Events stay editable here, while task due times and reminder slots appear beside them in a single ordered agenda.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          if (entries.isEmpty)
            _EmptyPanel(
              message: status == FeatureStatus.notReady
                  ? 'The backend event endpoint is not ready yet.'
                  : 'No timeline items match the current filters.',
            )
          else
            Column(
              children: entries.map((_TimelineEntry entry) {
                return _TimelineEntryCard(
                  entry: entry,
                  onEditEvent: entry.event == null
                      ? null
                      : () => onEditEvent(entry.event!),
                  onDeleteEvent: entry.event == null
                      ? null
                      : () => onDeleteEvent(entry.event!),
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
    required this.onEditEvent,
    required this.onDeleteEvent,
  });

  final _TimelineEntry entry;
  final VoidCallback? onEditEvent;
  final VoidCallback? onDeleteEvent;

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
              if (onEditEvent != null)
                IconButton(
                  tooltip: 'Edit event',
                  onPressed: onEditEvent,
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (onDeleteEvent != null)
                IconButton(
                  tooltip: 'Delete event',
                  onPressed: onDeleteEvent,
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
  });

  final List<ReminderModel> reminders;
  final List<_ConflictItem> conflicts;

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
            'Reminders & Conflicts',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Reminder editing remains in Control Center for compatibility. This panel keeps the operational view visible inside planning.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
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
                _MetaTag(
                  label:
                      'Due ${_formatDateTime(DateTime.tryParse(task.dueAt!))}',
                ),
              if (_planningSourceLabel(
                    createdVia: task.createdVia,
                    sourceChannel: task.sourceChannel,
                  )
                  case final String sourceLabel)
                _MetaTag(label: sourceLabel),
              if (task.bundleId?.isNotEmpty == true)
                _MetaTag(label: 'Bundle ${task.bundleId!}'),
              _MetaTag(
                label:
                    'Updated ${_formatDateTime(DateTime.tryParse(task.updatedAt ?? task.createdAt))}',
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

  factory _PlanningWorkbenchSnapshot.fromSources({
    required AppState state,
    required Object controller,
    required List<TaskModel> visibleTasks,
    required List<EventModel> visibleEvents,
    required List<ReminderModel> visibleReminders,
    required bool showTodayOnly,
  }) {
    final overview = _coerceStringMap(
      _readPlanningProperty(
        state: state,
        controller: controller,
        name: 'planningOverview',
      ),
    );
    final rawTimeline = _coerceList(
      _readPlanningProperty(
        state: state,
        controller: controller,
        name: 'planningTimeline',
      ),
    );
    final rawConflicts = _coerceList(
      _readPlanningProperty(
        state: state,
        controller: controller,
        name: 'planningConflicts',
      ),
    );

    final timelineEntries = rawTimeline.isNotEmpty
        ? rawTimeline
              .map(
                (Object? raw) => _TimelineEntry.fromDynamic(
                  raw,
                  events: visibleEvents,
                  tasks: visibleTasks,
                  reminders: visibleReminders,
                ),
              )
              .whereType<_TimelineEntry>()
              .toList()
        : _buildFallbackTimeline(
            tasks: visibleTasks,
            events: visibleEvents,
            reminders: visibleReminders,
            showTodayOnly: showTodayOnly,
          );
    timelineEntries.sort(_sortTimelineEntries);

    final conflicts = rawConflicts.isNotEmpty
        ? rawConflicts
              .map((_ConflictItem.fromDynamic))
              .whereType<_ConflictItem>()
              .toList()
        : _deriveConflicts(
            tasks: visibleTasks,
            events: visibleEvents,
            reminders: visibleReminders,
          );

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
      headline:
          _lookupString(overview, <String>[
            'headline',
            'today_summary',
            'todaySummary',
            'summary',
          ]) ??
          'Derived planning summary stays visible even before provider-side planning data arrives.',
      openTasks:
          _lookupInt(overview, <String>['open_tasks', 'openTaskCount']) ??
          _lookupInt(overview, <String>['pending_count', 'pendingCount']) ??
          openTaskFallback,
      completedTasks:
          _lookupInt(overview, <String>[
            'completed_tasks',
            'completedTaskCount',
          ]) ??
          completedTaskFallback,
      dueToday:
          _lookupInt(overview, <String>['due_today', 'dueTodayCount']) ??
          dueTodayFallback,
      activeReminders:
          _lookupInt(overview, <String>[
            'active_reminders',
            'activeReminderCount',
          ]) ??
          activeReminderFallback,
      conflictCount:
          _lookupInt(overview, <String>['conflict_count', 'conflictCount']) ??
          conflicts.length,
      nextTimelineLabel:
          _lookupString(overview, <String>[
            'next_item_title',
            'nextItemTitle',
            'next_event_title',
            'nextEventTitle',
          ]) ??
          nextEntry?.title ??
          'No timeline items yet.',
      nextTimelineTime:
          _lookupString(overview, <String>[
            'next_item_time',
            'nextItemTime',
            'next_event_time',
            'nextEventTime',
          ]) ??
          nextEntry?.timeLabel,
      timelineEntries: timelineEntries.take(12).toList(),
      conflicts: conflicts.take(8).toList(),
    );
  }
}

class _TimelineEntry {
  const _TimelineEntry({
    required this.id,
    required this.kindLabel,
    required this.title,
    required this.timeLabel,
    required this.icon,
    required this.sortAt,
    this.description,
    this.secondaryLabel,
    this.sourceLabel,
    this.bundleLabel,
    this.event,
  });

  final String id;
  final String kindLabel;
  final String title;
  final String timeLabel;
  final String? description;
  final String? secondaryLabel;
  final String? sourceLabel;
  final String? bundleLabel;
  final IconData icon;
  final DateTime? sortAt;
  final EventModel? event;

  factory _TimelineEntry.fromDynamic(
    Object? raw, {
    required List<EventModel> events,
    required List<TaskModel> tasks,
    required List<ReminderModel> reminders,
  }) {
    final map = _coerceStringMap(raw);
    if (map.isEmpty) {
      final fallbackTitle = raw?.toString().trim();
      return _TimelineEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        kindLabel: 'Timeline',
        title: fallbackTitle == null || fallbackTitle.isEmpty
            ? 'Planning item'
            : fallbackTitle,
        timeLabel: 'Unscheduled',
        icon: Icons.timeline_outlined,
        sortAt: null,
      );
    }
    final resourceId = _lookupString(map, <String>[
      'resource_id',
      'resourceId',
      'event_id',
      'eventId',
      'task_id',
      'taskId',
      'id',
    ]);
    final resourceType =
        _lookupString(map, <String>[
          'resource_type',
          'resourceType',
          'type',
          'kind',
        ]) ??
        _inferEntryType(map);
    EventModel? matchedEvent;
    TaskModel? matchedTask;
    ReminderModel? matchedReminder;
    if (resourceId != null) {
      for (final event in events) {
        if (event.id == resourceId) {
          matchedEvent = event;
          break;
        }
      }
      for (final task in tasks) {
        if (task.id == resourceId) {
          matchedTask = task;
          break;
        }
      }
      for (final reminder in reminders) {
        if (reminder.id == resourceId) {
          matchedReminder = reminder;
          break;
        }
      }
    }
    final startAt =
        _lookupDateTime(map, <String>['start_at', 'startAt', 'time', 'at']) ??
        _lookupDateTime(map, <String>['normalized_time', 'normalizedTime']) ??
        _lookupDateTime(map, <String>['scheduled_for', 'scheduledFor']) ??
        DateTime.tryParse(matchedEvent?.startAt ?? '') ??
        DateTime.tryParse(matchedTask?.dueAt ?? '');

    return _TimelineEntry(
      id: resourceId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      kindLabel: _titleCase(resourceType),
      title:
          _lookupString(map, <String>['title', 'summary', 'label', 'name']) ??
          matchedEvent?.title ??
          matchedTask?.title ??
          matchedReminder?.title ??
          'Planning item',
      timeLabel:
          _lookupString(map, <String>[
            'time_label',
            'timeLabel',
            'display_time',
            'displayTime',
          ]) ??
          _lookupString(map, <String>[
            'normalized_time',
            'normalizedTime',
            'scheduled_for',
            'scheduledFor',
          ]) ??
          _formatDateTime(startAt),
      description:
          _lookupString(map, <String>[
            'description',
            'detail',
            'message',
            'reason',
          ]) ??
          matchedEvent?.description ??
          matchedTask?.description ??
          matchedReminder?.message,
      secondaryLabel: _mergeLabels(<String?>[
        _lookupString(map, <String>['location', 'secondary_label']),
        matchedEvent?.location,
        matchedReminder?.repeat,
      ]),
      sourceLabel: _planningSourceLabel(
        createdVia:
            _lookupString(map, <String>['created_via', 'createdVia']) ??
            matchedEvent?.createdVia ??
            matchedTask?.createdVia ??
            matchedReminder?.createdVia,
        sourceChannel:
            _lookupString(map, <String>['source_channel', 'sourceChannel']) ??
            matchedEvent?.sourceChannel ??
            matchedTask?.sourceChannel ??
            matchedReminder?.sourceChannel,
      ),
      bundleLabel:
          _lookupString(map, <String>['bundle_id', 'bundleId']) ??
          matchedEvent?.bundleId ??
          matchedTask?.bundleId ??
          matchedReminder?.bundleId,
      icon: _iconForEntryType(resourceType),
      sortAt: startAt,
      event: matchedEvent,
    );
  }
}

class _ConflictItem {
  const _ConflictItem({
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String title;
  final String? detail;
  final String severity;

  static _ConflictItem? fromDynamic(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      return _ConflictItem(title: raw, detail: null, severity: 'warning');
    }
    final map = _coerceStringMap(raw);
    if (map.isEmpty) {
      return null;
    }
    return _ConflictItem(
      title:
          _lookupString(map, <String>[
            'title',
            'summary',
            'message',
            'reason',
          ]) ??
          'Conflict detected',
      detail: _lookupString(map, <String>['detail', 'description', 'context']),
      severity:
          _lookupString(map, <String>['severity', 'level', 'tone']) ??
          'warning',
    );
  }
}

List<_TimelineEntry> _buildFallbackTimeline({
  required List<TaskModel> tasks,
  required List<EventModel> events,
  required List<ReminderModel> reminders,
  required bool showTodayOnly,
}) {
  final now = DateTime.now();
  final entries = <_TimelineEntry>[
    ...events.map((EventModel event) {
      final startAt = DateTime.tryParse(event.startAt);
      return _TimelineEntry(
        id: event.id,
        kindLabel: 'Event',
        title: event.title,
        timeLabel: _formatTimeRange(
          DateTime.tryParse(event.startAt),
          DateTime.tryParse(event.endAt),
        ),
        description: event.description,
        secondaryLabel: event.location,
        sourceLabel: _planningSourceLabel(
          createdVia: event.createdVia,
          sourceChannel: event.sourceChannel,
        ),
        bundleLabel: event.bundleId,
        icon: Icons.event_outlined,
        sortAt: startAt,
        event: event,
      );
    }),
    ...tasks
        .where((TaskModel task) => !task.completed && task.dueAt != null)
        .map((TaskModel task) {
          final dueAt = DateTime.tryParse(task.dueAt!);
          return _TimelineEntry(
            id: task.id,
            kindLabel: 'Task Due',
            title: task.title,
            timeLabel: 'Due ${_formatDateTime(dueAt)}',
            description: task.description,
            secondaryLabel: task.priority,
            sourceLabel: _planningSourceLabel(
              createdVia: task.createdVia,
              sourceChannel: task.sourceChannel,
            ),
            bundleLabel: task.bundleId,
            icon: Icons.task_alt_outlined,
            sortAt: dueAt,
          );
        }),
    ...reminders.where((ReminderModel reminder) => reminder.enabled).map((
      ReminderModel reminder,
    ) {
      final reminderTime = _reminderDateTimeForToday(reminder.time);
      return _TimelineEntry(
        id: reminder.id,
        kindLabel: 'Reminder',
        title: reminder.title,
        timeLabel: reminderTime == null
            ? reminder.time
            : _formatDateTime(reminderTime),
        description: reminder.message,
        secondaryLabel: reminder.repeat,
        sourceLabel: _planningSourceLabel(
          createdVia: reminder.createdVia,
          sourceChannel: reminder.sourceChannel,
        ),
        bundleLabel: reminder.bundleId,
        icon: Icons.alarm_outlined,
        sortAt: reminderTime,
      );
    }),
  ];

  final filtered = showTodayOnly
      ? entries.where((_TimelineEntry entry) {
          if (entry.sortAt == null) {
            return false;
          }
          return _sameDay(entry.sortAt!, now);
        }).toList()
      : entries;
  filtered.sort(_sortTimelineEntries);
  return filtered;
}

List<_ConflictItem> _deriveConflicts({
  required List<TaskModel> tasks,
  required List<EventModel> events,
  required List<ReminderModel> reminders,
}) {
  final now = DateTime.now();
  final conflicts = <_ConflictItem>[];
  final overdueTasks = tasks.where((TaskModel task) {
    if (task.completed || task.dueAt == null) {
      return false;
    }
    final dueAt = DateTime.tryParse(task.dueAt!);
    return dueAt != null && dueAt.isBefore(now);
  });

  for (final task in overdueTasks.take(3)) {
    conflicts.add(
      _ConflictItem(
        title: 'Overdue task: ${task.title}',
        detail: task.dueAt == null
            ? null
            : 'Due ${_formatDateTime(DateTime.tryParse(task.dueAt!))}',
        severity: 'warning',
      ),
    );
  }

  final eventSpans =
      events
          .map((EventModel event) {
            final startAt = DateTime.tryParse(event.startAt);
            final endAt = DateTime.tryParse(event.endAt);
            if (startAt == null || endAt == null) {
              return null;
            }
            return (event: event, startAt: startAt, endAt: endAt);
          })
          .whereType<({EventModel event, DateTime startAt, DateTime endAt})>()
          .toList()
        ..sort(
          (
            ({EventModel event, DateTime startAt, DateTime endAt}) a,
            ({EventModel event, DateTime startAt, DateTime endAt}) b,
          ) => a.startAt.compareTo(b.startAt),
        );

  for (var index = 0; index < eventSpans.length - 1; index += 1) {
    final current = eventSpans[index];
    final next = eventSpans[index + 1];
    if (next.startAt.isBefore(current.endAt)) {
      conflicts.add(
        _ConflictItem(
          title: 'Event overlap',
          detail:
              '${current.event.title} overlaps ${next.event.title} around ${_formatDateTime(next.startAt)}.',
          severity: 'danger',
        ),
      );
    }
  }

  for (final reminder in reminders.where(
    (ReminderModel item) => item.enabled,
  )) {
    final reminderTime = _reminderDateTimeForToday(reminder.time);
    if (reminderTime == null) {
      continue;
    }
    for (final event in eventSpans) {
      final startsSoon =
          reminderTime.isAfter(
            event.startAt.subtract(const Duration(minutes: 20)),
          ) &&
          reminderTime.isBefore(event.endAt.add(const Duration(minutes: 20)));
      if (startsSoon) {
        conflicts.add(
          _ConflictItem(
            title: 'Reminder may clash with event',
            detail:
                '${reminder.title} is set for ${_formatDateTime(reminderTime)} while ${event.event.title} is on the calendar.',
            severity: 'warning',
          ),
        );
        break;
      }
    }
  }

  return conflicts;
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

DateTime? _lookupDateTime(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

String _inferEntryType(Map<String, dynamic> map) {
  if (map.containsKey('event_id') || map['kind'] == 'event') {
    return 'event';
  }
  if (map.containsKey('task_id') || map['kind'] == 'task') {
    return 'task';
  }
  if (map.containsKey('reminder_id') || map['kind'] == 'reminder') {
    return 'reminder';
  }
  return 'timeline';
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

DateTime? _reminderDateTimeForToday(String raw) {
  final parts = raw.split(':');
  if (parts.length < 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
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
