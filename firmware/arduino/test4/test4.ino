// ESP32-S3 MAX98357A 功放与喇叭测试
// 引脚: BCLK=IO17, LRC=IO18, DIN=IO21, SD_MODE=IO2
// 使用 Arduino ESP_I2S 库（兼容 USB CDC）

#include <ESP_I2S.h>
#include <math.h>
#include <Arduino.h>

#define I2S_BCLK  17
#define I2S_LRC   18
#define I2S_DIN    21
#define SD_MODE_PIN 2
#define SAMPLE_RATE  44100
#define TWO_PI       6.283185307f

enum SpeakerSdMode {
  SPEAKER_SD_SHUTDOWN = 0,
  SPEAKER_SD_LEFT = 1,
};

I2SClass i2s;
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

// 生成正弦波（标准立体声帧，带淡入淡出）
void playTone(int freq, int duration_ms, int amplitude) {
  int total_samples = (SAMPLE_RATE * duration_ms) / 1000;
  int fade_samples = SAMPLE_RATE * 15 / 1000;
  if (fade_samples > total_samples / 2) fade_samples = total_samples / 2;

  const int BATCH = 128;
  int16_t buf[BATCH * 2];  // [L, R, L, R, ...]
  int idx = 0;

  for (int i = 0; i < total_samples; i++) {
    float envelope = 1.0f;
    if (i < fade_samples) {
      envelope = (float)i / fade_samples;
    } else if (i > total_samples - fade_samples) {
      envelope = (float)(total_samples - i) / fade_samples;
    }
    int16_t sample = (int16_t)(amplitude * envelope * sinf(TWO_PI * freq * i / SAMPLE_RATE));
    buf[idx++] = sample;  // 左声道
    buf[idx++] = sample;  // 右声道

    if (idx >= BATCH * 2) {
      i2s.write((uint8_t*)buf, sizeof(buf));
      idx = 0;
    }
  }
  if (idx > 0) {
    i2s.write((uint8_t*)buf, idx * sizeof(int16_t));
  }
}

void runSpeakerTests() {
  if (currentSdMode != SPEAKER_SD_LEFT) {
    // SD_MODE 直接接 GPIO 时，稳定可用的是 HIGH=左声道、LOW=关机。
    applySpeakerSdMode(SPEAKER_SD_LEFT);
  }

  // 测试1: 440Hz 正弦波（极低幅值测试串口是否断开）
  Serial.println("\n测试1: 440Hz 正弦波 (A4) - 2秒 [低幅值]");
  playTone(440, 2000, 100);
  delay(500);

  // 测试2: 不同频率
  Serial.println("测试2: 不同频率蜂鸣声");
  int freqs[] = {262, 330, 392, 523, 659, 784, 1047};
  const char* names[] = {"C4", "E4", "G4", "C5", "E5", "G5", "C6"};
  for (int i = 0; i < 7; i++) {
    Serial.printf("  %s (%dHz)\n", names[i], freqs[i]);
    playTone(freqs[i], 400, 8000);
    delay(100);
  }
  delay(500);

  // 测试3: 音量渐变
  Serial.println("测试3: 音量渐变 (440Hz)");
  int volumes[] = {500, 2000, 5000, 10000, 16000};
  for (int i = 0; i < 5; i++) {
    Serial.printf("  音量 %d/%d (幅值=%d)\n", i + 1, 5, volumes[i]);
    playTone(440, 600, volumes[i]);
    delay(200);
  }
  delay(500);

  // 测试4: 小星星
  Serial.println("测试4: 旋律测试 (小星星)");
  int melody[] =    {262, 262, 392, 392, 440, 440, 392, 349, 349, 330, 330, 294, 294, 262};
  int durations[] = {300, 300, 300, 300, 300, 300, 600, 300, 300, 300, 300, 300, 300, 600};
  for (int i = 0; i < 14; i++) {
    playTone(melody[i], durations[i], 5000);
    delay(50);
  }

  Serial.println("\n所有测试完成!");
  Serial.println("串口命令: p = 再跑一次测试, l = 左声道开启, x = 关机静音");
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("MAX98357A 功放测试开始...");
  Serial.printf("I2S 引脚: BCLK=IO%d, LRC=IO%d, DIN=IO%d, SD_MODE=IO%d\n",
                I2S_BCLK, I2S_LRC, I2S_DIN, SD_MODE_PIN);

  applySpeakerSdMode(SPEAKER_SD_LEFT);

  i2s.setPins(I2S_BCLK, I2S_LRC, I2S_DIN);
  if (!i2s.begin(I2S_MODE_STD, SAMPLE_RATE, I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO)) {
    Serial.println("I2S 初始化失败!");
    return;
  }
  Serial.println("I2S 初始化成功!");
  runSpeakerTests();
}

void loop() {
  while (Serial.available() > 0) {
    char cmd = (char)Serial.read();

    if (cmd == 'p' || cmd == 'P') {
      runSpeakerTests();
    } else if (cmd == 'l' || cmd == 'L') {
      applySpeakerSdMode(SPEAKER_SD_LEFT);
    } else if (cmd == 'x' || cmd == 'X') {
      applySpeakerSdMode(SPEAKER_SD_SHUTDOWN);
    } else if (cmd == '\n' || cmd == '\r') {
      continue;
    } else {
      Serial.printf("未知命令: %c\n", cmd);
      Serial.println("可用命令: p = 再跑一次测试, l = 左声道开启, x = 关机静音");
    }
  }

  delay(5);
}
