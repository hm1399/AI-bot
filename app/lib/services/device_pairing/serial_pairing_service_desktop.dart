import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_pairing_service_base.dart';

SerialPairingService createSerialPairingService() {
  return _DesktopSerialPairingService();
}

class _DesktopSerialPairingService implements SerialPairingService {
  final StreamController<SerialPairingTransportEvent> _eventsController =
      StreamController<SerialPairingTransportEvent>.broadcast();

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSubscription;
  final StringBuffer _buffer = StringBuffer();

  @override
  bool get isSupported =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  Stream<SerialPairingTransportEvent> get events => _eventsController.stream;

  @override
  Future<List<String>> listPorts() async {
    if (!isSupported) {
      return const <String>[];
    }
    final ports = List<String>.from(SerialPort.availablePorts);
    ports.sort();
    return ports;
  }

  @override
  Future<void> connect(String portName) async {
    if (!isSupported) {
      throw UnsupportedError(
        'Robot pairing is only available on desktop builds.',
      );
    }
    final trimmed = portName.trim();
    if (trimmed.isEmpty) {
      throw StateError('Select a serial device first.');
    }

    await disconnect();

    final port = SerialPort(trimmed);
    if (!port.openReadWrite()) {
      port.dispose();
      throw StateError(
        SerialPort.lastError?.message ?? 'Unable to open $trimmed.',
      );
    }

    final config = SerialPortConfig()
      ..baudRate = 115200
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none;

    port.config = config;
    config.dispose();
    port.flush();

    final reader = SerialPortReader(port);
    _port = port;
    _reader = reader;
    _readerSubscription = reader.stream.listen(
      _handleChunk,
      onError: (Object error, StackTrace stackTrace) {
        _eventsController.add(
          SerialPairingTransportEvent(
            type: 'serial.error',
            data: <String, dynamic>{'message': error.toString()},
          ),
        );
      },
      onDone: () {
        _eventsController.add(
          const SerialPairingTransportEvent(
            type: 'serial.closed',
            data: <String, dynamic>{},
          ),
        );
      },
    );
  }

  void _handleChunk(Uint8List data) {
    _buffer.write(utf8.decode(data, allowMalformed: true));
    final buffered = _buffer.toString();
    final lines = buffered.split('\n');
    _buffer
      ..clear()
      ..write(lines.removeLast());
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          final type = decoded['type']?.toString() ?? 'serial.message';
          final payload = decoded['data'] is Map<String, dynamic>
              ? decoded['data'] as Map<String, dynamic>
              : <String, dynamic>{};
          _eventsController.add(
            SerialPairingTransportEvent(type: type, data: payload),
          );
          continue;
        }
      } catch (_) {
        // Fall back to exposing raw text below.
      }
      _eventsController.add(
        SerialPairingTransportEvent(
          type: 'serial.raw',
          data: <String, dynamic>{'line': line},
        ),
      );
    }
  }

  @override
  Future<void> sendJson(Map<String, dynamic> message) async {
    final port = _port;
    if (port == null || !port.isOpen) {
      throw StateError('Open a USB serial connection before sending pairing.');
    }
    final bytes = Uint8List.fromList(utf8.encode('${jsonEncode(message)}\n'));
    final written = port.write(bytes, timeout: 2000);
    if (written != bytes.length) {
      throw StateError('Serial write incomplete ($written / ${bytes.length}).');
    }
    port.drain();
  }

  @override
  Future<void> disconnect() async {
    await _readerSubscription?.cancel();
    _readerSubscription = null;
    _reader?.close();
    _reader = null;
    if (_port != null) {
      if (_port!.isOpen) {
        _port!.close();
      }
      _port!.dispose();
      _port = null;
    }
    _buffer.clear();
  }

  @override
  void dispose() {
    disconnect();
    _eventsController.close();
  }
}
