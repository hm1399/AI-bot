/*
 * face_display.cpp — AI-Bot 表情显示系统 (Phase 2: 动画表情)
 *
 * 屏幕 = 脸，不画轮廓框。眼睛和嘴巴直接绘制在黑色背景上。
 * 1.54" ST7789 240×240
 */

#include "face_display.h"
#include <math.h>

// ===== 内部状态 =====
static TFT_eSPI* _tft = nullptr;
static U8g2_for_TFT_eSPI _u8f;    // U8g2 中文字体渲染器
static FaceState _currentState = FACE_IDLE;
static char _textBuf[256] = "";
static int _textScrollOffset = 0;       // 文字滚动偏移（像素 Y）
static unsigned long _lastScrollTime = 0;
static bool _textNeedsScroll = false;    // 文字是否超出显示区域需要滚动
#define TEXT_SCROLL_INTERVAL 3000        // 滚动间隔 ms
#define TEXT_FONT_HEIGHT 16              // 中文字体像素高度
#define TEXT_LINE_SPACING 2              // 行间距
#define TEXT_LINE_HEIGHT (TEXT_FONT_HEIGHT + TEXT_LINE_SPACING)  // 行高
#define TEXT_MAX_LINES 2                 // 文字区最多显示行数（16px字体 × 2 + 间距 = 36px，适配48px区域）
#define TEXT_MARGIN_X 4                  // 左右边距

// ===== 动画状态变量 =====
static unsigned long _lastAnimTime = 0;
static unsigned long _stateEntryTime = 0;

// IDLE 眨眼
static unsigned long _nextBlinkTime = 0;
static unsigned long _blinkStartTime = 0;
static bool _isBlinking = false;

// ACTIVE 眼球移动
static int _eyeOffsetX = 0;

// LISTENING 歪头摇摆 + 单眼眨眼
static int _listenTiltPhase = 0;  // 0~359 度
static unsigned long _nextListenBlinkTime = 0;
static bool _listenBlink = false;
static unsigned long _listenBlinkStart = 0;

// PROCESSING 加载点
static int _dotPhase = 0;  // 0,1,2,3 (0=无点, 1=一个, 2=两个, 3=三个)
static unsigned long _lastDotTime = 0;

// SPEAKING 嘴巴开合 + 音符
static bool _mouthOpen = true;
static unsigned long _lastMouthTime = 0;
static float _noteY = 0;
static float _noteX = 0;
static bool _noteVisible = false;
static unsigned long _noteStartTime = 0;

// ===== 内部绘制函数 =====

// 清空表情区域
static void clearFaceArea() {
    _tft->fillRect(0, FACE_AREA_Y, SCREEN_W, FACE_AREA_H, COLOR_BG);
}

// 清空文字区域
static void clearTextArea() {
    _tft->fillRect(0, TEXT_AREA_Y, SCREEN_W, TEXT_AREA_H, COLOR_BG);
}

// 画实心圆眼睛
static void drawEye(int cx, int cy, int radius) {
    _tft->fillCircle(cx, cy, radius, COLOR_EYE);
}

// 画横线眼睛（闭眼/眯眼）
static void drawLineEye(int cx, int cy, int halfWidth) {
    _tft->drawLine(cx - halfWidth, cy, cx + halfWidth, cy, COLOR_EYE);
    _tft->drawLine(cx - halfWidth, cy + 1, cx + halfWidth, cy + 1, COLOR_EYE);
}

// 画微笑嘴（弧线向下弯 ﹏）
static void drawSmileMouth(int cx, int cy, int w) {
    // 用多段短线近似弧线
    for (int i = -w; i <= w; i++) {
        float t = (float)i / w;  // -1 to 1
        int y = cy + (int)(MOUTH_HEIGHT * (1.0f - t * t));  // 抛物线
        _tft->drawPixel(cx + i, y, COLOR_MOUTH);
        _tft->drawPixel(cx + i, y + 1, COLOR_MOUTH);
    }
}

