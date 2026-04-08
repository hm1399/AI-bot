import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/events/event_model.dart';
import '../../models/tasks/task_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool showTasks = true;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await ref.read(appControllerProvider.notifier).loadTasks();
      await ref.read(appControllerProvider.notifier).loadEvents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final status = showTasks ? state.tasksStatus : state.eventsStatus;
    final message = showTasks ? state.tasksMessage : state.eventsMessage;
    final items = showTasks ? state.tasks : state.events;

    return RefreshIndicator(
      onRefresh: () async {
        if (showTasks) {
          await controller.loadTasks();
        } else {
          await controller.loadEvents();
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => showTasks
                  ? _openTaskEditor(context)
                  : _openEventEditor(context),
              icon: const Icon(Icons.add),
              label: Text(showTasks ? 'Add Task' : 'Add Event'),
            ),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: 16),
            Card(
              color: status == FeatureStatus.notReady
                  ? const Color(0xFFFFFBEB)
                  : status == FeatureStatus.error
                  ? const Color(0xFFFEF2F2)
                  : const Color(0xFFF8FAFC),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(message),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                status == FeatureStatus.notReady
                    ? 'The backend endpoint is not ready yet.'
                    : showTasks
                    ? 'No tasks yet.'
                    : 'No upcoming events.',
                textAlign: TextAlign.center,
              ),
            )
          else if (showTasks)
            ...state.tasks.map(
              (TaskModel task) => Card(
                child: ListTile(
                  title: Text(task.title),
                  subtitle: Text(_buildTaskSubtitle(task)),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 4,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Edit task',
                        onPressed: () =>
                            _openTaskEditor(context, existing: task),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: task.completed
                            ? 'Mark incomplete'
                            : 'Mark complete',
                        onPressed: () => ref
                            .read(appControllerProvider.notifier)
                            .updateTask(
                              task.copyWith(completed: !task.completed),
                            ),
                        icon: Icon(
                          task.completed
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete task',
                        onPressed: () => _confirmDelete(
                          context,
                          title: 'Delete task?',
                          onConfirm: () => ref
                              .read(appControllerProvider.notifier)
                              .deleteTask(task.id),
                        ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ...state.events.map(
              (EventModel event) => Card(
                child: ListTile(
                  title: Text(event.title),
                  subtitle: Text(_buildEventSubtitle(event)),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 4,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Edit event',
                        onPressed: () =>
                            _openEventEditor(context, existing: event),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete event',
                        onPressed: () => _confirmDelete(
                          context,
                          title: 'Delete event?',
                          onConfirm: () => ref
                              .read(appControllerProvider.notifier)
                              .deleteEvent(event.id),
                        ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _buildTaskSubtitle(TaskModel task) {
    final description = task.description?.trim();
    final due = task.dueAt?.trim();
    final pieces = <String>[
      'Priority ${task.priority}',
      task.completed ? 'Completed' : 'Open',
      if (due != null && due.isNotEmpty) 'Due $due',
      if (description != null && description.isNotEmpty) description,
    ];
    return pieces.join('\n');
  }

  String _buildEventSubtitle(EventModel event) {
    final description = event.description?.trim();
    final location = event.location?.trim();
    final pieces = <String>[
      'Start ${event.startAt}',
      'End ${event.endAt}',
      if (location != null && location.isNotEmpty) 'Location $location',
      if (description != null && description.isNotEmpty) description,
    ];
    return pieces.join('\n');
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
