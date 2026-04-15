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
        ? 'Demo mode 不提供真实设备回连端点。'
        : !canPreviewCurrentConnection
        ? '请先完成 Step 1，连接 live backend 后再生成设备回连端点。'
        : endpointHost.isEmpty
        ? '$endpointScheme://<lan-host>:$endpointPort$endpointPath'
        : '$endpointScheme://$endpointHost:$endpointPort$endpointPath';
    final authSummary = pairing.bundle == null
        ? appState.isDemoMode
              ? 'Demo mode 不会请求真实 bundle'
              : canPreviewCurrentConnection
              ? '发送时会向当前 backend 请求最新 bundle'
              : '连接 live backend 后会请求最新 bundle'
        : pairing.bundle!.requiresDeviceToken
        ? '发送时会带 device token'
        : '当前无需 device token';
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
                  title: '连接机器人并长按触摸盘',
                  description: '这一页只处理 USB：接线、选串口、打开 USB，然后长按触摸盘进入配对态。',
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
                    '把机器人用数据线接到这台电脑。',
                    '点 Refresh USB，选中正确的串口设备。',
                    '点 Open USB，然后长按触摸盘约 5 秒，直到机器人进入 Armed。',
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
                        ? 'Demo mode 不能给真实机器人配对。请先回到 Step 1 连接 live backend。'
                        : '请先完成 Step 1。当前还没有 live backend，所以不会进入 USB 配对。',
                  )
                else ...<Widget>[
                  if (pairing.availablePorts.isEmpty &&
                      !pairing.isBusy) ...<Widget>[
                    const _InlineNotice(
                      tone: StatusPillTone.neutral,
                      message: '还没有读到任何串口设备。请确认机器人已接线，然后点 Refresh USB。',
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
                  title: '当前状态',
                  rows: <_SummaryRow>[
                    _SummaryRow(
                      label: 'USB',
                      value: pairing.connectedPortName.isNotEmpty
                          ? pairing.connectedPortName
                          : pairing.draft.trimmedPortName.isNotEmpty
                          ? '${pairing.draft.trimmedPortName} 已选中，尚未打开'
                          : '还没有选择串口设备',
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
                  title: '填写 WiFi 和局域网地址',
                  description: '这一页只填写机器人要连接的 WiFi，以及机器人回连这台电脑时要使用的局域网地址。',
                ),
                const SizedBox(height: LinearSpacing.lg),
                _InstructionCard(
                  items: const <String>[
                    '填写机器人要连接的 WiFi 名称。',
                    '填写 WiFi 密码；开放网络可留空。',
                    '填写这台电脑在局域网里的 IPv4 地址，不要填 localhost。',
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
                    helperText: '机器人会用这个地址回连到这台电脑。',
                    prefixIcon: Icon(Icons.router_outlined),
                  ),
                ),
                if (pairing.draft.requiresExplicitLanHost) ...<Widget>[
                  const SizedBox(height: LinearSpacing.sm),
                  const _InlineNotice(
                    tone: StatusPillTone.warning,
                    message:
                        '这里要填你电脑的局域网 IPv4 地址。localhost、127.0.0.1、0.0.0.0、::1 只在本机有效，机器人不能用。',
                  ),
                ],
                const SizedBox(height: LinearSpacing.lg),
                _SummaryCard(
                  title: '发送预览',
                  rows: <_SummaryRow>[
                    _SummaryRow(
                      label: 'USB',
                      value: pairing.connectedPortName.isNotEmpty
                          ? pairing.connectedPortName
                          : 'USB 还未连接好',
                    ),
                    _SummaryRow(
                      label: 'LAN Host',
                      value: endpointHost.isEmpty
                          ? '需要填写 LAN Host'
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
                      ? '配对已完成。右下角现在可以直接进入工作台。'
                      : fieldsEnabled && pairing.draft.canSubmit
                      ? '信息已齐。现在点击右下角“发送配对”。'
                      : '把 WiFi 和 LAN Host 填完整后，右下角会允许发送配对。',
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
    return ('当前平台不支持 USB 首配。请在桌面版 App 上操作。', StatusPillTone.warning);
  }
  if (!backendReady) {
    return (
      appState.isDemoMode
          ? 'Demo mode 不能继续机器人首配。先回到 Step 1 连接 live backend。'
          : '请先完成 Step 1；当前 backend 还没连好。',
      StatusPillTone.warning,
    );
  }
  if (pairing.stage == DevicePairingStage.refreshingPorts) {
    return ('正在刷新串口列表。', StatusPillTone.accent);
  }
  if (pairing.stage == DevicePairingStage.paired || pairing.deviceOnline) {
    return ('USB 步骤已完成，机器人已经在线。', StatusPillTone.success);
  }
  if (pairing.stage == DevicePairingStage.sending ||
      pairing.stage == DevicePairingStage.awaitingOnline) {
    return ('机器人已经收到了配对信息，请保持接线和供电，等待它重新上线。', StatusPillTone.success);
  }
  if (pairing.connectedPortName.isEmpty && !pairing.draft.hasSelectedPort) {
    return ('先选中机器人的串口设备。', StatusPillTone.neutral);
  }
  if (pairing.connectedPortName.isEmpty) {
    return ('串口已选中，但还没打开。请点 Open USB。', StatusPillTone.neutral);
  }
  if (!pairing.isArmed) {
    return ('USB 已打开。现在长按触摸盘约 5 秒，直到机器人进入 Armed。', StatusPillTone.accent);
  }
  return ('机器人已 Armed。右下角现在可以进入下一步。', StatusPillTone.success);
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
    return ('当前平台不支持 USB 首配。', StatusPillTone.warning);
  }
  if (!backendReady) {
    return ('请先完成 Step 1。', StatusPillTone.warning);
  }
  if (pairing.stage == DevicePairingStage.sending) {
    return ('正在通过 USB 下发配对信息。', StatusPillTone.accent);
  }
  if (pairing.stage == DevicePairingStage.awaitingOnline) {
    return ('配对信息已发出，正在等待机器人重新连上 WiFi。', StatusPillTone.accent);
  }
  if (pairing.stage == DevicePairingStage.paired || pairing.deviceOnline) {
    return ('机器人已经重新上线。', StatusPillTone.success);
  }
  if (pairing.connectedPortName.isEmpty || !pairing.isArmed) {
    return ('请先完成 Step 2：USB 打开并且机器人进入 Armed。', StatusPillTone.warning);
  }
  if (!pairing.draft.hasWifiSsid) {
    return ('先填写机器人要连接的 WiFi 名称。', StatusPillTone.neutral);
  }
  if (pairing.draft.requiresExplicitLanHost) {
    return ('再填写这台电脑的局域网 IPv4 地址。', StatusPillTone.warning);
  }
  return ('信息已齐。点右下角“发送配对”。', StatusPillTone.accent);
}

String _pairingStageDescription(DevicePairingStateModel pairing) {
  return switch (pairing.stage) {
    DevicePairingStage.unavailable => '当前平台不支持 USB 首配。',
    DevicePairingStage.refreshingPorts => '正在刷新串口列表。',
    DevicePairingStage.portReady => '串口已选中，等待打开 USB。',
    DevicePairingStage.usbLinked => 'USB 已连通，等待进入 Armed。',
    DevicePairingStage.armed => '机器人已进入 Armed，可继续发送配对。',
    DevicePairingStage.sending => '正在发送配对信息。',
    DevicePairingStage.awaitingOnline => '已发送，正在等待机器人上线。',
    DevicePairingStage.paired => '机器人已完成配对并重新在线。',
    DevicePairingStage.failed => '本次配对失败，需要重新尝试。',
    DevicePairingStage.idle => '等待选择 USB 串口。',
  };
}