// 画上扬弧线嘴 ‿（比微笑更明显）
static void drawHappyMouth(int cx, int cy, int w) {
    for (int i = -w; i <= w; i++) {
        float t = (float)i / w;
        int y = cy + (int)((MOUTH_HEIGHT + 4) * (1.0f - t * t));
        _tft->drawPixel(cx + i, y, COLOR_MOUTH);
        _tft->drawPixel(cx + i, y + 1, COLOR_MOUTH);
    }
}

// 画小短横线嘴（中性）
static void drawNeutralMouth(int cx, int cy, int halfWidth) {
    _tft->drawLine(cx - halfWidth, cy, cx + halfWidth, cy, COLOR_MOUTH);
    _tft->drawLine(cx - halfWidth, cy + 1, cx + halfWidth, cy + 1, COLOR_MOUTH);
}

// 画波浪线嘴 ～
static void drawWavyMouth(int cx, int cy, int w) {
    for (int i = -w; i <= w; i++) {
        float t = (float)i / w * 3.14159f * 2;
        int y = cy + (int)(3 * sin(t));
        _tft->drawPixel(cx + i, y, COLOR_MOUTH);
        _tft->drawPixel(cx + i, y + 1, COLOR_MOUTH);
    }
}

// 画张开的嘴（说话）
static void drawOpenMouth(int cx, int cy, int w, int h) {
    // 椭圆形张嘴
    for (int angle = 0; angle < 360; angle += 2) {
        float rad = angle * 3.14159f / 180.0f;
        int x = cx + (int)(w * cos(rad));
        int y = cy + (int)(h * sin(rad));
        _tft->drawPixel(x, y, COLOR_MOUTH);
    }
}

// 画眉毛（弯弧线，开心时用）
static void drawEyebrow(int cx, int cy, int w, bool happy) {
    int browY = cy - EYE_RADIUS_NORMAL - 6;
    if (happy) {
        for (int i = -w; i <= w; i++) {
            float t = (float)i / w;
            int y = browY - (int)(3 * (1.0f - t * t));
            _tft->drawPixel(cx + i, y, COLOR_EYE);
            _tft->drawPixel(cx + i, y - 1, COLOR_EYE);
        }
    }
}

// 画音符 ♪（像素风简笔）
static void drawNote(int cx, int cy, uint16_t color) {
    // 竖线（音符杆）
    _tft->drawLine(cx + 4, cy - 8, cx + 4, cy, color);
    // 小旗（顶部）
    _tft->drawLine(cx + 4, cy - 8, cx + 8, cy - 6, color);
    _tft->drawLine(cx + 4, cy - 7, cx + 8, cy - 5, color);
    // 圆头（底部）
    _tft->fillCircle(cx + 2, cy + 1, 2, color);
}

// 局部擦除眼睛区域（用于动画局部刷新）
static void clearEyeArea(int cx, int cy, int maxRadius) {
    int r = maxRadius + 2;
    _tft->fillRect(cx - r, cy - r, r * 2, r * 2, COLOR_BG);
}

// 局部擦除嘴巴区域
static void clearMouthArea() {
    int mouthY = FACE_CY + MOUTH_Y_OFFSET;
    _tft->fillRect(FACE_CX - MOUTH_WIDTH - 25, mouthY - 20,
                   (MOUTH_WIDTH + 25) * 2, 40, COLOR_BG);
}

// 局部擦除加载点区域
static void clearDotArea() {
    int dotY = FACE_CY + EYE_Y_OFFSET - 35;
    _tft->fillRect(FACE_CX - 25, dotY - 6, 50, 12, COLOR_BG);
}

// 局部擦除音符区域
static void clearNoteArea() {
    int noteAreaX = FACE_CX + EYE_SPACING + 30;
    int noteAreaY = FACE_CY - 50;
    _tft->fillRect(noteAreaX - 5, noteAreaY, 25, 80, COLOR_BG);
}

// ===== 5种表情绘制 =====

