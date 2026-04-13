import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/device_pairing/device_pairing_state_model.dart';
import '../../providers/app_providers.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class DevicePairingPanel extends ConsumerStatefulWidget {
  const DevicePairingPanel({super.key});

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

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final appState = ref.watch(appControllerProvider);
    final pairing = ref.watch(devicePairingControllerProvider);
    final pairingController = ref.read(
      devicePairingControllerProvider.notifier,
    );
    final backendReady = appState.isConnected && !appState.isDemoMode;
    final endpointBundle = pairing.bundle?.server;
    final endpointHost =
        endpointBundle != null && endpointBundle.host.trim().isNotEmpty
        ? endpointBundle.host.trim()
        : pairing.draft.trimmedHost;
    final endpointPort = endpointBundle?.port ?? pairing.draft.port;
    final endpointPath =
        endpointBundle?.normalizedPath ?? pairing.draft.normalizedPath;
    final endpointScheme = (endpointBundle?.secure ?? pairing.draft.secure)
        ? 'wss'
        : 'ws';
    final selectedPortValue =
        pairing.availablePorts.contains(pairing.draft.trimmedPortName)
        ? pairing.draft.trimmedPortName
        : null;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Robot Pairing',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Desktop-only USB pairing for first boot or re-pair. Connect the backend first, plug in the robot, then long-press the touch pad.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: chrome.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LinearSpacing.md),
              FilledButton.tonalIcon(
                onPressed: pairing.isBusy
                    ? null
                    : () => unawaited(pairingController.refreshPorts()),
                icon: const Icon(Icons.usb_rounded),
                label: const Text('Refresh USB'),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.lg),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: pairing.platformSupported
                    ? 'Desktop Serial Ready'
                    : 'Pairing Unavailable',
                tone: pairing.platformSupported
                    ? StatusPillTone.accent
                    : StatusPillTone.warning,
                icon: Icons.memory_outlined,
              ),
              StatusPill(
                label: backendReady
                    ? 'Backend Connected'
                    : appState.isDemoMode
                    ? 'Demo Mode Active'
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
                label: _pairingStageLabel(pairing.stage),
                tone: _pairingStageTone(pairing.stage),
                icon: Icons.sync_alt_outlined,
              ),
              StatusPill(
                label: pairing.deviceOnline
                    ? 'Device Online'
                    : 'Waiting Device',
                tone: pairing.deviceOnline
                    ? StatusPillTone.success
                    : StatusPillTone.neutral,
                icon: Icons.router_outlined,
              ),
            ],
          ),
          if (!pairing.platformSupported) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _InlineNotice(
              tone: StatusPillTone.warning,
              message:
                  'Pairing is gracefully disabled on web and unsupported targets. Use the desktop app on macOS, Linux, or Windows for USB serial provisioning.',
            ),
          ],
          if (!backendReady) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _InlineNotice(
              tone: StatusPillTone.warning,
              message: appState.isDemoMode
                  ? 'Demo mode cannot issue the real pairing bundle. Reconnect to the live backend before provisioning the robot.'
                  : 'Connect the live backend first so the app can request the pairing bundle and wait for the device to appear online.',
            ),
          ],
          if (pairing.draft.requiresExplicitLanHost) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _InlineNotice(
              tone: StatusPillTone.warning,
              message:
                  'Enter a LAN IPv4 host for the robot endpoint. localhost, 127.0.0.1, 0.0.0.0, and ::1 only work on this desktop, not on the robot.',
            ),
          ],
          const SizedBox(height: LinearSpacing.lg),
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
                    child: Text(portName, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: pairing.platformSupported
                ? (String? value) {
                    unawaited(pairingController.selectPort(value ?? ''));
                  }
                : null,
          ),
          const SizedBox(height: LinearSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: !pairing.platformSupported || pairing.isBusy
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
              ),
              const SizedBox(width: LinearSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed:
                      !pairing.platformSupported ||
                          !backendReady ||
                          pairing.isBusy
                      ? null
                      : () => unawaited(pairingController.submitPairing()),
                  child: Text(
                    pairing.stage == DevicePairingStage.awaitingOnline
                        ? 'Waiting Device Online...'
                        : pairing.stage == DevicePairingStage.sending
                        ? 'Sending Pairing Bundle...'
                        : 'Send Pairing Bundle',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.lg),
          TextField(
            controller: _ssidController,
            focusNode: _ssidFocusNode,
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
            onChanged: (String value) {
              unawaited(pairingController.updateHost(value));
            },
            decoration: const InputDecoration(
              labelText: 'LAN Host',
              hintText: '192.168.1.23',
              helperText: 'This must be reachable by the robot on WiFi.',
              prefixIcon: Icon(Icons.router_outlined),
            ),
          ),
          const SizedBox(height: LinearSpacing.lg),
          _PairingSummaryCard(
            title: 'Pairing Summary',
            rows: <_PairingSummaryRow>[
              _PairingSummaryRow(
                label: 'USB',
                value: pairing.connectedPortName.isNotEmpty
                    ? pairing.connectedPortName
                    : pairing.draft.trimmedPortName.isNotEmpty
                    ? '${pairing.draft.trimmedPortName} selected, not open yet'
                    : 'No serial device selected.',
              ),
              _PairingSummaryRow(
                label: 'Pairing',
                value:
                    pairing.transportReason == null ||
                        pairing.transportReason!.trim().isEmpty
                    ? _pairingStageDescription(pairing)
                    : '${_pairingStageDescription(pairing)} ${pairing.transportReason!}',
              ),
              _PairingSummaryRow(
                label: 'LAN Host',
                value: endpointHost.isEmpty
                    ? 'Needs LAN IPv4 input.'
                    : endpointHost,
                monospace: endpointHost.isNotEmpty,
              ),
              _PairingSummaryRow(
                label: 'Port / Path',
                value: '$endpointPort | $endpointPath',
                monospace: true,
              ),
              _PairingSummaryRow(
                label: 'Socket',
                value: endpointHost.isEmpty
                    ? '$endpointScheme://<lan-host>:$endpointPort$endpointPath'
                    : '$endpointScheme://$endpointHost:$endpointPort$endpointPath',
                monospace: true,
              ),
              _PairingSummaryRow(
                label: 'Auth',
                value: pairing.bundle == null
                    ? 'Bundle not requested yet.'
                    : pairing.bundle!.requiresDeviceToken
                    ? 'Device token included by backend.'
                    : 'No device token required.',
              ),
              if (pairing.deviceId?.trim().isNotEmpty == true)
                _PairingSummaryRow(
                  label: 'Device ID',
                  value: pairing.deviceId!,
                  monospace: true,
                ),
              if (pairing.firmwareVersion?.trim().isNotEmpty == true)
                _PairingSummaryRow(
                  label: 'Firmware',
                  value: pairing.firmwareVersion!,
                  monospace: true,
                ),
            ],
          ),
          if (pairing.statusMessage != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            Text(
              pairing.statusMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: chrome.textSecondary),
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

String _pairingStageLabel(DevicePairingStage stage) {
  return switch (stage) {
    DevicePairingStage.unavailable => 'Unavailable',
    DevicePairingStage.refreshingPorts => 'Refreshing USB',
    DevicePairingStage.portReady => 'Port Selected',
    DevicePairingStage.usbLinked => 'Waiting Arm',
    DevicePairingStage.armed => 'Armed',
    DevicePairingStage.sending => 'Writing Config',
    DevicePairingStage.awaitingOnline => 'Waiting Online',
    DevicePairingStage.paired => 'Paired',
    DevicePairingStage.failed => 'Needs Attention',
    DevicePairingStage.idle => 'Idle',
  };
}

StatusPillTone _pairingStageTone(DevicePairingStage stage) {
  return switch (stage) {
    DevicePairingStage.armed => StatusPillTone.accent,
    DevicePairingStage.awaitingOnline => StatusPillTone.warning,
    DevicePairingStage.paired => StatusPillTone.success,
    DevicePairingStage.failed => StatusPillTone.danger,
    DevicePairingStage.unavailable => StatusPillTone.warning,
    _ => StatusPillTone.neutral,
  };
}

String _pairingStageDescription(DevicePairingStateModel pairing) {
  return switch (pairing.stage) {
    DevicePairingStage.unavailable =>
      'USB serial pairing is disabled on this platform.',
    DevicePairingStage.refreshingPorts => 'Refreshing the USB serial list.',
    DevicePairingStage.portReady =>
      'Port selected. Open USB, then long-press the touch pad.',
    DevicePairingStage.usbLinked =>
      'USB linked. Waiting for pairing.status to report armed.',
    DevicePairingStage.armed => 'Device is armed and ready for pairing.apply.',
    DevicePairingStage.sending => 'Sending pairing bundle to the device.',
    DevicePairingStage.awaitingOnline =>
      'Waiting for the device to reconnect to WiFi and the backend.',
    DevicePairingStage.paired => 'Device confirmed online after pairing.',
    DevicePairingStage.failed => 'Pairing needs another attempt.',
    DevicePairingStage.idle => 'Waiting for USB device selection.',
  };
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

class _PairingSummaryCard extends StatelessWidget {
  const _PairingSummaryCard({required this.title, required this.rows});

  final String title;
  final List<_PairingSummaryRow> rows;

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
            (_PairingSummaryRow row) => Padding(
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

class _PairingSummaryRow {
  const _PairingSummaryRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;
}
