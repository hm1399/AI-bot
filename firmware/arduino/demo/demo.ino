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

// ===== WiFi 配置 =====
const char* WIFI_SSID = "EE3070_P1615_1"; //EE3070_P1615_1   /  AAAAA
const char* WIFI_PASS = "EE3070P1615";  //EE3070P1615。     / 92935903

// ===== WebSocket 服务端配置 =====
const char* WS_HOST = "192.168.0.241";  // ← 改为你电脑的局域网 IP
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

// ===== 屏幕布局常量 =====
#define SCREEN_W 240
#define SCREEN_H 280
#define STATUS_Y 10
#define REPLY_Y  80
#define REPLY_H  180

// ──────────────────────────────────────────────
// 屏幕显示函数
// ──────────────────────────────────────────────

void displayInit() {
  tft.init();
  tft.setRotation(0);
  tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(50, 120);
  tft.println("AI-Bot Demo");
  tft.setTextSize(1);
  tft.setCursor(60, 150);
  tft.println("Starting...");
}

void displayStatus(const char* wifi, const char* ws) {
  // 状态区域 (顶部)
  tft.fillRect(0, 0, SCREEN_W, 70, TFT_BLACK);
  tft.setTextSize(1);

  tft.setTextColor(TFT_CYAN, TFT_BLACK);
  tft.setCursor(10, STATUS_Y);
  tft.printf("WiFi: %s", wifi);

  tft.setCursor(10, STATUS_Y + 20);
  tft.printf("Server: %s", ws);

  // 分隔线
  tft.drawLine(0, 68, SCREEN_W, 68, TFT_DARKGREY);
}

void displayRecording(bool recording) {
  tft.fillRect(0, 70, SCREEN_W, 10, TFT_BLACK);
  if (recording) {
    tft.setTextColor(TFT_RED, TFT_BLACK);
    tft.setTextSize(1);
    tft.setCursor(10, 70);
    tft.println("[ Recording... ]");
  }
}

void displayReply(const String& text) {
  // 回复区域
  tft.fillRect(0, REPLY_Y, SCREEN_W, REPLY_H, TFT_BLACK);
  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.setTextSize(1);
  tft.setCursor(10, REPLY_Y);

  // 自动换行显示（每行约 38 个英文字符 / 19 个中文字符）
  int x = 10, y = REPLY_Y;
  int maxX = SCREEN_W - 10;
  for (unsigned int i = 0; i < text.length(); i++) {
    char c = text.charAt(i);
    if (c == '\n' || x > maxX - 6) {
      x = 10;
      y += 12;
      if (y > REPLY_Y + REPLY_H - 12) break;  // 超出区域
      if (c == '\n') continue;
    }
    tft.setCursor(x, y);
    tft.print(c);
    x += 6;  // 英文字符宽度
  }
}

void displayProcessing() {
  tft.fillRect(0, 70, SCREEN_W, 10, TFT_BLACK);
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.setTextSize(1);
  tft.setCursor(10, 70);
  tft.println("Processing...");
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
  displayStatus("Connecting...", "---");

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
    displayStatus("FAILED", "---");
    return false;
  }

  Serial.printf("WiFi connected! IP: %s\n", WiFi.localIP().toString().c_str());
  displayStatus("Connected", "Connecting...");
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
    Serial.printf("AI reply: %s\n", text);
    lastReply = String(text);
    displayReply(lastReply);

  } else if (strcmp(type, "state_change") == 0) {
    const char* state = data["state"] | "";
    Serial.printf("State: %s\n", state);
    if (strcmp(state, "PROCESSING") == 0) {
      displayProcessing();
    }

  } else if (strcmp(type, "display_update") == 0) {
    const char* text = data["text"] | "";
    lastReply = String(text);
    displayReply(lastReply);
  }
}

void webSocketEvent(WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      wsConnected = false;
      introSent = false;
      Serial.println("WebSocket disconnected");
      displayStatus("Connected", "Disconnected");
      break;

    case WStype_CONNECTED:
      wsConnected = true;
      Serial.println("WebSocket connected!");
      displayStatus("Connected", "Connected");

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
    displayRecording(true);
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
    displayRecording(false);
    displayProcessing();
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

  // 触摸录音检测（每 20ms 检查一次）
  if (millis() - lastTouchCheck >= 20) {
    lastTouchCheck = millis();
    if (wsConnected) {
      handleTouch();
    }
  }
}