// 1. 空闲：圆眼 + 微笑
static void drawFaceIdle() {
    int eyeY = FACE_CY + EYE_Y_OFFSET;
    int mouthY = FACE_CY + MOUTH_Y_OFFSET;

    // 两个圆眼
    drawEye(FACE_CX - EYE_SPACING, eyeY, EYE_RADIUS_NORMAL);
    drawEye(FACE_CX + EYE_SPACING, eyeY, EYE_RADIUS_NORMAL);

    // 微笑嘴
    drawSmileMouth(FACE_CX, mouthY, MOUTH_WIDTH);
}

// 2. 工作状态：大圆眼 + 上扬笑嘴
static void drawFaceActive() {
    int eyeY = FACE_CY + EYE_Y_OFFSET;
    int mouthY = FACE_CY + MOUTH_Y_OFFSET;

    // 稍大的眼睛
    drawEye(FACE_CX - EYE_SPACING, eyeY, EYE_RADIUS_ACTIVE);
    drawEye(FACE_CX + EYE_SPACING, eyeY, EYE_RADIUS_ACTIVE);

    // 上扬笑嘴
    drawHappyMouth(FACE_CX, mouthY, MOUTH_WIDTH);
}

// 3. 聆听中：歪头倾听（一大一小眼 + 偏侧短横嘴）
static void drawFaceListening() {
    int eyeY = FACE_CY + EYE_Y_OFFSET;
    int mouthY = FACE_CY + MOUTH_Y_OFFSET;

    // 歪头效果：左眼小（远），右眼大（近），整体略偏右
    int tiltOffsetX = 7;   // 水平偏移模拟歪头
    int tiltOffsetY = -5;  // 右眼略高

    // 左眼（小，远侧）
    drawEye(FACE_CX - EYE_SPACING + tiltOffsetX, eyeY + 3, EYE_RADIUS_SMALL);

    // 右眼（大，近侧）
    drawEye(FACE_CX + EYE_SPACING + tiltOffsetX, eyeY + tiltOffsetY, EYE_RADIUS_BIG);

    // 嘴巴偏向一侧的短横线
    drawNeutralMouth(FACE_CX + tiltOffsetX + 7, mouthY, 16);
}

// 4. 思考中：横线眯眼 + 波浪嘴
static void drawFaceProcessing() {
    int eyeY = FACE_CY + EYE_Y_OFFSET;
    int mouthY = FACE_CY + MOUTH_Y_OFFSET;

    // 横线眼（眯眼沉思）
    drawLineEye(FACE_CX - EYE_SPACING, eyeY, EYE_RADIUS_NORMAL);
    drawLineEye(FACE_CX + EYE_SPACING, eyeY, EYE_RADIUS_NORMAL);

    // 波浪嘴
    drawWavyMouth(FACE_CX, mouthY, MOUTH_WIDTH);

    // "..." 加载点（静态版，Phase 2 做动画）
    int dotY = FACE_CY + EYE_Y_OFFSET - 35;
    _tft->fillCircle(FACE_CX - 15, dotY, 4, COLOR_DOT);
    _tft->fillCircle(FACE_CX, dotY, 4, COLOR_DOT);
    _tft->fillCircle(FACE_CX + 15, dotY, 4, COLOR_DOT);
}

// 5. 回复中：圆眼+眉毛 + 张嘴说话
static void drawFaceSpeaking() {
    int eyeY = FACE_CY + EYE_Y_OFFSET;
    int mouthY = FACE_CY + MOUTH_Y_OFFSET;

    // 圆眼
    drawEye(FACE_CX - EYE_SPACING, eyeY, EYE_RADIUS_NORMAL);
    drawEye(FACE_CX + EYE_SPACING, eyeY, EYE_RADIUS_NORMAL);

    // 开心的弯眉毛
    drawEyebrow(FACE_CX - EYE_SPACING, eyeY, 8, true);
    drawEyebrow(FACE_CX + EYE_SPACING, eyeY, 8, true);

    // 张开的嘴
    drawOpenMouth(FACE_CX, mouthY, 20, 14);
}

// ===== 绘制底部文字（U8g2 中文渲染） =====

