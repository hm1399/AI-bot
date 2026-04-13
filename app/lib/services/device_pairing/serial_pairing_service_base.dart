import 'dart:async';

class SerialPairingTransportEvent {
  const SerialPairingTransportEvent({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;
}

abstract class SerialPairingService {
  bool get isSupported;
  Stream<SerialPairingTransportEvent> get events;

  Future<List<String>> listPorts();
  Future<void> connect(String portName);
  Future<void> sendJson(Map<String, dynamic> message);
  Future<void> disconnect();
  void dispose();
}
