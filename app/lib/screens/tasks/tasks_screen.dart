import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    final items = showTasks ? state.tasks : state.events;
    final status = showTasks ? state.tasksStatus : state.eventsStatus;
    final message = showTasks ? state.tasksMessage : state.eventsMessage;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
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
        if (message != null)
          Card(
            color: status == FeatureStatus.notReady
                ? const Color(0xFFFFFBEB)
                : const Color(0xFFF8FAFC),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(message),
            ),
          ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              status == FeatureStatus.notReady
                  ? 'The backend endpoint is not ready yet.'
                  : 'No items yet.',
              textAlign: TextAlign.center,
            ),
          )
        else
          ...items.map(
            (dynamic item) => Card(
              child: ListTile(
                title: Text((item as dynamic).title.toString()),
                subtitle: Text(
                  showTasks
                      ? 'Priority ${(item as dynamic).priority}'
                      : 'Start ${(item as dynamic).startAt}',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