// 计算文本总行数（基于 U8g2 UTF-8 字宽自动换行）
static int countTextLines() {
    if (_textBuf[0] == '\0') return 0;

    int lines = 1;
    int x = TEXT_MARGIN_X;
    int maxX = SCREEN_W - TEXT_MARGIN_X;
    const char* p = _textBuf;

    _u8f.setFont(u8g2_font_wqy16_t_gb2312);

    while (*p != '\0') {
        if (*p == '\n') {
            lines++;
            x = TEXT_MARGIN_X;
            p++;
            continue;
        }
        // 获取当前 UTF-8 字符宽度
        // 临时提取一个 UTF-8 字符
        char tmp[5] = {0};
        int charLen = 1;
        uint8_t c = (uint8_t)*p;
        if (c >= 0xF0) charLen = 4;
        else if (c >= 0xE0) charLen = 3;
        else if (c >= 0xC0) charLen = 2;
        for (int i = 0; i < charLen && p[i] != '\0'; i++) {
            tmp[i] = p[i];
        }

        int w = _u8f.getUTF8Width(tmp);
        if (x + w > maxX) {
            lines++;
            x = TEXT_MARGIN_X;
        }
        x += w;
        p += charLen;
    }
    return lines;
}

// 绘制一行文字，返回消耗的源字符串指针偏移
// startY 是 U8g2 的 baseline Y 坐标
static const char* drawOneLine(const char* p, int startY, int maxX) {
    int x = TEXT_MARGIN_X;
    _u8f.setCursor(x, startY);

    while (*p != '\0' && *p != '\n') {
        // 获取 UTF-8 字符长度
        char tmp[5] = {0};
        int charLen = 1;
        uint8_t c = (uint8_t)*p;
        if (c >= 0xF0) charLen = 4;
        else if (c >= 0xE0) charLen = 3;
        else if (c >= 0xC0) charLen = 2;
        for (int i = 0; i < charLen && p[i] != '\0'; i++) {
            tmp[i] = p[i];
        }

        int w = _u8f.getUTF8Width(tmp);
        if (x + w > maxX) {
            break;  // 换行
        }

        _u8f.setCursor(x, startY);
        _u8f.print(tmp);
        x += w;
        p += charLen;
    }

    // 跳过换行符
    if (*p == '\n') p++;
    return p;
}

static void drawText() {
    clearTextArea();

    // 分隔线
    _tft->drawLine(0, TEXT_AREA_Y, SCREEN_W, TEXT_AREA_Y, COLOR_DIVIDER);

    if (_textBuf[0] == '\0') return;

    _u8f.setFont(u8g2_font_wqy16_t_gb2312);
    _u8f.setFontMode(1);  // 透明模式
    _u8f.setForegroundColor(COLOR_TEXT_FG);

    int maxX = SCREEN_W - TEXT_MARGIN_X;
    const char* p = _textBuf;

    // 跳过滚动偏移的行
    int skipped = 0;
    while (*p != '\0' && skipped < _textScrollOffset) {
        // 模拟换行：遍历一行
        int x = TEXT_MARGIN_X;
        while (*p != '\0' && *p != '\n') {
            char tmp[5] = {0};
            int charLen = 1;
            uint8_t c = (uint8_t)*p;
            if (c >= 0xF0) charLen = 4;
            else if (c >= 0xE0) charLen = 3;
            else if (c >= 0xC0) charLen = 2;
            for (int i = 0; i < charLen && p[i] != '\0'; i++) {
                tmp[i] = p[i];
            }
            int w = _u8f.getUTF8Width(tmp);
            if (x + w > maxX) break;
            x += w;
            p += charLen;
        }
        if (*p == '\n') p++;
        skipped++;
    }

    // 绘制可见行
    for (int line = 0; line < TEXT_MAX_LINES && *p != '\0'; line++) {
        int baselineY = TEXT_AREA_Y + 6 + TEXT_FONT_HEIGHT + line * TEXT_LINE_HEIGHT;
        p = drawOneLine(p, baselineY, maxX);
    }

    // 如果有更多行未显示，在右下角画一个小箭头提示
    int totalLines = countTextLines();
    if (_textScrollOffset + TEXT_MAX_LINES < totalLines) {
        int arrowX = SCREEN_W - 10;
        int arrowY = TEXT_AREA_Y + TEXT_AREA_H - 6;
        _tft->drawLine(arrowX, arrowY - 3, arrowX, arrowY + 1, COLOR_DIVIDER);
        _tft->drawLine(arrowX - 2, arrowY - 1, arrowX, arrowY + 1, COLOR_DIVIDER);
        _tft->drawLine(arrowX + 2, arrowY - 1, arrowX, arrowY + 1, COLOR_DIVIDER);
    }
}

