// 确认 IO21 可以用于 I2S
#include <driver/i2s_std.h>

void setup() {
  Serial.begin(115200);
  delay(3000);
  Serial.println("=== 测试 IO21 做 I2S DIN ===");
  Serial.flush();

  i2s_chan_handle_t tx = NULL;
  i2s_chan_config_t chan_cfg = {
    .id = I2S_NUM_AUTO,
    .role = I2S_ROLE_MASTER,
    .dma_desc_num = 6,
    .dma_frame_num = 240,
    .auto_clear = true,
    .auto_clear_before_cb = false,
    .intr_priority = 0,
  };
  esp_err_t err = i2s_new_channel(&chan_cfg, &tx, NULL);
  Serial.printf("new_channel: %s\n", esp_err_to_name(err));
  Serial.flush();
  if (err != ESP_OK) return;

  i2s_std_config_t std_cfg = {
    .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(44100),
    .slot_cfg = I2S_STD_MSB_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO),
    .gpio_cfg = {
      .mclk = I2S_GPIO_UNUSED,
      .bclk = (gpio_num_t)17,
      .ws = (gpio_num_t)18,
      .dout = (gpio_num_t)21,
      .din = I2S_GPIO_UNUSED,
      .invert_flags = { false, false, false },
    },
  };
  err = i2s_channel_init_std_mode(tx, &std_cfg);
  Serial.printf("init_std_mode: %s\n", esp_err_to_name(err));
  Serial.flush();
  if (err != ESP_OK) { i2s_del_channel(tx); return; }

  err = i2s_channel_enable(tx);
  Serial.printf("enable: %s\n", esp_err_to_name(err));
  Serial.flush();

  Serial.println("\n=== IO21 测试通过! 可以飞线 ===");

  i2s_channel_disable(tx);
  i2s_del_channel(tx);
}

void loop() {
  Serial.println("loop...");
  delay(2000);
}
