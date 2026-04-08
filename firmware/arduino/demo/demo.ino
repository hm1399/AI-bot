/*
 * AI-Bot Demo 固件
 * ESP32-S3 + ST7789 屏幕 + 触摸触发 + 桌面麦克风代采 + MAX98357A 喇叭回放
 *
 * 功能:
 * 1. 连接 WiFi → 连接服务端 WebSocket
 * 2. 触摸 IO7 按下发送 long_press，松开发送 long_release
 * 3. 由电脑端 desktop voice client 负责实际采音
 * 4. 服务端回传 PCM 16kHz/16bit/mono 音频，固件本地播放到 MAX98357A
 * 5. 屏幕显示连接状态、AI 回复文字、播放状态
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
#include "face_display.h"

// ===== WiFi 配置 =====
const char* WIFI_SSID = "AAAAA";  // EE3070_P1615_1 / AAAAA
const char* WIFI_PASS = "92935903";  // EE3070P1615 / 92935903

// ===== WebSocket 服务端配置 =====
const char* WS_HOST = "172.20.10.3";  // ← 改为你电脑的局域网 IP
const uint16_t WS_PORT = 8765;
const char* WS_PATH = "/ws/device";

// ===== 触摸引脚 =====
#define TOUCH_PIN 7
#define TOUCH_THRESHOLD 40000

// ===== MAX98357A 喇叭引脚 =====
#define SPEAKER_BCLK 17
#define SPEAKER_LRC 18
#define SPEAKER_DOUT 21
#define SPEAKER_SD_MODE_PIN 2
#define SPEAKER_SAMPLE_RATE 16000
#define PLAYBACK_BATCH_SAMPLES 256

enum SpeakerSdMode {
  SPEAKER_SD_SHUTDOWN = 0,
  SPEAKER_SD_LEFT = 1,
};

// ===== 全局对象 =====
TFT_eSPI tft = TFT_eSPI();
WebSocketsClient webSocket;
I2SClass speakerI2S;

// ===== 状态变量 =====
bool wsConnected = false;
bool introSent = false;
bool lastTouchPressed = false;
bool speakerReady = false;
bool playbackActive = false;
SpeakerSdMode currentSpeakerMode = SPEAKER_SD_SHUTDOWN;
String lastReply = "";
unsigned long lastTouchCheck = 0;
unsigned long lastNtpUpdate = 0;
#define NTP_UPDATE_INTERVAL 30000  // NTP 时间更新间隔 (30秒)

// ===== 屏幕显示（通过 face_display 模块） =====

void displayInit() {
  faceInit(tft);
}

void updateStatusBar() {
  bool wifiOk = (WiFi.status() == WL_CONNECTED);
  faceSetStatusBar(nullptr, wifiOk, wsConnected);
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
    mode == SPEAKER_SD_LEFT ? "HIGH" : "LOW"
  );
}

bool initSpeaker() {
  applySpeakerMode(SPEAKER_SD_LEFT);

  speakerI2S.setPins(SPEAKER_BCLK, SPEAKER_LRC, SPEAKER_DOUT);
  if (!speakerI2S.begin(
        I2S_MODE_STD,
        SPEAKER_SAMPLE_RATE,
        I2S_DATA_BIT_WIDTH_16BIT,
        I2S_SLOT_MODE_STEREO
      )) {
    Serial.println("Speaker I2S init failed");
    applySpeakerMode(SPEAKER_SD_SHUTDOWN);
    return false;
  }

  Serial.printf(
    "Speaker initialized: BCLK=IO%d, LRC=IO%d, DOUT=IO%d, SD_MODE=IO%d\n",
    SPEAKER_BCLK,
    SPEAKER_LRC,
    SPEAKER_DOUT,
    SPEAKER_SD_MODE_PIN
  );
  return true;
}

void playMonoPcmChunk(const uint8_t* payload, size_t length) {
  if (!speakerReady || !playbackActive || payload == nullptr || length < 2) {
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
      stereoBuffer[i * 2] = sample;
      stereoBuffer[i * 2 + 1] = sample;
    }

    speakerI2S.write(
      reinterpret_cast<const uint8_t*>(stereoBuffer),
      batch * 2 * sizeof(int16_t)
    );
    offset += batch;
  }
}

// ──────────────────────────────────────────────
// WiFi 连接
// ──────────────────────────────────────────────

bool connectWiFi() {
  Serial.printf("Connecting to WiFi: %s\n", WIFI_SSID);
  faceSetText("WiFi 连接中...");

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  int retry = 0;
  while (WiFi.status() != WL_CONNECTED && retry < 40) {
    delay(500);
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

  // NTP 时间同步 (UTC+8 香港)
  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  Serial.println("NTP time sync configured (UTC+8)");

  updateStatusBar();
  faceSetText("WiFi 已连接");
  return true;
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

void sendTouchEvent(const char* action) {
  if (!wsConnected) return;

  JsonDocument doc;
  doc["type"] = "touch_event";
  JsonObject data = doc["data"].to<JsonObject>();
  data["action"] = action;

  String json;
  serializeJson(doc, json);
  webSocket.sendTXT(json);
  Serial.printf("Sent touch_event: %s\n", action);
}

// ──────────────────────────────────────────────
// WebSocket 事件处理
// ──────────────────────────────────────────────

void handleServerMessage(uint8_t* payload, size_t length) {
  Serial.printf("[WS RX] %.*s\n", (int)length, (char*)payload);

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
      weather ? weather : "null"
    );
    faceSetStatusBar(timeStr, WiFi.status() == WL_CONNECTED, wsConnected);
    if (battery >= 0) {
      faceSetBattery(battery);
    }
    if (weather) {
      faceSetWeather(weather);
    }

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
      lastTouchPressed = false;
      playbackActive = false;
      Serial.println("WebSocket disconnected");
      updateStatusBar();
      faceSetText("服务器已断开");
      break;

    case WStype_CONNECTED:
      wsConnected = true;
      lastTouchPressed = false;
      Serial.println("WebSocket connected!");
      updateStatusBar();
      faceSetText("已连接服务器");

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
// 触摸处理：只触发 long_press / long_release
// ──────────────────────────────────────────────

void handleTouch() {
  uint32_t touchVal = touchRead(TOUCH_PIN);
  bool touched = touchVal > TOUCH_THRESHOLD;

  if (touched && !lastTouchPressed) {
    lastTouchPressed = true;
    Serial.println("Touch long_press");
    faceSetState(FACE_LISTENING);
    faceSetText("请对电脑说话...");
    sendTouchEvent("long_press");
  }

  if (!touched && lastTouchPressed) {
    lastTouchPressed = false;
    Serial.println("Touch long_release");
    faceSetState(FACE_PROCESSING);
    faceSetText("录音结束，识别中...");
    sendTouchEvent("long_release");
  }
}

// ──────────────────────────────────────────────
// Arduino setup / loop
// ──────────────────────────────────────────────

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("\n=== AI-Bot Demo (desktop voice + speaker playback) ===");

  displayInit();
  delay(500);

  speakerReady = initSpeaker();
  if (!speakerReady) {
    Serial.println("Speaker init failed, will continue without local playback");
    faceSetText("喇叭初始化失败");
  }

  if (!connectWiFi()) {
    Serial.println("WiFi failed, restarting in 5s...");
    delay(5000);
    ESP.restart();
  }

  webSocket.begin(WS_HOST, WS_PORT, WS_PATH);
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(3000);

  Serial.println("Setup complete, waiting for WebSocket...");
}

void loop() {
  webSocket.loop();
  faceUpdate();

  if (millis() - lastNtpUpdate >= NTP_UPDATE_INTERVAL) {
    lastNtpUpdate = millis();
    struct tm timeinfo;
    if (getLocalTime(&timeinfo, 100)) {
      char timeBuf[8];
      strftime(timeBuf, sizeof(timeBuf), "%H:%M", &timeinfo);
      faceSetStatusBar(timeBuf, WiFi.status() == WL_CONNECTED, wsConnected);
    }
  }

  if (millis() - lastTouchCheck >= 20) {
    lastTouchCheck = millis();
    if (wsConnected) {
      handleTouch();
    }
  }
}
