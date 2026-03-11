// ESP32-S3 INMP441 麦克风 I2S 测试
// 引脚: SCK=IO14, WS=IO15, SD=IO16
// L/R: R12 100kΩ下拉 = 左声道

#include <driver/i2s.h>

#define I2S_SCK  14
#define I2S_WS   15
#define I2S_SD   16

#define SAMPLE_RATE   16000
#define SAMPLE_BITS   I2S_BITS_PER_SAMPLE_16BIT
#define I2S_PORT      I2S_NUM_0
#define BUFFER_SIZE   512

int16_t samples[BUFFER_SIZE];

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("INMP441 麦克风测试开始...");

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
  Serial.println("对着麦克风说话，观察数值变化...");
  Serial.println();
}

void loop() {
  size_t bytes_read = 0;
  esp_err_t err = i2s_read(I2S_PORT, samples, sizeof(samples), &bytes_read, portMAX_DELAY);

  if (err != ESP_OK || bytes_read == 0) {
    return;
  }

  int num_samples = bytes_read / sizeof(int16_t);

  // 计算本次采样的最大值、最小值、平均值
  int16_t max_val = -32768;
  int16_t min_val = 32767;
  long sum = 0;

  for (int i = 0; i < num_samples; i++) {
    if (samples[i] > max_val) max_val = samples[i];
    if (samples[i] < min_val) min_val = samples[i];
    sum += abs(samples[i]);
  }

  int avg = sum / num_samples;
  int peak = max_val - min_val;

  // 简易音量条 (0-50格)
  int bar_len = map(avg, 0, 5000, 0, 50);
  bar_len = constrain(bar_len, 0, 50);

  Serial.printf("平均:%5d  峰值:%5d  |", avg, peak);
  for (int i = 0; i < bar_len; i++) Serial.print("█");
  for (int i = bar_len; i < 50; i++) Serial.print(" ");
  Serial.println("|");

  delay(100);
}
