// ESP32-S3 MAX98357A + ESP32-audioI2S 库 TTS 语音合成测试
// 引脚: BCLK=IO17, LRC=IO18, DIN=IO8
// 使用 ESP32-audioI2S 库的 connecttospeech() (Google TTS)
// 需要 WiFi 连接
// 库安装: Arduino Library Manager 搜索 "ESP32-audioI2S" (作者 schreibfaul1)
// 分区方案: 选择 "Huge APP (3MB No OTA/1MB SPIFFS)"

#include <Arduino.h>
#include <WiFi.h>
#include "Audio.h"
#include <driver/gpio.h>
#include <esp_rom_gpio.h>

// ===== WiFi 配置 =====
const char* WIFI_SSID     = "AAAAA";
const char* WIFI_PASSWORD = "92935903";
// =====================

// ===== I2S 引脚 (MAX98357A) =====
#define I2S_BCLK  17
#define I2S_LRC   18
#define I2S_DOUT   8
// =================================

// ===== 电容触摸引脚 =====
#define TOUCH_PIN        7
#define TOUCH_THRESHOLD  40000
// ========================

// ===== 音量控制 =====
// 范围 0~21
uint8_t VOLUME = 15;
// ====================

Audio audio;
bool ttsPlaying = false;
bool lastTouched = false;

void prepareI2SDoutPin() {
  if (I2S_DOUT != 8) {
    return;
  }

  Serial.println("释放 IO8 的默认复用，准备给 I2S DOUT 使用...");

  esp_err_t rst = gpio_reset_pin(GPIO_NUM_8);
  Serial.printf("gpio_reset_pin(8): %s\n", esp_err_to_name(rst));

  gpio_set_direction(GPIO_NUM_39, GPIO_MODE_OUTPUT);
  esp_rom_gpio_connect_out_signal(39, FSPICS1_OUT_IDX, false, false);
  Serial.println("SUBSPICS1 已重定向到 IO39");

  gpio_iomux_out(8, 1, false);  // Function 1 = GPIO
  Serial.println("IO8 已切换为普通 GPIO 功能");
}

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

void playHello() {
  Serial.println("\n触摸按下，播放: Hello");
  audio.connecttospeech("Hello", "en");
  ttsPlaying = true;
}

void setup() {
  Serial.begin(115200);
  delay(3000);
  Serial.println("ESP32-audioI2S 电容触摸 TTS 测试");
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
  prepareI2SDoutPin();
  audio.setPinout(I2S_BCLK, I2S_LRC, I2S_DOUT);
  // audio.setVolume(VOLUME);
  Serial.printf("音量: %d/21\n", VOLUME);
  Serial.println("I2S 初始化成功!");
  Serial.printf("触摸引脚: IO%d, 阈值: %d\n", TOUCH_PIN, TOUCH_THRESHOLD);
  Serial.println("按一次电容按钮，说一次 Hello。\n");
}

void loop() {
  audio.loop();

  uint32_t touchValue = touchRead(TOUCH_PIN);
  bool touched = touchValue > TOUCH_THRESHOLD;

  // 只在按下瞬间触发一次，松手前不重复播放
  if (touched && !lastTouched && !ttsPlaying) {
    Serial.printf("检测到触摸，原始值: %u\n", touchValue);
    playHello();
  }

  if (!touched && lastTouched) {
    Serial.printf("触摸松开，原始值: %u\n", touchValue);
  }

  lastTouched = touched;
  delay(20);
}
