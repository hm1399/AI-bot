import 'dart:async';

import 'serial_pairing_service_base.dart';

SerialPairingService createSerialPairingService() {
  return _UnsupportedSerialPairingService();
}

class _UnsupportedSerialPairingService implements SerialPairingService {
  final StreamController<SerialPairingTransportEvent> _eventsController =
      StreamController<SerialPairingTransportEvent>.broadcast();

  @override
  bool get isSupported => false;

  @override
  Stream<SerialPairingTransportEvent> get events => _eventsController.stream;

  @override
  Future<void> connect(String portName) async {
    throw UnsupportedError(
      'Robot pairing is only available on desktop builds.',
    );
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<String>> listPorts() async => const <String>[];

  @override
  Future<void> sendJson(Map<String, dynamic> message) async {
    throw UnsupportedError(
      'Robot pairing is only available on desktop builds.',
    );
  }

  @override
  void dispose() {
    _eventsController.close();
  }
}
