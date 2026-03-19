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

// ===== 眼睛参数 =====
#define EYE_SPACING     50      // 两眼间距（中心到中心）
#define EYE_Y_OFFSET    -20     // 眼睛相对脸中心的 Y 偏移（负=上方）
#define EYE_RADIUS_NORMAL   16  // 正常眼睛半径
#define EYE_RADIUS_BIG      22  // 大眼半径（LISTENING 大眼侧）
#define EYE_RADIUS_SMALL    12  // 小眼半径（LISTENING 小眼侧）
#define EYE_RADIUS_ACTIVE   19  // ACTIVE 状态眼睛半径

// ===== 嘴巴参数 =====
#define MOUTH_Y_OFFSET  35      // 嘴巴相对脸中心的 Y 偏移（正=下方）
#define MOUTH_WIDTH     40      // 嘴巴宽度
#define MOUTH_HEIGHT    12      // 嘴巴高度/弧度

// ===== 颜色 =====
#define COLOR_BG        TFT_BLACK
#define COLOR_EYE       TFT_WHITE
#define COLOR_MOUTH     TFT_WHITE
#define COLOR_STATUS_BG TFT_BLACK
#define COLOR_STATUS_TXT 0x07FF   // TFT_CYAN
#define COLOR_TEXT_BG   TFT_BLACK
#define COLOR_TEXT_FG   TFT_GREEN
#define COLOR_DIVIDER   0x4208    // TFT_DARKGREY
#define COLOR_DOT       TFT_YELLOW
#define COLOR_NOTE      TFT_CYAN
#define COLOR_WAVE      0x4208    // 声波线颜色（暗灰）

// ===== 动画参数（Phase 2 用，Phase 1 先定义） =====
#define ANIM_FPS        15
#define ANIM_FRAME_MS   (1000 / ANIM_FPS)

#define BLINK_INTERVAL_MIN  3000  // 眨眼最小间隔 ms
#define BLINK_INTERVAL_MAX  5000  // 眨眼最大间隔 ms
#define BLINK_DURATION      200   // 眨眼持续 ms

#define ACTIVE_EYE_MOVE_RANGE  5  // ACTIVE 眼球移动像素
#define ACTIVE_EYE_MOVE_PERIOD 2000 // 眼球移动周期 ms

#define LISTEN_TILT_ANGLE   5     // 歪头角度（度）
#define LISTEN_TILT_PERIOD  2000  // 歪头周期 ms

#define PROCESS_DOT_PERIOD  500   // 加载点切换间隔 ms

#define SPEAK_MOUTH_PERIOD  400   // 说话嘴巴开合周期 ms

#endif // FACE_CONFIG_H
