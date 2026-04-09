import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/events/event_model.dart';
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
  bool showTasks = true;
  bool showCompletedTasks = true;
  bool showDueSoonOnly = false;
  String taskPriorityFilter = 'all';
  bool showTodayEventsOnly = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    Future<void>.microtask(() async {
      await ref.read(appControllerProvider.notifier).loadTasks();
      await ref.read(appControllerProvider.notifier).loadEvents();
    });
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
    final status = showTasks ? state.tasksStatus : state.eventsStatus;
    final message = showTasks ? state.tasksMessage : state.eventsMessage;
    final filteredTasks = _filterTasks(state.tasks);
    final filteredEvents = _filterEvents(state.events);
    final chrome = context.linear;

    return RefreshIndicator(
      onRefresh: () async {
        if (showTasks) {
          await controller.loadTasks();
        } else {
          await controller.loadEvents();
        }
      },
      child: ListView(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Tasks & Events',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton.filledTonal(
                onPressed: () async {
                  if (showTasks) {
                    await controller.loadTasks();
                  } else {
                    await controller.loadEvents();
                  }
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.md),
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: true, label: Text('Tasks')),
              ButtonSegment<bool>(value: false, label: Text('Events')),
            ],
            selected: <bool>{showTasks},
            onSelectionChanged: (Set<bool> values) {
              setState(() => showTasks = values.first);
            },
          ),
          const SizedBox(height: LinearSpacing.md),
          TaskFilterBar(
            searchController: _searchController,
            chips: showTasks ? _buildTaskChips() : _buildEventChips(),
          ),
          const SizedBox(height: LinearSpacing.md),
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => showTasks
                    ? _openTaskEditor(context)
                    : _openEventEditor(context),
                icon: const Icon(Icons.add),
                label: Text(showTasks ? 'Add Task' : 'Add Event'),
              ),
              const SizedBox(width: LinearSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => _searchController.clear(),
                icon: const Icon(Icons.layers_clear_outlined),
                label: const Text('Clear Filters'),
              ),
            ],
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _StatusPanel(status: status, message: message),
          ],
          const SizedBox(height: LinearSpacing.md),
          if (showTasks)
            _TaskList(
              status: status,
              tasks: filteredTasks,
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
            )
          else
            _EventList(
              status: status,
              events: filteredEvents,
              onEdit: (EventModel event) =>
                  _openEventEditor(context, existing: event),
              onDelete: (EventModel event) => _confirmDelete(
                context,
                title: 'Delete event?',
                onConfirm: () => controller.deleteEvent(event.id),
              ),
            ),
          if (state.globalMessage != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
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
        if (start == null ||
            start.year != now.year ||
            start.month != now.month ||
            start.day != now.day) {
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

  List<Widget> _buildTaskChips() {
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

  List<Widget> _buildEventChips() {
    return <Widget>[
      FilterChip(
        label: const Text('Today Only'),
        selected: showTodayEventsOnly,
        onSelected: (bool value) {
          setState(() => showTodayEventsOnly = value);
        },
      ),
    ];
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

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status, required this.message});

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
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: color,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Text(message),
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
            ? 'The backend endpoint is not ready yet.'
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

class _EventList extends StatelessWidget {
  const _EventList({
    required this.status,
    required this.events,
    required this.onEdit,
    required this.onDelete,
  });

  final FeatureStatus status;
  final List<EventModel> events;
  final ValueChanged<EventModel> onEdit;
  final ValueChanged<EventModel> onDelete;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return _EmptyPanel(
        message: status == FeatureStatus.notReady
            ? 'The backend endpoint is not ready yet.'
            : 'No events match the current filters.',
      );
    }
    return Column(
      children: events.map((EventModel event) {
        return _EventRow(
          event: event,
          onEdit: () => onEdit(event),
          onDelete: () => onDelete(event),
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
                _MetaTag(label: 'Due ${task.dueAt}'),
              _MetaTag(label: 'Updated ${task.updatedAt ?? task.createdAt}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.onEdit,
    required this.onDelete,
  });

  final EventModel event;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      margin: const EdgeInsets.only(bottom: LinearSpacing.sm),
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
                  event.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Edit event',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete event',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            event.description?.isEmpty == false
                ? event.description!
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
              _MetaTag(label: 'Start ${event.startAt}'),
              _MetaTag(label: 'End ${event.endAt}'),
              if (event.location?.isNotEmpty == true)
                _MetaTag(label: 'Location ${event.location}'),
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
        color: chrome.panel,
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
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
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
