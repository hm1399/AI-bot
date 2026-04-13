import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/device_pairing/device_pairing_state_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../../widgets/common/status_pill.dart';
import '../../widgets/connect/device_pairing_panel.dart';

enum _ConnectWizardStep { backend, usb, config }

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '8000',
  );
  final TextEditingController _tokenController = TextEditingController();
  bool _secureConnection = false;
  _ConnectWizardStep _currentStep = _ConnectWizardStep.backend;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(appControllerProvider);
      final pairing = ref.read(devicePairingControllerProvider);
      _hostController.text = state.connection.host;
      _portController.text = '${state.connection.port}';
      _tokenController.text = state.connection.token;
      _secureConnection = state.connection.secure;
      if (!state.connection.hasServer && kIsWeb && Uri.base.host.isNotEmpty) {
        _hostController.text = Uri.base.host;
        _secureConnection = Uri.base.scheme == 'https';
      }
      if (_backendReady(state)) {
        _currentStep = _usbReady(state, pairing)
            ? _ConnectWizardStep.config
            : _ConnectWizardStep.usb;
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _useCurrentPageOrigin() {
    if (!kIsWeb || Uri.base.host.isEmpty) {
      return;
    }
    setState(() {
      _hostController.text = Uri.base.host;
      final port = Uri.base.port;
      if (port > 0) {
        _portController.text = '$port';
      }
      _secureConnection = Uri.base.scheme == 'https';
    });
  }

  bool _backendReady(AppState state) {
    return state.isConnected && !state.isDemoMode;
  }

  bool _pairingActiveOrComplete(DevicePairingStateModel pairing) {
    return pairing.stage == DevicePairingStage.sending ||
        pairing.stage == DevicePairingStage.awaitingOnline ||
        pairing.stage == DevicePairingStage.paired ||
        pairing.deviceOnline;
  }

  bool _usbReady(AppState state, DevicePairingStateModel pairing) {
    return _backendReady(state) &&
        pairing.platformSupported &&
        (pairing.connectedPortName.isNotEmpty ||
            _pairingActiveOrComplete(pairing)) &&
        (pairing.isArmed || _pairingActiveOrComplete(pairing));
  }

  void _setWizardStep(_ConnectWizardStep nextStep) {
    if (!mounted || _currentStep == nextStep) {
      return;
    }
    setState(() => _currentStep = nextStep);
  }

  void _handleAppStateChange(AppState? previous, AppState next) {
    final wasReady = previous != null && _backendReady(previous);
    final isReady = _backendReady(next);
    final pairing = ref.read(devicePairingControllerProvider);
    if (!isReady) {
      _setWizardStep(_ConnectWizardStep.backend);
      return;
    }
    if (!wasReady && isReady && _currentStep == _ConnectWizardStep.backend) {
      _setWizardStep(
        _usbReady(next, pairing)
            ? _ConnectWizardStep.config
            : _ConnectWizardStep.usb,
      );
    }
  }

  void _handlePairingChange(
    DevicePairingStateModel? previous,
    DevicePairingStateModel next,
  ) {
    final appState = ref.read(appControllerProvider);
    if (!_backendReady(appState)) {
      _setWizardStep(_ConnectWizardStep.backend);
      return;
    }
    final wasReady = previous != null && _usbReady(appState, previous);
    final isReady = _usbReady(appState, next);
    if (!wasReady && isReady && _currentStep == _ConnectWizardStep.usb) {
      _setWizardStep(_ConnectWizardStep.config);
      return;
    }
    if (!isReady &&
        _currentStep == _ConnectWizardStep.config &&
        next.stage != DevicePairingStage.sending &&
        next.stage != DevicePairingStage.awaitingOnline &&
        next.stage != DevicePairingStage.paired &&
        !next.deviceOnline) {
      _setWizardStep(_ConnectWizardStep.usb);
    }
  }

  _ConnectWizardStep _effectiveStep(
    AppState state,
    DevicePairingStateModel pairing,
  ) {
    if (!_backendReady(state)) {
      return _ConnectWizardStep.backend;
    }
    if (_currentStep == _ConnectWizardStep.config &&
        !_usbReady(state, pairing) &&
        pairing.stage != DevicePairingStage.sending &&
        pairing.stage != DevicePairingStage.awaitingOnline &&
        pairing.stage != DevicePairingStage.paired &&
        !pairing.deviceOnline) {
      return _ConnectWizardStep.usb;
    }
    return _currentStep;
  }

  Future<void> _handlePrimaryAction(
    BuildContext context,
    AppState state,
    DevicePairingStateModel pairing,
    _ConnectWizardStep step,
  ) async {
    switch (step) {
      case _ConnectWizardStep.backend:
        if (_backendReady(state)) {
          _setWizardStep(_ConnectWizardStep.usb);
        }
        break;
      case _ConnectWizardStep.usb:
        if (_usbReady(state, pairing)) {
          _setWizardStep(_ConnectWizardStep.config);
        }
        break;
      case _ConnectWizardStep.config:
        if (pairing.stage == DevicePairingStage.paired ||
            pairing.deviceOnline) {
          context.go('/app/home');
          return;
        }
        if (pairing.stage == DevicePairingStage.sending ||
            pairing.stage == DevicePairingStage.awaitingOnline) {
          return;
        }
        if (_usbReady(state, pairing) && pairing.draft.canSubmit) {
          await ref
              .read(devicePairingControllerProvider.notifier)
              .submitPairing();
        }
        break;
    }
  }

  void _handleBackAction(_ConnectWizardStep step) {
    switch (step) {
      case _ConnectWizardStep.backend:
        break;
      case _ConnectWizardStep.usb:
        _setWizardStep(_ConnectWizardStep.backend);
        break;
      case _ConnectWizardStep.config:
        _setWizardStep(_ConnectWizardStep.usb);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppState>(appControllerProvider, _handleAppStateChange);
    ref.listen<DevicePairingStateModel>(
      devicePairingControllerProvider,
      _handlePairingChange,
    );

    final state = ref.watch(appControllerProvider);
    final pairing = ref.watch(devicePairingControllerProvider);
    final chrome = context.linear;
    final backendReady = _backendReady(state);
    final usbReady = _usbReady(state, pairing);
    final pairingDone =
        pairing.stage == DevicePairingStage.paired || pairing.deviceOnline;
    final step = _effectiveStep(state, pairing);

    final String title;
    final String description;
    final String primaryLabel;
    final bool primaryEnabled;
    final bool backEnabled;
    switch (step) {
      case _ConnectWizardStep.backend:
        title = '先连接电脑端服务';
        description = '先把 App 连到 live backend。没连上之前，不显示后面的 USB 和配网内容。';
        primaryLabel = backendReady ? '下一步' : '请先完成连接';
        primaryEnabled = backendReady;
        backEnabled = false;
        break;
      case _ConnectWizardStep.usb:
        title = '连接机器人并长按触摸盘';
        description = '这一页只做 USB 配对准备：接线、选串口、打开 USB、长按触摸盘进入 Armed。';
        primaryLabel = usbReady ? '下一步' : '等待机器人就绪';
        primaryEnabled = usbReady;
        backEnabled = true;
        break;
      case _ConnectWizardStep.config:
        title = pairingDone ? '机器人已完成配对' : '填写 WiFi 和局域网地址';
        description = pairingDone
            ? '机器人已经回到在线状态。你可以进入工作台继续使用。'
            : '这一页只填写要发给机器人的网络信息，然后从右下角发送配对。';
        primaryLabel = pairingDone
            ? '打开工作台'
            : pairing.stage == DevicePairingStage.awaitingOnline
            ? '等待机器人上线'
            : pairing.stage == DevicePairingStage.sending
            ? '正在发送'
            : '发送配对';
        primaryEnabled =
            pairingDone ||
            (usbReady &&
                pairing.draft.canSubmit &&
                pairing.stage != DevicePairingStage.sending &&
                pairing.stage != DevicePairingStage.awaitingOnline);
        backEnabled =
            pairing.stage != DevicePairingStage.sending &&
            pairing.stage != DevicePairingStage.awaitingOnline;
        break;
    }

    return Scaffold(
      backgroundColor: chrome.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(LinearSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _WizardProgress(
                    currentStep: step,
                    backendReady: backendReady,
                    usbReady: usbReady,
                    pairingDone: pairingDone,
                  ),
                  const SizedBox(height: LinearSpacing.xl),
                  Container(
                    padding: const EdgeInsets.all(LinearSpacing.xl),
                    decoration: BoxDecoration(
                      color: chrome.panel,
                      borderRadius: LinearRadius.panel,
                      border: Border.all(color: chrome.borderStandard),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        StatusPill(
                          label: switch (step) {
                            _ConnectWizardStep.backend => 'Step 1',
                            _ConnectWizardStep.usb => 'Step 2',
                            _ConnectWizardStep.config => 'Step 3',
                          },
                          tone: StatusPillTone.accent,
                          icon: Icons.route_outlined,
                        ),
                        const SizedBox(height: LinearSpacing.md),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: LinearSpacing.sm),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: chrome.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: LinearSpacing.lg),
                  switch (step) {
                    _ConnectWizardStep.backend => _BackendStepCard(
                      state: state,
                      hostController: _hostController,
                      portController: _portController,
                      tokenController: _tokenController,
                      secureConnection: _secureConnection,
                      onSecureChanged: (bool value) {
                        setState(() => _secureConnection = value);
                      },
                      onUseCurrentOrigin: _useCurrentPageOrigin,
                    ),
                    _ConnectWizardStep.usb => const DevicePairingPanel(
                      mode: DevicePairingPanelMode.usb,
                    ),
                    _ConnectWizardStep.config => const DevicePairingPanel(
                      mode: DevicePairingPanelMode.config,
                    ),
                  },
                  const SizedBox(height: LinearSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(LinearSpacing.lg),
                    decoration: BoxDecoration(
                      color: chrome.surface,
                      borderRadius: LinearRadius.panel,
                      border: Border.all(color: chrome.borderStandard),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: backEnabled
                                ? () => _handleBackAction(step)
                                : null,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('返回'),
                          ),
                        ),
                        const SizedBox(width: LinearSpacing.md),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: primaryEnabled
                                ? () => _handlePrimaryAction(
                                    context,
                                    state,
                                    pairing,
                                    step,
                                  )
                                : null,
                            icon: Icon(
                              step == _ConnectWizardStep.config && pairingDone
                                  ? Icons.open_in_new
                                  : Icons.arrow_forward,
                            ),
                            label: Text(primaryLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WizardProgress extends StatelessWidget {
  const _WizardProgress({
    required this.currentStep,
    required this.backendReady,
    required this.usbReady,
    required this.pairingDone,
  });

  final _ConnectWizardStep currentStep;
  final bool backendReady;
  final bool usbReady;
  final bool pairingDone;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.all(LinearSpacing.lg),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.panel,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ProgressNode(
              index: 1,
              title: '连接服务',
              state: backendReady
                  ? _ProgressNodeState.complete
                  : currentStep == _ConnectWizardStep.backend
                  ? _ProgressNodeState.current
                  : _ProgressNodeState.upcoming,
            ),
          ),
          _ProgressConnector(
            active: backendReady || currentStep != _ConnectWizardStep.backend,
          ),
          Expanded(
            child: _ProgressNode(
              index: 2,
              title: 'USB 配对',
              state: usbReady
                  ? _ProgressNodeState.complete
                  : currentStep == _ConnectWizardStep.usb
                  ? _ProgressNodeState.current
                  : backendReady
                  ? _ProgressNodeState.upcoming
                  : _ProgressNodeState.locked,
            ),
          ),
          _ProgressConnector(
            active: usbReady || currentStep == _ConnectWizardStep.config,
          ),
          Expanded(
            child: _ProgressNode(
              index: 3,
              title: '填写并发送',
              state: pairingDone
                  ? _ProgressNodeState.complete
                  : currentStep == _ConnectWizardStep.config
                  ? _ProgressNodeState.current
                  : usbReady
                  ? _ProgressNodeState.upcoming
                  : _ProgressNodeState.locked,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ProgressNodeState { complete, current, upcoming, locked }

class _ProgressNode extends StatelessWidget {
  const _ProgressNode({
    required this.index,
    required this.title,
    required this.state,
  });

  final int index;
  final String title;
  final _ProgressNodeState state;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final bool isComplete = state == _ProgressNodeState.complete;
    final bool isCurrent = state == _ProgressNodeState.current;
    final bool isLocked = state == _ProgressNodeState.locked;
    final Color accentColor = isComplete || isCurrent
        ? chrome.accent
        : isLocked
        ? chrome.textQuaternary
        : chrome.textSecondary;

    return Row(
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isComplete || isCurrent
                ? chrome.accent.withValues(alpha: 0.14)
                : chrome.panel,
            borderRadius: LinearRadius.control,
            border: Border.all(
              color: isComplete || isCurrent
                  ? chrome.accent.withValues(alpha: 0.4)
                  : chrome.borderStandard,
            ),
          ),
          child: isComplete
              ? Icon(Icons.check, size: 16, color: accentColor)
              : Text(
                  '$index',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: accentColor),
                ),
        ),
        const SizedBox(width: LinearSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: isLocked ? chrome.textTertiary : chrome.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressConnector extends StatelessWidget {
  const _ProgressConnector({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: 28,
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: LinearSpacing.xs),
      color: active
          ? chrome.accent.withValues(alpha: 0.4)
          : chrome.borderStandard,
    );
  }
}

class _BackendStepCard extends ConsumerWidget {
  const _BackendStepCard({
    required this.state,
    required this.hostController,
    required this.portController,
    required this.tokenController,
    required this.secureConnection,
    required this.onSecureChanged,
    required this.onUseCurrentOrigin,
  });

  final AppState state;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController tokenController;
  final bool secureConnection;
  final ValueChanged<bool> onSecureChanged;
  final VoidCallback onUseCurrentOrigin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chrome = context.linear;
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
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: state.isConnected && !state.isDemoMode
                    ? 'Backend Connected'
                    : state.isDemoMode
                    ? 'Demo Mode'
                    : 'Backend Pending',
                tone: state.isConnected && !state.isDemoMode
                    ? StatusPillTone.success
                    : state.isDemoMode
                    ? StatusPillTone.warning
                    : StatusPillTone.neutral,
                icon: Icons.cloud_done_outlined,
              ),
              StatusPill(
                label: state.connection.hasServer
                    ? 'Endpoint Saved'
                    : 'No Saved Endpoint',
                tone: state.connection.hasServer
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
                icon: Icons.dns_outlined,
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.lg),
          TextField(
            controller: hostController,
            decoration: const InputDecoration(
              labelText: 'Server Host',
              hintText: '192.168.1.100, localhost, or your deployed host',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: LinearSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                ),
              ),
              const SizedBox(width: LinearSpacing.sm),
              Expanded(
                child: TextField(
                  controller: tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'App Token (optional)',
                    helperText: 'Used for both HTTP and WebSocket auth.',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.sm),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: secureConnection,
            onChanged: onSecureChanged,
            title: const Text('Use HTTPS / WSS'),
            subtitle: const Text('Enable this when the backend uses HTTPS.'),
          ),
          if (kIsWeb)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onUseCurrentOrigin,
                icon: const Icon(Icons.language),
                label: const Text('Use Current Page Origin'),
              ),
            ),
          const SizedBox(height: LinearSpacing.md),
          FilledButton(
            onPressed: state.isConnecting
                ? null
                : () async {
                    try {
                      await ref
                          .read(appControllerProvider.notifier)
                          .connect(
                            host: hostController.text.trim(),
                            port:
                                int.tryParse(portController.text.trim()) ??
                                8000,
                            secure: secureConnection,
                            token: tokenController.text.trim(),
                          );
                    } catch (_) {}
                  },
            child: Text(
              state.isConnecting
                  ? 'Validating connection...'
                  : 'Validate Connection',
            ),
          ),
          const SizedBox(height: LinearSpacing.md),
          if (state.isConnected && !state.isDemoMode)
            _InfoNotice(
              tone: StatusPillTone.success,
              message: '连接成功。现在点右下角“下一步”，进入 USB 配对页。',
            )
          else
            _InfoNotice(
              tone: state.isDemoMode
                  ? StatusPillTone.warning
                  : StatusPillTone.neutral,
              message: state.isDemoMode
                  ? 'Demo mode 不能继续机器人首配。请连接 live backend。'
                  : '先完成 live backend 连接；没连上前，不会显示 USB 和 WiFi 配对页。',
            ),
          const SizedBox(height: LinearSpacing.md),
          Container(
            padding: const EdgeInsets.all(LinearSpacing.md),
            decoration: BoxDecoration(
              color: chrome.panel,
              borderRadius: LinearRadius.card,
              border: Border.all(color: chrome.borderSubtle),
            ),
            child: Text(
              'LAN scan is intentionally removed. Discovery should return only as a real mDNS / zeroconf feature, not as a fake convenience button.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ),
          if (state.globalMessage != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            Text(
              state.globalMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: chrome.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoNotice extends StatelessWidget {
  const _InfoNotice({required this.tone, required this.message});

  final StatusPillTone tone;
  final String message;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final Color borderColor;
    final Color fillColor;
    switch (tone) {
      case StatusPillTone.accent:
        borderColor = chrome.accent.withValues(alpha: 0.4);
        fillColor = chrome.accent.withValues(alpha: 0.12);
        break;
      case StatusPillTone.success:
        borderColor = chrome.success.withValues(alpha: 0.4);
        fillColor = chrome.success.withValues(alpha: 0.12);
        break;
      case StatusPillTone.warning:
        borderColor = chrome.warning.withValues(alpha: 0.4);
        fillColor = chrome.warning.withValues(alpha: 0.12);
        break;
      case StatusPillTone.danger:
        borderColor = chrome.danger.withValues(alpha: 0.4);
        fillColor = chrome.danger.withValues(alpha: 0.12);
        break;
      case StatusPillTone.neutral:
        borderColor = chrome.borderStandard;
        fillColor = chrome.panel;
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
        ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
      ),
    );
  }
}
