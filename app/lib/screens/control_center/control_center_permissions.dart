bool canAdjustDeviceControls({
  required bool deviceConnected,
  required bool commandPending,
}) {
  return deviceConnected;
}

bool canSendDeviceCommands({
  required bool deviceConnected,
  required bool commandPending,
}) {
  return deviceConnected && !commandPending;
}
