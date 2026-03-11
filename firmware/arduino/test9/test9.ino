// ESP32-S3 WiFi 连接测试
// 测试: 扫描热点、连接WiFi、HTTP请求

#include <WiFi.h>
#include <HTTPClient.h>

// ===== 修改为你的 WiFi 信息 =====
const char* WIFI_SSID = "AAAAA";
const char* WIFI_PASS = "92935903";
// ================================

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("WiFi 连接测试开始...");
  Serial.println();

  // 测试1: 扫描周围热点
  Serial.println("=== 测试1: 扫描 WiFi 热点 ===");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);

  int n = WiFi.scanNetworks();
  if (n == 0) {
    Serial.println("未发现任何热点! 检查天线区域是否有遮挡");
  } else {
    Serial.printf("发现 %d 个热点:\n", n);
    for (int i = 0; i < n; i++) {
      Serial.printf("  %2d. %-32s  信号: %d dBm  %s\n",
                    i + 1,
                    WiFi.SSID(i).c_str(),
                    WiFi.RSSI(i),
                    WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "[开放]" : "[加密]");
    }
  }
  Serial.println();

  // 测试2: 连接指定 WiFi
  Serial.println("=== 测试2: 连接 WiFi ===");
  Serial.printf("正在连接: %s\n", WIFI_SSID);

  WiFi.begin(WIFI_SSID, WIFI_PASS);

  int retry = 0;
  while (WiFi.status() != WL_CONNECTED && retry < 30) {
    delay(500);
    Serial.print(".");
    retry++;
  }
  Serial.println();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi 连接失败! 检查 SSID 和密码");
    Serial.println("程序停止，修改后重新上传");
    while (1) delay(1000);
  }

  Serial.println("WiFi 连接成功!");
  Serial.printf("  IP 地址: %s\n", WiFi.localIP().toString().c_str());
  Serial.printf("  子网掩码: %s\n", WiFi.subnetMask().toString().c_str());
  Serial.printf("  网关: %s\n", WiFi.gatewayIP().toString().c_str());
  Serial.printf("  DNS: %s\n", WiFi.dnsIP().toString().c_str());
  Serial.printf("  信号强度: %d dBm\n", WiFi.RSSI());
  Serial.printf("  MAC 地址: %s\n", WiFi.macAddress().c_str());
  Serial.println();

  // 测试3: HTTP 请求
  Serial.println("=== 测试3: HTTP 网络请求 ===");
  HTTPClient http;
  http.begin("http://httpbin.org/ip");
  int httpCode = http.GET();

  if (httpCode > 0) {
    Serial.printf("HTTP 状态码: %d\n", httpCode);
    if (httpCode == HTTP_CODE_OK) {
      String payload = http.getString();
      Serial.printf("响应内容: %s\n", payload.c_str());
      Serial.println("网络连通性测试通过!");
    }
  } else {
    Serial.printf("HTTP 请求失败: %s\n", http.errorToString(httpCode).c_str());
  }
  http.end();

  Serial.println();
  Serial.println("=== 所有 WiFi 测试完成 ===");
}

void loop() {
  // 每10秒检查一次连接状态
  static unsigned long lastCheck = 0;
  if (millis() - lastCheck >= 10000) {
    lastCheck = millis();
    if (WiFi.status() == WL_CONNECTED) {
      Serial.printf("[在线] IP: %s  信号: %d dBm  运行: %lu 秒\n",
                    WiFi.localIP().toString().c_str(),
                    WiFi.RSSI(),
                    millis() / 1000);
    } else {
      Serial.println("[离线] WiFi 连接已断开!");
    }
  }
}
