// ESP32-S3 INMP441 麦克风 I2S 测试
// 引脚: SCK=IO14, WS=IO15, SD=IO16
// L/R: R12 100kΩ下拉 = 左声道

#include <Arduino.h>
#include <driver/i2s.h>

#define I2S_SCK  14
#define I2S_WS   15
#define I2S_SD   16

#define SAMPLE_RATE   16000
#define SAMPLE_BITS   I2S_BITS_PER_SAMPLE_32BIT
#define I2S_PORT      I2S_NUM_0
#define FRAME_COUNT   128

int32_t samples[FRAME_COUNT * 2];

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("INMP441 麦克风测试开始...");
  Serial.println("使用 32-bit I2S 槽位读取 24-bit 麦克风数据");
  Serial.printf("引脚: SCK=IO%d, WS=IO%d, SD=IO%d\n", I2S_SCK, I2S_WS, I2S_SD);

  // I2S 配置
  i2s_config_t i2s_config = {
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

  // I2S 引脚
  i2s_pin_config_t pin_config = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };

  esp_err_t err = i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);
  if (err != ESP_OK) {
    Serial.printf("I2S 驱动安装失败: %d\n", err);
    return;
  }

  err = i2s_set_pin(I2S_PORT, &pin_config);
  if (err != ESP_OK) {
    Serial.printf("I2S 引脚设置失败: %d\n", err);
    return;
  }

  Serial.println("I2S 初始化成功!");
  Serial.println("对着麦克风说话，观察 slot0 / slot1 哪一边会明显变化。");
  Serial.println("如果只有其中一边会跟着说话变，说明麦克风实际工作声道和代码预期不一致。");
  Serial.println("如果两边都不变，优先检查 L/R、CHIPEN、3V3、麦克风朝向和焊接。");
  Serial.println();
}

void loop() {
  size_t bytes_read = 0;
  esp_err_t err = i2s_read(I2S_PORT, samples, sizeof(samples), &bytes_read, portMAX_DELAY);

  if (err != ESP_OK || bytes_read == 0) {
    return;
  }

  int total_slots = bytes_read / sizeof(int32_t);
  int num_frames = total_slots / 2;

  // INMP441 输出 24-bit、MSB-first；右移 8 位后得到对齐的有符号样本。
  int32_t slot0_max = INT32_MIN;
  int32_t slot0_min = INT32_MAX;
  int64_t slot0_sum = 0;

  int32_t slot1_max = INT32_MIN;
  int32_t slot1_min = INT32_MAX;
  int64_t slot1_sum = 0;

  for (int i = 0; i < num_frames; i++) {
    int32_t slot0 = samples[i * 2] >> 8;
    int32_t slot1 = samples[i * 2 + 1] >> 8;

    if (slot0 > slot0_max) slot0_max = slot0;
    if (slot0 < slot0_min) slot0_min = slot0;
    slot0_sum += llabs((long long)slot0);

    if (slot1 > slot1_max) slot1_max = slot1;
    if (slot1 < slot1_min) slot1_min = slot1;
    slot1_sum += llabs((long long)slot1);
  }

  long slot0_avg = (long)(slot0_sum / num_frames);
  long slot0_peak = slot0_max - slot0_min;
  long slot1_avg = (long)(slot1_sum / num_frames);
  long slot1_peak = slot1_max - slot1_min;

  long active_avg = slot0_avg > slot1_avg ? slot0_avg : slot1_avg;

  // 简易音量条 (0-50格)
  int bar_len = map(active_avg, 0, 4000, 0, 50);
  bar_len = constrain(bar_len, 0, 50);

  Serial.printf("slot0 平均:%6ld 峰值:%6ld | slot1 平均:%6ld 峰值:%6ld |",
                slot0_avg, slot0_peak, slot1_avg, slot1_peak);
  for (int i = 0; i < bar_len; i++) Serial.print("█");
  for (int i = bar_len; i < 50; i++) Serial.print(" ");
  Serial.println("|");

  delay(100);
}
