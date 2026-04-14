/*
 * face_display.cpp — AI-Bot 表情显示系统
 *
 * 脸区使用 DiceBear Avataaars Neutral 风格的静态资源图，
 * 并叠加轻量眨眼 / 说话 / processing 点点动画。
 */

#include "face_display.h"

#include <math.h>
#include <string.h>

#include "face_theme_assets.h"

static TFT_eSPI* _tft = nullptr;
static U8g2_for_TFT_eSPI _u8f;
static FaceState _currentState = FACE_IDLE;

static char _textBuf[256] = "";
static int _textScrollOffset = 0;
static unsigned long _lastScrollTime = 0;
static bool _textNeedsScroll = false;

static unsigned long _lastAnimTime = 0;
static unsigned long _nextBlinkTime = 0;
static unsigned long _blinkStartTime = 0;
static bool _isBlinking = false;
static int _dotPhase = 1;
static unsigned long _lastDotTime = 0;
static bool _mouthOpen = false;
static unsigned long _lastMouthTime = 0;

static char _timeBuf[16] = "--:--";
static char _weatherBuf[16] = "";
static bool _wifiOk = false;
static bool _wsOk = false;
static int _batteryPercent = -1;

#define TEXT_SCROLL_INTERVAL 3000
#define TEXT_FONT_HEIGHT 16
#define TEXT_LINE_SPACING 2
#define TEXT_LINE_HEIGHT (TEXT_FONT_HEIGHT + TEXT_LINE_SPACING)
#define TEXT_MAX_LINES 2
#define TEXT_MARGIN_X 4

static int stateIndex(FaceState state) {
    switch (state) {
        case FACE_IDLE:
            return 0;
        case FACE_ACTIVE:
            return 1;
        case FACE_LISTENING:
            return 2;
        case FACE_PROCESSING:
            return 3;
        case FACE_SPEAKING:
            return 4;
    }
    return 0;
}

static uint16_t currentFaceBackground() {
    return FACE_THEME_BACKGROUNDS[stateIndex(_currentState)];
}

static void scheduleNextBlink(unsigned long now) {
    unsigned long minInterval = BLINK_INTERVAL_MIN;
    unsigned long maxInterval = BLINK_INTERVAL_MAX;

    if (_currentState == FACE_ACTIVE) {
        minInterval = 2200;
        maxInterval = 3600;
    } else if (_currentState == FACE_LISTENING) {
        minInterval = 1800;
        maxInterval = 3000;
    }

    unsigned long jitter = 0;
    if (maxInterval > minInterval) {
        jitter = (unsigned long)random((long)(maxInterval - minInterval));
    }
    _nextBlinkTime = now + minInterval + jitter;
}

static void clearFaceArea(uint16_t color) {
    _tft->fillRect(0, FACE_AREA_Y, SCREEN_W, FACE_AREA_H, color);
}

static void clearTextArea() {
    _tft->fillRect(0, TEXT_AREA_Y, SCREEN_W, TEXT_AREA_H, COLOR_BG);
}

static void drawBaseFace(FaceState state) {
    const int index = stateIndex(state);
    const uint16_t bg = FACE_THEME_BACKGROUNDS[index];
    clearFaceArea(bg);
    _tft->pushImage(
        (SCREEN_W - FACE_THEME_IMAGE_W) / 2,
        FACE_AREA_Y + (FACE_AREA_H - FACE_THEME_IMAGE_H) / 2,
        FACE_THEME_IMAGE_W,
        FACE_THEME_IMAGE_H,
        FACE_THEME_IMAGES[index]);
}

static void drawBlinkOverlay() {
    const uint16_t bg = currentFaceBackground();
    const int eyeXs[] = {FACE_LEFT_EYE_X, FACE_RIGHT_EYE_X};
    for (int eyeX : eyeXs) {
        _tft->fillRoundRect(
            eyeX - FACE_EYE_CLEAR_W / 2,
            FACE_EYE_Y - FACE_EYE_CLEAR_H / 2,
            FACE_EYE_CLEAR_W,
            FACE_EYE_CLEAR_H,
            6,
            bg);
        _tft->drawFastHLine(eyeX - FACE_EYE_HALF_W, FACE_EYE_Y, FACE_EYE_HALF_W * 2, COLOR_FACE_FEATURE);
        _tft->drawFastHLine(eyeX - FACE_EYE_HALF_W + 2, FACE_EYE_Y + 1, FACE_EYE_HALF_W * 2 - 4, COLOR_FACE_FEATURE);
    }
}

static void drawProcessingDots() {
    for (int i = 0; i < _dotPhase; ++i) {
        _tft->fillCircle(FACE_CX - 16 + i * 16, FACE_DOT_Y, 4, COLOR_DOT);
    }
}

