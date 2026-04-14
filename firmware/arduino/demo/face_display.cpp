/*
 * face_display.cpp — AI-Bot 表情显示系统
 *
 * 使用接近 M5Stack-Avatar 默认脸构成的几何图元，
 * 渲染全屏静态表情脸。当前版本不渲染状态栏、底部文案，
 * 也不做眨眼、说话或 processing 动画。
 */

#include "face_display.h"

#include <Arduino.h>

namespace {

enum class ExpressionStyle {
    Neutral,
    Happy,
    Sleepy,
};

enum class MouthStyle {
    Neutral,
    Smile,
    SmallOpen,
    Open,
};

struct FaceTheme {
    uint16_t background;
    uint16_t feature;
    ExpressionStyle expression;
    MouthStyle mouth;
    int gazeX;
    int gazeY;
};

constexpr uint16_t COLOR_BG_IDLE = 0x0000;
constexpr uint16_t COLOR_BG_ACTIVE = 0x0881;
constexpr uint16_t COLOR_BG_LISTENING = 0x0083;
constexpr uint16_t COLOR_BG_PROCESSING = 0x1084;
constexpr uint16_t COLOR_BG_SPEAKING = 0x1061;

constexpr uint16_t COLOR_FEATURE_DEFAULT = 0xFFFF;
constexpr uint16_t COLOR_PROCESSING_DOT = 0xC7FF;

constexpr int FACE_EYE_Y = 92;
constexpr int FACE_EYE_OFFSET_X = 48;
constexpr int FACE_EYE_RADIUS = 16;

constexpr int FACE_MOUTH_Y = 150;
constexpr int FACE_DOT_Y = 52;
constexpr int FACE_DOT_RADIUS = 4;
constexpr int FACE_DOT_SPACING = 18;

TFT_eSPI* g_tft = nullptr;
FaceState g_currentState = FACE_IDLE;
unsigned long g_nextBlinkAt = 0;
unsigned long g_blinkStartedAt = 0;
unsigned long g_lastMouthToggleAt = 0;
unsigned long g_lastDotAdvanceAt = 0;
bool g_isBlinking = false;
bool g_isMouthOpen = true;
uint8_t g_dotPhase = 1;

FaceTheme themeForState(FaceState state) {
    switch (state) {
        case FACE_IDLE:
            return {COLOR_BG_IDLE, COLOR_FEATURE_DEFAULT, ExpressionStyle::Neutral, MouthStyle::Neutral, 0, 0};
        case FACE_ACTIVE:
            return {COLOR_BG_ACTIVE, COLOR_FEATURE_DEFAULT, ExpressionStyle::Happy, MouthStyle::Smile, 0, 0};
        case FACE_LISTENING:
            return {COLOR_BG_LISTENING, COLOR_FEATURE_DEFAULT, ExpressionStyle::Neutral, MouthStyle::SmallOpen, -4, 0};
        case FACE_PROCESSING:
            return {COLOR_BG_PROCESSING, COLOR_FEATURE_DEFAULT, ExpressionStyle::Sleepy, MouthStyle::Neutral, 0, 0};
        case FACE_SPEAKING:
            return {COLOR_BG_SPEAKING, COLOR_FEATURE_DEFAULT, ExpressionStyle::Neutral, MouthStyle::Open, 0, 1};
    }
    return {COLOR_BG_IDLE, COLOR_FEATURE_DEFAULT, ExpressionStyle::Neutral, MouthStyle::Neutral, 0, 0};
}

void scheduleNextBlink(unsigned long now) {
    const unsigned long minInterval = BLINK_INTERVAL_MIN_MS;
    const unsigned long maxInterval = BLINK_INTERVAL_MAX_MS;
    const unsigned long interval =
        minInterval + static_cast<unsigned long>(random(static_cast<long>(maxInterval - minInterval + 1)));
    g_nextBlinkAt = now + interval;
}

void resetAnimationState(FaceState state, unsigned long now) {
    g_isBlinking = false;
    g_blinkStartedAt = 0;
    scheduleNextBlink(now);

    g_isMouthOpen = true;
    g_lastMouthToggleAt = now;

    g_dotPhase = 1;
    g_lastDotAdvanceAt = now;

    if (state != FACE_SPEAKING) {
        g_isMouthOpen = false;
    }
}

void drawClosedEye(int centerX, const FaceTheme& theme) {
    const int eyeX = centerX + theme.gazeX;
    const int eyeY = FACE_EYE_Y + theme.gazeY;
    g_tft->fillRoundRect(
        eyeX - FACE_EYE_RADIUS,
        eyeY - 2,
        FACE_EYE_RADIUS * 2,
        4,
        2,
        theme.feature);
}

void drawEye(int centerX, const FaceTheme& theme) {
    const int eyeX = centerX + theme.gazeX;
    const int eyeY = FACE_EYE_Y + theme.gazeY;

    g_tft->fillCircle(eyeX, eyeY, FACE_EYE_RADIUS, theme.feature);

    switch (theme.expression) {
        case ExpressionStyle::Happy: {
            g_tft->fillCircle(eyeX, eyeY, FACE_EYE_RADIUS / 2 + 1, theme.background);
            g_tft->fillRect(
                eyeX - FACE_EYE_RADIUS - 2,
                eyeY,
                FACE_EYE_RADIUS * 2 + 4,
                FACE_EYE_RADIUS + 3,
                theme.background);
            break;
        }
        case ExpressionStyle::Sleepy: {
            g_tft->fillRect(
                eyeX - FACE_EYE_RADIUS - 2,
                eyeY - FACE_EYE_RADIUS,
                FACE_EYE_RADIUS * 2 + 4,
                FACE_EYE_RADIUS + 2,
                theme.background);
            break;
        }
        case ExpressionStyle::Neutral:
            break;
    }
}

void drawProcessingDots() {
    const int startX = FACE_CX - FACE_DOT_SPACING;
    for (uint8_t index = 0; index < g_dotPhase; ++index) {
        g_tft->fillCircle(
            startX + index * FACE_DOT_SPACING,
            FACE_DOT_Y,
            FACE_DOT_RADIUS,
            COLOR_PROCESSING_DOT);
    }
}

void drawSmileMouth(const FaceTheme& theme) {
    constexpr int radius = 26;
    constexpr int innerRadius = 16;

    g_tft->fillCircle(FACE_CX, FACE_MOUTH_Y, radius, theme.feature);
    g_tft->fillCircle(FACE_CX, FACE_MOUTH_Y - 8, innerRadius, theme.background);
    g_tft->fillRect(FACE_CX - radius - 4, FACE_MOUTH_Y - radius - 4, radius * 2 + 8, radius - 2, theme.background);
}

void drawNeutralMouth(const FaceTheme& theme, int width, int height) {
    g_tft->fillRoundRect(
        FACE_CX - width / 2,
        FACE_MOUTH_Y - height / 2,
        width,
        height,
        height / 2,
        theme.feature);
}

void drawOpenMouth(const FaceTheme& theme, int width, int height) {
    g_tft->fillRoundRect(
        FACE_CX - width / 2,
        FACE_MOUTH_Y - height / 2,
        width,
        height,
        10,
        theme.feature);
}

void drawMouth(FaceState state, const FaceTheme& theme) {
    switch (state) {
        case FACE_IDLE:
            drawNeutralMouth(theme, 48, 8);
            break;
        case FACE_ACTIVE:
            drawSmileMouth(theme);
            break;
        case FACE_LISTENING:
            drawOpenMouth(theme, 24, 14);
            break;
        case FACE_PROCESSING:
            drawNeutralMouth(theme, 40, 6);
            break;
        case FACE_SPEAKING:
            if (g_isMouthOpen) {
                drawOpenMouth(theme, 36, 28);
            } else {
                drawNeutralMouth(theme, 34, 8);
            }
            break;
    }
}

void drawCurrentFace() {
    if (g_tft == nullptr) {
        return;
    }

    const FaceTheme theme = themeForState(g_currentState);

    g_tft->fillScreen(theme.background);
    if (g_isBlinking) {
        drawClosedEye(FACE_CX - FACE_EYE_OFFSET_X, theme);
        drawClosedEye(FACE_CX + FACE_EYE_OFFSET_X, theme);
    } else {
        drawEye(FACE_CX - FACE_EYE_OFFSET_X, theme);
        drawEye(FACE_CX + FACE_EYE_OFFSET_X, theme);
    }
    drawMouth(g_currentState, theme);
    if (g_currentState == FACE_PROCESSING) {
        drawProcessingDots();
    }
}

}  // namespace

