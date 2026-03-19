/*
 * AI-Bot Demo 固件
 * ESP32-S3 + INMP441 麦克风 + ST7789 屏幕 + 触摸录音 + WebSocket
 *
 * 功能:
 * 1. 连接 WiFi → 连接服务端 WebSocket
 * 2. 触摸 IO7 按住录音，松开发送
 * 3. 麦克风 I2S 采集 16kHz 16bit 单声道 PCM
 * 4. 屏幕显示连接状态 + AI 回复文字
 * 5. 连接成功后发送自我介绍请求
 *
 * 依赖库: TFT_eSPI, WebSocketsClient (arduinoWebSockets), ArduinoJson
 * 引脚: 见 CLAUDE.md 引脚分配表
 */

#include <WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <driver/i2s.h>
#include <SPI.h>
#include <TFT_eSPI.h>
#include "face_display.h"

// ===== WiFi 配置 =====
const char* WIFI_SSID = "AAAAA"; //EE3070_P1615_1   /  AAAAA
const char* WIFI_PASS = "92935903";  //EE3070P1615。     / 92935903

// ===== WebSocket 服务端配置 =====
const char* WS_HOST = "172.20.10.2";  // ← 改为你电脑的局域网 IP
const uint16_t WS_PORT = 8765;
const char* WS_PATH = "/ws/device";

// ===== I2S 麦克风引脚 (INMP441) =====
#define I2S_SCK   14
#define I2S_WS    15
#define I2S_SD    16
#define I2S_PORT  I2S_NUM_0
#define SAMPLE_RATE 16000

// ===== 触摸引脚 =====
#define TOUCH_PIN 7
#define TOUCH_THRESHOLD 40000

// ===== 音频 buffer =====
#define AUDIO_BUFFER_SIZE 1024
int16_t audioBuffer[AUDIO_BUFFER_SIZE];

// ===== 全局对象 =====
TFT_eSPI tft = TFT_eSPI();
WebSocketsClient webSocket;

// ===== 状态变量 =====
bool wsConnected = false;
bool isRecording = false;
bool introSent = false;
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
// I2S 麦克风初始化
// ──────────────────────────────────────────────

bool initMicrophone() {
  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = SAMPLE_RATE,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = AUDIO_BUFFER_SIZE,
    .use_apll = false,
    .tx_desc_auto_clear = false,
    .fixed_mclk = 0
  };

  i2s_pin_config_t pin_config = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };

  if (i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL) != ESP_OK) {
    Serial.println("I2S driver install failed");
    return false;
  }
  if (i2s_set_pin(I2S_PORT, &pin_config) != ESP_OK) {
    Serial.println("I2S pin config failed");
    return false;
  }

  Serial.println("Microphone initialized");
  return true;
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
// WebSocket 事件处理
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

void sendAudioEnd() {
  if (!wsConnected) return;

  JsonDocument doc;
  doc["type"] = "audio_end";
  doc["data"] = JsonObject();

  String json;
  serializeJson(doc, json);
  webSocket.sendTXT(json);
  Serial.println("Sent audio_end");
}

void handleServerMessage(uint8_t* payload, size_t length) {
  // 打印原始 JSON
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
    Serial.printf("[status_bar_update] time=%s battery=%d weather=%s\n",
                  timeStr ? timeStr : "null", battery,
                  weather ? weather : "null");
    faceSetStatusBar(timeStr, WiFi.status() == WL_CONNECTED, wsConnected);
    if (battery >= 0) {
      faceSetBattery(battery);
    }
    if (weather) {
      faceSetWeather(weather);
    }

  } else {
    Serial.printf("[unknown type] %s\n", type);
  }
}

void webSocketEvent(WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      wsConnected = false;
      introSent = false;
      Serial.println("WebSocket disconnected");
      updateStatusBar();
      faceSetText("服务器已断开");
      break;

    case WStype_CONNECTED:
      wsConnected = true;
      Serial.println("WebSocket connected!");
      updateStatusBar();
      faceSetText("已连接服务器");

      // 连接成功后发送自我介绍请求
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
      // 服务端发来的音频数据（demo 不播放，忽略）
      break;

    case WStype_PING:
    case WStype_PONG:
      break;

    default:
      break;
  }
}

// ──────────────────────────────────────────────
// 触摸录音处理
// ──────────────────────────────────────────────

void handleTouch() {
  uint32_t touchVal = touchRead(TOUCH_PIN);
  bool touched = touchVal > TOUCH_THRESHOLD;

  if (touched && !isRecording) {
    // 开始录音
    isRecording = true;
    Serial.println("Recording started");
    faceSetState(FACE_LISTENING);
    faceSetText("聆听中...");
  }

  if (touched && isRecording) {
    // 持续录音：读取 I2S 数据并通过 WebSocket 发送
    size_t bytesRead = 0;
    esp_err_t err = i2s_read(I2S_PORT, audioBuffer, sizeof(audioBuffer),
                             &bytesRead, pdMS_TO_TICKS(50));
    if (err == ESP_OK && bytesRead > 0 && wsConnected) {
      webSocket.sendBIN((uint8_t*)audioBuffer, bytesRead);
    }
  }

  if (!touched && isRecording) {
    // 停止录音
    isRecording = false;
    Serial.println("Recording stopped, sending audio_end");
    faceSetState(FACE_PROCESSING);
    faceSetText("思考中...");
    sendAudioEnd();
  }
}

// ──────────────────────────────────────────────
// Arduino setup / loop
// ──────────────────────────────────────────────

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("\n=== AI-Bot Demo ===");

  // 初始化屏幕
  displayInit();
  delay(500);

  // 初始化麦克风
  if (!initMicrophone()) {
    Serial.println("Microphone init failed!");
    tft.fillScreen(TFT_RED);
    tft.setTextColor(TFT_WHITE);
    tft.setCursor(20, 120);
    tft.println("MIC INIT FAILED");
    while (1) delay(1000);
  }

  // 连接 WiFi
  if (!connectWiFi()) {
    Serial.println("WiFi failed, restarting in 5s...");
    delay(5000);
    ESP.restart();
  }

  // 初始化 WebSocket
  webSocket.begin(WS_HOST, WS_PORT, WS_PATH);
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(3000);

  Serial.println("Setup complete, waiting for WebSocket...");
}

void loop() {
  // 维持 WebSocket 连接
  webSocket.loop();

  // 表情动画更新（Phase 2 生效）
  faceUpdate();

  // NTP 本地时间更新（每 30 秒）
  if (millis() - lastNtpUpdate >= NTP_UPDATE_INTERVAL) {
    lastNtpUpdate = millis();
    struct tm timeinfo;
    if (getLocalTime(&timeinfo, 100)) {
      char timeBuf[8];
      strftime(timeBuf, sizeof(timeBuf), "%H:%M", &timeinfo);
      faceSetStatusBar(timeBuf, WiFi.status() == WL_CONNECTED, wsConnected);
    }
  }

  // 触摸录音检测（每 20ms 检查一次）
  if (millis() - lastTouchCheck >= 20) {
    lastTouchCheck = millis();
    if (wsConnected) {
      handleTouch();
    }
  }
}