// 文字滚动动画（在 faceUpdate 中调用）
static void updateTextScroll() {
    if (!_textNeedsScroll) return;

    unsigned long now = millis();
    if (now - _lastScrollTime < TEXT_SCROLL_INTERVAL) return;
    _lastScrollTime = now;

    int totalLines = countTextLines();
    if (_textScrollOffset + TEXT_MAX_LINES < totalLines) {
        _textScrollOffset++;
        drawText();
    } else {
        // 滚动到底，重置
        _textScrollOffset = 0;
        drawText();
    }
}

// ===== 绘制状态栏 =====

static char _timeBuf[16] = "--:--";
static char _weatherBuf[16] = "";  // 天气温度（如 "23°C"）
static bool _wifiOk = false;
static bool _wsOk = false;
static int _batteryPercent = -1;  // -1 = 未知

// 画电池图标 (16×10 px)
static void drawBatteryIcon(int x, int y) {
    uint16_t color = COLOR_STATUS_TXT;
    if (_batteryPercent >= 0) {
        if (_batteryPercent <= 20) color = TFT_RED;
        else if (_batteryPercent <= 50) color = TFT_YELLOW;
        else color = TFT_GREEN;
    }

    // 电池外框
    _tft->drawRect(x, y, 14, 8, COLOR_STATUS_TXT);
    // 电池正极凸起
    _tft->fillRect(x + 14, y + 2, 2, 4, COLOR_STATUS_TXT);

    // 电量填充
    if (_batteryPercent >= 0) {
        int fillW = (int)(10.0f * _batteryPercent / 100.0f);
        if (fillW > 0) {
            _tft->fillRect(x + 2, y + 2, fillW, 4, color);
        }
    } else {
        // 未知电量：画问号
        _tft->setCursor(x + 3, y + 1);
        _tft->setTextColor(COLOR_STATUS_TXT, COLOR_STATUS_BG);
        _tft->setTextSize(1);
        _tft->print("?");
    }
}

// 画 WiFi 图标（简笔弧线）
static void drawWifiIcon(int x, int y, bool ok) {
    uint16_t color = ok ? TFT_GREEN : TFT_RED;
    // 底部小圆点
    _tft->fillCircle(x + 6, y + 7, 1, color);
    if (ok) {
        // 两条弧线表示信号
        for (int r = 3; r <= 6; r += 3) {
            for (int angle = -45; angle <= 45; angle += 5) {
                float rad = (angle - 90) * 3.14159f / 180.0f;
                int px = x + 6 + (int)(r * cos(rad));
                int py = y + 7 + (int)(r * sin(rad));
                _tft->drawPixel(px, py, color);
            }
        }
    } else {
        // 断开：画 X
        _tft->drawLine(x + 2, y + 1, x + 10, y + 6, color);
        _tft->drawLine(x + 10, y + 1, x + 2, y + 6, color);
    }
}

static void drawStatusBar() {
    _tft->fillRect(0, 0, SCREEN_W, STATUS_BAR_H, COLOR_STATUS_BG);
    _tft->setTextColor(COLOR_STATUS_TXT, COLOR_STATUS_BG);
    _tft->setTextSize(1);

    // 左侧：时间
    _tft->setCursor(6, 8);
    _tft->print(_timeBuf);

    // 中间：WiFi 图标
    drawWifiIcon(80, 5, _wifiOk);

    // WS 状态点
    _tft->setCursor(100, 8);
    _tft->print("WS");
    uint16_t wsColor = _wsOk ? TFT_GREEN : TFT_RED;
    _tft->fillCircle(118, 11, 3, wsColor);

    // 中右：天气温度
    if (_weatherBuf[0] != '\0') {
        _tft->setCursor(130, 8);
        _tft->print(_weatherBuf);
    }

    // 右侧：电池图标
    drawBatteryIcon(210, 7);

    // 底部分隔线
    _tft->drawLine(0, STATUS_BAR_H - 1, SCREEN_W, STATUS_BAR_H - 1, COLOR_DIVIDER);
}

