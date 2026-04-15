part of 'app_providers.dart';

class DevicePairingController extends StateNotifier<DevicePairingStateModel> {
  DevicePairingController(this.ref, this._storage, this._serial)
    : super(
        DevicePairingStateModel.initial(platformSupported: _serial.isSupported),
      ) {
    _serialSubscription = _serial.events.listen(_handleSerialEvent);
    final appState = ref.read(appControllerProvider);
    state = state.copyWith(
      deviceOnline: appState.runtimeState.device.connected,
    );
    Future<void>.microtask(() async {
      await _restoreDraft();
      syncConnectionDefaults(appState.connection);
      if (_serial.isSupported) {
        await refreshPorts(silent: true);
      }
    });
  }

  final Ref ref;
  final DevicePairingStorageService _storage;
  final SerialPairingService _serial;

  StreamSubscription<SerialPairingTransportEvent>? _serialSubscription;
  Timer? _devicePollTimer;
  Completer<Map<String, dynamic>>? _pendingApplyResult;
  int _devicePollAttempts = 0;

  Future<void> _restoreDraft() async {
    final saved = await _storage.loadDraft();
    if (saved == null) {
      return;
    }
    state = state.copyWith(draft: saved);
  }

  Future<void> _persistDraft(DevicePairingDraftModel draft) {
    return _storage.saveDraft(draft.copyWith(wifiPassword: ''));
  }

  void syncConnectionDefaults(ConnectionConfigModel connection) {
    if (!connection.hasServer) {
      return;
    }
    final existingHost = state.draft.trimmedHost;
    final canOverwriteHost =
        existingHost.isEmpty ||
        DevicePairingDraftModel.isLoopbackHost(existingHost);
    if (!canOverwriteHost) {
      return;
    }
    final candidate = connection.host.trim();
    if (candidate.isEmpty ||
        DevicePairingDraftModel.isLoopbackHost(candidate)) {
      return;
    }
    final nextDraft = state.draft.copyWith(host: candidate);
    state = state.copyWith(draft: nextDraft);
    unawaited(_persistDraft(nextDraft));
  }

  void onDeviceOnlineChanged(bool online) {
    state = state.copyWith(deviceOnline: online);
    if (online &&
        (state.stage == DevicePairingStage.awaitingOnline ||
            state.stage == DevicePairingStage.sending)) {
      _completePairing('Device online. Pairing complete.');
    }
  }

  Future<void> refreshPorts({bool silent = false}) async {
    if (!_serial.isSupported) {
      state = state.copyWith(
        stage: DevicePairingStage.unavailable,
        statusMessage: 'Pairing unavailable on this platform.',
        errorMessage: null,
      );
      return;
    }

    if (!silent) {
      state = state.copyWith(
        stage: DevicePairingStage.refreshingPorts,
        statusMessage: 'Refreshing serial devices...',
        errorMessage: null,
      );
    }

    try {
      final ports = await _serial.listPorts();
      final selectedPort = ports.contains(state.draft.trimmedPortName)
          ? state.draft.trimmedPortName
          : '';
      final nextDraft = selectedPort == state.draft.trimmedPortName
          ? state.draft
          : state.draft.copyWith(portName: selectedPort);
      final nextStage = _stageAfterTransportRefresh(nextDraft);
      state = state.copyWith(
        availablePorts: ports,
        draft: nextDraft,
        stage: nextStage,
        statusMessage: ports.isEmpty
            ? 'No USB serial devices detected yet.'
            : 'USB serial devices refreshed.',
        errorMessage: null,
      );
      await _persistDraft(nextDraft);
    } catch (error) {
      _setFailure('Unable to list USB serial devices.', error.toString());
    }
  }

