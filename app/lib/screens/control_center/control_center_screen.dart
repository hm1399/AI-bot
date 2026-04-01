import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';

class ControlCenterScreen extends ConsumerStatefulWidget {
  const ControlCenterScreen({super.key});

  @override
  ConsumerState<ControlCenterScreen> createState() =>
      _ControlCenterScreenState();
}

class _ControlCenterScreenState extends ConsumerState<ControlCenterScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await ref.read(appControllerProvider.notifier).loadNotifications();
      await ref.read(appControllerProvider.notifier).loadReminders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Control Center',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonal(
                onPressed: () =>
                    ref.read(appControllerProvider.notifier).speakTestPhrase(),
                child: const Text('Speak'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: () =>
                    ref.read(appControllerProvider.notifier).refreshRuntime(),
                child: const Text('Sync'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Notifications',
          status: state.notificationsStatus,
          message: state.notificationsMessage,
          child: state.notifications.isEmpty
              ? const Text('No notifications.')
              : Column(
                  children: state.notifications
                      .map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.title),
                          subtitle: Text(item.message),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Reminders',
          status: state.remindersStatus,
          message: state.remindersMessage,
          child: state.reminders.isEmpty
              ? const Text('No reminders.')
              : Column(
                  children: state.reminders
                      .map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.title),
                          subtitle: Text('${item.time} · ${item.repeat}'),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.status,
    required this.message,
    required this.child,
  });

  final String title;
  final FeatureStatus status;
  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: status == FeatureStatus.notReady ? const Color(0xFFFFFBEB) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(message!),
            ],
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
