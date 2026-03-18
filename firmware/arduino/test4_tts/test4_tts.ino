// ESP32-S3 MAX98357A + ESP32-audioI2S 库 TTS 语音合成测试
// 引脚: BCLK=IO17, LRC=IO18, DIN=IO8
// 使用 ESP32-audioI2S 库的 connecttospeech() (Google TTS)
// 需要 WiFi 连接
// 库安装: Arduino Library Manager 搜索 "ESP32-audioI2S" (作者 schreibfaul1)
// 分区方案: 选择 "Huge APP (3MB No OTA/1MB SPIFFS)"

#include <Arduino.h>
#include <WiFi.h>
#include "Audio.h"

// ===== WiFi 配置 =====
const char* WIFI_SSID     = "AAAAA";
const char* WIFI_PASSWORD = "92935903";
// =====================

// ===== I2S 引脚 (MAX98357A) =====
#define I2S_BCLK  17
#define I2S_LRC   18
#define I2S_DOUT   21
// =================================

// ===== 音量控制 =====
// 范围 0~21
uint8_t VOLUME = 17;
// ====================

Audio audio;

// 待播放的 TTS 文本队列
struct TTSItem {
  const char* text;
  const char* lang;
};

TTSItem ttsQueue[] = {
  {"Hello, I am your AI assistant.",          "en"},
  {"one, two, three, four, five.",            "en"},
  {"The weather today is sunny and warm.",    "en"},
  {"AI Bot is ready.",                        "en"},
};

int ttsIndex = 0;
int ttsTotal = sizeof(ttsQueue) / sizeof(ttsQueue[0]);
bool ttsPlaying = false;
bool ttsDone = false;

// 音频事件回调
void audio_info(const char* info) {
  Serial.print("Audio Info: ");
  Serial.println(info);
}

void audio_eof_speech(const char* info) {
  Serial.printf("  语音播放完成: %s\n", info);
  Serial.printf("  堆内存剩余: %d bytes\n", ESP.getFreeHeap());
  ttsPlaying = false;
}

void playNext() {
  if (ttsIndex >= ttsTotal) {
    ttsDone = true;
    return;
  }
  Serial.printf("\n测试%d: %s\n", ttsIndex + 1, ttsQueue[ttsIndex].text);
  audio.connecttospeech(ttsQueue[ttsIndex].text, ttsQueue[ttsIndex].lang);
  ttsPlaying = true;
  ttsIndex++;
}

void setup() {
  Serial.begin(115200);
  delay(3000);
  Serial.println("ESP32-audioI2S TTS 语音合成测试");
  Serial.printf("空闲堆内存: %d bytes\n", ESP.getFreeHeap());

  // 连接 WiFi
  Serial.printf("连接 WiFi: %s ...\n", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int retry = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    if (++retry > 40) {  // 20秒超时
      Serial.println("\nWiFi 连接失败! 请检查 SSID 和密码。");
      return;
    }
  }
  Serial.printf("\nWiFi 已连接! IP: %s\n", WiFi.localIP().toString().c_str());

  // 初始化 I2S 音频
  audio.setPinout(I2S_BCLK, I2S_LRC, I2S_DOUT);
  audio.setVolume(VOLUME);
  Serial.printf("音量: %d/21\n", VOLUME);
  Serial.println("I2S 初始化成功!\n");

  // 播放第一条
  playNext();
}

void loop() {
  audio.loop();

  // 当前语音播放完成后，播放下一条
  if (!ttsPlaying && !ttsDone) {
    delay(500);
    playNext();
  }

  if (ttsDone) {
    Serial.println("\nTTS 测试全部完成!");
    Serial.println("如果声音太大或太小，修改代码顶部的 VOLUME 值 (0~21)");
    ttsDone = false;  // 只打印一次
    ttsIndex = -1;    // 标记已结束
  }
}
