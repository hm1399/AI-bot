// ESP32-S3 MPU6050 六轴传感器 I2C 测试
// 引脚: SDA=IO5, SCL=IO6, INT=IO4
// 模组: ZY-MPU-6050 邮票孔模组

#include <Wire.h>

#define I2C_SDA  5
#define I2C_SCL  6
#define MPU_INT  4
#define MPU_ADDR 0x68

// MPU6050 寄存器
#define REG_PWR_MGMT_1   0x6B
#define REG_ACCEL_XOUT_H 0x3B
#define REG_WHO_AM_I     0x75

int16_t ax, ay, az;  // 加速度
int16_t gx, gy, gz;  // 陀螺仪
int16_t temp_raw;     // 温度

// 动作检测状态
float prev_total_g = 1.0;
float prev_ax_g = 0, prev_ay_g = 0, prev_az_g = 0;
unsigned long lastTapTime = 0;
int tapCount = 0;
bool wasFaceDown = false;
bool wasFaceUp = true;

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("MPU6050 六轴传感器测试开始...");

  Wire.begin(I2C_SDA, I2C_SCL);

  // I2C 扫描
  Serial.println("I2C 扫描中...");
  bool found = false;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  发现设备: 0x%02X\n", addr);
      found = true;
    }
  }
  if (!found) {
    Serial.println("  未发现任何 I2C 设备! 检查接线和供电");
    while (1) delay(1000);
  }

  // 读取 WHO_AM_I
  uint8_t whoami = readByte(REG_WHO_AM_I);
  Serial.printf("WHO_AM_I: 0x%02X (期望 0x68 或 0x98)\n", whoami);

  // 唤醒 MPU6050（默认睡眠模式）
  writeByte(REG_PWR_MGMT_1, 0x00);
  delay(100);

  Serial.println("MPU6050 初始化完成!");
  Serial.println();
  Serial.println("支持检测动作:");
  Serial.println("  1. 摇一摇 (用力晃动)");
  Serial.println("  2. 敲击 (轻拍桌面)");
  Serial.println("  3. 翻转 (正面朝下/朝上)");
  Serial.println("  4. 左倾/右倾/前倾/后倾");
  Serial.println("  5. 自由落体 (小心!)");
  Serial.println("  6. 旋转 (绕Z轴转动)");
  Serial.println();
}

void loop() {
  readMPU();

  float temp_c = temp_raw / 340.0 + 36.53;

  // 加速度换算 (默认±2g量程, 16384 LSB/g)
  float ax_g = ax / 16384.0;
  float ay_g = ay / 16384.0;
  float az_g = az / 16384.0;

  float total_g = sqrt(ax_g * ax_g + ay_g * ay_g + az_g * az_g);

  // 每10次打印一行原始数据
  static int printCount = 0;
  if (printCount++ % 10 == 0) {
    Serial.printf("加速度: X=%+5.2f Y=%+5.2f Z=%+5.2f | 陀螺仪: X=%+6d Y=%+6d Z=%+6d | %.1f°C\n",
                  ax_g, ay_g, az_g, gx, gy, gz, temp_c);
  }

  // === 动作检测 ===

  // 1. 摇一摇
  if (total_g > 2.5) {
    Serial.println("  >>> 摇一摇!");
  }

  // 2. 敲击检测 (加速度突变)
  float delta_g = abs(total_g - prev_total_g);
  if (delta_g > 0.8 && delta_g < 2.5) {
    unsigned long now = millis();
    if (now - lastTapTime > 300) {
      tapCount = 1;
    } else {
      tapCount++;
    }
    lastTapTime = now;
    if (tapCount == 1) {
      Serial.println("  >>> 敲击!");
    } else {
      Serial.printf("  >>> 连续敲击 x%d\n", tapCount);
    }
  }

  // 3. 翻转检测
  bool faceDown = (az_g < -0.7);
  bool faceUp = (az_g > 0.7);

  if (faceDown && !wasFaceDown) {
    Serial.println("  >>> 翻转: 正面朝下 (扣放)");
  }
  if (faceUp && !wasFaceUp && wasFaceDown) {
    Serial.println("  >>> 翻转: 正面朝上 (翻回)");
  }
  wasFaceDown = faceDown;
  wasFaceUp = faceUp;

  // 4. 倾斜检测
  static unsigned long lastTiltPrint = 0;
  if (millis() - lastTiltPrint > 1000) {
    if (ax_g > 0.5)       { Serial.println("  >>> 左倾");   lastTiltPrint = millis(); }
    else if (ax_g < -0.5) { Serial.println("  >>> 右倾");   lastTiltPrint = millis(); }
    if (ay_g > 0.5)       { Serial.println("  >>> 前倾");   lastTiltPrint = millis(); }
    else if (ay_g < -0.5) { Serial.println("  >>> 后倾");   lastTiltPrint = millis(); }
  }

  // 5. 自由落体 (所有轴加速度接近0)
  if (total_g < 0.3) {
    Serial.println("  >>> 自由落体!");
  }

  // 6. 旋转检测 (陀螺仪Z轴)
  static unsigned long lastSpinPrint = 0;
  if (millis() - lastSpinPrint > 500) {
    if (abs(gz) > 15000) {
      Serial.printf("  >>> 旋转! %s (强度: %d)\n", gz > 0 ? "顺时针" : "逆时针", abs(gz));
      lastSpinPrint = millis();
    }
  }

  prev_total_g = total_g;
  prev_ax_g = ax_g;
  prev_ay_g = ay_g;
  prev_az_g = az_g;

  delay(50);
}

void readMPU() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(REG_ACCEL_XOUT_H);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14);

  ax = (Wire.read() << 8) | Wire.read();
  ay = (Wire.read() << 8) | Wire.read();
  az = (Wire.read() << 8) | Wire.read();
  temp_raw = (Wire.read() << 8) | Wire.read();
  gx = (Wire.read() << 8) | Wire.read();
  gy = (Wire.read() << 8) | Wire.read();
  gz = (Wire.read() << 8) | Wire.read();
}

void writeByte(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

uint8_t readByte(uint8_t reg) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 1);
  return Wire.read();
}
