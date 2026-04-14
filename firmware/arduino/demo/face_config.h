#ifndef FACE_CONFIG_H
#define FACE_CONFIG_H

// ===== 屏幕尺寸 (1.54" ST7789 240×240) =====
#define SCREEN_W        240
#define SCREEN_H        240

// ===== 三区布局 =====
#define STATUS_BAR_H    24      // 状态栏高度
#define FACE_AREA_Y     24      // 表情区起始 Y
#define FACE_AREA_H     168     // 表情区高度
#define TEXT_AREA_Y     192     // 文字区起始 Y
#define TEXT_AREA_H     48      // 文字区高度

// ===== 表情区中心坐标 =====
#define FACE_CX         (SCREEN_W / 2)              // 120
#define FACE_CY         (FACE_AREA_Y + FACE_AREA_H / 2)  // 108

// ===== Avataaars 脸区资源参数 =====
#define FACE_ASSET_W        168
#define FACE_ASSET_H        168

// 轻量覆盖动画落点（以整屏坐标表示）
#define FACE_LEFT_EYE_X     80
#define FACE_RIGHT_EYE_X    160
#define FACE_EYE_Y          86
#define FACE_EYE_HALF_W     18
#define FACE_EYE_CLEAR_W    32
#define FACE_EYE_CLEAR_H    16
#define FACE_MOUTH_X        120
#define FACE_MOUTH_Y        137
#define FACE_MOUTH_W        48
#define FACE_MOUTH_H        30
#define FACE_MOUTH_CLEAR_W  60
#define FACE_MOUTH_CLEAR_H  38
#define FACE_DOT_Y          60

// ===== 颜色 =====
#define COLOR_BG        TFT_BLACK
#define COLOR_STATUS_BG TFT_BLACK
#define COLOR_STATUS_TXT 0x07FF   // TFT_CYAN
#define COLOR_TEXT_BG   TFT_BLACK
#define COLOR_TEXT_FG   TFT_GREEN
#define COLOR_DIVIDER   0x4208    // TFT_DARKGREY
#define COLOR_FACE_FEATURE 0x4229
#define COLOR_FACE_TONGUE  0xFA6D
#define COLOR_FACE_HIGHLIGHT 0xFFBE
#define COLOR_DOT       0xFA6D

// ===== 动画参数（Phase 2 用，Phase 1 先定义） =====
#define ANIM_FPS        15
#define ANIM_FRAME_MS   (1000 / ANIM_FPS)

#define BLINK_INTERVAL_MIN  3000  // 眨眼最小间隔 ms
#define BLINK_INTERVAL_MAX  5000  // 眨眼最大间隔 ms
#define BLINK_DURATION      200   // 眨眼持续 ms

#define PROCESS_DOT_PERIOD  500   // 加载点切换间隔 ms

#define SPEAK_MOUTH_PERIOD  400   // 说话嘴巴开合周期 ms

#endif // FACE_CONFIG_H
