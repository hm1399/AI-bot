import 'serial_pairing_service_base.dart';
import 'serial_pairing_service_stub.dart'
    if (dart.library.io) 'serial_pairing_service_desktop.dart'
    as impl;

SerialPairingService createSerialPairingService() {
  return impl.createSerialPairingService();
}
