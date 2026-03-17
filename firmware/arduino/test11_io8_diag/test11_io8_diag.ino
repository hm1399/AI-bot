// 诊断第二步：确认是 IO8 的问题还是 I2S 的问题
//
// 测试 A: 把 IO8 配成普通 GPIO 输出
// 测试 B: 把 I2S DIN 改到 IO21，看是否正常
// 测试 C: 把 I2S DIN 改到 IO4，再验证一个引脚

#include <Arduino.h>
#include <driver/i2s_std.h>
#include <driver/gpio.h>
#include <soc/io_mux_reg.h>
#include <esp_private/esp_gpio_reserve.h>

// ===== 改这里选择测试 =====
// 1 = 测试 IO8 做普通 GPIO
// 2 = 测试 IO8 做 I2S DIN
// 3 = 测试 IO21 做 I2S DIN
// 4 = 测试 先 gpio_reset_pin(IO8) 再做 I2S DIN
// 5 = 测试 把 SUBSPICS1 重定向到 IO39，释放 IO8 给 I2S
#define TEST_MODE 5
// ==========================

i2s_chan_handle_t tx_handle = NULL;

bool testGPIO(int pin) {
  Serial.printf("[GPIO测试] 配置 IO%d 为输出 ...\n", pin);
  Serial.flush(); delay(100);

  pinMode(pin, OUTPUT);
  Serial.printf("[GPIO测试] pinMode 完成，写 HIGH ...\n");
  Serial.flush(); delay(100);

  digitalWrite(pin, HIGH);
  delay(100);
  digitalWrite(pin, LOW);

  Serial.printf("[GPIO测试] IO%d 做普通 GPIO 输出正常!\n", pin);
  Serial.flush();
  return true;
}

bool testI2S(int din_pin) {
  Serial.printf("[I2S测试] DIN = IO%d\n", din_pin);
  Serial.flush(); delay(100);

  i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_1, I2S_ROLE_MASTER);
  chan_cfg.dma_desc_num = 8;
  chan_cfg.dma_frame_num = 256;

  esp_err_t err = i2s_new_channel(&chan_cfg, &tx_handle, NULL);
  Serial.printf("  new_channel: %s\n", esp_err_to_name(err));
  Serial.flush(); delay(100);
  if (err != ESP_OK) return false;

  i2s_std_config_t std_cfg = {
    .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(22050),
    .slot_cfg = I2S_STD_MSB_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO),
    .gpio_cfg = {
      .mclk = I2S_GPIO_UNUSED,
      .bclk = (gpio_num_t)17,
      .ws   = (gpio_num_t)18,
      .dout = (gpio_num_t)din_pin,
      .din  = I2S_GPIO_UNUSED,
      .invert_flags = { false, false, false },
    },
  };

  Serial.println("  init_std_mode ...");
  Serial.println("  如果下一行没出现就是这里崩了");
  Serial.flush(); delay(100);

  err = i2s_channel_init_std_mode(tx_handle, &std_cfg);
  Serial.printf("  init_std_mode: %s\n", esp_err_to_name(err));
  Serial.flush(); delay(100);
  if (err != ESP_OK) { i2s_del_channel(tx_handle); return false; }

  err = i2s_channel_enable(tx_handle);
  Serial.printf("  enable: %s\n", esp_err_to_name(err));
  Serial.flush(); delay(100);

  // 写一帧静音
  int16_t silence[64] = {0};
  size_t written;
  i2s_channel_write(tx_handle, silence, sizeof(silence), &written, 1000);
  Serial.printf("  写入 %d bytes 成功!\n", written);
  Serial.flush();

  // 清理
  i2s_channel_disable(tx_handle);
  i2s_del_channel(tx_handle);
  tx_handle = NULL;

  return true;
}

void setup() {
  Serial.begin(115200);
  delay(3000);

  Serial.println("===== IO8 / I2S 诊断 =====");
  Serial.printf("TEST_MODE = %d\n", TEST_MODE);
  Serial.printf("堆内存: %d bytes\n\n", ESP.getFreeHeap());
  Serial.flush();

#if TEST_MODE == 1
  Serial.println(">>> 测试 A: IO8 做普通 GPIO 输出");
  testGPIO(8);
#elif TEST_MODE == 2
  Serial.println(">>> 测试 B: IO8 做 I2S DIN");
  testI2S(8);
#elif TEST_MODE == 3
  Serial.println(">>> 测试 C: IO21 做 I2S DIN");
  testI2S(21);
#elif TEST_MODE == 4
  Serial.println(">>> 测试 D: gpio_reset_pin(IO8) 后再做 I2S DIN");
  Serial.println("  尝试先清除 SUBSPICS1 的 IO MUX 绑定...");
  Serial.flush(); delay(100);

  // 重置 IO8 为默认 GPIO 功能（清除 SUBSPICS1）
  esp_err_t rst = gpio_reset_pin(GPIO_NUM_8);
  Serial.printf("  gpio_reset_pin(8): %s\n", esp_err_to_name(rst));
  Serial.flush(); delay(100);

  // 额外：强制设为 GPIO 功能 (Function 1 = GPIO)
  gpio_iomux_out(8, 1, false);
  Serial.println("  gpio_iomux_out(8, 1, false) 完成");
  Serial.flush(); delay(100);

  testI2S(8);
#elif TEST_MODE == 5
  Serial.println(">>> 测试 E: 把 SUBSPICS1 重定向到 IO39，释放 IO8");
  Serial.flush(); delay(100);

  // 第一步：重置 IO8，断开它与 SUBSPICS1 的绑定
  esp_err_t rst2 = gpio_reset_pin(GPIO_NUM_8);
  Serial.printf("  gpio_reset_pin(8): %s\n", esp_err_to_name(rst2));
  Serial.flush(); delay(100);

  // 第二步：通过 GPIO Matrix 把 SUBSPICS1 输出信号路由到 IO39
  // SUBSPICS1 的信号编号 = FSPICS1_OUT_IDX (在 ESP32-S3 上)
  // 先把 IO39 配为输出
  gpio_set_direction(GPIO_NUM_39, GPIO_MODE_OUTPUT);
  // 用 esp_rom_gpio_connect_out_signal 把 SPI CS1 信号连到 IO39
  esp_rom_gpio_connect_out_signal(39, FSPICS1_OUT_IDX, false, false);
  Serial.println("  SUBSPICS1 已重定向到 IO39");
  Serial.flush(); delay(100);

  // 第三步：强制 IO8 为普通 GPIO
  gpio_iomux_out(8, 1, false);  // Function 1 = GPIO
  Serial.println("  IO8 切换为普通 GPIO 功能");
  Serial.flush(); delay(100);

  // 第四步：用 IO8 做 I2S DIN
  testI2S(8);
#endif

  Serial.println("\n===== 测试完成! 串口正常! =====");
  Serial.flush();
}

void loop() {
  Serial.printf("[心跳] %lus\n", millis()/1000);
  Serial.flush();
  delay(3000);
}
