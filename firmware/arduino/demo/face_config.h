#ifndef FACE_CONFIG_H
#define FACE_CONFIG_H

// ===== 屏幕尺寸 (1.54" ST7789 240×240) =====
#define SCREEN_W        240
#define SCREEN_H        240

// ===== 全屏静态脸布局 =====
#define STATUS_BAR_H    0
#define FACE_AREA_Y     0
#define FACE_AREA_H     SCREEN_H
#define TEXT_AREA_Y     SCREEN_H
#define TEXT_AREA_H     0

// ===== 表情区中心坐标 =====
#define FACE_CX         (SCREEN_W / 2)
#define FACE_CY         (FACE_AREA_Y + FACE_AREA_H / 2)

// ===== 兼容保留：脸区资源尺寸 =====
#define FACE_ASSET_W        SCREEN_W
#define FACE_ASSET_H        SCREEN_H

// ===== 颜色 =====
#define COLOR_BG        0x0000

// ===== 动画参数 =====
#define BLINK_INTERVAL_MIN_MS   2500
#define BLINK_INTERVAL_MAX_MS   4400
#define BLINK_DURATION_MS       220
#define PROCESS_DOT_PERIOD_MS   380
#define SPEAK_MOUTH_PERIOD_MS   220

#endif // FACE_CONFIG_H
