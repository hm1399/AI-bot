// ESP32-S3 MAX98357A + ESP32-audioI2S TTS 测试
// 引脚: BCLK=IO17, LRC=IO18, DIN=IO21
// 行为:
// 1. 上电后自动连接 WiFi
// 2. 初始化 I2S 和音频库
// 3. 自动播放一段测试语音
// 4. 串口输入 r 可再次播放
//
// 需要:
// - Arduino Library Manager 安装 "ESP32-audioI2S" (作者 schreibfaul1)
// - 分区方案选择 "Huge APP (3MB No OTA/1MB SPIFFS)"

#include <Arduino.h>
#include <WiFi.h>
#include "Audio.h"

// ===== WiFi 配置 =====
const char* WIFI_SSID = "AAAAA";
const char* WIFI_PASSWORD = "92935903";
// =====================

// ===== I2S 引脚 (MAX98357A) =====
#define I2S_BCLK 17
#define I2S_LRC  18
#define I2S_DOUT 21
#define SD_MODE_PIN 2
// =================================

// ===== TTS 配置 =====
const char* TEST_TEXT = "Hello, this is the I O twenty one speaker test.";
const char* TEST_LANG = "en";
const uint32_t AUTO_PLAY_DELAY_MS = 1500;
const uint32_t WIFI_TIMEOUT_MS = 20000;
// ====================

// ===== 音量控制 =====
// 范围 0~21
uint8_t VOLUME = 10;
// ====================

enum SpeakerSdMode {
  SPEAKER_SD_SHUTDOWN = 0,
  SPEAKER_SD_LEFT = 1,
};

Audio audio;
bool ttsPlaying = false;
bool autoPlayPending = true;
uint32_t autoPlayAt = 0;
SpeakerSdMode currentSdMode = SPEAKER_SD_LEFT;

const char* speakerSdModeName(SpeakerSdMode mode) {
  switch (mode) {
    case SPEAKER_SD_SHUTDOWN:
      return "shutdown";
    case SPEAKER_SD_LEFT:
      return "left channel";
    default:
      return "unknown";
  }
}

void applySpeakerSdMode(SpeakerSdMode mode) {
  pinMode(SD_MODE_PIN, OUTPUT);
  digitalWrite(SD_MODE_PIN, mode == SPEAKER_SD_LEFT ? HIGH : LOW);
  currentSdMode = mode;
  delay(10);
  Serial.printf("SD_MODE -> %s (IO%d = %s)\n",
                speakerSdModeName(mode),
                SD_MODE_PIN,
                mode == SPEAKER_SD_LEFT ? "HIGH" : "LOW");
}

void audio_info(const char* info) {
  Serial.print("Audio Info: ");
  Serial.println(info);
}

void audio_eof_speech(const char* info) {
  Serial.printf("语音播放完成: %s\n", info);
  Serial.printf("堆内存剩余: %u bytes\n", ESP.getFreeHeap());
  ttsPlaying = false;
}

bool connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return true;
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.printf("连接 WiFi: %s ...\n", WIFI_SSID);

  uint32_t startedAt = millis();
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");

    if (millis() - startedAt >= WIFI_TIMEOUT_MS) {
      Serial.println("\nWiFi 连接失败! 请检查 SSID 和密码。");
      return false;
    }
  }

  Serial.printf("\nWiFi 已连接! IP: %s\n", WiFi.localIP().toString().c_str());
  return true;
}

void startTTS(const char* text) {
  if (ttsPlaying) {
    Serial.println("TTS 正在播放，跳过本次请求。");
    return;
  }

  if (WiFi.status() != WL_CONNECTED && !connectWiFi()) {
    Serial.println("WiFi 未连接，无法播放 TTS。");
    return;
  }

  if (currentSdMode != SPEAKER_SD_LEFT) {
    applySpeakerSdMode(SPEAKER_SD_LEFT);
  }

  Serial.printf("\n开始播放 TTS: %s\n", text);
  audio.connecttospeech(text, TEST_LANG);
  ttsPlaying = true;
}

void handleSerialCommand() {
  while (Serial.available() > 0) {
    char cmd = (char)Serial.read();

    if (cmd == 'r' || cmd == 'R') {
      startTTS(TEST_TEXT);
    } else if (cmd == 'l' || cmd == 'L') {
      // SD_MODE 直接接 GPIO 时，稳定可用的是 HIGH=左声道、LOW=关机。
      applySpeakerSdMode(SPEAKER_SD_LEFT);
    } else if (cmd == 'x' || cmd == 'X') {
      applySpeakerSdMode(SPEAKER_SD_SHUTDOWN);
    } else if (cmd == '\n' || cmd == '\r') {
      continue;
    } else {
      Serial.printf("未知命令: %c\n", cmd);
      Serial.println("可用命令: r = 再播放一次测试语音, l = 左声道开启, x = 关机静音");
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(3000);

  Serial.println("ESP32-audioI2S 无触摸 TTS 测试");
  Serial.printf("空闲堆内存: %u bytes\n", ESP.getFreeHeap());
  Serial.printf("I2S 引脚: BCLK=IO%d, LRC=IO%d, DOUT=IO%d, SD_MODE=IO%d\n",
                I2S_BCLK, I2S_LRC, I2S_DOUT, SD_MODE_PIN);

  if (!connectWiFi()) {
    Serial.println("启动阶段 WiFi 失败，后续可按复位键重试。");
    autoPlayPending = false;
    return;
  }

  applySpeakerSdMode(SPEAKER_SD_LEFT);

  audio.setPinout(I2S_BCLK, I2S_LRC, I2S_DOUT);
  audio.setVolume(VOLUME);

  Serial.printf("音量: %u/21\n", VOLUME);
  Serial.println("I2S 初始化成功!");
  Serial.println("启动后会自动播报一次测试语音。");
  Serial.println("串口命令: r = 重播, l = 左声道开启, x = 关机静音。");
  Serial.println("说明: 目前 SD_MODE 直连 IO2，只支持 HIGH=左声道、LOW=关机。\n");

  autoPlayAt = millis() + AUTO_PLAY_DELAY_MS;
}

void loop() {
  audio.loop();
  handleSerialCommand();

  if (autoPlayPending && millis() >= autoPlayAt) {
    autoPlayPending = false;
    startTTS(TEST_TEXT);
  }

  delay(5);
}