// ===== 重绘当前表情 =====

static void drawCurrentFace() {
    clearFaceArea();

    switch (_currentState) {
        case FACE_IDLE:       drawFaceIdle(); break;
        case FACE_ACTIVE:     drawFaceActive(); break;
        case FACE_LISTENING:  drawFaceListening(); break;
        case FACE_PROCESSING: drawFaceProcessing(); break;
        case FACE_SPEAKING:   drawFaceSpeaking(); break;
    }
}

// ===== 公开接口实现 =====

void faceInit(TFT_eSPI &tft) {
    _tft = &tft;
    _tft->init();
    _tft->setRotation(0);
    _tft->fillScreen(COLOR_BG);

    // 初始化 U8g2 中文字体渲染器
    _u8f.begin(tft);
    _u8f.setFontMode(1);            // 透明模式
    _u8f.setFontDirection(0);       // 从左到右
    _u8f.setForegroundColor(COLOR_TEXT_FG);

    _currentState = FACE_IDLE;
    _stateEntryTime = millis();
    _lastAnimTime = millis();
    _nextBlinkTime = millis() + BLINK_INTERVAL_MIN + (unsigned long)(random(BLINK_INTERVAL_MAX - BLINK_INTERVAL_MIN));
    _nextListenBlinkTime = millis() + 2000;

    drawStatusBar();
    drawCurrentFace();
    drawText();
}

void faceSetState(FaceState state) {
    if (state == _currentState) return;
    _currentState = state;
    _stateEntryTime = millis();

    // 重置动画状态
    _isBlinking = false;
    _nextBlinkTime = millis() + BLINK_INTERVAL_MIN + (unsigned long)(random(BLINK_INTERVAL_MAX - BLINK_INTERVAL_MIN));
    _eyeOffsetX = 0;
    _listenBlink = false;
    _nextListenBlinkTime = millis() + 2000;
    _dotPhase = 0;
    _lastDotTime = millis();
    _mouthOpen = true;
    _lastMouthTime = millis();
    _noteVisible = false;

    drawCurrentFace();
}

FaceState faceGetState() {
    return _currentState;
}

