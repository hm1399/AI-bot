import 'dart:async';

import 'package:ai_bot_app/models/connect/connection_config_model.dart';
import 'package:ai_bot_app/models/device_pairing/device_pairing_draft_model.dart';
import 'package:ai_bot_app/models/device_pairing/device_pairing_state_model.dart';
import 'package:ai_bot_app/providers/app_providers.dart';
import 'package:ai_bot_app/services/api/api_client.dart';
import 'package:ai_bot_app/services/connect/connect_service.dart';
import 'package:ai_bot_app/services/device_pairing/device_pairing_storage_service.dart';
import 'package:ai_bot_app/services/device_pairing/serial_pairing_service_base.dart';
import 'package:ai_bot_app/services/storage/auth_storage_service.dart';
import 'package:ai_bot_app/services/storage/theme_preference_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  ProviderContainer buildContainer(_FakeSerialPairingService serial) {
    return ProviderContainer(
      overrides: <Override>[
        storageServiceProvider.overrideWithValue(_FakeAuthStorageService()),
        themePreferenceServiceProvider.overrideWithValue(
          _FakeThemePreferenceService(),
        ),
        connectServiceProvider.overrideWithValue(_FakeConnectService()),
        devicePairingStorageServiceProvider.overrideWithValue(
          _FakeDevicePairingStorageService(),
        ),
        serialPairingServiceProvider.overrideWithValue(serial),
      ],
    );
  }

  test(
    'openSelectedPort requests current pairing status and promotes armed devices',
    () async {
      final serial = _FakeSerialPairingService(
        statusResponse: const <String, dynamic>{
          'state': 'armed',
          'reason': 'touch_long_press',
        },
      );
      final container = buildContainer(serial);
      addTearDown(() {
        container.dispose();
        serial.dispose();
      });

      final controller = container.read(
        devicePairingControllerProvider.notifier,
      );
      await Future<void>.delayed(Duration.zero);

      await controller.selectPort('/dev/tty.usbmodem-test');
      await controller.openSelectedPort();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(devicePairingControllerProvider);
      expect(serial.connectedPortName, '/dev/tty.usbmodem-test');
      expect(
        serial.sentMessages.map(
          (Map<String, dynamic> message) => message['type'],
        ),
        contains('pairing.status'),
      );
      expect(state.stage, DevicePairingStage.armed);
      expect(state.transportState, 'armed');
      expect(state.transportReason, 'touch_long_press');
      expect(state.isArmed, isTrue);
    },
  );
}

class _FakeThemePreferenceService extends ThemePreferenceService {
  @override
  Future<ThemeMode?> loadThemeMode() async => null;

  @override
  Future<void> saveThemeMode(ThemeMode themeMode) async {}
}

class _FakeAuthStorageService extends AuthStorageService {
  @override
  Future<void> saveConnection(ConnectionConfigModel connection) async {}

  @override
  Future<ConnectionConfigModel?> loadConnection() async => null;
}

class _FakeConnectService extends ConnectService {
  _FakeConnectService() : super(_FakeAuthStorageService(), ApiClient());

  @override
  Future<void> saveConnection(ConnectionConfigModel config) async {}

  @override
  Future<ConnectionConfigModel?> loadConnection() async => null;
}

class _FakeDevicePairingStorageService extends DevicePairingStorageService {
  @override
  Future<void> saveDraft(DevicePairingDraftModel draft) async {}

  @override
  Future<DevicePairingDraftModel?> loadDraft() async => null;
}

class _FakeSerialPairingService implements SerialPairingService {
  _FakeSerialPairingService({this.statusResponse});

  final StreamController<SerialPairingTransportEvent> _eventsController =
      StreamController<SerialPairingTransportEvent>.broadcast();

  final Map<String, dynamic>? statusResponse;
  final List<Map<String, dynamic>> sentMessages = <Map<String, dynamic>>[];
  String? connectedPortName;

  @override
  bool get isSupported => true;

  @override
  Stream<SerialPairingTransportEvent> get events => _eventsController.stream;

  @override
  Future<List<String>> listPorts() async => const <String>[];

  @override
  Future<void> connect(String portName) async {
    connectedPortName = portName;
  }

  @override
  Future<void> sendJson(Map<String, dynamic> message) async {
    sentMessages.add(Map<String, dynamic>.from(message));
    if (message['type'] == 'pairing.status' && statusResponse != null) {
      _eventsController.add(
        SerialPairingTransportEvent(
          type: 'pairing.status',
          data: Map<String, dynamic>.from(statusResponse!),
        ),
      );
    }
  }

  @override
  Future<void> disconnect() async {
    connectedPortName = null;
  }

  @override
  void dispose() {
    _eventsController.close();
  }
}