static void clearSpeakingMouthArea() {
    _tft->fillRoundRect(
        FACE_MOUTH_X - FACE_MOUTH_CLEAR_W / 2,
        FACE_MOUTH_Y - FACE_MOUTH_CLEAR_H / 2,
        FACE_MOUTH_CLEAR_W,
        FACE_MOUTH_CLEAR_H,
        10,
        currentFaceBackground());
}

static void drawSpeakingMouthOverlay() {
    clearSpeakingMouthArea();
    _tft->fillRoundRect(
        FACE_MOUTH_X - FACE_MOUTH_W / 2,
        FACE_MOUTH_Y - FACE_MOUTH_H / 2,
        FACE_MOUTH_W,
        FACE_MOUTH_H,
        12,
        COLOR_FACE_FEATURE);
    _tft->drawFastHLine(FACE_MOUTH_X - 18, FACE_MOUTH_Y - 9, 36, COLOR_FACE_HIGHLIGHT);
    _tft->fillRoundRect(FACE_MOUTH_X - 16, FACE_MOUTH_Y + 1, 32, 11, 8, COLOR_FACE_TONGUE);
}

static void drawCurrentFace() {
    drawBaseFace(_currentState);

    switch (_currentState) {
        case FACE_IDLE:
        case FACE_ACTIVE:
        case FACE_LISTENING:
            if (_isBlinking) {
                drawBlinkOverlay();
            }
            break;
        case FACE_PROCESSING:
            drawProcessingDots();
            break;
        case FACE_SPEAKING:
            if (_mouthOpen) {
                drawSpeakingMouthOverlay();
            }
            break;
    }
}

