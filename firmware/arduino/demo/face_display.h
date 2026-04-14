#ifndef FACE_DISPLAY_H
#define FACE_DISPLAY_H

#include <TFT_eSPI.h>

#include "face_config.h"

// 表情状态
enum FaceState {
    FACE_IDLE,          // 空闲待机
    FACE_ACTIVE,        // 最近聊过天（30秒内）
    FACE_FOCUS,         // 聚焦 / 决策提示
    FACE_DENY,          // 拒绝 / 否定提示
    FACE_INTERRUPT,     // 打断提示
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

// 兼容接口：设置 AI 回复字幕
void faceSetText(const char* text);

// 设置 AI 回复字幕
void faceSetReplyText(const char* text);

// 设置状态字幕（优先级高于 AI 回复）
void faceSetStatusText(const char* text);

// 清空状态字幕，回退显示上一句 AI 回复
void faceClearStatusText();

// 更新状态栏
void faceSetStatusBar(const char* time, bool wifiOk, bool wsOk);

// 设置电池电量 (0~100, -1=未知)
void faceSetBattery(int percent);

// 设置天气显示（如 "23°C"）
void faceSetWeather(const char* weather);

#endif // FACE_DISPLAY_H
