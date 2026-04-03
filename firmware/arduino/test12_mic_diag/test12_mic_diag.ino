// ESP32-S3 INMP441 麦克风诊断测试
// 目标板卡: AI-Bot 硬件板 v2.x
// 引脚: SCK=IO14, WS=IO15, SD=IO16
// 说明:
// 1. 使用 32-bit I2S 槽位读取 INMP441 的 24-bit 数据
// 2. 同时统计 slot0 / slot1 的平均绝对值和峰峰值
// 3. 自动选择更活跃的 slot 作为当前音量与状态判断依据

#include <Arduino.h>
#include <driver/i2s.h>
#include <limits.h>

namespace {
constexpr i2s_port_t I2S_PORT = I2S_NUM_0;
constexpr int I2S_SCK = 14;
constexpr int I2S_WS = 15;
constexpr int I2S_SD = 16;
constexpr int SAMPLE_RATE = 16000;
constexpr i2s_bits_per_sample_t SAMPLE_BITS = I2S_BITS_PER_SAMPLE_32BIT;
constexpr size_t FRAME_COUNT = 128;
constexpr unsigned long PRINT_INTERVAL_MS = 100;
constexpr int BAR_WIDTH = 40;
constexpr int CALIBRATION_PASSES = 12;
}  // namespace

struct ChannelStats {
  int32_t minValue;
  int32_t maxValue;
  int64_t absSum;
  long avgAbs;
  long peakToPeak;
};

struct MicStats {
  ChannelStats slot0;
  ChannelStats slot1;
  int activeSlot;
  long activeAvg;
  long activePeak;
};

int32_t g_samples[FRAME_COUNT * 2];
long g_noiseFloor = 1;
bool g_verboseOutput = true;
unsigned long g_lastPrintAt = 0;

int64_t sampleAbs(int32_t value) {
  return value < 0 ? -(int64_t)value : (int64_t)value;
}

void resetChannelStats(ChannelStats& stats) {
  stats.minValue = INT32_MAX;
  stats.maxValue = INT32_MIN;
  stats.absSum = 0;
  stats.avgAbs = 0;
  stats.peakToPeak = 0;
}

void finalizeChannelStats(ChannelStats& stats, int frameCount) {
  if (frameCount <= 0) {
    stats.minValue = 0;
    stats.maxValue = 0;
    stats.avgAbs = 0;
    stats.peakToPeak = 0;
    return;
  }

  stats.avgAbs = (long)(stats.absSum / frameCount);

  int64_t span = (int64_t)stats.maxValue - (int64_t)stats.minValue;
  if (span < 0) {
    span = 0;
  }
  if (span > LONG_MAX) {
    span = LONG_MAX;
  }
  stats.peakToPeak = (long)span;
}

void printHelp() {
  Serial.println("Commands:");
  Serial.println("  h  show help");
  Serial.println("  p  toggle detailed/compact output");
  Serial.println("  r  recalibrate noise floor");
  Serial.println();
}

bool initMicrophone() {
  i2s_config_t i2sConfig = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = SAMPLE_RATE,
    .bits_per_sample = SAMPLE_BITS,
    .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = FRAME_COUNT,
    .use_apll = false,
    .tx_desc_auto_clear = false,
    .fixed_mclk = 0
  };

  i2s_pin_config_t pinConfig = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };

  esp_err_t err = i2s_driver_install(I2S_PORT, &i2sConfig, 0, NULL);
  if (err != ESP_OK) {
    Serial.printf("I2S driver install failed: %d\n", err);
    return false;
  }

  err = i2s_set_pin(I2S_PORT, &pinConfig);
  if (err != ESP_OK) {
    Serial.printf("I2S pin config failed: %d\n", err);
    return false;
  }

  Serial.println("I2S RX initialized.");
  return true;
}

bool readMicStats(MicStats& stats) {
  size_t bytesRead = 0;
  esp_err_t err = i2s_read(I2S_PORT, g_samples, sizeof(g_samples), &bytesRead, portMAX_DELAY);
  if (err != ESP_OK) {
    Serial.printf("I2S read failed: %d\n", err);
    return false;
  }

  if (bytesRead < sizeof(int32_t) * 2) {
    return false;
  }

  const int totalSlots = bytesRead / sizeof(int32_t);
  const int frameCount = totalSlots / 2;
  if (frameCount <= 0) {
    return false;
  }

  resetChannelStats(stats.slot0);
  resetChannelStats(stats.slot1);

  for (int i = 0; i < frameCount; ++i) {
    const int32_t slot0 = g_samples[i * 2] >> 8;
    const int32_t slot1 = g_samples[i * 2 + 1] >> 8;

    if (slot0 < stats.slot0.minValue) stats.slot0.minValue = slot0;
    if (slot0 > stats.slot0.maxValue) stats.slot0.maxValue = slot0;
    if (slot1 < stats.slot1.minValue) stats.slot1.minValue = slot1;
    if (slot1 > stats.slot1.maxValue) stats.slot1.maxValue = slot1;

    stats.slot0.absSum += sampleAbs(slot0);
    stats.slot1.absSum += sampleAbs(slot1);
  }

  finalizeChannelStats(stats.slot0, frameCount);
  finalizeChannelStats(stats.slot1, frameCount);

  if (stats.slot0.avgAbs > stats.slot1.avgAbs) {
    stats.activeSlot = 0;
    stats.activeAvg = stats.slot0.avgAbs;
    stats.activePeak = stats.slot0.peakToPeak;
  } else if (stats.slot1.avgAbs > stats.slot0.avgAbs) {
    stats.activeSlot = 1;
    stats.activeAvg = stats.slot1.avgAbs;
    stats.activePeak = stats.slot1.peakToPeak;
  } else if (stats.slot0.peakToPeak >= stats.slot1.peakToPeak) {
    stats.activeSlot = 0;
    stats.activeAvg = stats.slot0.avgAbs;
    stats.activePeak = stats.slot0.peakToPeak;
  } else {
    stats.activeSlot = 1;
    stats.activeAvg = stats.slot1.avgAbs;
    stats.activePeak = stats.slot1.peakToPeak;
  }

  return true;
}