void faceUpdate() {
    unsigned long now = millis();

    // 帧率控制：~15fps
    if (now - _lastAnimTime < ANIM_FRAME_MS) return;
    _lastAnimTime = now;

    switch (_currentState) {

    // ─── IDLE：定期眨眼 ───
    case FACE_IDLE: {
        if (!_isBlinking && now >= _nextBlinkTime) {
            // 开始眨眼：擦除眼睛区域，画横线眼
            _isBlinking = true;
            _blinkStartTime = now;
            int eyeY = FACE_CY + EYE_Y_OFFSET;
            int lx = FACE_CX - EYE_SPACING;
            int rx = FACE_CX + EYE_SPACING;
            clearEyeArea(lx, eyeY, EYE_RADIUS_NORMAL);
            clearEyeArea(rx, eyeY, EYE_RADIUS_NORMAL);
            drawLineEye(lx, eyeY, EYE_RADIUS_NORMAL);
            drawLineEye(rx, eyeY, EYE_RADIUS_NORMAL);
        }
        if (_isBlinking && (now - _blinkStartTime >= BLINK_DURATION)) {
            // 眨眼结束：恢复圆眼
            _isBlinking = false;
            int eyeY = FACE_CY + EYE_Y_OFFSET;
            int lx = FACE_CX - EYE_SPACING;
            int rx = FACE_CX + EYE_SPACING;
            clearEyeArea(lx, eyeY, EYE_RADIUS_NORMAL);
            clearEyeArea(rx, eyeY, EYE_RADIUS_NORMAL);
            drawEye(lx, eyeY, EYE_RADIUS_NORMAL);
            drawEye(rx, eyeY, EYE_RADIUS_NORMAL);
            // 设置下次眨眼时间
            _nextBlinkTime = now + BLINK_INTERVAL_MIN
                + (unsigned long)(random(BLINK_INTERVAL_MAX - BLINK_INTERVAL_MIN));
        }
        break;
    }

    // ─── ACTIVE：眼球左右缓慢移动 ───
    case FACE_ACTIVE: {
        unsigned long elapsed = now - _stateEntryTime;
        float phase = (float)(elapsed % ACTIVE_EYE_MOVE_PERIOD) / ACTIVE_EYE_MOVE_PERIOD;
        int newOffsetX = (int)(ACTIVE_EYE_MOVE_RANGE * sin(phase * 2 * 3.14159f));

        if (newOffsetX != _eyeOffsetX) {
            int eyeY = FACE_CY + EYE_Y_OFFSET;
            int lx = FACE_CX - EYE_SPACING;
            int rx = FACE_CX + EYE_SPACING;
            // 擦除旧位置
            clearEyeArea(lx + _eyeOffsetX, eyeY, EYE_RADIUS_ACTIVE);
            clearEyeArea(rx + _eyeOffsetX, eyeY, EYE_RADIUS_ACTIVE);
            // 画新位置
            _eyeOffsetX = newOffsetX;
            drawEye(lx + _eyeOffsetX, eyeY, EYE_RADIUS_ACTIVE);
            drawEye(rx + _eyeOffsetX, eyeY, EYE_RADIUS_ACTIVE);
        }
        break;
    }

    // ─── LISTENING：歪头摇摆 + 大眼单眼眨眼 ───
    case FACE_LISTENING: {
        unsigned long elapsed = now - _stateEntryTime;
        float phase = (float)(elapsed % LISTEN_TILT_PERIOD) / LISTEN_TILT_PERIOD;
        // 摇摆范围：tiltOffsetX 在 5~9 之间来回
        int newTiltX = 7 + (int)(2.0f * sin(phase * 2 * 3.14159f));
        int newTiltY = -5 + (int)(2.0f * sin(phase * 2 * 3.14159f));

        // 检测是否需要重绘（每帧 tilt 变化或眨眼状态变化）
        bool needRedraw = false;
        static int _prevTiltX = 7;
        static int _prevTiltY = -5;
        if (newTiltX != _prevTiltX || newTiltY != _prevTiltY) {
            needRedraw = true;
        }

        // 大眼侧单眼眨眼
        if (!_listenBlink && now >= _nextListenBlinkTime) {
            _listenBlink = true;
            _listenBlinkStart = now;
            needRedraw = true;
        }
        if (_listenBlink && (now - _listenBlinkStart >= BLINK_DURATION)) {
            _listenBlink = false;
            _nextListenBlinkTime = now + 2000 + (unsigned long)(random(1000));
            needRedraw = true;
        }

        if (needRedraw) {
            clearFaceArea();
            int eyeY = FACE_CY + EYE_Y_OFFSET;
            int mouthY = FACE_CY + MOUTH_Y_OFFSET;

            // 左眼（小，远侧）
            drawEye(FACE_CX - EYE_SPACING + newTiltX, eyeY + 3, EYE_RADIUS_SMALL);

            // 右眼（大，近侧）— 可能眨眼
            if (_listenBlink) {
                drawLineEye(FACE_CX + EYE_SPACING + newTiltX, eyeY + newTiltY, EYE_RADIUS_BIG);
            } else {
                drawEye(FACE_CX + EYE_SPACING + newTiltX, eyeY + newTiltY, EYE_RADIUS_BIG);
            }

            // 嘴巴
            drawNeutralMouth(FACE_CX + newTiltX + 7, mouthY, 16);

            _prevTiltX = newTiltX;
            _prevTiltY = newTiltY;
        }
        break;
    }

    // ─── PROCESSING：加载点循环动画 ───
    case FACE_PROCESSING: {
        if (now - _lastDotTime >= PROCESS_DOT_PERIOD) {
            _lastDotTime = now;
            _dotPhase = (_dotPhase + 1) % 4;  // 0→1→2→3→0

            // 擦除并重绘点
            clearDotArea();
            int dotY = FACE_CY + EYE_Y_OFFSET - 35;
            if (_dotPhase >= 1) _tft->fillCircle(FACE_CX - 15, dotY, 4, COLOR_DOT);
            if (_dotPhase >= 2) _tft->fillCircle(FACE_CX, dotY, 4, COLOR_DOT);
            if (_dotPhase >= 3) _tft->fillCircle(FACE_CX + 15, dotY, 4, COLOR_DOT);
        }
        break;
    }

    // ─── SPEAKING：嘴巴开合 + 音符上飘 ───
    case FACE_SPEAKING: {
        // 嘴巴开合动画
        if (now - _lastMouthTime >= SPEAK_MOUTH_PERIOD) {
            _lastMouthTime = now;
            _mouthOpen = !_mouthOpen;

            clearMouthArea();
            int mouthY = FACE_CY + MOUTH_Y_OFFSET;
            if (_mouthOpen) {
                drawOpenMouth(FACE_CX, mouthY, 20, 14);
            } else {
                drawNeutralMouth(FACE_CX, mouthY, 20);
            }
        }

        // 音符上飘动画
        if (!_noteVisible) {
            // 启动新音符
            _noteVisible = true;
            _noteStartTime = now;
            _noteX = FACE_CX + EYE_SPACING + 35;
            _noteY = FACE_CY + 10;
        }

        if (_noteVisible) {
            unsigned long noteElapsed = now - _noteStartTime;
            float progress = (float)noteElapsed / 2000.0f;  // 2秒飘完

            if (progress >= 1.0f) {
                // 音符消失，重新开始
                clearNoteArea();
                _noteVisible = false;
            } else {
                clearNoteArea();
                float curY = _noteY - progress * 60;  // 上飘60px
                float curX = _noteX + sin(progress * 3.14159f * 2) * 5;  // 左右轻微摆动
                // 音符颜色随高度渐淡（通过不同颜色模拟）
                uint16_t noteColor = (progress < 0.7f) ? COLOR_NOTE : COLOR_DIVIDER;
                drawNote((int)curX, (int)curY, noteColor);
            }
        }
        break;
    }

    } // end switch

    // 文字区滚动动画（所有状态通用）
    updateTextScroll();
}

