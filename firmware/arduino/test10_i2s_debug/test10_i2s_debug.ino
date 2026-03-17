// 最小化 I2S 诊断 — 精确定位串口断连发生在哪一步
//
// Arduino IDE 设置:
//   Board: ESP32S3 Dev Module
//   USB CDC On Boot: Enabled
//   USB Mode: Hardware CDC and JTAG
//   PSRAM: QSPI PSRAM (或 Disabled)
//
// 每一步都有 Serial.flush() 确保消息发出去再继续

#include <Arduino.h>
#include <driver/i2s_std.h>

#define I2S_BCLK  17
#define I2S_LRC   18
#define I2S_DIN    8

i2s_chan_handle_t tx_handle = NULL;

void setup() {
  Serial.begin(115200);
  delay(3000);

  Serial.println("===== I2S 逐步诊断 =====");
  Serial.printf("堆内存: %d bytes\n", ESP.getFreeHeap());
  Serial.flush();

  // 步骤 1: 创建 I2S channel
  Serial.println("[步骤1] i2s_new_channel ...");
  Serial.flush();
  delay(100);

  i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_1, I2S_ROLE_MASTER);
  chan_cfg.dma_desc_num = 8;
  chan_cfg.dma_frame_num = 256;

  esp_err_t err = i2s_new_channel(&chan_cfg, &tx_handle, NULL);
  Serial.printf("[步骤1] 结果: %s\n", esp_err_to_name(err));
  Serial.flush();
  delay(100);
  if (err != ESP_OK) { Serial.println("失败，停止"); while(1) delay(1000); }

  // 步骤 2: 配置 GPIO (不初始化 I2S)
  Serial.println("[步骤2] 准备 i2s_std_config ...");
  Serial.flush();
  delay(100);

  i2s_std_config_t std_cfg = {
    .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(22050),
    .slot_cfg = I2S_STD_MSB_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO),
    .gpio_cfg = {
      .mclk = I2S_GPIO_UNUSED,
      .bclk = (gpio_num_t)I2S_BCLK,
      .ws   = (gpio_num_t)I2S_LRC,
      .dout = (gpio_num_t)I2S_DIN,
      .din  = I2S_GPIO_UNUSED,
      .invert_flags = { false, false, false },
    },
  };
  Serial.println("[步骤2] 配置结构体创建完成");
  Serial.flush();
  delay(100);

  // 步骤 3: i2s_channel_init_std_mode (最可能崩溃的地方)
  Serial.println("[步骤3] i2s_channel_init_std_mode ...");
  Serial.println("        如果下一行没有出现，就是这里崩溃了");
  Serial.flush();
  delay(100);

  err = i2s_channel_init_std_mode(tx_handle, &std_cfg);
  Serial.printf("[步骤3] 结果: %s\n", esp_err_to_name(err));
  Serial.flush();
  delay(100);
  if (err != ESP_OK) { Serial.println("失败，停止"); while(1) delay(1000); }

  // 步骤 4: i2s_channel_enable
  Serial.println("[步骤4] i2s_channel_enable ...");
  Serial.flush();
  delay(100);

  err = i2s_channel_enable(tx_handle);
  Serial.printf("[步骤4] 结果: %s\n", esp_err_to_name(err));
  Serial.flush();
  delay(100);
  if (err != ESP_OK) { Serial.println("失败，停止"); while(1) delay(1000); }

  // 步骤 5: 写一帧静音数据
  Serial.println("[步骤5] 写入静音数据 ...");
  Serial.flush();
  delay(100);

  int16_t silence[64] = {0};
  size_t written;
  err = i2s_channel_write(tx_handle, silence, sizeof(silence), &written, 1000);
  Serial.printf("[步骤5] 结果: %s, 写入 %d bytes\n", esp_err_to_name(err), written);
  Serial.flush();
  delay(100);

  Serial.println();
  Serial.println("===== 所有步骤完成! 串口正常! =====");
  Serial.printf("堆内存: %d bytes\n", ESP.getFreeHeap());
  Serial.flush();
}

void loop() {
  Serial.printf("[心跳] %lu秒 | 堆: %d\n", millis()/1000, ESP.getFreeHeap());
  Serial.flush();
  delay(3000);
}