long silenceThreshold() {
  return g_noiseFloor + max(80L, g_noiseFloor / 2);
}

long activeThreshold() {
  return g_noiseFloor * 3 + 200;
}

const char* signalState(long activeAvg) {
  if (activeAvg <= silenceThreshold()) {
    return "silence";
  }
  if (activeAvg < activeThreshold()) {
    return "weak";
  }
  return "active";
}

void updateNoiseFloor(long activeAvg) {
  if (activeAvg <= silenceThreshold()) {
    g_noiseFloor = (g_noiseFloor * 15 + activeAvg) / 16;
    if (g_noiseFloor < 1) {
      g_noiseFloor = 1;
    }
  }
}

void printBar(long activeAvg) {
  long normalized = activeAvg - g_noiseFloor;
  if (normalized < 0) {
    normalized = 0;
  }

  int barLength = (int)map((long)min(normalized, 6000L), 0L, 6000L, 0L, (long)BAR_WIDTH);
  if (barLength < 0) {
    barLength = 0;
  }
  if (barLength > BAR_WIDTH) {
    barLength = BAR_WIDTH;
  }

  Serial.print("|");
  for (int i = 0; i < barLength; ++i) {
    Serial.print("#");
  }
  for (int i = barLength; i < BAR_WIDTH; ++i) {
    Serial.print(".");
  }
  Serial.print("|");
}

void printStats(const MicStats& stats) {
  const char* state = signalState(stats.activeAvg);

  if (g_verboseOutput) {
    Serial.printf(
      "slot0 avg:%6ld p2p:%6ld | slot1 avg:%6ld p2p:%6ld | active:slot%d avg:%6ld peak:%6ld "
      "base:%4ld state:%s ",
      stats.slot0.avgAbs,
      stats.slot0.peakToPeak,
      stats.slot1.avgAbs,
      stats.slot1.peakToPeak,
      stats.activeSlot,
      stats.activeAvg,
      stats.activePeak,
      g_noiseFloor,
      state
    );
  } else {
    Serial.printf(
      "slot%d avg:%6ld peak:%6ld base:%4ld state:%s ",
      stats.activeSlot,
      stats.activeAvg,
      stats.activePeak,
      g_noiseFloor,
      state
    );
  }

  printBar(stats.activeAvg);
  Serial.println();
}

void calibrateNoiseFloor() {
  Serial.println();
  Serial.println("Noise floor calibration: keep the room quiet for about 1 second.");

  uint64_t sum = 0;
  int goodReads = 0;

  for (int i = 0; i < CALIBRATION_PASSES; ++i) {
    MicStats stats;
    if (!readMicStats(stats)) {
      continue;
    }

    sum += (uint64_t)stats.activeAvg;
    ++goodReads;
    Serial.printf(
      "  pass %02d/%02d -> slot%d avg:%ld peak:%ld\n",
      i + 1,
      CALIBRATION_PASSES,
      stats.activeSlot,
      stats.activeAvg,
      stats.activePeak
    );
    delay(20);
  }

  if (goodReads == 0) {
    g_noiseFloor = 1;
    Serial.println("Calibration failed, fallback noise floor = 1.");
    Serial.println();
    return;
  }

  g_noiseFloor = (long)(sum / (uint64_t)goodReads);
  if (g_noiseFloor < 1) {
    g_noiseFloor = 1;
  }

  Serial.printf("Noise floor set to %ld.\n", g_noiseFloor);
  Serial.println();
}

void handleSerialCommands() {
  while (Serial.available() > 0) {
    const char cmd = (char)Serial.read();

    switch (cmd) {
      case 'h':
      case 'H':
        printHelp();
        break;

      case 'p':
      case 'P':
        g_verboseOutput = !g_verboseOutput;
        Serial.printf("Output mode -> %s\n\n", g_verboseOutput ? "detailed" : "compact");
        break;

      case 'r':
      case 'R':
        calibrateNoiseFloor();
        break;

      case '\n':
      case '\r':
        break;

      default:
        Serial.printf("Unknown command: %c\n", cmd);
        printHelp();
        break;
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("========================================");
  Serial.println("INMP441 microphone diagnostic test");
  Serial.println("========================================");
  Serial.printf("Pins: SCK=IO%d, WS=IO%d, SD=IO%d\n", I2S_SCK, I2S_WS, I2S_SD);
  Serial.printf("Sample rate: %d Hz, I2S slot width: 32-bit\n", SAMPLE_RATE);
  Serial.println("Speak toward the microphone and watch which slot becomes active.");
  Serial.println("If both slots stay near zero, check power, soldering, orientation, and L/R wiring.");
  Serial.println();
  printHelp();

  if (!initMicrophone()) {
    Serial.println("Microphone init failed. Stop here.");
    while (true) {
      delay(1000);
    }
  }

  calibrateNoiseFloor();
  Serial.println("Live diagnostics started.");
  Serial.println();
}

void loop() {
  handleSerialCommands();

  if (millis() - g_lastPrintAt < PRINT_INTERVAL_MS) {
    delay(5);
    return;
  }

  MicStats stats;
  if (!readMicStats(stats)) {
    delay(5);
    return;
  }

  updateNoiseFloor(stats.activeAvg);
  printStats(stats);
  g_lastPrintAt = millis();
}