  DevicePairingStage _stageAfterTransportRefresh(
    DevicePairingDraftModel draft,
  ) {
    if (state.stage == DevicePairingStage.awaitingOnline) {
      return DevicePairingStage.awaitingOnline;
    }
    if (state.stage == DevicePairingStage.paired) {
      return DevicePairingStage.paired;
    }
    if (state.transportState == 'armed') {
      return DevicePairingStage.armed;
    }
    if (state.connectedPortName.isNotEmpty) {
      return DevicePairingStage.usbLinked;
    }
    return draft.hasSelectedPort
        ? DevicePairingStage.portReady
        : DevicePairingStage.idle;
  }

  Future<void> selectPort(String portName) async {
    final trimmed = portName.trim();
    if (trimmed == state.draft.trimmedPortName) {
      return;
    }
    if (state.connectedPortName.isNotEmpty &&
        state.connectedPortName != trimmed) {
      await closePort();
    }
    final nextDraft = state.draft.copyWith(portName: trimmed);
    state = state.copyWith(
      draft: nextDraft,
      stage: trimmed.isEmpty
          ? DevicePairingStage.idle
          : DevicePairingStage.portReady,
      statusMessage: trimmed.isEmpty
          ? 'Select a USB serial device to start pairing.'
          : 'USB serial selected. Open the port, then long-press the robot touch pad.',
      errorMessage: null,
    );
    await _persistDraft(nextDraft);
  }

  Future<void> openSelectedPort() async {
    if (!_serial.isSupported) {
      state = state.copyWith(
        stage: DevicePairingStage.unavailable,
        statusMessage: 'Pairing unavailable on this platform.',
        errorMessage: null,
      );
      return;
    }
    if (!state.draft.hasSelectedPort) {
      _setFailure('Select a USB serial device first.', null);
      return;
    }

    try {
      await _serial.connect(state.draft.trimmedPortName);
      state = state.copyWith(
        connectedPortName: state.draft.trimmedPortName,
        stage: DevicePairingStage.usbLinked,
        transportState: 'idle',
        transportReason: 'Hold the robot touch pad to arm pairing.',
        statusMessage:
            'USB linked. Hold the touch pad until the device reports pairing armed.',
        errorMessage: null,
      );
    } catch (error) {
      _setFailure(
        'Unable to open the selected USB serial device.',
        error.toString(),
      );
    }
  }

  Future<void> closePort() async {
    _cancelDevicePolling();
    _pendingApplyResult = null;
    await _serial.disconnect();
    final nextStage = state.draft.hasSelectedPort
        ? DevicePairingStage.portReady
        : DevicePairingStage.idle;
    state = state.copyWith(
      connectedPortName: '',
      transportState: 'idle',
      transportReason: state.draft.hasSelectedPort
          ? 'Open USB again to listen for pairing status.'
          : 'Select a USB serial device to start pairing.',
      stage: nextStage,
      statusMessage: state.draft.hasSelectedPort
          ? 'USB released.'
          : 'Select a USB serial device to start pairing.',
      errorMessage: null,
    );
  }

  Future<void> updateWifiSsid(String value) async {
    final nextDraft = state.draft.copyWith(wifiSsid: value);
    state = state.copyWith(draft: nextDraft, errorMessage: null);
    await _persistDraft(nextDraft);
  }

  void updateWifiPassword(String value) {
    final nextDraft = state.draft.copyWith(wifiPassword: value);
    state = state.copyWith(draft: nextDraft, errorMessage: null);
  }

  Future<void> updateHost(String value) async {
    final nextDraft = state.draft.copyWith(host: value);
    state = state.copyWith(draft: nextDraft, errorMessage: null);
    await _persistDraft(nextDraft);
  }

