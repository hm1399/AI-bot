#ifndef SERIAL_PAIRING_H
#define SERIAL_PAIRING_H

#include <Arduino.h>
#include <ArduinoJson.h>

#include "device_config_store.h"

enum SerialPairingCommandType {
  SERIAL_PAIRING_COMMAND_NONE = 0,
  SERIAL_PAIRING_COMMAND_STATUS,
  SERIAL_PAIRING_COMMAND_APPLY,
  SERIAL_PAIRING_COMMAND_CLEAR,
};

struct SerialPairingCommand {
  SerialPairingCommandType type;
  uint32_t schemaVersion;
  DeviceConfig config;

  SerialPairingCommand();
};

struct PairingStatusSnapshot {
  String state;
  String reason;
  String deviceId;
  String firmware;
  bool provisioned;
  String wifiSsid;
  String wsHost;
  uint16_t wsPort;
  String wsPath;
  bool secure;
  bool tokenPresent;

  PairingStatusSnapshot();
};

class SerialPairingManager {
 public:
  explicit SerialPairingManager(Stream& serial);

  bool poll(SerialPairingCommand* outCommand);
  void sendStatus(const PairingStatusSnapshot& snapshot);
  void sendResult(bool ok, const char* code, const char* message, bool requiresRestart);
  void sendProtocolError(const char* code, const char* message);

 private:
  bool parseLine(const String& line, SerialPairingCommand* outCommand);
  void writeJsonLine(JsonDocument& doc);

  Stream& serial_;
  String lineBuffer_;
};

#endif  // SERIAL_PAIRING_H
