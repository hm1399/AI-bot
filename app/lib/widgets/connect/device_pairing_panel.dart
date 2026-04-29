import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/device_pairing/device_pairing_draft_model.dart';
import '../../models/device_pairing/device_pairing_state_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

enum DevicePairingPanelMode { usb, config }

class DevicePairingPanel extends ConsumerStatefulWidget {
  const DevicePairingPanel({super.key, required this.mode});

  final DevicePairingPanelMode mode;

  @override
  ConsumerState<DevicePairingPanel> createState() => _DevicePairingPanelState();
}

class _DevicePairingPanelState extends ConsumerState<DevicePairingPanel> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final FocusNode _ssidFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _hostFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final pairing = ref.read(devicePairingControllerProvider);
    _ssidController.text = pairing.draft.wifiSsid;
    _passwordController.text = pairing.draft.wifiPassword;
    _hostController.text = pairing.draft.host;
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _hostController.dispose();
    _ssidFocusNode.dispose();
    _passwordFocusNode.dispose();
    _hostFocusNode.dispose();
    super.dispose();
  }

  void _syncController(
    TextEditingController controller,
    FocusNode focusNode,
    String value,
  ) {
    if (focusNode.hasFocus || controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  bool _pairingActiveOrComplete(DevicePairingStateModel pairing) {
    return pairing.stage == DevicePairingStage.sending ||
        pairing.stage == DevicePairingStage.awaitingOnline ||
        pairing.stage == DevicePairingStage.paired ||
        pairing.deviceOnline;
  }

  bool _backendReady(AppState appState) {
    return appState.isConnected && !appState.isDemoMode;
  }

  bool _usbReady(AppState appState, DevicePairingStateModel pairing) {
    return _backendReady(appState) &&
        pairing.platformSupported &&
        (pairing.connectedPortName.isNotEmpty ||
            _pairingActiveOrComplete(pairing)) &&
        (pairing.isArmed || _pairingActiveOrComplete(pairing));
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final appState = ref.watch(appControllerProvider);
    final pairing = ref.watch(devicePairingControllerProvider);
    final pairingController = ref.read(
      devicePairingControllerProvider.notifier,
    );
    final backendReady = _backendReady(appState);
    final usbReady = _usbReady(appState, pairing);
    final selectedPortValue =
        pairing.availablePorts.contains(pairing.draft.trimmedPortName)
        ? pairing.draft.trimmedPortName
        : null;
    final currentConnection = appState.connection;
    final endpointBundle = pairing.bundle?.server;
    final endpointHost =
        endpointBundle != null && endpointBundle.host.trim().isNotEmpty
        ? endpointBundle.host.trim()
        : pairing.draft.trimmedHost;
    final endpointPort = endpointBundle?.port ?? currentConnection.port;
    final endpointPath =
        endpointBundle?.normalizedPath ??
        DevicePairingDraftModel.defaultServerPath;
    final endpointScheme = (endpointBundle?.secure ?? currentConnection.secure)
        ? 'wss'
        : 'ws';
    final canPreviewCurrentConnection =
        backendReady && currentConnection.hasServer;
    final showSocketAsEndpoint =
        endpointBundle != null || canPreviewCurrentConnection;
    final socketSummary = endpointBundle != null
        ? endpointHost.isEmpty
              ? '$endpointScheme://<lan-host>:$endpointPort$endpointPath'
              : '$endpointScheme://$endpointHost:$endpointPort$endpointPath'
        : appState.isDemoMode
        ? 'Demo mode does not provide a real device callback endpoint.'
        : !canPreviewCurrentConnection
        ? 'Complete Step 1 and connect to a live backend to generate the device callback endpoint.'
        : endpointHost.isEmpty
        ? '$endpointScheme://<lan-host>:$endpointPort$endpointPath'
        : '$endpointScheme://$endpointHost:$endpointPort$endpointPath';
    final authSummary = pairing.bundle == null
        ? appState.isDemoMode
              ? 'Demo mode does not request a real bundle'
              : canPreviewCurrentConnection
              ? 'Will request the latest bundle from the current backend on send'
              : 'Will request the latest bundle after connecting to a live backend'
        : pairing.bundle!.requiresDeviceToken
        ? 'Will include device token on send'
        : 'No device token required';
    final fieldsEnabled =
        usbReady &&
        !pairing.isBusy &&
        pairing.stage != DevicePairingStage.paired &&
        !pairing.deviceOnline;

    _syncController(_ssidController, _ssidFocusNode, pairing.draft.wifiSsid);
    _syncController(
      _passwordController,
      _passwordFocusNode,
      pairing.draft.wifiPassword,
    );
    _syncController(_hostController, _hostFocusNode, pairing.draft.host);

    return Container(
      padding: const EdgeInsets.all(LinearSpacing.xl),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.panel,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: widget.mode == DevicePairingPanelMode.usb
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _StepHeader(
                  stepLabel: 'Step 2',
                  title: 'Connect Robot & Long-Press Touch Pad',
                  description: 'This step handles USB only: plug in, select serial port, open USB, then long-press the touch pad to enter pairing mode.',
                  trailing: FilledButton.tonalIcon(
                    onPressed: !backendReady || pairing.isBusy
                        ? null
                        : () => unawaited(pairingController.refreshPorts()),
                    icon: const Icon(Icons.usb_rounded),
                    label: const Text('Refresh USB'),
                  ),
                ),
                const SizedBox(height: LinearSpacing.lg),
                _InstructionCard(
                  items: const <String>[
                    'Connect the robot to this computer with a data cable.',
                    'Click Refresh USB and select the correct serial device.',
                    'Click Open USB, then long-press the touch pad for about 5 seconds until the robot enters Armed mode.',
                  ],
                ),
                const SizedBox(height: LinearSpacing.lg),
                Wrap(
                  spacing: LinearSpacing.xs,
                  runSpacing: LinearSpacing.xs,
                  children: <Widget>[
                    StatusPill(
                      label: backendReady
                          ? 'Backend Connected'
                          : 'Backend Required',
                      tone: backendReady
                          ? StatusPillTone.success
                          : StatusPillTone.warning,
                      icon: Icons.cloud_done_outlined,
                    ),
                    StatusPill(
                      label: pairing.connectedPortName.isEmpty
                          ? 'USB Idle'
                          : 'USB Linked',
                      tone: pairing.connectedPortName.isEmpty
                          ? StatusPillTone.neutral
                          : StatusPillTone.success,
                      icon: Icons.usb_outlined,
                    ),
                    StatusPill(
                      label: pairing.isArmed ? 'Armed' : 'Waiting Arm',
                      tone: pairing.isArmed
                          ? StatusPillTone.success
                          : StatusPillTone.accent,
                      icon: Icons.touch_app_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: LinearSpacing.md),
                _InlineNotice(
                  tone: _step2Guide(appState, pairing).$2,
                  message: _step2Guide(appState, pairing).$1,
                ),
                const SizedBox(height: LinearSpacing.lg),
                if (!backendReady)
                  _InlineNotice(
                    tone: StatusPillTone.warning,
                    message: appState.isDemoMode
                        ? 'Demo mode cannot pair a real robot. Please go back to Step 1 and connect to a live backend.'
                        : 'Please complete Step 1 first. Without a live backend, USB pairing cannot proceed.',
                  )
                else ...<Widget>[
                  if (pairing.availablePorts.isEmpty &&
                      !pairing.isBusy) ...<Widget>[
                    const _InlineNotice(
                      tone: StatusPillTone.neutral,
                      message: 'No serial devices detected. Make sure the robot is plugged in, then click Refresh USB.',
                    ),
                    const SizedBox(height: LinearSpacing.md),
                  ],
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey<String>(selectedPortValue ?? '__none__'),
                    initialValue: selectedPortValue,
                    decoration: const InputDecoration(
                      labelText: 'USB Serial Device',
                      prefixIcon: Icon(Icons.usb_rounded),
                    ),
                    hint: const Text('Select a serial device'),
                    items: pairing.availablePorts
                        .map(
                          (String portName) => DropdownMenuItem<String>(
                            value: portName,
                            child: Text(
                              portName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: pairing.isBusy
                        ? null
                        : (String? value) {
                            unawaited(
                              pairingController.selectPort(value ?? ''),
                            );
                          },
                  ),
                  const SizedBox(height: LinearSpacing.sm),
                  FilledButton.tonalIcon(
                    onPressed: pairing.isBusy
                        ? null
                        : pairing.connectedPortName.isEmpty
                        ? () => unawaited(pairingController.openSelectedPort())
                        : () => unawaited(pairingController.closePort()),
                    icon: Icon(
                      pairing.connectedPortName.isEmpty
                          ? Icons.link
                          : Icons.link_off,
                    ),
                    label: Text(
                      pairing.connectedPortName.isEmpty
                          ? 'Open USB'
                          : 'Release USB',
                    ),
                  ),
                ],
                const SizedBox(height: LinearSpacing.lg),
                _SummaryCard(
                  title: 'Current Status',
                  rows: <_SummaryRow>[
                    _SummaryRow(
                      label: 'USB',
                      value: pairing.connectedPortName.isNotEmpty
                          ? pairing.connectedPortName
                          : pairing.draft.trimmedPortName.isNotEmpty
                          ? '${pairing.draft.trimmedPortName} selected, not yet opened'
                          : 'No serial device selected',
                    ),
                    _SummaryRow(
                      label: 'Pairing',
                      value: _pairingStageDescription(pairing),
                    ),
                  ],
                ),
                if (pairing.statusMessage != null) ...<Widget>[
                  const SizedBox(height: LinearSpacing.md),
                  Text(
                    pairing.statusMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: chrome.textSecondary,
                    ),
                  ),
                ],
                if (pairing.errorMessage != null) ...<Widget>[
                  const SizedBox(height: LinearSpacing.xs),
                  Text(
                    pairing.errorMessage!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: chrome.danger),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _StepHeader(
                  stepLabel: 'Step 3',
                  title: 'Enter WiFi & LAN Address',
                  description: 'Enter the WiFi the robot should connect to, and the LAN address it will use to reach this computer.',
                ),
                const SizedBox(height: LinearSpacing.lg),
                _InstructionCard(
                  items: const <String>[
                    'Enter the WiFi network name the robot should connect to.',
                    'Enter the WiFi password. Leave blank for open networks.',
                    'Enter this computer\'s LAN IPv4 address. Do not use localhost.',
                  ],
                ),
                const SizedBox(height: LinearSpacing.lg),
                Wrap(
                  spacing: LinearSpacing.xs,
                  runSpacing: LinearSpacing.xs,
                  children: <Widget>[
                    StatusPill(
                      label: backendReady
                          ? 'Backend Connected'
                          : 'Backend Required',
                      tone: backendReady
                          ? StatusPillTone.success
                          : StatusPillTone.warning,
                      icon: Icons.cloud_done_outlined,
                    ),
                    StatusPill(
                      label: pairing.connectedPortName.isEmpty
                          ? 'USB Missing'
                          : 'USB Linked',
                      tone: pairing.connectedPortName.isEmpty
                          ? StatusPillTone.warning
                          : StatusPillTone.success,
                      icon: Icons.usb_outlined,
                    ),
                    StatusPill(
                      label:
                          pairing.stage == DevicePairingStage.paired ||
                              pairing.deviceOnline
                          ? 'Paired'
                          : pairing.isArmed
                          ? 'Ready To Send'
                          : 'Waiting Arm',
                      tone:
                          pairing.stage == DevicePairingStage.paired ||
                              pairing.deviceOnline
                          ? StatusPillTone.success
                          : pairing.isArmed
                          ? StatusPillTone.accent
                          : StatusPillTone.warning,
                      icon: Icons.sync_alt_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: LinearSpacing.md),
                _InlineNotice(
                  tone: _step3Guide(appState, pairing).$2,
                  message: _step3Guide(appState, pairing).$1,
                ),
                const SizedBox(height: LinearSpacing.lg),
                TextField(
                  controller: _ssidController,
                  focusNode: _ssidFocusNode,
                  enabled: fieldsEnabled,
                  onChanged: (String value) {
                    unawaited(pairingController.updateWifiSsid(value));
                  },
                  decoration: const InputDecoration(
                    labelText: 'WiFi SSID',
                    hintText: 'Office-5G, StudioLab, Guest',
                    prefixIcon: Icon(Icons.wifi_outlined),
                  ),
                ),
                const SizedBox(height: LinearSpacing.sm),
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  enabled: fieldsEnabled,
                  obscureText: true,
                  onChanged: pairingController.updateWifiPassword,
                  decoration: const InputDecoration(
                    labelText: 'WiFi Password',
                    hintText: 'Leave blank only for open networks',
                    prefixIcon: Icon(Icons.password_outlined),
                  ),
                ),
                const SizedBox(height: LinearSpacing.sm),
                TextField(
                  controller: _hostController,
                  focusNode: _hostFocusNode,
                  enabled: fieldsEnabled,
                  onChanged: (String value) {
                    unawaited(pairingController.updateHost(value));
                  },
                  decoration: const InputDecoration(
                    labelText: 'LAN Host',
                    hintText: '192.168.1.23',
                    helperText: 'The robot will use this address to connect back to this computer.',
                    prefixIcon: Icon(Icons.router_outlined),
                  ),
                ),
                if (pairing.draft.requiresExplicitLanHost) ...<Widget>[
                  const SizedBox(height: LinearSpacing.sm),
                  const _InlineNotice(
                    tone: StatusPillTone.warning,
                    message:
                        'Enter your computer\'s LAN IPv4 address. localhost, 127.0.0.1, 0.0.0.0, and ::1 only work locally and cannot be used by the robot.',
                  ),
                ],
                const SizedBox(height: LinearSpacing.lg),
                _SummaryCard(
                  title: 'Send Preview',
                  rows: <_SummaryRow>[
                    _SummaryRow(
                      label: 'USB',
                      value: pairing.connectedPortName.isNotEmpty
                          ? pairing.connectedPortName
                          : 'USB not connected',
                    ),
                    _SummaryRow(
                      label: 'LAN Host',
                      value: endpointHost.isEmpty
                          ? 'LAN Host required'
                          : endpointHost,
                      monospace: endpointHost.isNotEmpty,
                    ),
                    _SummaryRow(
                      label: 'Socket',
                      value: socketSummary,
                      monospace: showSocketAsEndpoint,
                    ),
                    _SummaryRow(label: 'Auth', value: authSummary),
                  ],
                ),
                const SizedBox(height: LinearSpacing.md),
                _InlineNotice(
                  tone:
                      pairing.stage == DevicePairingStage.paired ||
                          pairing.deviceOnline
                      ? StatusPillTone.success
                      : fieldsEnabled && pairing.draft.canSubmit
                      ? StatusPillTone.accent
                      : StatusPillTone.neutral,
                  message:
                      pairing.stage == DevicePairingStage.paired ||
                          pairing.deviceOnline
                      ? 'Pairing complete. You can now proceed to the workspace from the bottom-right.'
                      : fieldsEnabled && pairing.draft.canSubmit
                      ? 'All info provided. Click “Send Pairing” in the bottom-right.'
                      : 'Fill in WiFi and LAN Host to enable the send button in the bottom-right.',
                ),
                if (pairing.statusMessage != null) ...<Widget>[
                  const SizedBox(height: LinearSpacing.md),
                  Text(
                    pairing.statusMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: chrome.textSecondary,
                    ),
                  ),
                ],
                if (pairing.errorMessage != null) ...<Widget>[
                  const SizedBox(height: LinearSpacing.xs),
                  Text(
                    pairing.errorMessage!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: chrome.danger),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.stepLabel,
    required this.title,
    required this.description,
    this.trailing,
  });

  final String stepLabel;
  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatusPill(
                label: stepLabel,
                tone: StatusPillTone.accent,
                icon: stepLabel == 'Step 2' ? Icons.filter_2 : Icons.filter_3,
              ),
              const SizedBox(height: LinearSpacing.sm),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.linear.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: LinearSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        children: List<Widget>.generate(items.length, (int index) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == items.length - 1 ? 0 : LinearSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: chrome.surface,
                    borderRadius: LinearRadius.control,
                    border: Border.all(color: chrome.borderStandard),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: chrome.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: LinearSpacing.sm),
                Expanded(
                  child: Text(
                    items[index],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: chrome.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.tone, required this.message});

  final StatusPillTone tone;
  final String message;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final Color borderColor;
    final Color fillColor;
    final Color textColor;
    switch (tone) {
      case StatusPillTone.accent:
        borderColor = chrome.accent.withValues(alpha: 0.4);
        fillColor = chrome.accent.withValues(alpha: 0.12);
        textColor = chrome.textSecondary;
        break;
      case StatusPillTone.success:
        borderColor = chrome.success.withValues(alpha: 0.4);
        fillColor = chrome.success.withValues(alpha: 0.12);
        textColor = chrome.textSecondary;
        break;
      case StatusPillTone.warning:
        borderColor = chrome.warning.withValues(alpha: 0.4);
        fillColor = chrome.warning.withValues(alpha: 0.12);
        textColor = chrome.textSecondary;
        break;
      case StatusPillTone.danger:
        borderColor = chrome.danger.withValues(alpha: 0.4);
        fillColor = chrome.danger.withValues(alpha: 0.12);
        textColor = chrome.textSecondary;
        break;
      case StatusPillTone.neutral:
        borderColor = chrome.borderStandard;
        fillColor = chrome.panel;
        textColor = chrome.textTertiary;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: LinearRadius.card,
        border: Border.all(color: borderColor),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: textColor),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.rows});

  final String title;
  final List<_SummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final monoStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: chrome.textSecondary,
      fontFamily: 'monospace',
    );
    return Container(
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
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: LinearSpacing.md),
          ...rows.map(
            (_SummaryRow row) => Padding(
              padding: const EdgeInsets.only(bottom: LinearSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 92,
                    child: Text(
                      row.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: chrome.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: row.monospace
                          ? monoStyle
                          : Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: chrome.textSecondary,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;
}

(String, StatusPillTone) _step2Guide(
  AppState appState,
  DevicePairingStateModel pairing,
) {
  final backendReady = appState.isConnected && !appState.isDemoMode;
  if (pairing.errorMessage?.trim().isNotEmpty == true) {
    return (pairing.errorMessage!, StatusPillTone.danger);
  }
  if (!pairing.platformSupported) {
    return ('USB pairing is not supported on this platform. Please use the desktop app.', StatusPillTone.warning);
  }
  if (!backendReady) {
    return (
      appState.isDemoMode
          ? 'Demo mode cannot pair a real robot. Go back to Step 1 and connect to a live backend.'
          : 'Please complete Step 1 first. The backend is not connected yet.',
      StatusPillTone.warning,
    );
  }
  if (pairing.stage == DevicePairingStage.refreshingPorts) {
    return ('Refreshing serial port list.', StatusPillTone.accent);
  }
  if (pairing.stage == DevicePairingStage.paired || pairing.deviceOnline) {
    return ('USB step complete. The robot is online.', StatusPillTone.success);
  }
  if (pairing.stage == DevicePairingStage.sending ||
      pairing.stage == DevicePairingStage.awaitingOnline) {
    return ('The robot has received the pairing info. Keep it plugged in and powered on while it reconnects.', StatusPillTone.success);
  }
  if (pairing.connectedPortName.isEmpty && !pairing.draft.hasSelectedPort) {
    return ('Select the robot\'s serial device first.', StatusPillTone.neutral);
  }
  if (pairing.connectedPortName.isEmpty) {
    return ('Serial device selected but not opened. Click Open USB.', StatusPillTone.neutral);
  }
  if (!pairing.isArmed) {
    return ('USB is open. Now long-press the touch pad for about 5 seconds until the robot enters Armed mode.', StatusPillTone.accent);
  }
  return ('Robot is Armed. You can proceed to the next step from the bottom-right.', StatusPillTone.success);
}

(String, StatusPillTone) _step3Guide(
  AppState appState,
  DevicePairingStateModel pairing,
) {
  final backendReady = appState.isConnected && !appState.isDemoMode;
  if (pairing.errorMessage?.trim().isNotEmpty == true) {
    return (pairing.errorMessage!, StatusPillTone.danger);
  }
  if (!pairing.platformSupported) {
    return ('USB pairing is not supported on this platform.', StatusPillTone.warning);
  }
  if (!backendReady) {
    return ('Please complete Step 1 first.', StatusPillTone.warning);
  }
  if (pairing.stage == DevicePairingStage.sending) {
    return ('Sending pairing info via USB.', StatusPillTone.accent);
  }
  if (pairing.stage == DevicePairingStage.awaitingOnline) {
    return ('Pairing info sent. Waiting for the robot to reconnect via WiFi.', StatusPillTone.accent);
  }
  if (pairing.stage == DevicePairingStage.paired || pairing.deviceOnline) {
    return ('The robot is back online.', StatusPillTone.success);
  }
  if (pairing.connectedPortName.isEmpty || !pairing.isArmed) {
    return ('Please complete Step 2 first: open USB and get the robot into Armed mode.', StatusPillTone.warning);
  }
  if (!pairing.draft.hasWifiSsid) {
    return ('Enter the WiFi network name the robot should connect to.', StatusPillTone.neutral);
  }
  if (pairing.draft.requiresExplicitLanHost) {
    return ('Enter this computer\'s LAN IPv4 address.', StatusPillTone.warning);
  }
  return ('All info provided. Click “Send Pairing” in the bottom-right.', StatusPillTone.accent);
}

String _pairingStageDescription(DevicePairingStateModel pairing) {
  return switch (pairing.stage) {
    DevicePairingStage.unavailable => 'USB pairing is not supported on this platform.',
    DevicePairingStage.refreshingPorts => 'Refreshing serial port list.',
    DevicePairingStage.portReady => 'Serial device selected. Waiting to open USB.',
    DevicePairingStage.usbLinked => 'USB connected. Waiting for Armed mode.',
    DevicePairingStage.armed => 'Robot is Armed. Ready to send pairing.',
    DevicePairingStage.sending => 'Sending pairing info.',
    DevicePairingStage.awaitingOnline => 'Sent. Waiting for robot to come online.',
    DevicePairingStage.paired => 'Robot paired and back online.',
    DevicePairingStage.failed => 'Pairing failed. Please try again.',
    DevicePairingStage.idle => 'Waiting for USB serial device selection.',
  };
}
