/*
 * AI-Bot Demo 固件
 * ESP32-S3 + ST7789 屏幕 + 触摸触发 + 桌面麦克风代采 + MAX98357A 喇叭回放
 *
 * 功能:
 * 1. 从 NVS 读取 WiFi / WebSocket / device token 运行时配置
 * 2. 无配置时进入首配提示态，通过 USB CDC 串口完成 pairing
 * 3. 有配置时正常连接服务端 WebSocket
 * 4. 触摸 IO7 按下发送 long_press，松开发送 long_release
 * 5. 服务端回传 PCM 16kHz/16bit/mono 音频，固件本地播放到 MAX98357A
 * 6. 屏幕显示连接状态、AI 回复文字、播放状态
 *
 * 依赖库: TFT_eSPI, WebSocketsClient (arduinoWebSockets), ArduinoJson, ESP_I2S
 * 引脚: 见 CLAUDE.md 引脚分配表
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <SPI.h>
#include <TFT_eSPI.h>
#include <ESP_I2S.h>
#include <Wire.h>
#include <math.h>

#include "device_config_store.h"
#include "face_display.h"
#include "serial_pairing.h"

// ===== 触摸引脚 =====
#define TOUCH_PIN 7
#define TOUCH_THRESHOLD 40000

// ===== MPU6050 六轴传感器 =====
#define I2C_SDA 5
#define I2C_SCL 6
#define MPU6050_ADDR 0x68
#define MPU6050_REG_PWR_MGMT_1 0x6B
#define MPU6050_REG_ACCEL_XOUT_H 0x3B
#define MPU6050_REG_WHO_AM_I 0x75

// ===== MAX98357A 喇叭引脚 =====
#define SPEAKER_BCLK 17
#define SPEAKER_LRC 18
#define SPEAKER_DOUT 21
#define SPEAKER_SD_MODE_PIN 2
#define SPEAKER_SAMPLE_RATE 16000
#define PLAYBACK_BATCH_SAMPLES 256

constexpr unsigned long NTP_UPDATE_INTERVAL = 30000;
constexpr unsigned long DEVICE_STATUS_INTERVAL = 15000;
constexpr unsigned long TOUCH_SAMPLE_INTERVAL = 20;
constexpr unsigned long REPAIR_TOUCH_HOLD_MS = 5000;
constexpr unsigned long MOTION_SAMPLE_INTERVAL = 50;
constexpr unsigned long SHAKE_WINDOW_MS = 400;
constexpr unsigned long SHAKE_COOLDOWN_MS = 1200;
constexpr unsigned long WIFI_RETRY_DELAY_MS = 500;
constexpr const char* FIRMWARE_VERSION = "demo-2026-04-11";
constexpr float SHAKE_DELTA_THRESHOLD_G = 0.75f;
constexpr int SHAKE_MIN_PEAKS = 2;

enum SpeakerSdMode {
  SPEAKER_SD_SHUTDOWN = 0,
  SPEAKER_SD_LEFT = 1,
};

enum PairingPhase {
  PAIRING_DISABLED = 0,
  PAIRING_IDLE,
  PAIRING_ARMED,
  PAIRING_APPLYING,
  PAIRING_RESTARTING,
};

// ===== 全局对象 =====
TFT_eSPI tft = TFT_eSPI();
WebSocketsClient webSocket;
I2SClass speakerI2S;
DeviceConfigStore deviceConfigStore;
SerialPairingManager serialPairing(Serial);

// ===== 状态变量 =====
DeviceConfig currentConfig;
PairingPhase pairingPhase = PAIRING_IDLE;
bool wsConnected = false;
bool introSent = false;
bool touchPressed = false;
bool voiceTouchActive = false;
bool repairHoldHandled = false;
bool motionReady = false;
bool speakerReady = false;
bool playbackActive = false;
SpeakerSdMode currentSpeakerMode = SPEAKER_SD_SHUTDOWN;
String lastReply = "";
String lastStatusBarTime = "";
String lastStatusWeather = "";
String lastPairingReason = "boot";
unsigned long touchPressedAt = 0;
unsigned long lastTouchCheck = 0;
unsigned long lastMotionCheck = 0;
unsigned long lastShakeEventAt = 0;
unsigned long lastShakeMotionAt = 0;
unsigned long lastNtpUpdate = 0;
unsigned long lastDeviceStatusPush = 0;
float previousMotionTotalG = 1.0f;
int shakeMotionPeaks = 0;

void sendTouchEvent(const char* action, int tapCount = 0, bool hold = false);
void sendShakeEvent();

int currentVolume = 70;
bool currentMuted = false;
bool currentSleeping = false;
bool ledEnabled = true;
int ledBrightness = 50;
String ledColor = "#2563eb";
const bool LED_HARDWARE_AVAILABLE = false;

// ===== 屏幕显示（通过 face_display 模块） =====

void displayInit() {
  faceInit(tft);
}

void updateStatusBar() {
  const bool wifiOk = WiFi.status() == WL_CONNECTED;
  faceSetStatusBar(
      lastStatusBarTime.isEmpty() ? nullptr : lastStatusBarTime.c_str(),
      wifiOk,
      wsConnected);
  faceSetWeather(lastStatusWeather.isEmpty() ? nullptr : lastStatusWeather.c_str());
}

// ──────────────────────────────────────────────
// 配对状态
// ──────────────────────────────────────────────

String buildDeviceId() {
  const unsigned long long chipId = static_cast<unsigned long long>(ESP.getEfuseMac());
  char buffer[24];
  snprintf(buffer, sizeof(buffer), "esp32s3-%08llx", chipId & 0xffffffffULL);
  return String(buffer);
}

const char* pairingStateLabel() {
  switch (pairingPhase) {
    case PAIRING_IDLE:
      return "idle";
    case PAIRING_ARMED:
      return "armed";
    case PAIRING_APPLYING:
      return "applying";
    case PAIRING_RESTARTING:
      return "restarting";
    case PAIRING_DISABLED:
    default:
      return currentConfig.provisioned ? "provisioned" : "idle";
  }
}

void sendPairingStatus(const char* reason) {
  if (reason != nullptr && reason[0] != '\0') {
    lastPairingReason = String(reason);
  }

  PairingStatusSnapshot snapshot;
  snapshot.state = pairingStateLabel();
  snapshot.reason = lastPairingReason;
  snapshot.deviceId = buildDeviceId();
  snapshot.firmware = FIRMWARE_VERSION;
  snapshot.provisioned = currentConfig.provisioned;
  snapshot.wifiSsid = currentConfig.wifiSsid;
  snapshot.wsHost = currentConfig.wsHost;
  snapshot.wsPort = currentConfig.wsPort;
  snapshot.wsPath = currentConfig.wsPath;
  snapshot.secure = currentConfig.secure;
  snapshot.tokenPresent = currentConfig.deviceToken.length() > 0;
  serialPairing.sendStatus(snapshot);
}

void enterPairingPrompt(const char* reason, const char* faceMessage = nullptr) {
  pairingPhase = PAIRING_IDLE;
  lastPairingReason = reason ? String(reason) : "await_long_press";
  wsConnected = false;
  introSent = false;
  voiceTouchActive = false;
  playbackActive = false;
  WiFi.mode(WIFI_OFF);
  faceSetState(FACE_IDLE);
  faceSetText(faceMessage != nullptr ? faceMessage : "请插线并长按配对");
  updateStatusBar();
  sendPairingStatus(lastPairingReason.c_str());
}

void stopRuntimeForPairing(const char* faceMessage) {
  if (voiceTouchActive && wsConnected) {
    sendTouchEvent("long_release", 0, false);
  }

  voiceTouchActive = false;
  introSent = false;
  playbackActive = false;
  wsConnected = false;
  webSocket.disconnect();
  WiFi.disconnect(false, false);
  WiFi.mode(WIFI_OFF);
  faceSetState(FACE_IDLE);
  if (faceMessage != nullptr) {
    faceSetText(faceMessage);
  }
  updateStatusBar();
}

void enterPairingMode(const char* reason) {
  if (pairingPhase == PAIRING_ARMED ||
      pairingPhase == PAIRING_APPLYING ||
      pairingPhase == PAIRING_RESTARTING) {
    return;
  }

  pairingPhase = PAIRING_ARMED;
  lastPairingReason = reason ? String(reason) : "touch_long_press";
  stopRuntimeForPairing("配对模式已就绪");
  Serial.printf("Pairing armed: %s\n", lastPairingReason.c_str());
  sendPairingStatus(lastPairingReason.c_str());
}

bool canSendVoiceTouch() {
  return pairingPhase == PAIRING_DISABLED && wsConnected && !currentSleeping;
}

bool canArmPairingFromTouch() {
  if (pairingPhase == PAIRING_APPLYING || pairingPhase == PAIRING_RESTARTING) {
    return false;
  }
  if (voiceTouchActive) {
    return false;
  }
  return !currentConfig.provisioned || pairingPhase == PAIRING_IDLE;
}

bool writeMpu6050Byte(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

bool readMpu6050Bytes(uint8_t reg, uint8_t* buffer, size_t length) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) {
    return false;
  }

  const size_t received = Wire.requestFrom(MPU6050_ADDR, static_cast<uint8_t>(length));
  if (received != length) {
    return false;
  }

  for (size_t i = 0; i < length; ++i) {
    buffer[i] = Wire.read();
  }

  return true;
}

bool readMotionTotalG(float* totalG) {
  uint8_t raw[6];
  if (!readMpu6050Bytes(MPU6050_REG_ACCEL_XOUT_H, raw, sizeof(raw))) {
    return false;
  }

  const int16_t ax = static_cast<int16_t>((raw[0] << 8) | raw[1]);
  const int16_t ay = static_cast<int16_t>((raw[2] << 8) | raw[3]);
  const int16_t az = static_cast<int16_t>((raw[4] << 8) | raw[5]);
  const float axG = static_cast<float>(ax) / 16384.0f;
  const float ayG = static_cast<float>(ay) / 16384.0f;
  const float azG = static_cast<float>(az) / 16384.0f;
  *totalG = sqrtf(axG * axG + ayG * ayG + azG * azG);
  return true;
}

bool initMotionSensor() {
  Wire.begin(I2C_SDA, I2C_SCL);

  uint8_t whoami = 0;
  if (!readMpu6050Bytes(MPU6050_REG_WHO_AM_I, &whoami, 1)) {
    Serial.println("MPU6050 not detected, gesture events disabled");
    return false;
  }

  if (whoami != 0x68 && whoami != 0x98) {
    Serial.printf("Unexpected MPU6050 WHO_AM_I: 0x%02X\n", whoami);
    return false;
  }

  if (!writeMpu6050Byte(MPU6050_REG_PWR_MGMT_1, 0x00)) {
    Serial.println("Failed to wake MPU6050, gesture events disabled");
    return false;
  }

  delay(100);

  float totalG = 1.0f;
  if (readMotionTotalG(&totalG)) {
    previousMotionTotalG = totalG;
  }

  Serial.printf("MPU6050 ready (WHO_AM_I=0x%02X)\n", whoami);
  return true;
}

bool canSendGestureEvent() {
  if (pairingPhase != PAIRING_DISABLED || !wsConnected || currentSleeping) {
    return false;
  }
  if (voiceTouchActive || playbackActive) {
    return false;
  }

  FaceState faceState = faceGetState();
  return faceState != FACE_LISTENING &&
         faceState != FACE_PROCESSING &&
         faceState != FACE_SPEAKING;
}

void showGestureFeedback(const char* text) {
  if (!canSendGestureEvent()) {
    return;
  }

  faceSetState(FACE_ACTIVE);
  faceSetText(text);
}

// ──────────────────────────────────────────────
// 喇叭初始化 / 播放
// ──────────────────────────────────────────────

const char* speakerModeName(SpeakerSdMode mode) {
  switch (mode) {
    case SPEAKER_SD_SHUTDOWN:
      return "shutdown";
    case SPEAKER_SD_LEFT:
      return "left channel";
    default:
      return "unknown";
  }
}

void applySpeakerMode(SpeakerSdMode mode) {
  pinMode(SPEAKER_SD_MODE_PIN, OUTPUT);
  digitalWrite(SPEAKER_SD_MODE_PIN, mode == SPEAKER_SD_LEFT ? HIGH : LOW);
  currentSpeakerMode = mode;
  delay(10);
  Serial.printf(
      "Speaker SD_MODE -> %s (IO%d = %s)\n",
      speakerModeName(mode),
      SPEAKER_SD_MODE_PIN,
      mode == SPEAKER_SD_LEFT ? "HIGH" : "LOW");
}

bool initSpeaker() {
  applySpeakerMode(SPEAKER_SD_LEFT);

  speakerI2S.setPins(SPEAKER_BCLK, SPEAKER_LRC, SPEAKER_DOUT);
  if (!speakerI2S.begin(
          I2S_MODE_STD,
          SPEAKER_SAMPLE_RATE,
          I2S_DATA_BIT_WIDTH_16BIT,
          I2S_SLOT_MODE_STEREO)) {
    Serial.println("Speaker I2S init failed");
    applySpeakerMode(SPEAKER_SD_SHUTDOWN);
    return false;
  }

  Serial.printf(
      "Speaker initialized: BCLK=IO%d, LRC=IO%d, DOUT=IO%d, SD_MODE=IO%d\n",
      SPEAKER_BCLK,
      SPEAKER_LRC,
      SPEAKER_DOUT,
      SPEAKER_SD_MODE_PIN);
  return true;
}

void playMonoPcmChunk(const uint8_t* payload, size_t length) {
  if (!speakerReady ||
      !playbackActive ||
      payload == nullptr ||
      length < 2 ||
      currentMuted ||
      currentSleeping ||
      currentVolume <= 0) {
    return;
  }

  if (currentSpeakerMode != SPEAKER_SD_LEFT) {
    applySpeakerMode(SPEAKER_SD_LEFT);
  }

  const int16_t* monoSamples = reinterpret_cast<const int16_t*>(payload);
  size_t sampleCount = length / sizeof(int16_t);
  int16_t stereoBuffer[PLAYBACK_BATCH_SAMPLES * 2];
  size_t offset = 0;

  while (offset < sampleCount) {
    size_t batch = sampleCount - offset;
    if (batch > PLAYBACK_BATCH_SAMPLES) {
      batch = PLAYBACK_BATCH_SAMPLES;
    }

    for (size_t i = 0; i < batch; ++i) {
      int16_t sample = monoSamples[offset + i];
      int32_t scaled = (static_cast<int32_t>(sample) * currentVolume) / 100;
      if (scaled > 32767) {
        scaled = 32767;
      } else if (scaled < -32768) {
        scaled = -32768;
      }
      stereoBuffer[i * 2] = static_cast<int16_t>(scaled);
      stereoBuffer[i * 2 + 1] = static_cast<int16_t>(scaled);
    }

    speakerI2S.write(
        reinterpret_cast<const uint8_t*>(stereoBuffer),
        batch * 2 * sizeof(int16_t));
    offset += batch;
  }
}

// ──────────────────────────────────────────────
// WebSocket 上行消息
// ──────────────────────────────────────────────

void sendTextInput(const char* text) {
  if (!wsConnected) return;

  JsonDocument doc;
  doc["type"] = "text_input";
  JsonObject data = doc["data"].to<JsonObject>();
  data["text"] = text;

  String json;
  serializeJson(doc, json);
  webSocket.sendTXT(json);
  Serial.printf("Sent text_input: %s\n", text);
}

void sendTouchEvent(const char* action, int tapCount, bool hold) {
  if (!wsConnected) return;

  JsonDocument doc;
  doc["type"] = "touch_event";
  JsonObject data = doc["data"].to<JsonObject>();
  if (action != nullptr && action[0] != '\0') {
    data["action"] = action;
  }
  if (tapCount > 0) {
    data["tap_count"] = tapCount;
  }
  data["hold"] = hold;

  String json;
  serializeJson(doc, json);
  webSocket.sendTXT(json);
  Serial.printf(
      "Sent touch_event: action=%s tap_count=%d hold=%d\n",
      action ? action : "-",
      tapCount,
      hold ? 1 : 0);
}

void sendShakeEvent() {
  if (!wsConnected) return;

  JsonDocument doc;
  doc["type"] = "shake_event";
  doc["data"].to<JsonObject>();

  String json;
  serializeJson(doc, json);
  webSocket.sendTXT(json);
  Serial.println("Sent shake_event");
}

void sendDeviceStatus() {
  if (!wsConnected) return;

  JsonDocument doc;
  doc["type"] = "device_status";
  JsonObject data = doc["data"].to<JsonObject>();
  data["battery"] = -1;
  data["wifi_rssi"] = WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0;
  data["charging"] = false;
  data["volume"] = currentVolume;
  data["muted"] = currentMuted;
  data["sleeping"] = currentSleeping;
  JsonObject led = data["led"].to<JsonObject>();
  led["enabled"] = ledEnabled;
  led["brightness"] = ledBrightness;
  led["color"] = ledColor;
  JsonObject statusBar = data["status_bar"].to<JsonObject>();
  if (!lastStatusBarTime.isEmpty()) {
    statusBar["time"] = lastStatusBarTime;
  }
  if (!lastStatusWeather.isEmpty()) {
    statusBar["weather"] = lastStatusWeather;
  }

  String json;
  serializeJson(doc, json);
  webSocket.sendTXT(json);
  Serial.printf(
      "Sent device_status: wifi=%d volume=%d muted=%d sleeping=%d\n",
      WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0,
      currentVolume,
      currentMuted ? 1 : 0,
      currentSleeping ? 1 : 0);
}

JsonObject beginDeviceCommandResult(
    JsonDocument& doc,
    const String& commandId,
    const String& clientCommandId,
    const String& command,
    bool ok,
    const String& error) {
  doc["type"] = "device_command_result";
  JsonObject data = doc["data"].to<JsonObject>();
  data["command_id"] = commandId;
  if (clientCommandId.length() > 0) {
    data["client_command_id"] = clientCommandId;
  }
  data["command"] = command;
  data["ok"] = ok;
  data["error"] = error;
  return data;
}

void sendCommandResultDoc(JsonDocument& doc) {
  String json;
  serializeJson(doc, json);
  webSocket.sendTXT(json);
  Serial.printf("Sent device_command_result: %s\n", json.c_str());
}

void sendDeviceCommandFailure(
    const String& commandId,
    const String& clientCommandId,
    const String& command,
    const String& error) {
  JsonDocument doc;
  beginDeviceCommandResult(doc, commandId, clientCommandId, command, false, error);
  sendCommandResultDoc(doc);
  sendDeviceStatus();
}

void handleDeviceCommand(JsonObject data) {
  const char* commandIdValue = data["command_id"] | "";
  const char* clientCommandIdValue = data["client_command_id"] | "";
  const char* commandValue = data["command"] | "";
  JsonObject params = data["params"].as<JsonObject>();

  String commandId = String(commandIdValue);
  String clientCommandId = String(clientCommandIdValue);
  String command = String(commandValue);

  if (command.length() == 0) {
    sendDeviceCommandFailure(commandId, clientCommandId, command, "invalid_command");
    return;
  }

  if (command == "set_volume") {
    if (params.isNull() || !params["level"].is<int>()) {
      sendDeviceCommandFailure(commandId, clientCommandId, command, "invalid_params");
      return;
    }
    currentVolume = constrain(params["level"].as<int>(), 0, 100);
    JsonDocument doc;
    JsonObject result = beginDeviceCommandResult(
        doc,
        commandId,
        clientCommandId,
        command,
        true,
        "");
    JsonObject applied = result["applied_state"].to<JsonObject>();
    applied["volume"] = currentVolume;
    sendCommandResultDoc(doc);
    sendDeviceStatus();
    return;
  }

  if (command == "mute") {
    currentMuted = !currentMuted;
    if (currentMuted) {
      playbackActive = false;
    }
    JsonDocument doc;
    JsonObject result = beginDeviceCommandResult(
        doc,
        commandId,
        clientCommandId,
        command,
        true,
        "");
    JsonObject applied = result["applied_state"].to<JsonObject>();
    applied["muted"] = currentMuted;
    sendCommandResultDoc(doc);
    sendDeviceStatus();
    return;
  }

  if (command == "wake") {
    currentSleeping = false;
    faceSetState(FACE_IDLE);
    faceSetText("设备已唤醒");
    updateStatusBar();
    JsonDocument doc;
    JsonObject result = beginDeviceCommandResult(
        doc,
        commandId,
        clientCommandId,
        command,
        true,
        "");
    JsonObject applied = result["applied_state"].to<JsonObject>();
    applied["sleeping"] = false;
    sendCommandResultDoc(doc);
    sendDeviceStatus();
    return;
  }

  if (command == "sleep") {
    currentSleeping = true;
    playbackActive = false;
    faceSetState(FACE_IDLE);
    faceSetText("设备休眠中");
    updateStatusBar();
    JsonDocument doc;
    JsonObject result = beginDeviceCommandResult(
        doc,
        commandId,
        clientCommandId,
        command,
        true,
        "");
    JsonObject applied = result["applied_state"].to<JsonObject>();
    applied["sleeping"] = true;
    sendCommandResultDoc(doc);
    sendDeviceStatus();
    return;
  }

  if (command == "restart") {
    JsonDocument doc;
    JsonObject result = beginDeviceCommandResult(
        doc,
        commandId,
        clientCommandId,
        command,
        true,
        "");
    JsonObject applied = result["applied_state"].to<JsonObject>();
    applied["restarting"] = true;
    sendCommandResultDoc(doc);
    sendDeviceStatus();
    delay(150);
    ESP.restart();
    return;
  }

  if (command == "toggle_led" ||
      command == "set_led_brightness" ||
      command == "set_led_color") {
    if (!LED_HARDWARE_AVAILABLE) {
      sendDeviceCommandFailure(
          commandId,
          clientCommandId,
          command,
          "hardware_unavailable");
      return;
    }
  }

  sendDeviceCommandFailure(commandId, clientCommandId, command, "unsupported_command");
}

// ──────────────────────────────────────────────
// WebSocket 事件处理
// ──────────────────────────────────────────────

void handleServerMessage(uint8_t* payload, size_t length) {
  Serial.printf("[WS RX] %.*s\n", static_cast<int>(length), reinterpret_cast<char*>(payload));

  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, payload, length);
  if (err) {
    Serial.printf("JSON parse error: %s\n", err.c_str());
    return;
  }

  const char* type = doc["type"] | "";
  JsonObject data = doc["data"];

  if (strcmp(type, "text_reply") == 0) {
    const char* text = data["text"] | "";
    Serial.printf("[text_reply] %s\n", text);
    lastReply = String(text);
    faceSetText(text);

  } else if (strcmp(type, "state_change") == 0) {
    const char* state = data["state"] | "";
    Serial.printf("[state_change] %s\n", state);
    if (strcmp(state, "IDLE") == 0) {
      faceSetState(FACE_IDLE);
    } else if (strcmp(state, "LISTENING") == 0) {
      faceSetState(FACE_LISTENING);
    } else if (strcmp(state, "PROCESSING") == 0) {
      faceSetState(FACE_PROCESSING);
      faceSetText("思考中...");
    } else if (strcmp(state, "SPEAKING") == 0) {
      faceSetState(FACE_SPEAKING);
    }

  } else if (strcmp(type, "display_update") == 0) {
    const char* text = data["text"] | "";
    Serial.printf("[display_update] %s\n", text);
    lastReply = String(text);
    faceSetText(text);

  } else if (strcmp(type, "face_update") == 0) {
    const char* faceState = data["state"] | "";
    Serial.printf("[face_update] %s\n", faceState);
    if (strcmp(faceState, "ACTIVE") == 0) {
      faceSetState(FACE_ACTIVE);
    } else if (strcmp(faceState, "IDLE") == 0) {
      faceSetState(FACE_IDLE);
    }

  } else if (strcmp(type, "status_bar_update") == 0) {
    const char* timeStr = data["time"] | nullptr;
    int battery = data["battery"] | -1;
    const char* weather = data["weather"] | nullptr;
    Serial.printf(
        "[status_bar_update] time=%s battery=%d weather=%s\n",
        timeStr ? timeStr : "null",
        battery,
        weather ? weather : "null");
    if (timeStr) {
      lastStatusBarTime = String(timeStr);
    }
    if (weather) {
      lastStatusWeather = String(weather);
    }
    faceSetStatusBar(timeStr, WiFi.status() == WL_CONNECTED, wsConnected);
    if (battery >= 0) {
      faceSetBattery(battery);
    }
    if (weather) {
      faceSetWeather(weather);
    }

  } else if (strcmp(type, "device_command") == 0) {
    handleDeviceCommand(data);

  } else if (strcmp(type, "audio_play") == 0) {
    playbackActive = true;
    Serial.println("[audio_play] start");

  } else if (strcmp(type, "audio_play_end") == 0) {
    playbackActive = false;
    Serial.println("[audio_play_end] done");

  } else {
    Serial.printf("[unknown type] %s\n", type);
  }
}

void webSocketEvent(WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      wsConnected = false;
      introSent = false;
      voiceTouchActive = false;
      playbackActive = false;
      Serial.println("WebSocket disconnected");
      updateStatusBar();
      if (pairingPhase == PAIRING_DISABLED) {
        faceSetText("服务器已断开");
      } else {
        faceSetText("配对模式已就绪");
      }
      break;

    case WStype_CONNECTED:
      wsConnected = true;
      voiceTouchActive = false;
      Serial.println("WebSocket connected!");
      updateStatusBar();
      faceSetText("已连接服务器");
      sendDeviceStatus();

      if (!introSent) {
        delay(500);
        sendTextInput("设备已连接，请用中文简短地自我介绍一下（不超过50字）");
        introSent = true;
      }
      break;

    case WStype_TEXT:
      handleServerMessage(payload, length);
      break;

    case WStype_BIN:
      if (playbackActive) {
        playMonoPcmChunk(payload, length);
      }
      break;

    case WStype_PING:
    case WStype_PONG:
      break;

    default:
      break;
  }
}

// ──────────────────────────────────────────────
// WiFi / WebSocket
// ──────────────────────────────────────────────

void processPairingTraffic();

bool connectWiFi() {
  if (!currentConfig.isValid()) {
    return false;
  }

  Serial.printf("Connecting to WiFi: %s\n", currentConfig.wifiSsid.c_str());
  faceSetText("WiFi 连接中...");

  WiFi.mode(WIFI_STA);
  WiFi.begin(currentConfig.wifiSsid.c_str(), currentConfig.wifiPass.c_str());

  int retry = 0;
  while (WiFi.status() != WL_CONNECTED && retry < 40) {
    unsigned long startedAt = millis();
    while (millis() - startedAt < WIFI_RETRY_DELAY_MS) {
      processPairingTraffic();
      handleTouch();
      faceUpdate();
      delay(TOUCH_SAMPLE_INTERVAL);
      if (pairingPhase != PAIRING_DISABLED) {
        Serial.println("WiFi connect aborted for pairing");
        return false;
      }
      if (WiFi.status() == WL_CONNECTED) {
        break;
      }
    }
    if (WiFi.status() == WL_CONNECTED) {
      break;
    }
    Serial.print(".");
    retry++;
  }
  Serial.println();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi connection failed!");
    faceSetText("WiFi 连接失败!");
    return false;
  }

  Serial.printf("WiFi connected! IP: %s\n", WiFi.localIP().toString().c_str());

  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  Serial.println("NTP time sync configured (UTC+8)");

  updateStatusBar();
  faceSetText("WiFi 已连接");
  return true;
}

void beginProvisionedWebSocket() {
  if (!currentConfig.isValid()) {
    return;
  }

  String wsPath = currentConfig.wsPath;
  if (!wsPath.startsWith("/")) {
    wsPath = "/" + wsPath;
  }

  Serial.printf(
      "Opening %s://%s:%u%s\n",
      currentConfig.secure ? "wss" : "ws",
      currentConfig.wsHost.c_str(),
      currentConfig.wsPort,
      wsPath.c_str());

#if defined(HAS_SSL)
  if (currentConfig.secure) {
    webSocket.beginSSL(currentConfig.wsHost.c_str(), currentConfig.wsPort, wsPath.c_str());
  } else {
    webSocket.begin(currentConfig.wsHost.c_str(), currentConfig.wsPort, wsPath.c_str());
  }
#else
  if (currentConfig.secure) {
    Serial.println("Secure WebSocket requested, but this build has no SSL support");
  }
  webSocket.begin(currentConfig.wsHost.c_str(), currentConfig.wsPort, wsPath.c_str());
#endif

  if (currentConfig.deviceToken.length() > 0) {
    String authorization = "Bearer ";
    authorization += currentConfig.deviceToken;
    webSocket.setAuthorization(authorization.c_str());
  }

  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(3000);
}

// ──────────────────────────────────────────────
// 配对处理
// ──────────────────────────────────────────────

void handlePairingApply(const DeviceConfig& config) {
  if (pairingPhase != PAIRING_ARMED) {
    serialPairing.sendResult(
        false,
        "pairing_not_armed",
        "Long press the touch pad before applying pairing",
        false);
    sendPairingStatus("await_long_press");
    return;
  }

  pairingPhase = PAIRING_APPLYING;
  faceSetState(FACE_IDLE);
  faceSetText("正在写入配置...");
  updateStatusBar();
  sendPairingStatus("apply_requested");

  if (!deviceConfigStore.save(config)) {
    pairingPhase = PAIRING_ARMED;
    faceSetText("配置写入失败");
    serialPairing.sendResult(
        false,
        "storage_write_failed",
        "Failed to persist pairing config",
        false);
    sendPairingStatus("apply_failed");
    return;
  }

  currentConfig = config;
  pairingPhase = PAIRING_RESTARTING;
  faceSetText("配置已保存，重启中...");
  sendPairingStatus("apply_saved");
  serialPairing.sendResult(true, "applied", "Pairing config saved", true);
  delay(250);
  ESP.restart();
}

void handlePairingClear() {
  if (pairingPhase != PAIRING_ARMED && pairingPhase != PAIRING_IDLE) {
    serialPairing.sendResult(
        false,
        "pairing_not_armed",
        "Enter pairing mode before clearing config",
        false);
    sendPairingStatus("await_long_press");
    return;
  }

  pairingPhase = PAIRING_RESTARTING;
  faceSetState(FACE_IDLE);
  faceSetText("正在清空配置...");
  sendPairingStatus("clear_requested");

  if (!deviceConfigStore.clear()) {
    pairingPhase = currentConfig.provisioned ? PAIRING_ARMED : PAIRING_IDLE;
    faceSetText("清空配置失败");
    serialPairing.sendResult(
        false,
        "clear_failed",
        "Failed to clear pairing config",
        false);
    sendPairingStatus("clear_failed");
    return;
  }

  currentConfig.clear();
  serialPairing.sendResult(true, "cleared", "Pairing config cleared", true);
  delay(250);
  ESP.restart();
}

void handlePairingCommand(const SerialPairingCommand& command) {
  switch (command.type) {
    case SERIAL_PAIRING_COMMAND_STATUS:
      sendPairingStatus(nullptr);
      break;
    case SERIAL_PAIRING_COMMAND_APPLY:
      handlePairingApply(command.config);
      break;
    case SERIAL_PAIRING_COMMAND_CLEAR:
      handlePairingClear();
      break;
    case SERIAL_PAIRING_COMMAND_NONE:
    default:
      break;
  }
}

// ──────────────────────────────────────────────
// 触摸处理：保留 long_press / long_release，并支持长按重配
// ──────────────────────────────────────────────

void handleMotion() {
  if (!motionReady) {
    return;
  }

  float totalG = previousMotionTotalG;
  if (!readMotionTotalG(&totalG)) {
    return;
  }

  const unsigned long now = millis();
  const float deltaG = fabsf(totalG - previousMotionTotalG);

  if (!canSendGestureEvent()) {
    shakeMotionPeaks = 0;
    lastShakeMotionAt = 0;
    previousMotionTotalG = totalG;
    return;
  }

  if (deltaG >= SHAKE_DELTA_THRESHOLD_G) {
    if (shakeMotionPeaks <= 0 || now - lastShakeMotionAt > SHAKE_WINDOW_MS) {
      shakeMotionPeaks = 1;
    } else {
      shakeMotionPeaks++;
    }
    lastShakeMotionAt = now;
  } else if (shakeMotionPeaks > 0 && now - lastShakeMotionAt > SHAKE_WINDOW_MS) {
    shakeMotionPeaks = 0;
    lastShakeMotionAt = 0;
  }

  if (shakeMotionPeaks >= SHAKE_MIN_PEAKS &&
      now - lastShakeEventAt >= SHAKE_COOLDOWN_MS) {
    lastShakeEventAt = now;
    shakeMotionPeaks = 0;
    lastShakeMotionAt = 0;
    showGestureFeedback("检测到摇一摇");
    sendShakeEvent();
    Serial.printf("Shake detected: delta=%.2fG total=%.2fG\n", deltaG, totalG);
  }

  previousMotionTotalG = totalG;
}

void handleTouch() {
  const uint32_t touchVal = touchRead(TOUCH_PIN);
  const bool touched = touchVal > TOUCH_THRESHOLD;
  const unsigned long now = millis();

  if (touched && !touchPressed) {
    touchPressed = true;
    touchPressedAt = now;
    repairHoldHandled = false;

    if (canSendVoiceTouch()) {
      voiceTouchActive = true;
      Serial.println("Touch long_press");
      faceSetState(FACE_LISTENING);
      faceSetText("请对电脑说话...");
      sendTouchEvent("long_press", 0, true);
    }
  }

  if (touched && touchPressed && !repairHoldHandled) {
    if (canArmPairingFromTouch() && now - touchPressedAt >= REPAIR_TOUCH_HOLD_MS) {
      repairHoldHandled = true;
      enterPairingMode("touch_long_press");
    }
  }

  if (!touched && touchPressed) {
    touchPressed = false;
    touchPressedAt = 0;
    repairHoldHandled = false;

    if (voiceTouchActive) {
      voiceTouchActive = false;
      Serial.println("Touch long_release");
      faceSetState(FACE_PROCESSING);
      faceSetText("录音结束，识别中...");
      sendTouchEvent("long_release", 0, false);
    }
  }
}

void processPairingTraffic() {
  SerialPairingCommand command;
  while (serialPairing.poll(&command)) {
    handlePairingCommand(command);
    command = SerialPairingCommand();
  }
}

// ──────────────────────────────────────────────
// Arduino setup / loop
// ──────────────────────────────────────────────

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("\n=== AI-Bot Demo (runtime pairing + speaker playback) ===");

  displayInit();
  delay(500);

  speakerReady = initSpeaker();
  if (!speakerReady) {
    Serial.println("Speaker init failed, will continue without local playback");
    faceSetText("喇叭初始化失败");
  }

  motionReady = initMotionSensor();

  if (deviceConfigStore.load(&currentConfig)) {
    pairingPhase = PAIRING_DISABLED;
    sendPairingStatus("normal_boot");

    if (!connectWiFi()) {
      if (pairingPhase == PAIRING_DISABLED) {
        Serial.println("WiFi failed, entering pairing recovery prompt");
        enterPairingPrompt("wifi_connect_failed", "WiFi失败，请重启或长按重配");
      }
    } else if (pairingPhase == PAIRING_DISABLED) {
      beginProvisionedWebSocket();
    }
  } else {
    currentConfig.clear();
    enterPairingPrompt("await_long_press");
  }

  Serial.println("Setup complete");
}

void loop() {
  processPairingTraffic();

  if (pairingPhase == PAIRING_DISABLED) {
    webSocket.loop();
  }

  faceUpdate();

  if (millis() - lastNtpUpdate >= NTP_UPDATE_INTERVAL) {
    lastNtpUpdate = millis();
    struct tm timeinfo;
    if (getLocalTime(&timeinfo, 100)) {
      char timeBuf[8];
      strftime(timeBuf, sizeof(timeBuf), "%H:%M", &timeinfo);
      lastStatusBarTime = String(timeBuf);
      faceSetStatusBar(timeBuf, WiFi.status() == WL_CONNECTED, wsConnected);
    }
  }

  if (wsConnected && millis() - lastDeviceStatusPush >= DEVICE_STATUS_INTERVAL) {
    lastDeviceStatusPush = millis();
    sendDeviceStatus();
  }

  if (millis() - lastTouchCheck >= TOUCH_SAMPLE_INTERVAL) {
    lastTouchCheck = millis();
    handleTouch();
  }

  if (millis() - lastMotionCheck >= MOTION_SAMPLE_INTERVAL) {
    lastMotionCheck = millis();
    handleMotion();
  }
}
