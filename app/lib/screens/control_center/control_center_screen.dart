import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/reminders/reminder_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';

class ControlCenterScreen extends ConsumerStatefulWidget {
  const ControlCenterScreen({super.key});

  @override
  ConsumerState<ControlCenterScreen> createState() =>
      _ControlCenterScreenState();
}

class _ControlCenterScreenState extends ConsumerState<ControlCenterScreen> {
  double _volume = 70;
  double _brightness = 50;
  bool _seededFromSettings = false;
  late final TextEditingController _colorController;

  @override
  void initState() {
    super.initState();
    _colorController = TextEditingController(text: '#2563eb');
    Future<void>.microtask(() async {
      await ref.read(appControllerProvider.notifier).loadNotifications();
      await ref.read(appControllerProvider.notifier).loadReminders();
      await ref.read(appControllerProvider.notifier).loadSettings();
    });
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final settings = state.settings;
    final runtime = state.runtimeState;

    if (settings != null && !_seededFromSettings) {
      _volume = settings.deviceVolume.toDouble();
      _brightness = settings.ledBrightness.toDouble();
      _colorController.text = settings.ledColor;
      _seededFromSettings = true;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Control Center',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              onPressed: () async {
                await controller.refreshRuntime();
                await controller.loadNotifications();
                await controller.loadReminders();
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonal(
                onPressed: controller.speakTestPhrase,
                child: const Text('Speak'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: controller.refreshRuntime,
                child: const Text('Sync Runtime'),
              ),
            ),
          ],
        ),
        if (state.globalMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFF8FAFC),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(state.globalMessage!),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Device Commands',
          status: runtime.device.connected
              ? FeatureStatus.ready
              : FeatureStatus.notReady,
          message: runtime.device.connected
              ? 'Device state: ${runtime.device.state}. Commands go to the hardware entry point directly.'
              : 'Device is offline. Commands will fail until the hardware reconnects.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Volume ${_volume.round()}'),
              Slider(
                value: _volume,
                min: 0,
                max: 100,
                divisions: 20,
                label: _volume.round().toString(),
                onChanged: (double value) => setState(() => _volume = value),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => controller.sendDeviceCommand(
                    'set_volume',
                    params: <String, dynamic>{'level': _volume.round()},
                  ),
                  child: const Text('Send Volume'),
                ),
              ),
              const SizedBox(height: 16),
              Text('LED Brightness ${_brightness.round()}'),
              Slider(
                value: _brightness,
                min: 0,
                max: 100,
                divisions: 20,
                label: _brightness.round().toString(),
                onChanged: (double value) =>
                    setState(() => _brightness = value),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => controller.sendDeviceCommand(
                    'set_led_brightness',
                    params: <String, dynamic>{'level': _brightness.round()},
                  ),
                  child: const Text('Send Brightness'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _colorController,
                decoration: const InputDecoration(
                  labelText: 'LED Color',
                  hintText: '#2563eb',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => controller.sendDeviceCommand(
                    'set_led_color',
                    params: <String, dynamic>{
                      'color': _colorController.text.trim(),
                    },
                  ),
                  child: const Text('Send Color'),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: () => controller.sendDeviceCommand('wake'),
                    child: const Text('Wake'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => controller.sendDeviceCommand('sleep'),
                    child: const Text('Sleep'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => controller.sendDeviceCommand('mute'),
                    child: const Text('Mute'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Notifications',
          status: state.notificationsStatus,
          message: state.notificationsMessage,
          headerActions: <Widget>[
            TextButton(
              onPressed: controller.loadNotifications,
              child: const Text('Refresh'),
            ),
            TextButton(
              onPressed: controller.markAllNotificationsRead,
              child: const Text('Mark All Read'),
            ),
          ],
          child: state.notifications.isEmpty
              ? const Text('No notifications.')
              : Column(
                  children: state.notifications
                      .map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            item.read
                                ? Icons.mark_email_read_outlined
                                : Icons.mark_email_unread_outlined,
                          ),
                          title: Text(item.title),
                          subtitle: Text('${item.message}\n${item.createdAt}'),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 4,
                            children: <Widget>[
                              IconButton(
                                tooltip: item.read
                                    ? 'Mark unread'
                                    : 'Mark read',
                                onPressed: () =>
                                    controller.markNotificationRead(
                                      item.id,
                                      read: !item.read,
                                    ),
                                icon: Icon(
                                  item.read
                                      ? Icons.undo_outlined
                                      : Icons.done_outline,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete notification',
                                onPressed: () =>
                                    controller.deleteNotification(item.id),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
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
          headerActions: <Widget>[
            TextButton(
              onPressed: controller.loadReminders,
              child: const Text('Refresh'),
            ),
            FilledButton.tonal(
              onPressed: () => _openReminderEditor(context),
              child: const Text('Add'),
            ),
          ],
          child: state.reminders.isEmpty
              ? const Text('No reminders.')
              : Column(
                  children: state.reminders
                      .map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.time} · ${item.repeat}\n${item.message}',
                          ),
                          isThreeLine: item.message.isNotEmpty,
                          trailing: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              Switch.adaptive(
                                value: item.enabled,
                                onChanged: (bool value) => controller
                                    .setReminderEnabled(item.id, value),
                              ),
                              IconButton(
                                tooltip: 'Edit reminder',
                                onPressed: () => _openReminderEditor(
                                  context,
                                  existing: item,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete reminder',
                                onPressed: () =>
                                    controller.deleteReminder(item.id),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  Future<void> _openReminderEditor(
    BuildContext context, {
    ReminderModel? existing,
  }) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final messageController = TextEditingController(
      text: existing?.message ?? '',
    );
    final timeController = TextEditingController(text: existing?.time ?? '');
    var repeat = existing?.repeat ?? 'daily';
    var enabled = existing?.enabled ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Reminder' : 'Edit Reminder'),
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
                      controller: messageController,
                      decoration: const InputDecoration(labelText: 'Message'),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: timeController,
                      decoration: const InputDecoration(
                        labelText: 'Time',
                        hintText: '09:00',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: repeat,
                      decoration: const InputDecoration(labelText: 'Repeat'),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem(value: 'daily', child: Text('Daily')),
                        DropdownMenuItem(
                          value: 'weekdays',
                          child: Text('Weekdays'),
                        ),
                        DropdownMenuItem(
                          value: 'weekends',
                          child: Text('Weekends'),
                        ),
                        DropdownMenuItem(value: 'once', child: Text('Once')),
                      ],
                      onChanged: (String? value) {
                        if (value != null) {
                          setState(() => repeat = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: enabled,
                      onChanged: (bool value) {
                        setState(() => enabled = value);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enabled'),
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
      final reminder = ReminderModel(
        id:
            existing?.id ??
            'rem_local_${DateTime.now().millisecondsSinceEpoch}',
        title: titleController.text.trim(),
        message: messageController.text.trim(),
        time: timeController.text.trim(),
        repeat: repeat,
        enabled: enabled,
        createdAt: existing?.createdAt ?? DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      if (existing == null) {
        await ref.read(appControllerProvider.notifier).createReminder(reminder);
      } else {
        await ref.read(appControllerProvider.notifier).updateReminder(reminder);
      }
    }

    titleController.dispose();
    messageController.dispose();
    timeController.dispose();
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.status,
    required this.message,
    required this.child,
    this.headerActions = const <Widget>[],
  });

  final String title;
  final FeatureStatus status;
  final String? message;
  final Widget child;
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context) {
    final color = status == FeatureStatus.notReady
        ? const Color(0xFFFFFBEB)
        : status == FeatureStatus.error
        ? const Color(0xFFFEF2F2)
        : null;

    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (headerActions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: headerActions),
            ],
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