  Future<void> submitPairing() async {
    final appState = ref.read(appControllerProvider);
    if (!appState.isConnected || appState.isDemoMode) {
      _setFailure(
        'Connect the live backend before starting robot pairing.',
        null,
      );
      return;
    }
    if (!state.draft.hasSelectedPort) {
      _setFailure('Select and open a USB serial device first.', null);
      return;
    }
    if (state.connectedPortName.isEmpty) {
      _setFailure('Open the USB serial device first.', null);
      return;
    }
    if (!state.isArmed) {
      _setFailure(
        'Long-press the robot touch pad until pairing is armed before sending.',
        null,
      );
      return;
    }
    if (!state.draft.hasWifiSsid) {
      _setFailure('Enter the robot WiFi SSID first.', null);
      return;
    }
    if (state.draft.requiresExplicitLanHost) {
      _setFailure(
        'Use a LAN IPv4 host for the device endpoint. localhost and loopback addresses will not work on the robot.',
        null,
      );
      return;
    }

    _cancelDevicePolling();
    state = state.copyWith(
      stage: DevicePairingStage.sending,
      statusMessage: 'Requesting pairing bundle from the backend...',
      errorMessage: null,
      deviceOnline: false,
    );

    try {
      final bundle = await _requestBundle(host: state.draft.trimmedHost);
      state = state.copyWith(
        bundle: bundle,
        statusMessage: 'Sending pairing bundle over USB...',
        errorMessage: null,
      );

      final completer = Completer<Map<String, dynamic>>();
      _pendingApplyResult = completer;
      await _serial.sendJson(
        bundle.toPairingApplyEnvelope(
          wifiSsid: state.draft.trimmedWifiSsid,
          wifiPassword: state.draft.wifiPassword,
        ),
      );

      final result = await completer.future.timeout(
        const Duration(seconds: 18),
        onTimeout: () => throw StateError(
          'Timed out waiting for pairing.result from the device.',
        ),
      );

      if (result['ok'] != true) {
        final detail =
            result['reason']?.toString() ??
            result['message']?.toString() ??
            'Device rejected the pairing payload.';
        _setFailure('Device did not accept the pairing payload.', detail);
        return;
      }

      _pendingApplyResult = null;
      _beginAwaitDeviceOnline();
    } on ApiError catch (error) {
      final message = error.isBackendNotReady
          ? 'Pairing bundle endpoint is not ready on the backend yet. The frontend contract is wired and waiting for server support.'
          : error.message;
      _setFailure('Unable to fetch the pairing bundle.', message);
    } catch (error) {
      _setFailure(
        'Unable to send the pairing payload over USB.',
        error.toString(),
      );
    }
  }

