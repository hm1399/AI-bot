#ifndef FACE_DISPLAY_H
#define FACE_DISPLAY_H

#include <TFT_eSPI.h>

#include "face_config.h"

// 表情状态
enum FaceState {
    FACE_IDLE,          // 空闲待机
    FACE_ACTIVE,        // 最近聊过天（30秒内）
    FACE_LISTENING,     // 聆听中
    FACE_PROCESSING,    // 思考中
    FACE_SPEAKING       // 回复中
};

// 初始化表情系统
void faceInit(TFT_eSPI &tft);

// 设置表情状态（会立即重绘）
void faceSetState(FaceState state);

// 获取当前状态
FaceState faceGetState();

// 动画帧更新（loop 中调用）
void faceUpdate();

// 设置底部文字区内容
void faceSetText(const char* text);

// 更新状态栏
void faceSetStatusBar(const char* time, bool wifiOk, bool wsOk);

// 设置电池电量 (0~100, -1=未知)
void faceSetBattery(int percent);

// 设置天气显示（如 "23°C"）
void faceSetWeather(const char* weather);

#endif // FACE_DISPLAY_H
