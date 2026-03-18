"""
ASR 语音识别服务
使用 SenseVoice-Small (FunASR) 将 PCM/WAV 音频转换为文字

音频格式约定:
- ESP32 → 服务端: PCM 16kHz 16bit 单声道 (raw bytes, little-endian)
- SenseVoice 输入: numpy float32 数组 (归一化到 [-1, 1])
"""
from __future__ import annotations

import asyncio
import io
import re
import wave
from typing import Optional

import numpy as np
from loguru import logger

# 情感标签映射
_EMOTION_PATTERN = re.compile(r"<\|(HAPPY|SAD|ANGRY|NEUTRAL)\|>", re.IGNORECASE)


class ASRService:
    """基于 SenseVoice-Small (FunASR) 的语音识别服务。"""

    def __init__(
        self,
        model: str = "FunAudioLLM/SenseVoiceSmall",
        language: str = "auto",
        device: str = "cpu",
        use_vad: bool = True,
        use_itn: bool = True,
    ):
        self.model_name = model
        self.language = language
        self.device = device
        self.use_vad = use_vad
        self.use_itn = use_itn
        self._model = None
        self.last_emotion: Optional[str] = None

    def _ensure_model(self):
        """懒加载 SenseVoice 模型（首次调用时加载）。"""
        if self._model is not None:
            return
        from funasr import AutoModel

        logger.info("正在加载 SenseVoice 模型: {} (device={})", self.model_name, self.device)

        model_kwargs = {
            "model": self.model_name,
            "device": self.device,
            "hub": "hf",
        }
        if self.use_vad:
            model_kwargs["vad_model"] = "fsmn-vad"
            model_kwargs["vad_kwargs"] = {"max_single_segment_time": 30000}

        self._model = AutoModel(**model_kwargs)
        logger.info("SenseVoice 模型加载完成")

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

    @staticmethod
    def _pcm_to_float32(pcm_data: bytes) -> np.ndarray:
        """将 PCM 16bit 原始字节转为归一化 float32 numpy 数组。"""
        audio_int16 = np.frombuffer(pcm_data, dtype=np.int16)
        return audio_int16.astype(np.float32) / 32768.0

    def _parse_emotion(self, raw_text: str) -> Optional[str]:
        """从 SenseVoice 原始输出中解析情感标签。"""
        match = _EMOTION_PATTERN.search(raw_text)
        if match:
            return match.group(1).lower()
        return None

    def _transcribe_sync(self, audio_bytes: bytes) -> str:
        """同步识别（在线程池中运行）。

        Args:
            audio_bytes: WAV 或 PCM 格式的音频数据。
                         如果没有 WAV 头（前4字节不是 RIFF），会自动当作 PCM 处理。
        """
        self._ensure_model()
        from funasr.utils.postprocess_utils import rich_transcription_postprocess

        # 提取 PCM 数据并转为 float32
        if audio_bytes[:4] == b"RIFF":
            # WAV 格式：读取 PCM 数据
            with wave.open(io.BytesIO(audio_bytes), "rb") as wf:
                pcm_data = wf.readframes(wf.getnframes())
            audio_array = self._pcm_to_float32(pcm_data)
        else:
            audio_array = self._pcm_to_float32(audio_bytes)

        res = self._model.generate(
            input=audio_array,
            cache={},
            language=self.language,
            use_itn=self.use_itn,
            batch_size_s=60,
            merge_vad=True,
        )

        if not res or not res[0].get("text"):
            logger.debug("ASR 识别结果为空")
            self.last_emotion = None
            return ""

        raw_text = res[0]["text"]

        # 解析情感标签
        self.last_emotion = self._parse_emotion(raw_text)

        # 清洗文本（去除特殊标记）
        result = rich_transcription_postprocess(raw_text)

        logger.debug("ASR 识别结果: '{}' (情感={}, 语言={})", result, self.last_emotion, self.language)
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
