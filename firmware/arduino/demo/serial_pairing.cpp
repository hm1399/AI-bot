#include "serial_pairing.h"

#include <ArduinoJson.h>

namespace {

constexpr uint32_t kSupportedSchemaVersion = 1;
constexpr size_t kMaxLineLength = 2048;

bool jsonHasString(JsonVariantConst value) {
  return value.is<const char*>();
}

}  // namespace

SerialPairingCommand::SerialPairingCommand()
    : type(SERIAL_PAIRING_COMMAND_NONE), schemaVersion(kSupportedSchemaVersion) {}

PairingStatusSnapshot::PairingStatusSnapshot()
    : provisioned(false),
      wsPort(0),
      secure(false),
      tokenPresent(false) {}

SerialPairingManager::SerialPairingManager(Stream& serial)
    : serial_(serial) {}

bool SerialPairingManager::poll(SerialPairingCommand* outCommand) {
  if (outCommand == nullptr) {
    return false;
  }

  while (serial_.available() > 0) {
    const char ch = static_cast<char>(serial_.read());
    if (ch == '\r') {
      continue;
    }

    if (ch == '\n') {
      String line = lineBuffer_;
      lineBuffer_ = "";
      line.trim();
      if (line.isEmpty()) {
        continue;
      }
      *outCommand = SerialPairingCommand();
      return parseLine(line, outCommand);
    }

    if (lineBuffer_.length() >= kMaxLineLength) {
      lineBuffer_ = "";
      sendProtocolError("line_too_long", "Pairing command exceeds maximum length");
      return false;
    }

    lineBuffer_ += ch;
  }

  return false;
}

void SerialPairingManager::sendStatus(const PairingStatusSnapshot& snapshot) {
  JsonDocument doc;
  doc["type"] = "pairing.status";
  JsonObject data = doc["data"].to<JsonObject>();
  data["state"] = snapshot.state;
  data["reason"] = snapshot.reason;
  data["device_id"] = snapshot.deviceId;
  data["firmware"] = snapshot.firmware;
  data["provisioned"] = snapshot.provisioned;

  if (!snapshot.wifiSsid.isEmpty()) {
    JsonObject wifi = data["wifi"].to<JsonObject>();
    wifi["ssid"] = snapshot.wifiSsid;
  }

  if (!snapshot.wsHost.isEmpty() || !snapshot.wsPath.isEmpty() || snapshot.wsPort > 0) {
    JsonObject server = data["server"].to<JsonObject>();
    if (!snapshot.wsHost.isEmpty()) {
      server["host"] = snapshot.wsHost;
    }
    if (snapshot.wsPort > 0) {
      server["port"] = snapshot.wsPort;
    }
    if (!snapshot.wsPath.isEmpty()) {
      server["path"] = snapshot.wsPath;
    }
    server["secure"] = snapshot.secure;
  }

  JsonObject auth = data["auth"].to<JsonObject>();
  auth["token_present"] = snapshot.tokenPresent;

  writeJsonLine(doc);
}

void SerialPairingManager::sendResult(
    bool ok,
    const char* code,
    const char* message,
    bool requiresRestart) {
  JsonDocument doc;
  doc["type"] = "pairing.result";
  JsonObject data = doc["data"].to<JsonObject>();
  data["ok"] = ok;
  data["code"] = code ? code : "";
  data["message"] = message ? message : "";
  data["requires_restart"] = requiresRestart;
  writeJsonLine(doc);
}

void SerialPairingManager::sendProtocolError(const char* code, const char* message) {
  sendResult(false, code, message, false);
}

bool SerialPairingManager::parseLine(const String& line, SerialPairingCommand* outCommand) {
  JsonDocument doc;
  const DeserializationError error = deserializeJson(doc, line);
  if (error) {
    sendProtocolError("invalid_json", error.c_str());
    return false;
  }

  const char* type = doc["type"] | "";
  if (strcmp(type, "pairing.status") == 0) {
    outCommand->type = SERIAL_PAIRING_COMMAND_STATUS;
    return true;
  }

  if (strcmp(type, "pairing.clear") == 0) {
    outCommand->type = SERIAL_PAIRING_COMMAND_CLEAR;
    return true;
  }

  if (strcmp(type, "pairing.apply") != 0) {
    sendProtocolError("unsupported_type", "Unsupported pairing message type");
    return false;
  }

  JsonObjectConst data = doc["data"].as<JsonObjectConst>();
  if (data.isNull()) {
    sendProtocolError("invalid_payload", "Missing pairing payload");
    return false;
  }

  const uint32_t schemaVersion = data["schema_version"] | kSupportedSchemaVersion;
  if (schemaVersion != kSupportedSchemaVersion) {
    sendProtocolError("unsupported_schema", "Only schema_version=1 is supported");
    return false;
  }

  JsonObjectConst wifi = data["wifi"].as<JsonObjectConst>();
  JsonObjectConst server = data["server"].as<JsonObjectConst>();
  JsonObjectConst auth = data["auth"].as<JsonObjectConst>();
  if (wifi.isNull() || server.isNull()) {
    sendProtocolError("invalid_payload", "Missing wifi or server section");
    return false;
  }

  if (!jsonHasString(wifi["ssid"]) || !jsonHasString(wifi["password"])) {
    sendProtocolError("invalid_payload", "wifi.ssid and wifi.password must be strings");
    return false;
  }

  if (!jsonHasString(server["host"]) || !jsonHasString(server["path"])) {
    sendProtocolError("invalid_payload", "server.host and server.path must be strings");
    return false;
  }

  if (!server["port"].is<int>()) {
    sendProtocolError("invalid_payload", "server.port must be an integer");
    return false;
  }

  const int port = server["port"].as<int>();
  if (port <= 0 || port > 65535) {
    sendProtocolError("invalid_payload", "server.port must be between 1 and 65535");
    return false;
  }

  DeviceConfig config;
  config.wifiSsid = String(wifi["ssid"].as<const char*>());
  config.wifiPass = String(wifi["password"].as<const char*>());
  config.wsHost = String(server["host"].as<const char*>());
  config.wsPort = static_cast<uint16_t>(port);
  config.wsPath = String(server["path"].as<const char*>());
  config.secure = server["secure"] | false;
  config.deviceToken = auth.isNull() ? "" : String(auth["device_token"] | "");
  config.provisioned = true;
  config.wsHost.trim();
  config.wsPath.trim();
  config.deviceToken.trim();
  if (!config.wsPath.isEmpty() && !config.wsPath.startsWith("/")) {
    config.wsPath = "/" + config.wsPath;
  }

  if (!config.isValid()) {
    sendProtocolError("invalid_payload", "Pairing payload is incomplete");
    return false;
  }

  outCommand->type = SERIAL_PAIRING_COMMAND_APPLY;
  outCommand->schemaVersion = schemaVersion;
  outCommand->config = config;
  return true;
}

void SerialPairingManager::writeJsonLine(JsonDocument& doc) {
  String json;
  serializeJson(doc, json);
  serial_.println(json);
}
