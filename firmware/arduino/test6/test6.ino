// ESP32-S3 电容触摸感应测试
// 主触摸: IO7 (TOUCH_MAIN)
// 触摸子板通过 H4 排母连接，ESD保护电阻 R5 (4.7kΩ)

#define TOUCH_PIN  7  // TOUCH_MAIN

// 阈值（需根据实际硬件调整）
#define TOUCH_THRESHOLD  40000

// 手势识别参数
#define DOUBLE_CLICK_MS  400   // 双击间隔
#define LONG_PRESS_MS    800   // 长按时间

bool lastTouched = false;
unsigned long pressStart = 0;
unsigned long lastClickTime = 0;
int clickCount = 0;

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("触摸感应测试开始...");
  Serial.println("触摸铜皮区域，观察数值变化");
  Serial.println("支持: 单击 / 双击 / 长按");
  Serial.println();

  // 先打印10秒原始值帮助确定阈值
  Serial.println("--- 原始值采样 (10秒) ---");
  Serial.println("不触摸时记录基准值，触摸时观察变化");
  for (int i = 0; i < 100; i++) {
    uint32_t val = touchRead(TOUCH_PIN);
    bool touched = val > TOUCH_THRESHOLD;
    Serial.printf("触摸值: %6u  %s\n", val, touched ? "<<< 触摸中" : "");
    delay(100);
  }
  Serial.println("--- 采样结束，开始手势识别 ---");
  Serial.println();
}

void loop() {
  uint32_t val = touchRead(TOUCH_PIN);
  bool touched = val > TOUCH_THRESHOLD;

  // 按下瞬间
  if (touched && !lastTouched) {
    pressStart = millis();
  }

  // 松开瞬间
  if (!touched && lastTouched) {
    unsigned long pressDuration = millis() - pressStart;

    if (pressDuration >= LONG_PRESS_MS) {
      Serial.printf(">>> 长按 (%lu ms)  原始值: %u\n", pressDuration, val);
      clickCount = 0;
    } else {
      clickCount++;
      lastClickTime = millis();
    }
  }

  // 检测双击超时 → 判定单击还是双击
  if (clickCount > 0 && !touched && (millis() - lastClickTime > DOUBLE_CLICK_MS)) {
    if (clickCount == 1) {
      Serial.printf(">>> 单击  原始值: %u\n", val);
    } else {
      Serial.printf(">>> 双击 (%d次)  原始值: %u\n", clickCount, val);
    }
    clickCount = 0;
  }

  // 长按实时提示
  if (touched && (millis() - pressStart > LONG_PRESS_MS)) {
    static unsigned long lastHint = 0;
    if (millis() - lastHint > 500) {
      lastHint = millis();
      Serial.printf("    长按中... %lu ms  原始值: %u\n", millis() - pressStart, val);
    }
  }

  lastTouched = touched;
  delay(20);
}
