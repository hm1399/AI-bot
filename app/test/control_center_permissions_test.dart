import 'package:ai_bot_app/screens/control_center/control_center_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending commands still allow local control adjustments', () {
    expect(
      canAdjustDeviceControls(deviceConnected: true, commandPending: true),
      isTrue,
    );
    expect(
      canSendDeviceCommands(deviceConnected: true, commandPending: true),
      isFalse,
    );
  });
}
