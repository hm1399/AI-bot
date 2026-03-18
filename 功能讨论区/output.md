# 屏幕表情显示系统 — 设计计划

## 概述

为 AI-Bot 的 1.54寸 ST7789 屏幕 (240×240) 设计一套**像素风机器人表情系统**，根据设备状态切换不同表情，替代当前的纯文字状态提示。

## 设计目标

- 表情使用简笔画/像素风机器人脸（眼睛+嘴巴），不使用 emoji
- 表情占据屏幕中央主区域，辨识度高
- 顶部保留状态栏（WiFi/时间/天气）
- 状态切换时表情有简单动画过渡

---

## 屏幕布局

```
┌──────────────────────────┐
│  12:30  WiFi ● 晴 23°C  │ ← 状态栏 (y: 0~24, 24px)
├──────────────────────────┤
│                          │
│                          │
│        ◉        ◉        │ ← 表情区域 (y: 24~192, 168px)
│                          │    无脸框，眼睛嘴巴直接画在屏幕上
│          ───             │    屏幕边框本身就是"脸"
│                          │
│                          │
├──────────────────────────┤
│   AI: 今天天气不错~      │ ← 文字区域 (y: 192~240, 48px)
└──────────────────────────┘
```

**设计理念：屏幕 = 脸。** 不绘制任何脸部轮廓/矩形框，眼睛和嘴巴直接浮在黑色背景上，屏幕的物理边框就是机器人的脸边界。这样表情更大、更有冲击力，也更简洁。

- **状态栏 (24px)**: 时间 + WiFi连接图标 + 天气信息
- **表情区 (168px)**: 眼睛+嘴巴直接绘制，无轮廓框
- **文字区 (48px)**: AI最近回复文字 / 状态提示文字

---

## 表情设计（5种状态）

屏幕即脸，不画轮廓框。眼睛和嘴巴直接绘制在黑色背景上，通过改变形态来表达不同情绪。

### 1. 空闲/待机 — 显示时间天气

```
                           眼睛：圆形实心，正常大小
    ◉            ◉         嘴巴：短横线微笑 ﹏
                           动画：每隔几秒眨一次眼
        ﹏                   （眼睛变成短横线再恢复）

```

- 表情平静友好
- **定期眨眼动画**：每 3~5 秒随机眨眼一次（圆眼→横线→圆眼，约200ms）
- 状态栏正常显示时间+天气

### 2. 工作状态（最近30秒和用户聊过天）

```
                           眼睛：大圆半实心，显得精神
    ◕            ◕         嘴巴：上扬弧线 ‿
                           动画：眼睛微微左右移动
         ‿                   （像在思考/关注用户）

```

- 表情活泼、有互动感
- **眼球跟踪动画**：眼球缓慢左右小幅移动（±3px，周期2秒）
- 文字区显示最近AI回复内容

### 3. 聆听中 (LISTENING)

```
                           眼睛：一大一小（右眼稍大），整体微倾斜
      ◉          ●         嘴巴：小短横线，微微偏向一侧
                           动画：整组五官轻微旋转倾斜（像歪头）
          -                  + 大眼侧偶尔眨一下

```

- 表情可爱好奇、在认真倾听
- **歪头动画**：所有五官整体绕中心旋转 ±5°（周期2秒，缓动来回）
- **不对称眼睛**：左眼半径10px，右眼半径14px，营造歪头透视感
- **单眼眨眼**：大眼一侧每 2~3 秒眨一次
- 文字区显示 "聆听中..."

### 4. 执行中/思考中 (PROCESSING)

```
                           眼睛：横线（半闭眼沉思）
    ─            ─         嘴巴：波浪线 ～
                           动画：上方"..."加载点循环
         ～

```

- 表情沉思/正在努力工作
- **加载动画**：脸上方绘制三个点 `...` 依次出现循环（经典loading）
- **齿轮动画**（可选）：眼睛上方画小齿轮缓慢旋转
- 文字区显示 "思考中..."

### 5. 回复中 (SPEAKING)

```
                           眼睛：圆形+弯眉毛(开心)
    ◉            ◉         嘴巴：张开的弧形 ◡ (在说话)
                           动画：嘴巴开合交替
         ◡                   + 右侧有音符♪飘出

```

- 表情开心、正在输出
- **说话动画**：嘴巴在张开 ◡ 和闭合 ── 之间交替（周期400ms）
- **音符动画**：右侧绘制 ♪ 符号缓慢上飘并淡出
- 文字区显示当前AI回复文字

---

## 技术实现方案

### 方案选择：代码绘制（TFT_eSPI 基本图形）

不使用位图资源，直接用 TFT_eSPI 提供的绘图API绘制表情：

- `fillCircle()` / `drawCircle()` — 眼睛
- `drawArc()` — 嘴巴弧线
- `drawLine()` — 横线眼、声波线
- `fillRect()` — 局部刷新擦除