void faceSetText(const char* text) {
    if (text == nullptr) {
        _textBuf[0] = '\0';
    } else {
        strncpy(_textBuf, text, sizeof(_textBuf) - 1);
        _textBuf[sizeof(_textBuf) - 1] = '\0';
    }
    _textScrollOffset = 0;
    _lastScrollTime = millis();
    _textNeedsScroll = (countTextLines() > TEXT_MAX_LINES);
    drawText();
}

void faceSetStatusBar(const char* time, bool wifiOk, bool wsOk) {
    bool needRedraw = false;

    if (time != nullptr && strcmp(time, _timeBuf) != 0) {
        strncpy(_timeBuf, time, sizeof(_timeBuf) - 1);
        _timeBuf[sizeof(_timeBuf) - 1] = '\0';
        needRedraw = true;
    }
    if (wifiOk != _wifiOk || wsOk != _wsOk) {
        _wifiOk = wifiOk;
        _wsOk = wsOk;
        needRedraw = true;
    }

    if (needRedraw) {
        drawStatusBar();
    }
}

void faceSetBattery(int percent) {
    if (percent == _batteryPercent) return;
    _batteryPercent = percent;
    drawStatusBar();
}

void faceSetWeather(const char* weather) {
    if (weather == nullptr) {
        _weatherBuf[0] = '\0';
    } else {
        strncpy(_weatherBuf, weather, sizeof(_weatherBuf) - 1);
        _weatherBuf[sizeof(_weatherBuf) - 1] = '\0';
    }
    drawStatusBar();
}
