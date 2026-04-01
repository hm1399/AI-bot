import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/device_status.dart';

class DeviceNotifier extends StateNotifier<DeviceStatus> {
  DeviceNotifier() : super(DeviceStatus(
    isOnline: false,
    batteryLevel: 0,
    wifiStrength: 0,
    mode: DeviceMode.standby,
    isMuted: false,
    ledOn: false,
  ));

  void updateStatus(DeviceStatus newStatus) {
    state = newStatus;
  }

  void handleWsMessage(Map<String, dynamic> message) {
    if (message['type'] == 'device_status') {
      final status = DeviceStatus.fromJson(message['data']);
      updateStatus(status);
    }
  }

  void refreshStatus() {}
}

final deviceProvider = StateNotifierProvider<DeviceNotifier, DeviceStatus>((ref) {
  return DeviceNotifier();
});

final deviceWsHandlerProvider = Provider<Function>((ref) {
  return (Map<String, dynamic> message) {
    ref.read(deviceProvider.notifier).handleWsMessage(message);
  };
});