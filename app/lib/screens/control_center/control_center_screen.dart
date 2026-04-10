import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/home/runtime_state_model.dart';
import '../../models/reminders/reminder_model.dart';
import '../../providers/app_providers.dart';
import '../../theme/linear_tokens.dart';
import '../../widgets/common/status_pill.dart';
import '../../widgets/control/notification_panel.dart';
import '../../widgets/control/reminder_panel.dart';

class ControlCenterScreen extends ConsumerStatefulWidget {
  const ControlCenterScreen({super.key});

  @override
  ConsumerState<ControlCenterScreen> createState() =>
      _ControlCenterScreenState();
}

class _ControlCenterScreenState extends ConsumerState<ControlCenterScreen> {
  double _volume = 70;
  double _brightness = 50;
  String _lastRuntimeSyncToken = '';
  late final TextEditingController _colorController;

  @override
  void initState() {
    super.initState();
    _colorController = TextEditingController(text: '#2563eb');
    Future<void>.microtask(() async {
      await ref.read(appControllerProvider.notifier).loadNotifications();
      await ref.read(appControllerProvider.notifier).loadReminders();
      await ref.read(appControllerProvider.notifier).loadSettings();
      await ref.read(appControllerProvider.notifier).refreshPlanningWorkbench();
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
    final chrome = context.linear;
    final commandsAvailable =
        runtime.device.connected && !runtime.device.lastCommand.isPending;
    final planning = _ControlCenterPlanningSnapshot.fromSources(
      state: state,
      controller: controller,
    );

    final controls = runtime.device.controls;
    final runtimeSyncToken =
        '${runtime.device.connected}|${runtime.device.reconnectCount}|'
        '${controls.volume}|${controls.muted}|${controls.sleeping}|'
        '${controls.ledEnabled}|${controls.ledBrightness}|${controls.ledColor}|'
        '${runtime.device.lastCommand.updatedAt ?? ''}';
    if (runtimeSyncToken != _lastRuntimeSyncToken) {
      _volume = controls.volume.toDouble();
      _brightness = controls.ledBrightness.toDouble();
      _colorController.text = controls.ledColor;
      _lastRuntimeSyncToken = runtimeSyncToken;
    }

    return ListView(
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
                await controller.refreshPlanningWorkbench();
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: LinearSpacing.md),
        Wrap(
          spacing: LinearSpacing.sm,
          runSpacing: LinearSpacing.sm,
          children: <Widget>[
            const StatusPill(
              label: 'Compatibility Entry',
              tone: StatusPillTone.accent,
              icon: Icons.swap_horiz_outlined,
            ),
            FilledButton.tonalIcon(
              onPressed: controller.speakTestPhrase,
              icon: const Icon(Icons.volume_up_outlined, size: 16),
              label: const Text('Speak'),
            ),
            FilledButton.tonalIcon(
              onPressed: controller.refreshRuntime,
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Sync Runtime'),
            ),
            OutlinedButton.icon(
              onPressed: commandsAvailable
                  ? () => controller.sendDeviceCommand('toggle_led')
                  : null,
              icon: const Icon(Icons.lightbulb_circle_outlined, size: 16),
              label: const Text('Toggle LED'),
            ),
          ],
        ),
        const SizedBox(height: LinearSpacing.md),
        _CompatibilityPlanningCard(snapshot: planning),
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
        const SizedBox(height: LinearSpacing.md),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final stacked = constraints.maxWidth < 1040;
            final devicePanel = _DeviceCommandPanel(
              runtimeState: runtime.device.state,
              deviceConnected: runtime.device.connected,
              bridgeReady: runtime.voice.desktopBridgeReady,
              controls: runtime.device.controls,
              statusBar: runtime.device.statusBar,
              lastCommand: runtime.device.lastCommand,
              ledMode: settings?.ledMode ?? 'breathing',
              volume: _volume,
              brightness: _brightness,
              colorController: _colorController,
              onVolumeChanged: (double value) =>
                  setState(() => _volume = value),
              onBrightnessChanged: (double value) =>
                  setState(() => _brightness = value),
              onSendVolume: () => controller.sendDeviceCommand(
                'set_volume',
                params: <String, dynamic>{'level': _volume.round()},
              ),
              onSendBrightness: () => controller.sendDeviceCommand(
                'set_led_brightness',
                params: <String, dynamic>{'level': _brightness.round()},
              ),
              onSendColor: () => controller.sendDeviceCommand(
                'set_led_color',
                params: <String, dynamic>{
                  'color': _colorController.text.trim(),
                },
              ),
              onWake: () => controller.sendDeviceCommand('wake'),
              onSleep: () => controller.sendDeviceCommand('sleep'),
              onMute: () => controller.sendDeviceCommand('mute'),
              onToggleLed: () => controller.sendDeviceCommand('toggle_led'),
            );

            final notificationPanel = NotificationPanel(
              items: state.notifications,
              statusMessage: state.notificationsMessage,
              onRefresh: controller.loadNotifications,
              onMarkAllRead: controller.markAllNotificationsRead,
              onClearAll: controller.clearNotifications,
              onToggleRead: (item) =>
                  controller.markNotificationRead(item.id, read: !item.read),
              onDelete: (item) => controller.deleteNotification(item.id),
            );

            if (stacked) {
              return Column(
                children: <Widget>[
                  devicePanel,
                  const SizedBox(height: LinearSpacing.md),
                  notificationPanel,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 5, child: devicePanel),
                const SizedBox(width: LinearSpacing.md),
                Expanded(flex: 4, child: notificationPanel),
              ],
            );
          },
        ),
        const SizedBox(height: LinearSpacing.md),
        ReminderPanel(
          items: state.reminders,
          statusMessage: state.remindersMessage,
          onRefresh: controller.loadReminders,
          onAdd: () => _openReminderEditor(context),
          onToggleEnabled: (ReminderModel item, bool enabled) =>
              controller.setReminderEnabled(item.id, enabled),
          onEdit: (ReminderModel item) =>
              _openReminderEditor(context, existing: item),
          onDelete: (ReminderModel item) => controller.deleteReminder(item.id),
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

class _DeviceCommandPanel extends StatelessWidget {
  const _DeviceCommandPanel({
    required this.runtimeState,
    required this.deviceConnected,
    required this.bridgeReady,
    required this.controls,
    required this.statusBar,
    required this.lastCommand,
    required this.ledMode,
    required this.volume,
    required this.brightness,
    required this.colorController,
    required this.onVolumeChanged,
    required this.onBrightnessChanged,
    required this.onSendVolume,
    required this.onSendBrightness,
    required this.onSendColor,
    required this.onWake,
    required this.onSleep,
    required this.onMute,
    required this.onToggleLed,
  });

  final String runtimeState;
  final bool deviceConnected;
  final bool bridgeReady;
  final DeviceControlsModel controls;
  final DeviceStatusBarModel statusBar;
  final DeviceCommandModel lastCommand;
  final String ledMode;
  final double volume;
  final double brightness;
  final TextEditingController colorController;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onBrightnessChanged;
  final Future<void> Function() onSendVolume;
  final Future<void> Function() onSendBrightness;
  final Future<void> Function() onSendColor;
  final Future<void> Function() onWake;
  final Future<void> Function() onSleep;
  final Future<void> Function() onMute;
  final Future<void> Function() onToggleLed;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final commandPending = lastCommand.isPending;
    final canSendCommands = deviceConnected && !commandPending;
    final commandStatusLabel = switch (lastCommand.status) {
      'pending' => 'Command Pending',
      'succeeded' => 'Command OK',
      'failed' => 'Command Failed',
      _ => 'Command Idle',
    };
    final commandStatusTone = switch (lastCommand.status) {
      'pending' => StatusPillTone.warning,
      'succeeded' => StatusPillTone.success,
      'failed' => StatusPillTone.danger,
      _ => StatusPillTone.neutral,
    };
    final weatherLabel = switch (statusBar.weatherStatus) {
      'ready' => statusBar.weather ?? 'Weather Ready',
      'missing_api_key' => 'Weather Key Missing',
      'fetch_failed' => 'Weather Retry Needed',
      _ => 'Weather Waiting',
    };
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
            'Device Commands',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: deviceConnected ? 'Device Online' : 'Device Offline',
                tone: deviceConnected
                    ? StatusPillTone.success
                    : StatusPillTone.danger,
              ),
              StatusPill(
                label: 'State $runtimeState',
                tone: StatusPillTone.neutral,
              ),
              StatusPill(
                label: bridgeReady
                    ? 'Desktop Bridge Ready'
                    : 'Desktop Bridge Waiting',
                tone: bridgeReady
                    ? StatusPillTone.success
                    : StatusPillTone.warning,
              ),
              StatusPill(label: commandStatusLabel, tone: commandStatusTone),
              StatusPill(
                label: controls.ledEnabled ? 'LED $ledMode' : 'LED Disabled',
                tone: controls.ledEnabled
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
              ),
              StatusPill(
                label: controls.muted ? 'Muted' : 'Audio Live',
                tone: controls.muted
                    ? StatusPillTone.warning
                    : StatusPillTone.success,
              ),
              StatusPill(
                label: controls.sleeping ? 'Sleeping' : 'Awake',
                tone: controls.sleeping
                    ? StatusPillTone.warning
                    : StatusPillTone.success,
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.md),
          Wrap(
            spacing: LinearSpacing.sm,
            runSpacing: LinearSpacing.sm,
            children: <Widget>[
              _MetricPill(
                label: 'Status Bar',
                value:
                    '${statusBar.time ?? '--:--'} · ${weatherLabel.isEmpty ? 'Waiting' : weatherLabel}',
              ),
              _MetricPill(label: 'Runtime Volume', value: '${controls.volume}'),
              _MetricPill(
                label: 'LED',
                value:
                    '${controls.ledBrightness}% · ${controls.ledColor.toUpperCase()}',
              ),
            ],
          ),
          if (lastCommand.command != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            Text(
              'Last command: ${lastCommand.command} · ${lastCommand.status}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ],
          if (lastCommand.error != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              lastCommand.error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.danger),
            ),
          ],
          const SizedBox(height: LinearSpacing.md),
          Text('Volume ${volume.round()}'),
          Slider(
            value: volume,
            min: 0,
            max: 100,
            divisions: 20,
            label: volume.round().toString(),
            onChanged: canSendCommands ? onVolumeChanged : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: canSendCommands ? onSendVolume : null,
              child: const Text('Send Volume'),
            ),
          ),
          const SizedBox(height: LinearSpacing.md),
          Text('LED Brightness ${brightness.round()}'),
          Slider(
            value: brightness,
            min: 0,
            max: 100,
            divisions: 20,
            label: brightness.round().toString(),
            onChanged: canSendCommands ? onBrightnessChanged : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: canSendCommands ? onSendBrightness : null,
              child: const Text('Send Brightness'),
            ),
          ),
          const SizedBox(height: LinearSpacing.md),
          TextField(
            controller: colorController,
            enabled: canSendCommands,
            decoration: const InputDecoration(
              labelText: 'LED Color',
              hintText: '#2563eb',
            ),
          ),
          const SizedBox(height: LinearSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: canSendCommands ? onSendColor : null,
              child: const Text('Send Color'),
            ),
          ),
          const SizedBox(height: LinearSpacing.md),
          Wrap(
            spacing: LinearSpacing.sm,
            runSpacing: LinearSpacing.sm,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: canSendCommands ? onWake : null,
                child: const Text('Wake'),
              ),
              FilledButton.tonal(
                onPressed: canSendCommands ? onSleep : null,
                child: const Text('Sleep'),
              ),
              FilledButton.tonal(
                onPressed: canSendCommands ? onMute : null,
                child: Text(controls.muted ? 'Unmute' : 'Mute'),
              ),
              FilledButton.tonal(
                onPressed: canSendCommands ? onToggleLed : null,
                child: const Text('Toggle LED'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

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

class _CompatibilityPlanningCard extends StatelessWidget {
  const _CompatibilityPlanningCard({required this.snapshot});

  final _ControlCenterPlanningSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: double.infinity,
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
            'Planning Compatibility',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Control Center keeps notifications, reminders, and device/runtime actions available. The primary planning workbench now lives in Tasks.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              Chip(label: Text('${snapshot.activeReminders} active reminders')),
              Chip(label: Text('${snapshot.conflictCount} conflicts')),
              Chip(label: Text(snapshot.nextTimelineLabel)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlCenterPlanningSnapshot {
  const _ControlCenterPlanningSnapshot({
    required this.activeReminders,
    required this.conflictCount,
    required this.nextTimelineLabel,
  });

  final int activeReminders;
  final int conflictCount;
  final String nextTimelineLabel;

  factory _ControlCenterPlanningSnapshot.fromSources({
    required Object state,
    required Object controller,
  }) {
    final overview = _coerceStringMap(
      _readPlanningProperty(
        state: state,
        controller: controller,
        name: 'planningOverview',
      ),
    );
    final timeline = _coerceList(
      _readPlanningProperty(
        state: state,
        controller: controller,
        name: 'planningTimeline',
      ),
    );
    final conflicts = _coerceList(
      _readPlanningProperty(
        state: state,
        controller: controller,
        name: 'planningConflicts',
      ),
    );
    final dynamic dynamicState = state;
    final reminders = (dynamicState.reminders as List<dynamic>)
        .whereType<ReminderModel>()
        .where((ReminderModel item) => item.enabled)
        .length;

    return _ControlCenterPlanningSnapshot(
      activeReminders:
          _lookupInt(overview, <String>[
            'active_reminders',
            'activeReminderCount',
          ]) ??
          reminders,
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
          _deriveTimelineLabel(timeline) ??
          'Open Tasks for the full workbench view',
    );
  }
}

Object? _readPlanningProperty({
  required Object state,
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

String? _deriveTimelineLabel(List<Object?> timeline) {
  for (final item in timeline) {
    final map = _coerceStringMap(item);
    final label = _lookupString(map, <String>['title', 'summary', 'label']);
    if (label != null && label.isNotEmpty) {
      return label;
    }
  }
  return null;
}
