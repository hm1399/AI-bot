import 'package:flutter/material.dart';

import '../../models/home/runtime_state_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class RuntimeQueuePanel extends StatelessWidget {
  const RuntimeQueuePanel({
    required this.currentTask,
    required this.queue,
    super.key,
  });

  final RuntimeTaskModel? currentTask;
  final List<RuntimeTaskModel> queue;

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
          Text('Runtime Queue', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: LinearSpacing.xs),
          Text(
            'Current task and queued work from the backend runtime.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          if (currentTask != null)
            _QueueItem(task: currentTask!, active: true)
          else
            Text(
              'No active task.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: chrome.textTertiary),
            ),
          if (queue.isNotEmpty) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            const Divider(),
            const SizedBox(height: LinearSpacing.md),
            ...queue.take(4).map((RuntimeTaskModel task) {
              return Padding(
                padding: const EdgeInsets.only(bottom: LinearSpacing.sm),
                child: _QueueItem(task: task),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({required this.task, this.active = false});

  final RuntimeTaskModel task;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.all(LinearSpacing.sm),
      decoration: BoxDecoration(
        color: active ? chrome.surfaceHover : chrome.panel,
        borderRadius: LinearRadius.control,
        border: Border.all(
          color: active ? chrome.borderStrong : chrome.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  task.summary.isEmpty ? 'Untitled task' : task.summary,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              StatusPill(
                label: task.stage,
                tone: active ? StatusPillTone.accent : StatusPillTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${task.kind} · ${task.sourceChannel} · ${task.sourceSessionId}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
        ],
      ),
    );
  }
}
