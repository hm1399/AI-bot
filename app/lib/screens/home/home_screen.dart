import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../widgets/home/device_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final runtime = state.runtimeState;
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(appControllerProvider.notifier).refreshRuntime(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Dashboard',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton.filledTonal(
                onPressed: () =>
                    ref.read(appControllerProvider.notifier).refreshRuntime(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DeviceCard(status: runtime.device),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Current Runtime Task'),
              subtitle: Text(runtime.currentTask?.summary ?? 'No active task.'),
              trailing: Text('Queue ${runtime.taskQueue.length}'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => ref
                      .read(appControllerProvider.notifier)
                      .speakTestPhrase(),
                  child: const Text('Speak'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => ref
                      .read(appControllerProvider.notifier)
                      .stopCurrentTask(),
                  child: const Text('Stop'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Todo Summary'),
              subtitle: Text(
                runtime.todoSummary.enabled
                    ? 'Pending ${runtime.todoSummary.pendingCount} · Overdue ${runtime.todoSummary.overdueCount}'
                    : 'Todo summary is not enabled on the backend.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Calendar Summary'),
              subtitle: Text(
                runtime.calendarSummary.enabled
                    ? 'Today ${runtime.calendarSummary.todayCount} · Next ${runtime.calendarSummary.nextEventTitle ?? 'Not set'}'
                    : 'Calendar summary is not enabled on the backend.',
              ),
            ),
          ),
          if (state.globalMessage != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(state.globalMessage!),
          ],
        ],
      ),
    );
  }
}
