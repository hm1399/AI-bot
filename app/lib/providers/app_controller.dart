part of 'app_providers.dart';

Future<void> _refreshRuntime(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      runtimeState: DemoServiceBundle.runtime,
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  final runtime = await controller.ref
      .read(runtimeServiceProvider)
      .fetchRuntimeState();
  controller.state = controller.state.copyWith(runtimeState: runtime);
}

Future<void> _stopCurrentTask(AppController controller) async {
  if (controller.state.runtimeState.currentTask == null) {
    controller.state = controller.state.copyWith(
      globalMessage: 'No running task to stop.',
    );
    return;
  }
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      runtimeState: controller.state.runtimeState.copyWithCurrentTask(null),
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  await controller.ref
      .read(runtimeServiceProvider)
      .stopCurrentTask(
        taskId: controller.state.runtimeState.currentTask?.taskId,
      );
  controller.state = controller.state.copyWith(
    globalMessage: 'Stop request sent to backend.',
  );
}

Future<void> _speakTestPhrase(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      globalMessage: 'Demo device accepted the test phrase.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  await controller.ref
      .read(deviceServiceProvider)
      .speak('Testing speech output from the Flutter app.');
  controller.state = controller.state.copyWith(
    globalMessage: 'Device speech request accepted.',
  );
}

Future<void> _triggerVoiceInput(AppController controller) async {
  final selectedSession = controller.state.sessions.where(
    (SessionModel item) => item.sessionId == controller.state.currentSessionId,
  );
  if (selectedSession.isNotEmpty && selectedSession.first.archived) {
    controller.state = controller.state.copyWith(
      globalMessage:
          'Restore this conversation before continuing it with voice.',
    );
    return;
  }
  final deviceOnline = controller.state.runtimeState.device.connected;
  final bridgeReady = controller.state.runtimeState.voice.desktopBridgeReady;
  final backendReported = controller.state.runtimeState.voice.reportedByBackend;

  final message = !deviceOnline
      ? 'Voice starts from the device. Bring the device online, then press and hold it to talk.'
      : !bridgeReady
      ? backendReported
            ? 'Device feedback is online, but the desktop microphone bridge is not ready yet. The app does not record directly.'
            : 'The app no longer records voice directly. Use press-to-talk on the device once the desktop microphone bridge reports ready.'
      : 'Press and hold the device to talk. Audio is captured by the desktop microphone bridge, and replies currently return as device text/status feedback.';

  controller.state = controller.state.copyWith(globalMessage: message);
}

Future<void> _loadSettings(AppController controller) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      settingsStatus: FeatureStatus.demo,
      settings: controller._demoSettings(),
      settingsMessage: 'Demo mode keeps settings local.',
    );
    return;
  }
  controller.state = controller.state.copyWith(
    settingsStatus: FeatureStatus.loading,
  );
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final settings = await controller.ref
        .read(settingsServiceProvider)
        .getSettings();
    controller.state = controller.state.copyWith(
      settingsStatus: FeatureStatus.ready,
      settings: settings,
      settingsMessage: null,
    );
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      settingsStatus: error.isBackendNotReady
          ? FeatureStatus.notReady
          : FeatureStatus.error,
      settingsMessage: error.isBackendNotReady
          ? AppConfig.backendNotReadyMessage
          : error.message,
    );
  }
}

Future<void> _saveSettings(
  AppController controller,
  AppSettingsModel draft, {
  String? apiKey,
}) async {
  if (controller.state.isDemoMode) {
    final nextSettings = draft.copyWith(
      llmApiKeyConfigured:
          controller.state.settings?.llmApiKeyConfigured == true ||
          (apiKey?.trim().isNotEmpty ?? false),
      applyResults: controller._demoApplyResults(),
    );
    controller.state = controller.state.copyWith(
      settings: nextSettings,
      settingsMessage:
          nextSettings.applySummary ?? 'Demo settings updated locally.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  final next = await controller.ref
      .read(settingsServiceProvider)
      .updateSettings(draft.toUpdate(llmApiKey: apiKey));
  controller.state = controller.state.copyWith(
    settingsStatus: FeatureStatus.ready,
    settings: next,
    settingsMessage: next.applySummary ?? 'Settings saved through the backend.',
  );
}

Future<void> _loadComputerControl(
  AppController controller, {
  bool silent = false,
}) async {
  final bootstrap = controller.state.bootstrap;
  if (bootstrap == null) {
    return;
  }

  final supportedActions = controller._computerControlSupportedActions();
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      bootstrap: controller._demoBootstrap(),
      globalMessage: silent
          ? controller.state.globalMessage
          : 'Demo mode has no live computer control.',
    );
    return;
  }

  if (!controller._computerControlAvailable()) {
    controller.state = controller.state.copyWith(
      bootstrap: bootstrap.copyWith(
        computerControl: controller._computerControlSeed(
          statusMessage:
              'Structured computer actions are unavailable on this backend.',
        ),
      ),
    );
    return;
  }

  controller._apiClient.setConnection(controller.state.connection);
  try {
    final snapshot = await controller.ref
        .read(computerControlServiceProvider)
        .getState(fallbackSupportedActions: supportedActions);
    controller.state = controller.state.copyWith(
      bootstrap: bootstrap.copyWith(computerControl: snapshot),
    );
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(
      bootstrap: bootstrap.copyWith(
        computerControl: controller._computerControlSeed(
          statusMessage: error.isBackendNotReady
              ? AppConfig.backendNotReadyMessage
              : error.message,
        ),
      ),
      globalMessage: silent ? controller.state.globalMessage : error.message,
    );
  }
}

