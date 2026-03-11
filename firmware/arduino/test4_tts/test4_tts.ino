// ESP32-S3 MAX98357A + SAM TTS 语音合成测试
// 引脚: BCLK=IO17, LRC=IO18, DIN=IO8
// 使用 IDF5 新版 I2S API

#include <Arduino.h>
#include <driver/i2s_std.h>
#include <ESP8266SAM_ES.h>

SET_LOOP_TASK_STACK_SIZE(16 * 1024);

#define I2S_BCLK  17
#define I2S_LRC   18
#define I2S_DIN    8

// ===== 音量控制 =====
// 范围 0.0 ~ 1.0，改这个值调音量
// 0.1 = 很小声, 0.3 = 中等, 0.5 = 较大, 1.0 = 满幅
float VOLUME = 0.03;
// ====================

i2s_chan_handle_t tx_handle = NULL;

class I2SOutput : public AudioOutput {
public:
  float volume = 0.15;

  bool begin() override {
    i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_1, I2S_ROLE_MASTER);
    chan_cfg.dma_desc_num = 8;
    chan_cfg.dma_frame_num = 256;
    if (i2s_new_channel(&chan_cfg, &tx_handle, NULL) != ESP_OK) return false;

    i2s_std_config_t std_cfg = {
      .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(22050),
      .slot_cfg = I2S_STD_MSB_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO),
      .gpio_cfg = {
        .mclk = I2S_GPIO_UNUSED,
        .bclk = (gpio_num_t)I2S_BCLK,
        .ws = (gpio_num_t)I2S_LRC,
        .dout = (gpio_num_t)I2S_DIN,
        .din = I2S_GPIO_UNUSED,
        .invert_flags = { false, false, false },
      },
    };
    if (i2s_channel_init_std_mode(tx_handle, &std_cfg) != ESP_OK) return false;
    if (i2s_channel_enable(tx_handle) != ESP_OK) return false;
    return true;
  }

  bool ConsumeSample(int16_t sample[2]) override {
    // 应用音量缩放
    int16_t frame[2];
    frame[0] = (int16_t)(sample[0] * volume);
    frame[1] = (int16_t)(sample[1] * volume);
    size_t written;
    i2s_channel_write(tx_handle, frame, sizeof(frame), &written, portMAX_DELAY);
    return written > 0;
  }

  bool SetRate(int hz) override {
    i2s_std_clk_config_t clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(hz);
    i2s_channel_disable(tx_handle);
    i2s_channel_reconfig_std_clock(tx_handle, &clk_cfg);
    i2s_channel_enable(tx_handle);
    return true;
  }

  bool stop() override {
    if (tx_handle) {
      i2s_channel_disable(tx_handle);
      i2s_del_channel(tx_handle);
      tx_handle = NULL;
    }
    return true;
  }
};

I2SOutput *out = NULL;

void sayText(const char* text) {
  ESP8266SAM_ES *sam = new ESP8266SAM_ES;
  if (sam) {
    sam->Say(out, text);
    delete sam;
  }
  Serial.printf("  堆内存剩余: %d bytes\n", ESP.getFreeHeap());
}

void setup() {
  Serial.begin(115200);
  delay(3000);  // 多等一会让 USB CDC 稳定
  Serial.println("SAM TTS 语音合成测试开始...");
  Serial.printf("空闲堆内存: %d bytes\n", ESP.getFreeHeap());

  out = new I2SOutput();
  out->volume = VOLUME;  // 应用音量设置

  if (!out->begin()) {
    Serial.println("I2S 初始化失败!");
    return;
  }
  Serial.println("I2S 初始化成功!");
  Serial.printf("音量: %.0f%%\n", VOLUME * 100);

  Serial.println("\n测试1: Hola");
  sayText("Hola");
  delay(500);

  Serial.println("测试2: 数字计数");
  sayText("uno, dos, tres, cuatro, cinco");
  delay(500);

  Serial.println("测试3: 完整句子");
  sayText("Soy tu asistente.");
  delay(500);

  Serial.println("测试4: AI Bot");
  sayText("ey ay bot, lista.");
  delay(500);

  Serial.println("\nTTS 测试完成!");
  Serial.println("如果声音太大或太小，修改代码顶部的 VOLUME 值 (0.0~1.0)");
}

void loop() {
}
