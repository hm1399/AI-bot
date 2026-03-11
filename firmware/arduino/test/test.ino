// ESP32-S3 串口测试
// 测试 USB CDC 串口通信是否正常

#define LED_PIN 38  // WS2812B数据引脚，用于简单指示

void setup() {
  Serial.begin(115200);
  delay(2000);  // 等待USB CDC连接

  Serial.println("=============================");
  Serial.println("  ESP32-S3 串口测试程序");
  Serial.println("=============================");
  Serial.println("串口初始化成功！波特率: 115200");
  Serial.println("输入任意内容，设备将回显...");
  Serial.println();
}

void loop() {
  // 回显测试：收到什么就发回什么
  if (Serial.available() > 0) {
    String input = Serial.readStringUntil('\n');
    input.trim();

    if (input.length() > 0) {
      Serial.print("收到 (");
      Serial.print(input.length());
      Serial.print(" 字节): ");
      Serial.println(input);

      // 打印每个字节的十六进制值
      Serial.print("HEX: ");
      for (int i = 0; i < input.length(); i++) {
        if (i > 0) Serial.print(" ");
        Serial.printf("%02X", input[i]);
      }
      Serial.println();
      Serial.println();
    }
  }

  // 每5秒发送心跳，确认设备在线
  static unsigned long lastHeartbeat = 0;
  if (millis() - lastHeartbeat >= 5000) {
    lastHeartbeat = millis();
    Serial.printf("[心跳] 运行时间: %lu 秒\n", millis() / 1000);
  }
}