  Future<DevicePairingBundleModel> _requestBundle({
    required String host,
  }) async {
    final appState = ref.read(appControllerProvider);
    final apiClient = ref.read(apiClientProvider);
    apiClient.setConnection(appState.connection);
    return apiClient.post(
      ApiConstants.devicePairingBundlePath,
      body: <String, dynamic>{'host': host},
      parser: (dynamic data) => DevicePairingBundleModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  void _beginAwaitDeviceOnline() {
    state = state.copyWith(
      stage: DevicePairingStage.awaitingOnline,
      statusMessage:
          'Config written. Waiting for the device to reconnect over WiFi and /ws/device.',
      errorMessage: null,
    );

    if (ref.read(appControllerProvider).runtimeState.device.connected) {
      _completePairing('Device online. Pairing complete.');
      return;
    }

    _devicePollAttempts = 0;
    _devicePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollDeviceOnline());
    });
    unawaited(_pollDeviceOnline());
  }

  Future<void> _pollDeviceOnline() async {
    if (state.stage != DevicePairingStage.awaitingOnline) {
      return;
    }
    _devicePollAttempts += 1;
    try {
      await ref.read(appControllerProvider.notifier).refreshRuntime();
      if (ref.read(appControllerProvider).runtimeState.device.connected) {
        _completePairing('Device online. Pairing complete.');
        return;
      }
    } catch (_) {
      // Keep waiting. The realtime stream may still report the device state.
    }

    if (_devicePollAttempts >= 20) {
      _setFailure(
        'The device did not come online yet.',
        'Check WiFi credentials, LAN host reachability, and device power, then retry pairing.',
      );
    }
  }

  void _handleSerialEvent(SerialPairingTransportEvent event) {
    switch (event.type) {
      case 'pairing.status':
        final nextTransportState =
            event.data['state']?.toString().trim().toLowerCase() ?? 'idle';
        final reason = event.data['reason']?.toString();
        final nextStage = switch (nextTransportState) {
          'armed' => DevicePairingStage.armed,
          'applying' => DevicePairingStage.sending,
          'restarting' => DevicePairingStage.awaitingOnline,
          _ =>
            state.connectedPortName.isNotEmpty
                ? DevicePairingStage.usbLinked
                : state.stage,
        };
        state = state.copyWith(
          stage: nextStage,
          transportState: nextTransportState,
          transportReason: reason,
          deviceId: event.data['device_id']?.toString(),
          firmwareVersion: event.data['firmware']?.toString(),
          statusMessage: _transportStatusMessage(nextTransportState, reason),
          errorMessage: null,
        );
        break;
      case 'pairing.result':
        final resultData = <String, dynamic>{...event.data};
        if (!(_pendingApplyResult?.isCompleted ?? true)) {
          _pendingApplyResult?.complete(resultData);
        }
        break;
      case 'serial.closed':
        if (state.stage == DevicePairingStage.awaitingOnline) {
          state = state.copyWith(
            connectedPortName: '',
            transportState: 'restarting',
            transportReason: 'Device rebooted after pairing apply.',
            stage: DevicePairingStage.awaitingOnline,
            statusMessage:
                'Device rebooted after pairing. Waiting for WiFi and /ws/device reconnect.',
            errorMessage: null,
          );
          break;
        }
        final nextStage = state.draft.hasSelectedPort
            ? DevicePairingStage.portReady
            : DevicePairingStage.idle;
        state = state.copyWith(
          connectedPortName: '',
          transportState: 'idle',
          transportReason: 'USB serial connection closed.',
          stage: nextStage,
          statusMessage: 'USB serial connection closed.',
          errorMessage: null,
        );
        break;
      case 'serial.error':
        _setFailure(
          'USB serial transport reported an error.',
          event.data['message']?.toString(),
        );
        break;
      case 'serial.raw':
        state = state.copyWith(
          statusMessage: event.data['line']?.toString() ?? state.statusMessage,
        );
        break;
    }
  }

  String _transportStatusMessage(String transportState, String? reason) {
    return switch (transportState) {
      'armed' => 'Device armed. Send the pairing bundle now.',
      'applying' => 'Device is applying the pairing payload.',
      'restarting' =>
        'Device acknowledged pairing. Waiting for WiFi and runtime reconnect.',
      _ =>
        reason == null || reason.trim().isEmpty
            ? 'USB linked. Hold the touch pad until the device reports pairing armed.'
            : 'USB linked: $reason',
    };
  }

  void _completePairing(String message) {
    _cancelDevicePolling();
    _pendingApplyResult = null;
    state = state.copyWith(
      stage: DevicePairingStage.paired,
      deviceOnline: true,
      statusMessage: message,
      errorMessage: null,
    );
  }

  void _cancelDevicePolling() {
    _devicePollTimer?.cancel();
    _devicePollTimer = null;
    _devicePollAttempts = 0;
  }

  void _setFailure(String message, String? detail) {
    _cancelDevicePolling();
    if (!(_pendingApplyResult?.isCompleted ?? true)) {
      _pendingApplyResult?.complete(<String, dynamic>{
        'ok': false,
        if (detail != null && detail.trim().isNotEmpty) 'message': detail,
      });
    }
    _pendingApplyResult = null;
    state = state.copyWith(
      stage: DevicePairingStage.failed,
      statusMessage: message,
      errorMessage: detail,
    );
  }

  @override
  void dispose() {
    _cancelDevicePolling();
    _serialSubscription?.cancel();
    super.dispose();
  }
}
