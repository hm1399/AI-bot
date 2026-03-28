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
#define BUFFER_SIZE   256

int32_t samples[BUFFER_SIZE];

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
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = BUFFER_SIZE,
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
  Serial.println("对着麦克风说话，观察平均值和峰值变化...");
  Serial.println("如果始终接近 0，优先检查 L/R、CHIPEN、3V3 和焊接。");
  Serial.println();
}

void loop() {
  size_t bytes_read = 0;
  esp_err_t err = i2s_read(I2S_PORT, samples, sizeof(samples), &bytes_read, portMAX_DELAY);

  if (err != ESP_OK || bytes_read == 0) {
    return;
  }

  int num_samples = bytes_read / sizeof(int32_t);

  // INMP441 输出 24-bit、MSB-first；右移 8 位后得到对齐的有符号样本。
  int32_t max_val = INT32_MIN;
  int32_t min_val = INT32_MAX;
  int64_t sum = 0;

  for (int i = 0; i < num_samples; i++) {
    int32_t sample = samples[i] >> 8;
    if (sample > max_val) max_val = sample;
    if (sample < min_val) min_val = sample;
    sum += llabs((long long)sample);
  }

  long avg = (long)(sum / num_samples);
  long peak = max_val - min_val;

  // 简易音量条 (0-50格)
  int bar_len = map(avg, 0, 4000, 0, 50);
  bar_len = constrain(bar_len, 0, 50);

  Serial.printf("平均:%6ld  峰值:%6ld  最小:%6ld  最大:%6ld  |",
                avg, peak, (long)min_val, (long)max_val);
  for (int i = 0; i < bar_len; i++) Serial.print("█");
  for (int i = bar_len; i < 50; i++) Serial.print(" ");
  Serial.println("|");

  delay(100);
}
