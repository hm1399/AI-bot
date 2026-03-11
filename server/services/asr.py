"""
ASR 语音识别服务
使用 faster-whisper 将 PCM/WAV 音频转换为文字

音频格式约定:
- ESP32 → 服务端: PCM 16kHz 16bit 单声道 (raw bytes, little-endian)
- Whisper 输入: WAV 16kHz 16bit 单声道
"""
from __future__ import annotations

import asyncio
import io
import wave
from typing import Optional

from loguru import logger


class ASRService:
    """基于 faster-whisper 的语音识别服务。"""

    def __init__(self, model: str = "base", language: str = "zh", device: str = "cpu"):
        self.model_name = model
        self.language = language if language else None
        self.device = device
        self._model = None

    def _ensure_model(self):
        """懒加载 Whisper 模型（首次调用时加载）。"""
        if self._model is not None:
            return
        from faster_whisper import WhisperModel
        logger.info("正在加载 Whisper 模型: {} (device={})", self.model_name, self.device)
        self._model = WhisperModel(self.model_name, device=self.device, compute_type="int8")
        logger.info("Whisper 模型加载完成")

    @staticmethod
    def pcm_to_wav(pcm_data: bytes, sample_rate: int = 16000, channels: int = 1, sample_width: int = 2) -> bytes:
        """将 PCM 原始数据转为 WAV 格式。

        Args:
            pcm_data: PCM 原始字节 (16bit signed little-endian)
            sample_rate: 采样率，默认 16000Hz
            channels: 声道数，默认 1（单声道）
            sample_width: 采样位宽(字节)，默认 2（16bit）

        Returns:
            WAV 格式字节
        """
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(channels)
            wf.setsampwidth(sample_width)
            wf.setframerate(sample_rate)
            wf.writeframes(pcm_data)
        return buf.getvalue()

    def _transcribe_sync(self, audio_bytes: bytes) -> str:
        """同步识别（在线程池中运行）。

        Args:
            audio_bytes: WAV 或 PCM 格式的音频数据。
                         如果没有 WAV 头（前4字节不是 RIFF），会自动当作 PCM 处理。
        """
        self._ensure_model()

        # 判断是否有 WAV 头
        if audio_bytes[:4] != b"RIFF":
            audio_bytes = self.pcm_to_wav(audio_bytes)

        audio_stream = io.BytesIO(audio_bytes)
        segments, info = self._model.transcribe(
            audio_stream,
            language=self.language,
            beam_size=5,
            vad_filter=True,
        )

        text_parts = []
        for segment in segments:
            text_parts.append(segment.text.strip())

        result = "".join(text_parts)
        logger.debug("ASR 识别结果: '{}' (语言={}, 概率={:.2f})", result, info.language, info.language_probability)
        return result

    async def transcribe(self, audio_bytes: bytes) -> str:
        """异步识别音频，不阻塞主事件循环。

        Args:
            audio_bytes: PCM 16kHz 16bit 单声道 原始字节，或 WAV 格式字节

        Returns:
            识别出的文字
        """
        if not audio_bytes:
            logger.warning("ASR 收到空音频数据")
            return ""

        logger.info("ASR 开始识别, 音频大小: {} bytes", len(audio_bytes))
        result = await asyncio.to_thread(self._transcribe_sync, audio_bytes)
        logger.info("ASR 识别完成: '{}'", result[:50] + "..." if len(result) > 50 else result)
        return result
