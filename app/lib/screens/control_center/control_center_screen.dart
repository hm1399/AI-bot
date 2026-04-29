import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/control/computer_action_model.dart';
import '../../models/home/runtime_state_model.dart';
import '../../models/planning/planning_editor_models.dart';
import '../../models/reminders/reminder_model.dart';
import '../../models/settings/settings_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../../widgets/common/status_pill.dart';
import '../../widgets/control/computer_action_panel.dart';
import '../../widgets/control/notification_panel.dart';
import '../../widgets/control/physical_interaction_panel.dart';
import '../../widgets/control/reminder_panel.dart';
import '../../widgets/planning/planning_editor_dialog.dart';
import 'control_center_permissions.dart';

class ControlCenterScreen extends ConsumerStatefulWidget {
  const ControlCenterScreen({super.key});

  @override
  ConsumerState<ControlCenterScreen> createState() =>
      _ControlCenterScreenState();
}

class _ControlCenterScreenState extends ConsumerState<ControlCenterScreen> {
  double _volume = 70;
  double _brightness = 50;
  bool _volumeDirty = false;
  bool _brightnessDirty = false;
  String? _pendingPhysicalSettingKey;

  @override
  void initState() {
    super.initState();
    final controls = ref
        .read(appControllerProvider)
        .runtimeState
        .device
        .controls;
    _volume = controls.volume.toDouble();
    _brightness = controls.ledBrightness.toDouble();
    Future<void>.microtask(() async {
      await ref.read(appControllerProvider.notifier).loadNotifications();
      await ref.read(appControllerProvider.notifier).loadReminders();
      await ref.read(appControllerProvider.notifier).loadSettings();
      await ref.read(appControllerProvider.notifier).refreshPlanningWorkbench();
      await ref
          .read(appControllerProvider.notifier)
          .loadComputerControl(silent: true);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool _controlsChanged(
    DeviceControlsModel? previous,
    DeviceControlsModel next,
  ) {
    if (previous == null) {
      return true;
    }
    return previous.volume != next.volume ||
        previous.ledBrightness != next.ledBrightness ||
        previous.ledEnabled != next.ledEnabled ||
        previous.muted != next.muted ||
        previous.sleeping != next.sleeping;
  }

  void _syncDraftsFromRuntime(DeviceStatusModel device) {
    var shouldSetState = false;
    final controls = device.controls;

    if (!_volumeDirty && _volume != controls.volume.toDouble()) {
      _volume = controls.volume.toDouble();
      shouldSetState = true;
    }
    if (!_brightnessDirty && _brightness != controls.ledBrightness.toDouble()) {
      _brightness = controls.ledBrightness.toDouble();
      shouldSetState = true;
    }

    if (shouldSetState && mounted) {
      setState(() {});
    }
  }

  void _clearDirtyForCommand(String? command) {
    switch (command) {
      case 'set_volume':
        _volumeDirty = false;
        break;
      case 'set_led_brightness':
        _brightnessDirty = false;
        break;
      default:
        break;
    }
  }

  void _handleDeviceRuntimeChange(
    DeviceStatusModel? previous,
    DeviceStatusModel next,
  ) {
    final wasConnected = previous?.connected ?? false;
    final justReconnected = !wasConnected && next.connected;
    final previousCommand = previous?.lastCommand ?? DeviceCommandModel.empty();
    final commandCompleted =
        previousCommand.isPending && !next.lastCommand.isPending;

    if (commandCompleted && next.lastCommand.isSucceeded) {
      _clearDirtyForCommand(next.lastCommand.command);
    }

    if (justReconnected ||
        _controlsChanged(previous?.controls, next.controls)) {
      _syncDraftsFromRuntime(next);
    }
  }

  void _handleVolumeChanged(double value) {
    final runtimeValue = ref
        .read(appControllerProvider)
        .runtimeState
        .device
        .controls
        .volume;
    setState(() {
      _volume = value;
      _volumeDirty = value.round() != runtimeValue;
    });
  }

  void _handleBrightnessChanged(double value) {
    final runtimeValue = ref
        .read(appControllerProvider)
        .runtimeState
        .device
        .controls
        .ledBrightness;
    setState(() {
      _brightness = value;
      _brightnessDirty = value.round() != runtimeValue;
    });
  }

  Future<void> _togglePhysicalInteractionSetting({
    required String key,
    required AppSettingsModel? settings,
    required AppSettingsModel Function(AppSettingsModel current) buildNext,
  }) async {
    if (_pendingPhysicalSettingKey != null || settings == null) {
      return;
    }

    setState(() {
      _pendingPhysicalSettingKey = key;
    });

    final controller = ref.read(appControllerProvider.notifier);
    try {
      await controller.saveSettings(buildNext(settings));
      await controller.refreshRuntime();
    } finally {
      if (mounted) {
        setState(() {
          _pendingPhysicalSettingKey = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DeviceStatusModel>(
      appControllerProvider.select(
        (AppState state) => state.runtimeState.device,
      ),
      _handleDeviceRuntimeChange,
    );

    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final runtime = state.runtimeState;
    final chrome = context.linear;
    final computerControl =
        state.bootstrap?.computerControl ??
        ComputerControlStateModel(
          available: state.capabilities.computerControl,
          supportedActions: state.capabilities.computerActions,
        );
    final showComputerActions =
        state.capabilities.computerControl ||
        state.capabilities.computerActions.isNotEmpty ||
        computerControl.hasStructuredActions ||
        computerControl.statusMessage != null;
    final commandsAvailable = canSendDeviceCommands(
      deviceConnected: runtime.device.connected,
      commandPending: runtime.device.lastCommand.isPending,
    );
    final planning = _ControlCenterPlanningSnapshot.fromSources(state: state);
    final experience = state.currentExperience;
    final physicalInteraction = experience.physicalInteraction;
    final settings = state.settings;
    final canTogglePhysicalSettings = settings != null;
    final physicalToggleBusy = _pendingPhysicalSettingKey != null;

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
                await controller.loadComputerControl(silent: true);
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
                  ? () => controller.sendDeviceCommand(
                      'toggle_led',
                      params: <String, dynamic>{
                        'enabled': !runtime.device.controls.ledEnabled,
                      },
                    )
                  : null,
              icon: const Icon(Icons.lightbulb_circle_outlined, size: 16),
              label: Text(
                runtime.device.controls.ledEnabled
                    ? 'Turn Light Off'
                    : 'Turn Light On',
              ),
            ),
          ],
        ),
        const SizedBox(height: LinearSpacing.md),
        Container(
          width: double.infinity,
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
                'Speech Triggers',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Turn off shake and tap speech triggers here without scrolling into the lower physical interaction panel.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
              ),
              const SizedBox(height: LinearSpacing.sm),
              Wrap(
                spacing: LinearSpacing.sm,
                runSpacing: LinearSpacing.sm,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: canTogglePhysicalSettings && !physicalToggleBusy
                        ? () => _togglePhysicalInteractionSetting(
                            key: 'shake',
                            settings: settings,
                            buildNext: (AppSettingsModel current) => current
                                .copyWith(shakeEnabled: !current.shakeEnabled),
                          )
                        : null,
                    icon: Icon(
                      physicalInteraction.shakeEnabled
                          ? Icons.motion_photos_off_outlined
                          : Icons.motion_photos_on_outlined,
                      size: 16,
                    ),
                    label: Text(
                      _pendingPhysicalSettingKey == 'shake'
                          ? 'Saving...'
                          : physicalInteraction.shakeEnabled
                          ? 'Turn Shake Off'
                          : 'Turn Shake On',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: canTogglePhysicalSettings && !physicalToggleBusy
                        ? () => _togglePhysicalInteractionSetting(
                            key: 'tap',
                            settings: settings,
                            buildNext: (AppSettingsModel current) =>
                                current.copyWith(
                                  tapConfirmationEnabled:
                                      !current.tapConfirmationEnabled,
                                ),
                          )
                        : null,
                    icon: Icon(
                      physicalInteraction.tapConfirmationEnabled
                          ? Icons.touch_app_outlined
                          : Icons.pan_tool_alt_outlined,
                      size: 16,
                    ),
                    label: Text(
                      _pendingPhysicalSettingKey == 'tap'
                          ? 'Saving...'
                          : physicalInteraction.tapConfirmationEnabled
                          ? 'Turn Tap Off'
                          : 'Turn Tap On',
                    ),
                  ),
                ],
              ),
            ],
          ),
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
              volume: _volume,
              brightness: _brightness,
              onVolumeChanged: _handleVolumeChanged,
              onBrightnessChanged: _handleBrightnessChanged,
              onSendVolume: () => controller.sendDeviceCommand(
                'set_volume',
                params: <String, dynamic>{'level': _volume.round()},
              ),
              onSendBrightness: () => controller.sendDeviceCommand(
                'set_led_brightness',
                params: <String, dynamic>{'level': _brightness.round()},
              ),
              onWake: () => controller.sendDeviceCommand('wake'),
              onSleep: () => controller.sendDeviceCommand('sleep'),
              onMute: () => controller.sendDeviceCommand('mute'),
              onTurnLightOn: () => controller.sendDeviceCommand(
                'toggle_led',
                params: const <String, dynamic>{'enabled': true},
              ),
              onTurnLightOff: () => controller.sendDeviceCommand(
                'toggle_led',
                params: const <String, dynamic>{'enabled': false},
              ),
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
        PhysicalInteractionPanel(
          sceneLabel: experience.sceneLabel,
          personaLabel: experience.personaLabel,
          interaction: experience.physicalInteraction,
          lastResult: experience.lastInteractionResult,
          deviceConnected: runtime.device.connected,
          desktopBridgeReady: runtime.voice.desktopBridgeReady,
          pendingSettingToggleKey: _pendingPhysicalSettingKey,
          onToggleShakeEnabled: canTogglePhysicalSettings
              ? () => _togglePhysicalInteractionSetting(
                  key: 'shake',
                  settings: settings,
                  buildNext: (AppSettingsModel current) =>
                      current.copyWith(shakeEnabled: !current.shakeEnabled),
                )
              : null,
          onToggleTapTriggerEnabled: canTogglePhysicalSettings
              ? () => _togglePhysicalInteractionSetting(
                  key: 'tap',
                  settings: settings,
                  buildNext: (AppSettingsModel current) => current.copyWith(
                    tapConfirmationEnabled: !current.tapConfirmationEnabled,
                  ),
                )
              : null,
          pendingDebugTriggerKey: state.physicalInteractionDebugPendingKey,
          onTriggerPhysicalInteraction:
              (String kind, Map<String, dynamic> payload) => controller
                  .triggerPhysicalInteraction(kind: kind, payload: payload),
        ),
        const SizedBox(height: LinearSpacing.md),
        if (showComputerActions) ...<Widget>[
          ComputerActionPanel(
            state: computerControl,
            onRefresh: () => controller.loadComputerControl(),
            onRunAction: controller.runComputerAction,
            onConfirmAction: controller.confirmComputerAction,
            onCancelAction: controller.cancelComputerAction,
          ),
          const SizedBox(height: LinearSpacing.md),
        ],
        ReminderPanel(
          items: state.reminders,
          statusMessage: state.remindersMessage,
          onRefresh: controller.loadReminders,
          onAdd: () => showPlanningEditorDialog(
            context,
            kind: PlanningEditorKind.reminder,
            origin: 'control_center_manual',
          ),
          onToggleEnabled: (ReminderModel item, bool enabled) =>
              controller.setReminderEnabled(item.id, enabled),
          onEdit: (ReminderModel item) => showPlanningEditorDialog(
            context,
            kind: PlanningEditorKind.reminder,
            origin: 'control_center_manual',
            reminder: item,
          ),
          onDelete: (ReminderModel item) => controller.deleteReminder(item.id),
        ),
      ],
    );
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
    required this.volume,
    required this.brightness,
    required this.onVolumeChanged,
    required this.onBrightnessChanged,
    required this.onSendVolume,
    required this.onSendBrightness,
    required this.onWake,
    required this.onSleep,
    required this.onMute,
    required this.onTurnLightOn,
    required this.onTurnLightOff,
  });

  final String runtimeState;
  final bool deviceConnected;
  final bool bridgeReady;
  final DeviceControlsModel controls;
  final DeviceStatusBarModel statusBar;
  final DeviceCommandModel lastCommand;
  final double volume;
  final double brightness;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onBrightnessChanged;
  final Future<void> Function() onSendVolume;
  final Future<void> Function() onSendBrightness;
  final Future<void> Function() onWake;
  final Future<void> Function() onSleep;
  final Future<void> Function() onMute;
  final Future<void> Function() onTurnLightOn;
  final Future<void> Function() onTurnLightOff;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final commandPending = lastCommand.isPending;
    final canAdjustControls = canAdjustDeviceControls(
      deviceConnected: deviceConnected,
      commandPending: commandPending,
    );
    final canSendCommands = canSendDeviceCommands(
      deviceConnected: deviceConnected,
      commandPending: commandPending,
    );
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
                label: controls.ledEnabled ? 'Light On' : 'Light Off',
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
                label: 'Light',
                value:
                    '${controls.ledEnabled ? 'On' : 'Off'} · ${controls.ledBrightness}%',
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
            onChanged: canAdjustControls ? onVolumeChanged : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: canSendCommands ? onSendVolume : null,
              child: const Text('Send Volume'),
            ),
          ),
          const SizedBox(height: LinearSpacing.md),
          Text('Light Brightness ${brightness.round()}'),
          Slider(
            value: brightness,
            min: 0,
            max: 100,
            divisions: 20,
            label: brightness.round().toString(),
            onChanged: canAdjustControls ? onBrightnessChanged : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: canSendCommands ? onSendBrightness : null,
              child: const Text('Send Brightness'),
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
                onPressed: canSendCommands && !controls.ledEnabled
                    ? onTurnLightOn
                    : null,
                child: const Text('Turn Light On'),
              ),
              FilledButton.tonal(
                onPressed: canSendCommands && controls.ledEnabled
                    ? onTurnLightOff
                    : null,
                child: const Text('Turn Light Off'),
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
    required AppState state,
  }) {
    final overview = state.planningOverview;
    final timeline = state.planningTimeline;
    final conflicts = state.planningConflicts;
    final reminders = state.reminders
        .where((ReminderModel item) => item.enabled)
        .length;

    return _ControlCenterPlanningSnapshot(
      activeReminders: overview?.activeReminderCount ?? reminders,
      conflictCount: overview?.conflictCount ?? conflicts.length,
      nextTimelineLabel:
          overview?.nextItemTitle ??
          (timeline.isEmpty ? null : timeline.first.title) ??
          'Open Tasks for the full workbench view',
    );
  }
}