**优点：**
- 零资源占用，不需要存位图
- 动画灵活，改参数即可调整
- 代码量小，适合 ESP32

### 文件结构（新增）

```
firmware/arduino/demo/
├── demo.ino              # 主程序（修改）
├── face_display.h        # 表情系统头文件（新增）
├── face_display.cpp      # 表情绘制+动画逻辑（新增）
└── face_config.h         # 表情参数配置（新增）
```

### 核心代码结构

```cpp
// face_config.h — 布局与颜色常量
#define STATUS_BAR_H    24
#define FACE_AREA_Y     24
#define FACE_AREA_H     168
#define TEXT_AREA_Y     192
#define TEXT_AREA_H     48

#define EYE_COLOR       TFT_WHITE
#define MOUTH_COLOR     TFT_WHITE
#define BG_COLOR        TFT_BLACK

// face_display.h — 接口
enum FaceState {
    FACE_IDLE,
    FACE_ACTIVE,       // 最近聊过天
    FACE_LISTENING,
    FACE_PROCESSING,
    FACE_SPEAKING
};

void faceInit(TFT_eSPI &tft);
void faceSetState(FaceState state);
void faceUpdate();              // 主循环调用，驱动动画帧
void faceSetText(const char* text);  // 底部文字
void faceSetTime(const char* time);  // 状态栏时间
void faceSetWeather(const char* weather); // 状态栏天气
```

### 动画实现

- 主循环 `loop()` 中每帧调用 `faceUpdate()`
- `faceUpdate()` 内部用 `millis()` 计时，控制动画帧率（目标 ~15fps）
- 使用**局部刷新**：只重绘变化的部分（眼睛、嘴巴区域），避免全屏刷新闪烁
- 动画参数（速度、幅度）在 `face_config.h` 中可调

### 服务端配合修改

1. **新增 `display_face` 消息类型**（server/models/protocol.py）：
   ```python
   # 服务端发给设备的表情指令
   ServerMessageType.FACE_UPDATE = "face_update"
   # payload: {"state": "IDLE|ACTIVE|LISTENING|PROCESSING|SPEAKING"}
   ```

2. **device_channel.py 状态切换时发送表情指令**：
   ```python
   async def _set_state(self, new_state):
       # ... 现有状态切换逻辑 ...
       face_map = {
           DeviceState.IDLE: "IDLE",
           DeviceState.LISTENING: "LISTENING",
           DeviceState.PROCESSING: "PROCESSING",
           DeviceState.SPEAKING: "SPEAKING",
       }
       await self._send_message("face_update", {"state": face_map[new_state]})
   ```

3. **"最近聊过天" ACTIVE 状态判定**：
   ```python
   # 在 device_channel.py 中记录最后对话时间
   self._last_chat_time = 0

   # IDLE 状态下，如果30秒内聊过天，发送 ACTIVE 而不是 IDLE
   if new_state == DeviceState.IDLE and (time.time() - self._last_chat_time < 30):
       face_state = "ACTIVE"
   ```

4. **时间/天气推送**：
   - 服务端定时（每分钟）推送时间更新
   - 天气通过 API 获取，每30分钟更新一次
   - 新增 `status_bar_update` 消息类型

---

## 实施步骤

### Phase 1: 基础表情框架
1. 创建 `face_config.h` — 定义布局常量、颜色、动画参数
2. 创建 `face_display.h/cpp` — 实现 5 种静态表情绘制
3. 修改 `demo.ino` — 集成表情系统，状态切换时调表情
4. 测试：手动切换状态，确认 5 种表情正确显示

### Phase 2: 动画系统
5. 实现眨眼动画（IDLE 状态）
6. 实现眼球移动动画（ACTIVE 状态）
7. 实现声波+浮动动画（LISTENING 状态）
8. 实现加载点动画（PROCESSING 状态）
9. 实现说话+音符动画（SPEAKING 状态）
10. 优化局部刷新，消除闪烁

### Phase 3: 状态栏与文字区
11. 实现顶部状态栏（时间+WiFi图标+天气）
12. 实现底部文字区（AI回复文字滚动显示）
13. 服务端新增时间/天气推送逻辑

### Phase 4: 服务端集成
14. ✅ protocol.py 新增 `face_update` / `status_bar_update` 消息类型
15. ✅ device_channel.py 添加 ACTIVE 状态判定逻辑
16. ✅ device_channel.py 状态切换时发送表情指令（所有状态均发送 face_update）
17. 联调测试全链路（需设备连接后测试）

---

## 资源估算

| 项目 | 估算 |
|------|------|
| Flash 占用 | ~3-5 KB（纯代码绘制，无位图） |
| RAM 占用 | ~200 bytes（状态+动画参数） |
| CPU 占用 | 动画帧率 15fps，影响极小 |
| 新增文件 | 3个（face_config.h, face_display.h, face_display.cpp） |
| 修改文件 | 4个（demo.ino, protocol.py, device_channel.py, device_state.py） |