static int countTextLines() {
    if (_textBuf[0] == '\0') return 0;

    int lines = 1;
    int x = TEXT_MARGIN_X;
    const int maxX = SCREEN_W - TEXT_MARGIN_X;
    const char* p = _textBuf;

    _u8f.setFont(u8g2_font_wqy16_t_gb2312);

    while (*p != '\0') {
        if (*p == '\n') {
            lines++;
            x = TEXT_MARGIN_X;
            p++;
            continue;
        }

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

static const char* drawOneLine(const char* p, int startY, int maxX) {
    int x = TEXT_MARGIN_X;
    _u8f.setCursor(x, startY);

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
        if (x + w > maxX) {
            break;
        }

        _u8f.setCursor(x, startY);
        _u8f.print(tmp);
        x += w;
        p += charLen;
    }

    if (*p == '\n') p++;
    return p;
}

static void drawText() {
    clearTextArea();
    _tft->drawLine(0, TEXT_AREA_Y, SCREEN_W, TEXT_AREA_Y, COLOR_DIVIDER);

    if (_textBuf[0] == '\0') return;

    _u8f.setFont(u8g2_font_wqy16_t_gb2312);
    _u8f.setFontMode(1);
    _u8f.setForegroundColor(COLOR_TEXT_FG);

    const int maxX = SCREEN_W - TEXT_MARGIN_X;
    const char* p = _textBuf;

    int skipped = 0;
    while (*p != '\0' && skipped < _textScrollOffset) {
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

    for (int line = 0; line < TEXT_MAX_LINES && *p != '\0'; line++) {
        int baselineY = TEXT_AREA_Y + 6 + TEXT_FONT_HEIGHT + line * TEXT_LINE_HEIGHT;
        p = drawOneLine(p, baselineY, maxX);
    }

    int totalLines = countTextLines();
    if (_textScrollOffset + TEXT_MAX_LINES < totalLines) {
        int arrowX = SCREEN_W - 10;
        int arrowY = TEXT_AREA_Y + TEXT_AREA_H - 6;
        _tft->drawLine(arrowX, arrowY - 3, arrowX, arrowY + 1, COLOR_DIVIDER);
        _tft->drawLine(arrowX - 2, arrowY - 1, arrowX, arrowY + 1, COLOR_DIVIDER);
        _tft->drawLine(arrowX + 2, arrowY - 1, arrowX, arrowY + 1, COLOR_DIVIDER);
    }
}

static void updateTextScroll() {
    if (!_textNeedsScroll) return;

    unsigned long now = millis();
    if (now - _lastScrollTime < TEXT_SCROLL_INTERVAL) return;
    _lastScrollTime = now;

    int totalLines = countTextLines();
    if (_textScrollOffset + TEXT_MAX_LINES < totalLines) {
        _textScrollOffset++;
    } else {
        _textScrollOffset = 0;
    }
    drawText();
}

static void drawBatteryIcon(int x, int y) {
    uint16_t color = COLOR_STATUS_TXT;
    if (_batteryPercent >= 0) {
        if (_batteryPercent <= 20) color = TFT_RED;
        else if (_batteryPercent <= 50) color = TFT_YELLOW;
        else color = TFT_GREEN;
    }

    _tft->drawRect(x, y, 14, 8, COLOR_STATUS_TXT);
    _tft->fillRect(x + 14, y + 2, 2, 4, COLOR_STATUS_TXT);

    if (_batteryPercent >= 0) {
        int fillW = (int)(10.0f * _batteryPercent / 100.0f);
        if (fillW > 0) {
            _tft->fillRect(x + 2, y + 2, fillW, 4, color);
        }
    } else {
        _tft->setCursor(x + 3, y + 1);
        _tft->setTextColor(COLOR_STATUS_TXT, COLOR_STATUS_BG);
        _tft->setTextSize(1);
        _tft->print("?");
    }
}

static void drawWifiIcon(int x, int y, bool ok) {
    uint16_t color = ok ? TFT_GREEN : TFT_RED;
    _tft->fillCircle(x + 6, y + 7, 1, color);
    if (ok) {
        for (int r = 3; r <= 6; r += 3) {
            for (int angle = -45; angle <= 45; angle += 5) {
                float rad = (angle - 90) * 3.14159f / 180.0f;
                int px = x + 6 + (int)(r * cos(rad));
                int py = y + 7 + (int)(r * sin(rad));
                _tft->drawPixel(px, py, color);
            }
        }
    } else {
        _tft->drawLine(x + 2, y + 1, x + 10, y + 6, color);
        _tft->drawLine(x + 10, y + 1, x + 2, y + 6, color);
    }
}

static void drawStatusBar() {
    _tft->fillRect(0, 0, SCREEN_W, STATUS_BAR_H, COLOR_STATUS_BG);
    _tft->setTextColor(COLOR_STATUS_TXT, COLOR_STATUS_BG);
    _tft->setTextSize(1);

    _tft->setCursor(6, 8);
    _tft->print(_timeBuf);

    drawWifiIcon(80, 5, _wifiOk);

    _tft->setCursor(100, 8);
    _tft->print("WS");
    _tft->fillCircle(118, 11, 3, _wsOk ? TFT_GREEN : TFT_RED);

    if (_weatherBuf[0] != '\0') {
        _tft->setCursor(130, 8);
        _tft->print(_weatherBuf);
    }

    drawBatteryIcon(210, 7);
    _tft->drawLine(0, STATUS_BAR_H - 1, SCREEN_W, STATUS_BAR_H - 1, COLOR_DIVIDER);
}

void faceInit(TFT_eSPI &tft) {
    _tft = &tft;
    _tft->init();
    _tft->setRotation(0);
    _tft->fillScreen(COLOR_BG);

    _u8f.begin(tft);
    _u8f.setFontMode(1);
    _u8f.setFontDirection(0);
    _u8f.setForegroundColor(COLOR_TEXT_FG);

    unsigned long now = millis();
    _lastAnimTime = now;
    _lastDotTime = now;
    _lastMouthTime = now;
    _mouthOpen = false;
    _dotPhase = 1;
    scheduleNextBlink(now);

    drawStatusBar();
    drawCurrentFace();
    drawText();
}

void faceSetState(FaceState state) {
    if (state == _currentState) return;
    _currentState = state;

    unsigned long now = millis();
    _isBlinking = false;
    _dotPhase = 1;
    _lastDotTime = now;
    _mouthOpen = (state == FACE_SPEAKING);
    _lastMouthTime = now;
    scheduleNextBlink(now);

    drawCurrentFace();
}

FaceState faceGetState() {
    return _currentState;
}

void faceUpdate() {
    unsigned long now = millis();
    if (now - _lastAnimTime < ANIM_FRAME_MS) {
        updateTextScroll();
        return;
    }
    _lastAnimTime = now;

    bool needRedraw = false;

    switch (_currentState) {
        case FACE_IDLE:
        case FACE_ACTIVE:
        case FACE_LISTENING:
            if (!_isBlinking && now >= _nextBlinkTime) {
                _isBlinking = true;
                _blinkStartTime = now;
                needRedraw = true;
            } else if (_isBlinking && now - _blinkStartTime >= BLINK_DURATION) {
                _isBlinking = false;
                scheduleNextBlink(now);
                needRedraw = true;
            }
            break;
        case FACE_PROCESSING:
            if (now - _lastDotTime >= PROCESS_DOT_PERIOD) {
                _lastDotTime = now;
                _dotPhase = (_dotPhase % 3) + 1;
                needRedraw = true;
            }
            break;
        case FACE_SPEAKING:
            if (now - _lastMouthTime >= SPEAK_MOUTH_PERIOD) {
                _lastMouthTime = now;
                _mouthOpen = !_mouthOpen;
                needRedraw = true;
            }
            break;
    }

    if (needRedraw) {
        drawCurrentFace();
    }

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