void faceInit(TFT_eSPI &tft) {
    g_tft = &tft;
    g_tft->init();
    g_tft->setRotation(0);
    randomSeed(micros());
    g_currentState = FACE_IDLE;
    resetAnimationState(g_currentState, millis());
    drawCurrentFace();
}

void faceSetState(FaceState state) {
    if (state == g_currentState) {
        return;
    }

    g_currentState = state;
    resetAnimationState(g_currentState, millis());
    drawCurrentFace();
}

FaceState faceGetState() {
    return g_currentState;
}

void faceUpdate() {
    const unsigned long now = millis();
    bool shouldRedraw = false;

    if (g_isBlinking) {
        if (now - g_blinkStartedAt >= BLINK_DURATION_MS) {
            g_isBlinking = false;
            scheduleNextBlink(now);
            shouldRedraw = true;
        }
    } else if (now >= g_nextBlinkAt) {
        g_isBlinking = true;
        g_blinkStartedAt = now;
        shouldRedraw = true;
    }

    if (g_currentState == FACE_SPEAKING && now - g_lastMouthToggleAt >= SPEAK_MOUTH_PERIOD_MS) {
        g_lastMouthToggleAt = now;
        g_isMouthOpen = !g_isMouthOpen;
        shouldRedraw = true;
    }

    if (g_currentState == FACE_PROCESSING && now - g_lastDotAdvanceAt >= PROCESS_DOT_PERIOD_MS) {
        g_lastDotAdvanceAt = now;
        g_dotPhase = (g_dotPhase % 3) + 1;
        shouldRedraw = true;
    }

    if (shouldRedraw) {
        drawCurrentFace();
    }
}

void faceSetText(const char* text) {
    (void)text;
}

void faceSetStatusBar(const char* time, bool wifiOk, bool wsOk) {
    (void)time;
    (void)wifiOk;
    (void)wsOk;
}

void faceSetBattery(int percent) {
    (void)percent;
}

void faceSetWeather(const char* weather) {
    (void)weather;
}
