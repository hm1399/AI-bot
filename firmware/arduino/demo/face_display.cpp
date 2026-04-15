/*
 * face_display.cpp — AI-Bot 表情显示系统
 *
 * 使用接近 M5Stack-Avatar 默认脸构成的几何图元，
 * 渲染全屏静态表情脸，并在底部覆盖带优先级的字幕层。
 */

#include "face_display.h"

#include <Arduino.h>
#include <U8g2_for_TFT_eSPI.h>

#include <string.h>

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
constexpr uint16_t COLOR_BG_FOCUS = 0x0192;
constexpr uint16_t COLOR_BG_DENY = 0xA1E0;
constexpr uint16_t COLOR_BG_INTERRUPT = 0xB8A3;
constexpr uint16_t COLOR_BG_LISTENING = 0x0083;
constexpr uint16_t COLOR_BG_PROCESSING = 0x1084;
constexpr uint16_t COLOR_BG_SPEAKING = 0x1061;

constexpr uint16_t COLOR_FEATURE_DEFAULT = 0xFFFF;
constexpr uint16_t COLOR_PROCESSING_DOT = 0xC7FF;
constexpr uint16_t COLOR_SUBTITLE_BG = 0x0000;
constexpr uint16_t COLOR_SUBTITLE_TEXT = 0xFFFF;

constexpr int FACE_EYE_Y = 92;
constexpr int FACE_EYE_OFFSET_X = 48;
constexpr int FACE_EYE_RADIUS = 16;

constexpr int FACE_MOUTH_Y = 150;
constexpr int FACE_DOT_Y = 52;
constexpr int FACE_DOT_RADIUS = 4;
constexpr int FACE_DOT_SPACING = 18;
constexpr int EYE_CLEAR_PADDING_X = 6;
constexpr int EYE_CLEAR_PADDING_Y = 8;
constexpr int MOUTH_CLEAR_W = 80;
constexpr int MOUTH_CLEAR_H = 68;
constexpr int DOT_CLEAR_X = FACE_CX - FACE_DOT_SPACING - 10;
constexpr int DOT_CLEAR_Y = FACE_DOT_Y - 10;
constexpr int DOT_CLEAR_W = FACE_DOT_SPACING * 2 + 20;
constexpr int DOT_CLEAR_H = 20;
constexpr int SUBTITLE_BOX_MARGIN_X = 10;
constexpr int SUBTITLE_BOX_MARGIN_BOTTOM = 8;
constexpr int SUBTITLE_BOX_PADDING_X = 12;
constexpr int SUBTITLE_BOX_RADIUS = 10;
constexpr int SUBTITLE_BOX_H = 48;
constexpr int SUBTITLE_CLIP_PADDING_Y = 6;
constexpr int SUBTITLE_SCROLL_STEP_PX = 1;
constexpr unsigned long SUBTITLE_SCROLL_STEP_INTERVAL_MS = 50;
constexpr unsigned long SUBTITLE_SCROLL_START_HOLD_MS = 900;
constexpr unsigned long SUBTITLE_SCROLL_END_HOLD_MS = 1200;
constexpr size_t SUBTITLE_BUFFER_SIZE = 256;

enum class SubtitleScrollPhase {
    Idle,
    LeadingHold,
    Scrolling,
    TrailingHold,
};

TFT_eSPI* g_tft = nullptr;
U8g2_for_TFT_eSPI g_u8f;
FaceState g_currentState = FACE_IDLE;
unsigned long g_nextBlinkAt = 0;
unsigned long g_blinkStartedAt = 0;
unsigned long g_lastMouthToggleAt = 0;
unsigned long g_lastDotAdvanceAt = 0;
bool g_isBlinking = false;
bool g_isMouthOpen = true;
uint8_t g_dotPhase = 1;
char g_replySubtitleText[SUBTITLE_BUFFER_SIZE] = "";
char g_statusSubtitleText[SUBTITLE_BUFFER_SIZE] = "";
SubtitleScrollPhase g_subtitleScrollPhase = SubtitleScrollPhase::Idle;
unsigned long g_subtitleScrollPhaseStartedAt = 0;
unsigned long g_lastSubtitleScrollAt = 0;
int g_subtitleScrollOffsetPx = 0;
int g_subtitleScrollDistancePx = 0;