Future<void> _runComputerAction(
  AppController controller,
  ComputerActionRequest request,
) async {
  if (!controller._computerControlAvailable()) {
    controller.state = controller.state.copyWith(
      globalMessage: 'Computer actions are not available on this backend.',
    );
    return;
  }
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      globalMessage: 'Demo mode does not execute live computer actions.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final action = await controller.ref
        .read(computerControlServiceProvider)
        .createAction(request);
    controller._storeComputerControl(
      controller
          ._computerControlSeed(clearStatusMessage: true)
          .upsertAction(action),
      globalMessage: controller._computerActionMessage(action),
    );
  } on ApiError catch (error) {
    controller._storeComputerControl(
      controller._computerControlSeed(statusMessage: error.message),
      globalMessage: error.message,
    );
  }
}

Future<void> _confirmComputerAction(
  AppController controller,
  String actionId,
) async {
  if (actionId.trim().isEmpty || controller.state.isDemoMode) {
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final action = await controller.ref
        .read(computerControlServiceProvider)
        .confirmAction(actionId);
    controller._storeComputerControl(
      controller
          ._computerControlSeed(clearStatusMessage: true)
          .upsertAction(action),
      globalMessage: controller._computerActionMessage(action),
    );
  } on ApiError catch (error) {
    controller._storeComputerControl(
      controller._computerControlSeed(statusMessage: error.message),
      globalMessage: error.message,
    );
  }
}

Future<void> _cancelComputerAction(
  AppController controller,
  String actionId,
) async {
  if (actionId.trim().isEmpty || controller.state.isDemoMode) {
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final action = await controller.ref
        .read(computerControlServiceProvider)
        .cancelAction(actionId);
    controller._storeComputerControl(
      controller
          ._computerControlSeed(clearStatusMessage: true)
          .upsertAction(action),
      globalMessage: controller._computerActionMessage(action),
    );
  } on ApiError catch (error) {
    controller._storeComputerControl(
      controller._computerControlSeed(statusMessage: error.message),
      globalMessage: error.message,
    );
  }
}

Future<void> _testAiConnection(
  AppController controller, {
  AppSettingsModel? draft,
  String? apiKey,
}) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      settingsMessage: 'Demo mode does not call the backend test endpoint.',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  final candidate = (draft ?? controller.state.settings)?.toUpdate(
    llmApiKey: apiKey,
  );
  final result = await controller.ref
      .read(settingsServiceProvider)
      .testAiConnection(draft: candidate);
  controller.state = controller.state.copyWith(
    settingsMessage: '${result.provider}/${result.model}: ${result.message}',
  );
}

Future<void> _sendDeviceCommand(
  AppController controller,
  String command, {
  Map<String, dynamic>? params,
}) async {
  if (controller.state.isDemoMode) {
    controller.state = controller.state.copyWith(
      globalMessage: 'Demo device accepted "$command".',
    );
    return;
  }
  controller._apiClient.setConnection(controller.state.connection);
  try {
    final clientCommandId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';
    final result = await controller.ref
        .read(deviceServiceProvider)
        .sendCommand(command, params: params, clientCommandId: clientCommandId);
    final acceptedCommand = result['command']?.toString() ?? command;
    final acceptedStatus = result['status']?.toString() ?? 'pending';
    controller.state = controller.state.copyWith(
      globalMessage: acceptedStatus == 'pending'
          ? 'Device command pending: $acceptedCommand.'
          : 'Device command accepted: $acceptedCommand.',
    );
    await controller.refreshRuntime();
  } on ApiError catch (error) {
    controller.state = controller.state.copyWith(globalMessage: error.message);
  }
}
