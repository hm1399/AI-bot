# AI-Bot Flutter Network Layer

這是 Flutter App 的網絡層實現，用於 AI-Bot 專案（聲控桌面 AI 助理）。涵蓋 WebSocket 連接管理、REST API 封裝和局域網服務發現。

## 依賴
在 `pubspec.yaml` 中已定義，請執行 `flutter pub get`。

## 結構
- `lib/services/api_service.dart`: REST API 封裝（GET/POST/PUT）。
- `lib/services/discovery_service.dart`: 局域網 mDNS 發現。
- `lib/services/ws_service.dart`: WebSocket 管理（心跳、重連、生命週期）。

## 使用方式
1. **初始化**：
   - 發現服務：`await DiscoveryService().discover();`
   - 設定基底 URL：`ApiService().setBaseUrl(discoveredUrl);`
   - 初始化 WebSocket：`WsService().init('ws://ip:port/ws/app');`

2. **範例**：
   - 取得配置：`await apiService.getConfig();`
   - 送出聊天：`await apiService.postChat('Hello');`
   - WebSocket 送訊息：`wsService.sendMessage({'type': 'chat', 'content': 'Hi'});`

## 測試
- 在模擬器運行 `flutter run`。
- 用 Postman 模擬伺服器測試 API/WebSocket。
- 注意權限：iOS/Android 需要網路和發現權限（在 Info.plist/AndroidManifest 添加）。

## 注意事項
- AI-Bot 伺服器需實作 mDNS 廣播（Python zeroconf）和 /api/health 端點。
- 擴展：加入 SSL 支援（wss/https）。

如果有問題，歡迎 Issue 或 PR！