FaceTheme themeForState(FaceState state) {
    switch (state) {
        case FACE_IDLE:
            return {COLOR_BG_IDLE, COLOR_FEATURE_DEFAULT, ExpressionStyle::Neutral, MouthStyle::Neutral, 0, 0};
        case FACE_ACTIVE:
            return {COLOR_BG_ACTIVE, COLOR_FEATURE_DEFAULT, ExpressionStyle::Happy, MouthStyle::Smile, 0, 0};
        case FACE_FOCUS:
            return {COLOR_BG_FOCUS, COLOR_FEATURE_DEFAULT, ExpressionStyle::Sleepy, MouthStyle::Neutral, 0, -1};
        case FACE_DENY:
            return {COLOR_BG_DENY, COLOR_FEATURE_DEFAULT, ExpressionStyle::Neutral, MouthStyle::Neutral, -3, 0};
        case FACE_INTERRUPT:
            return {COLOR_BG_INTERRUPT, COLOR_FEATURE_DEFAULT, ExpressionStyle::Neutral, MouthStyle::Open, 0, -1};
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

void clearFaceRegion(int x, int y, int w, int h, const FaceTheme& theme) {
    g_tft->fillRect(x, y, w, h, theme.background);
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
        case FACE_FOCUS:
        case FACE_DENY:
            drawNeutralMouth(theme, 42, 8);
            break;
        case FACE_INTERRUPT:
            drawOpenMouth(theme, 30, 18);
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

void redrawEyeRegion(int centerX, const FaceTheme& theme) {
    const int eyeX = centerX + theme.gazeX;
    const int eyeY = FACE_EYE_Y + theme.gazeY;
    clearFaceRegion(
        eyeX - FACE_EYE_RADIUS - EYE_CLEAR_PADDING_X,
        eyeY - FACE_EYE_RADIUS - EYE_CLEAR_PADDING_Y,
        FACE_EYE_RADIUS * 2 + EYE_CLEAR_PADDING_X * 2,
        FACE_EYE_RADIUS * 2 + EYE_CLEAR_PADDING_Y * 2,
        theme);

    if (g_isBlinking) {
        drawClosedEye(centerX, theme);
    } else {
        drawEye(centerX, theme);
    }
}

void redrawEyes(const FaceTheme& theme) {
    redrawEyeRegion(FACE_CX - FACE_EYE_OFFSET_X, theme);
    redrawEyeRegion(FACE_CX + FACE_EYE_OFFSET_X, theme);
}

void redrawMouthRegion(const FaceTheme& theme) {
    clearFaceRegion(
        FACE_CX - MOUTH_CLEAR_W / 2,
        FACE_MOUTH_Y - MOUTH_CLEAR_H / 2,
        MOUTH_CLEAR_W,
        MOUTH_CLEAR_H,
        theme);
    drawMouth(g_currentState, theme);
}

void redrawProcessingDotRegion(const FaceTheme& theme) {
    clearFaceRegion(DOT_CLEAR_X, DOT_CLEAR_Y, DOT_CLEAR_W, DOT_CLEAR_H, theme);
    if (g_currentState == FACE_PROCESSING) {
        drawProcessingDots();
    }
}

int utf8CharLength(const char* text) {
    const uint8_t c = static_cast<uint8_t>(text[0]);
    if (c >= 0xF0) {
        return 4;
    }
    if (c >= 0xE0) {
        return 3;
    }
    if (c >= 0xC0) {
        return 2;
    }
    return 1;
}

const char* activeSubtitleText() {
    if (g_statusSubtitleText[0] != '\0') {
        return g_statusSubtitleText;
    }
    return g_replySubtitleText;
}

void prepareSubtitleFont() {
    g_u8f.setFont(u8g2_font_wqy16_t_gb2312);
    g_u8f.setFontMode(1);
    g_u8f.setForegroundColor(COLOR_SUBTITLE_TEXT);
}

int subtitleVisibleWidth() {
    return SCREEN_W - SUBTITLE_BOX_MARGIN_X * 2 - SUBTITLE_BOX_PADDING_X * 2;
}

void normalizeSubtitleText(char* buffer, const char* text) {
    const char* source = text != nullptr ? text : "";
    size_t writeIndex = 0;
    bool previousWasSpace = true;

    while (*source != '\0' && writeIndex < SUBTITLE_BUFFER_SIZE - 1) {
        const bool isWhitespace =
            *source == ' ' || *source == '\t' || *source == '\n' || *source == '\r';
        if (isWhitespace) {
            if (!previousWasSpace) {
                buffer[writeIndex++] = ' ';
                previousWasSpace = true;
            }
            source++;
            continue;
        }

        const int len = utf8CharLength(source);
        if (writeIndex + static_cast<size_t>(len) >= SUBTITLE_BUFFER_SIZE) {
            break;
        }
        memcpy(buffer + writeIndex, source, static_cast<size_t>(len));
        writeIndex += static_cast<size_t>(len);
        source += len;
        previousWasSpace = false;
    }

    if (writeIndex > 0 && buffer[writeIndex - 1] == ' ') {
        writeIndex--;
    }
    buffer[writeIndex] = '\0';
}

void resetSubtitleScrollState(unsigned long now) {
    g_subtitleScrollPhase = SubtitleScrollPhase::Idle;
    g_subtitleScrollPhaseStartedAt = now;
    g_lastSubtitleScrollAt = now;
    g_subtitleScrollOffsetPx = 0;
    g_subtitleScrollDistancePx = 0;

    if (g_tft == nullptr) {
        return;
    }

    const char* subtitle = activeSubtitleText();
    if (subtitle[0] == '\0') {
        return;
    }

    prepareSubtitleFont();
    const int visibleWidth = subtitleVisibleWidth();
    const int subtitleWidth = g_u8f.getUTF8Width(subtitle);
    if (subtitleWidth > visibleWidth) {
        g_subtitleScrollDistancePx = subtitleWidth - visibleWidth;
        g_subtitleScrollPhase = SubtitleScrollPhase::LeadingHold;
    }
}

bool updateSubtitleScroll(unsigned long now) {
    if (g_subtitleScrollDistancePx <= 0) {
        return false;
    }

    switch (g_subtitleScrollPhase) {
        case SubtitleScrollPhase::Idle:
            return false;
        case SubtitleScrollPhase::LeadingHold:
            if (now - g_subtitleScrollPhaseStartedAt < SUBTITLE_SCROLL_START_HOLD_MS) {
                return false;
            }
            g_subtitleScrollPhase = SubtitleScrollPhase::Scrolling;
            g_lastSubtitleScrollAt = now;
            return false;
        case SubtitleScrollPhase::Scrolling: {
            if (now - g_lastSubtitleScrollAt < SUBTITLE_SCROLL_STEP_INTERVAL_MS) {
                return false;
            }

            const unsigned long elapsed = now - g_lastSubtitleScrollAt;
            const int stepCount = static_cast<int>(elapsed / SUBTITLE_SCROLL_STEP_INTERVAL_MS);
            if (stepCount <= 0) {
                return false;
            }

            const int previousOffset = g_subtitleScrollOffsetPx;
            g_lastSubtitleScrollAt +=
                static_cast<unsigned long>(stepCount) * SUBTITLE_SCROLL_STEP_INTERVAL_MS;
            g_subtitleScrollOffsetPx = min(
                g_subtitleScrollOffsetPx + stepCount * SUBTITLE_SCROLL_STEP_PX,
                g_subtitleScrollDistancePx);

            if (g_subtitleScrollOffsetPx >= g_subtitleScrollDistancePx) {
                g_subtitleScrollPhase = SubtitleScrollPhase::TrailingHold;
                g_subtitleScrollPhaseStartedAt = now;
            }
            return g_subtitleScrollOffsetPx != previousOffset;
        }
        case SubtitleScrollPhase::TrailingHold:
            if (now - g_subtitleScrollPhaseStartedAt < SUBTITLE_SCROLL_END_HOLD_MS) {
                return false;
            }
            g_subtitleScrollOffsetPx = 0;
            g_subtitleScrollPhase = SubtitleScrollPhase::LeadingHold;
            g_subtitleScrollPhaseStartedAt = now;
            g_lastSubtitleScrollAt = now;
            return true;
    }

    return false;
}

bool updateSubtitleBuffer(char* buffer, const char* text) {
    char normalized[SUBTITLE_BUFFER_SIZE] = {0};
    normalizeSubtitleText(normalized, text);
    if (strncmp(buffer, normalized, SUBTITLE_BUFFER_SIZE - 1) == 0 &&
        strlen(buffer) == strlen(normalized)) {
        return false;
    }

    snprintf(buffer, SUBTITLE_BUFFER_SIZE, "%s", normalized);
    return true;
}

void drawSubtitle() {
    if (g_tft == nullptr) {
        return;
    }

    const char* subtitle = activeSubtitleText();
    const FaceTheme theme = themeForState(g_currentState);
    constexpr int boxX = SUBTITLE_BOX_MARGIN_X;
    constexpr int boxY = SCREEN_H - SUBTITLE_BOX_H - SUBTITLE_BOX_MARGIN_BOTTOM;
    constexpr int boxW = SCREEN_W - SUBTITLE_BOX_MARGIN_X * 2;
    constexpr int boxH = SUBTITLE_BOX_H;
    constexpr int textStartX = boxX + SUBTITLE_BOX_PADDING_X;
    constexpr int textClipY = boxY + SUBTITLE_CLIP_PADDING_Y;
    constexpr int textClipH = boxH - SUBTITLE_CLIP_PADDING_Y * 2;
    constexpr int textClipW = boxW - SUBTITLE_BOX_PADDING_X * 2;

    if (subtitle[0] == '\0') {
        clearFaceRegion(boxX, boxY, boxW, boxH, theme);
        return;
    }

    g_tft->fillRoundRect(boxX, boxY, boxW, boxH, SUBTITLE_BOX_RADIUS, COLOR_SUBTITLE_BG);

    prepareSubtitleFont();
    const int baselineY =
        boxY + (boxH + g_u8f.getFontAscent() - g_u8f.getFontDescent()) / 2;

    g_tft->setViewport(textStartX, textClipY, textClipW, textClipH, false);
    g_u8f.drawUTF8(textStartX - g_subtitleScrollOffsetPx, baselineY, subtitle);
    g_tft->resetViewport();
}

void drawFullFace() {
    if (g_tft == nullptr) {
        return;
    }

    const FaceTheme theme = themeForState(g_currentState);

    g_tft->fillScreen(theme.background);
    redrawEyes(theme);
    redrawMouthRegion(theme);
    redrawProcessingDotRegion(theme);
    drawSubtitle();
}

void redrawFaceRegions(
    bool redrawEyesFlag,
    bool redrawMouthFlag,
    bool redrawDotsFlag,
    bool redrawSubtitleFlag) {
    if (g_tft == nullptr) {
        return;
    }

    const FaceTheme theme = themeForState(g_currentState);
    if (redrawEyesFlag) {
        redrawEyes(theme);
    }
    if (redrawMouthFlag) {
        redrawMouthRegion(theme);
    }
    if (redrawDotsFlag) {
        redrawProcessingDotRegion(theme);
    }
    if (redrawSubtitleFlag) {
        drawSubtitle();
    }
}

}  // namespace

void faceInit(TFT_eSPI &tft) {
    g_tft = &tft;
    g_tft->init();
    g_tft->setRotation(0);
    g_u8f.begin(tft);
    randomSeed(micros());
    g_currentState = FACE_IDLE;
    const unsigned long now = millis();
    resetAnimationState(g_currentState, now);
    resetSubtitleScrollState(now);
    drawFullFace();
}

void faceSetState(FaceState state) {
    if (state == g_currentState) {
        return;
    }

    g_currentState = state;
    resetAnimationState(g_currentState, millis());
    drawFullFace();
}

FaceState faceGetState() {
    return g_currentState;
}

void faceUpdate() {
    const unsigned long now = millis();
    bool redrawEyesFlag = false;
    bool redrawMouthFlag = false;
    bool redrawDotsFlag = false;
    bool redrawSubtitleFlag = false;

    if (g_isBlinking) {
        if (now - g_blinkStartedAt >= BLINK_DURATION_MS) {
            g_isBlinking = false;
            scheduleNextBlink(now);
            redrawEyesFlag = true;
        }
    } else if (now >= g_nextBlinkAt) {
        g_isBlinking = true;
        g_blinkStartedAt = now;
        redrawEyesFlag = true;
    }

    if (g_currentState == FACE_SPEAKING && now - g_lastMouthToggleAt >= SPEAK_MOUTH_PERIOD_MS) {
        g_lastMouthToggleAt = now;
        g_isMouthOpen = !g_isMouthOpen;
        redrawMouthFlag = true;
    }

    if (g_currentState == FACE_PROCESSING && now - g_lastDotAdvanceAt >= PROCESS_DOT_PERIOD_MS) {
        g_lastDotAdvanceAt = now;
        g_dotPhase = (g_dotPhase % 3) + 1;
        redrawDotsFlag = true;
    }

    if (updateSubtitleScroll(now)) {
        redrawSubtitleFlag = true;
    }

    if (redrawEyesFlag || redrawMouthFlag || redrawDotsFlag || redrawSubtitleFlag) {
        redrawFaceRegions(
            redrawEyesFlag,
            redrawMouthFlag,
            redrawDotsFlag,
            redrawSubtitleFlag);
    }
}

void faceSetText(const char* text) {
    faceSetReplyText(text);
}

void faceSetReplyText(const char* text) {
    const bool visibleSubtitleWillChange = g_statusSubtitleText[0] == '\0';
    if (!updateSubtitleBuffer(g_replySubtitleText, text)) {
        return;
    }
    if (!visibleSubtitleWillChange) {
        return;
    }
    resetSubtitleScrollState(millis());
    drawSubtitle();
}

void faceSetStatusText(const char* text) {
    if (!updateSubtitleBuffer(g_statusSubtitleText, text)) {
        return;
    }
    resetSubtitleScrollState(millis());
    drawSubtitle();
}

void faceClearStatusText() {
    if (!updateSubtitleBuffer(g_statusSubtitleText, "")) {
        return;
    }
    resetSubtitleScrollState(millis());
    drawSubtitle();
}

void faceSetStatusBar(const char* time, bool wifiOk, bool wsOk) {
    // Demo face renderer currently has no real status-bar layer.
    (void)time;
    (void)wifiOk;
    (void)wsOk;
}

void faceSetBattery(int percent) {
    // Demo hardware currently has no battery telemetry wiring.
    (void)percent;
}

void faceSetWeather(const char* weather) {
    // Demo face renderer currently has no weather/status-bar overlay.
    (void)weather;
}
