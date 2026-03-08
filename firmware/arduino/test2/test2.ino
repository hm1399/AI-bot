// ESP32-S3 ST7789 屏幕驱动测试
// 1.69寸 IPS TFT 240x280 ST7789
// 使用 TFT_eSPI 库

#include <SPI.h>
#include <TFT_eSPI.h>

TFT_eSPI tft = TFT_eSPI();

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("ST7789 屏幕测试开始...");

  tft.init();
  tft.setRotation(0);  // 竖屏 240x240

  // 测试1: 纯色填充
  Serial.println("测试1: 红色填充");
  tft.fillScreen(TFT_RED);
  delay(1000);

  Serial.println("测试2: 绿色填充");
  tft.fillScreen(TFT_GREEN);
  delay(1000);

  Serial.println("测试3: 蓝色填充");
  tft.fillScreen(TFT_BLUE);
  delay(1000);

  // 测试2: 文字显示
  Serial.println("测试4: 文字显示");
  tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(30, 20);
  tft.println("AI-Bot");
  tft.setTextSize(1);
  tft.setCursor(30, 60);
  tft.println("ST7789 240x280");
  tft.setCursor(30, 80);
  tft.println("Screen Test OK!");
  delay(2000);

  // 测试3: 几何图形
  Serial.println("测试5: 几何图形");
  tft.fillScreen(TFT_BLACK);
  tft.drawRect(10, 10, 220, 100, TFT_WHITE);
  tft.fillCircle(120, 170, 40, TFT_CYAN);
  tft.drawLine(0, 240, 240, 240, TFT_YELLOW);
  tft.fillRoundRect(50, 220, 140, 40, 8, TFT_MAGENTA);
  tft.setTextColor(TFT_WHITE);
  tft.setTextSize(1);
  tft.setCursor(75, 233);
  tft.println("Hello World");

  Serial.println("所有测试完成!");
}

void loop() {
  // 循环显示彩色渐变条
  static uint32_t lastUpdate = 0;
  static int offset = 0;

  if (millis() - lastUpdate > 50) {
    lastUpdate = millis();
    for (int y = 260; y < 280; y++) {
      for (int x = 0; x < 240; x++) {
        uint16_t color = tft.color565((x + offset) & 0xFF, (y * 4) & 0xFF, 128);
        tft.drawPixel(x, y, color);
      }
    }
    offset += 2;
  }
}
