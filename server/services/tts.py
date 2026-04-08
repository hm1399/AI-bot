"""
TTS 语音合成服务
使用 edge-tts 将文字转换为语音，输出 PCM 16kHz 16bit 单声道

音频格式约定:
- 服务端 → ESP32: PCM 16kHz 16bit 单声道 (raw bytes, little-endian)
- Edge-TTS 输出: MP3 → 通过 miniaudio 解码转换为 PCM
"""
from __future__ import annotations

import asyncio
import io
import re
from typing import AsyncGenerator

from loguru import logger


_CJK_PATTERN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")


def _mp3_to_pcm_16k_mono(mp3_data: bytes) -> bytes:
    """将 MP3 字节转为 PCM 16kHz 16bit 单声道。

    使用 miniaudio 解码，不依赖 ffmpeg。
    """
    import miniaudio

    # 解码 MP3 → 原始 PCM samples
    decoded = miniaudio.decode(mp3_data, output_format=miniaudio.SampleFormat.SIGNED16,
                                nchannels=1, sample_rate=16000)
    return bytes(decoded.samples)


def _scale_pcm_16bit_le(pcm_data: bytes, volume_scale: float) -> bytes:
    """按比例缩放 16-bit little-endian PCM 振幅。"""
    if not pcm_data or volume_scale >= 0.999:
        return pcm_data

    import numpy as np

    samples = np.frombuffer(pcm_data, dtype=np.int16).astype(np.float32)
    samples *= volume_scale
    samples = np.clip(samples, -32768, 32767).astype(np.int16)
    return samples.tobytes()


class TTSService:
    """基于 edge-tts 的语音合成服务。"""

    def __init__(self, voice: str = "zh-CN-XiaoxiaoNeural", volume_scale: float = 0.55):
        self.voice = voice
        self.english_voice = voice if voice.startswith("en-") else "en-US-AriaNeural"
        self.chinese_voice = voice if voice.startswith("zh-") else "zh-CN-XiaoxiaoNeural"
        self.volume_scale = max(0.0, min(float(volume_scale), 1.0))

    @staticmethod
    def _contains_cjk(text: str) -> bool:
        return bool(_CJK_PATTERN.search(text))

    def _candidate_voices(self, text: str) -> list[str]:
        """按文本内容返回候选 voice，优先保证中英文都可播报。"""
        candidates: list[str] = []
        if self._contains_cjk(text):
            candidates.extend([self.chinese_voice, self.english_voice, self.voice])
        else:
            candidates.extend([self.english_voice, self.chinese_voice, self.voice])

        deduped: list[str] = []
        for item in candidates:
            if item and item not in deduped:
                deduped.append(item)
        return deduped

    async def synthesize(self, text: str) -> bytes:
        """将文字合成为 PCM 音频。

        Args:
            text: 要合成的文字

        Returns:
            PCM 16kHz 16bit 单声道字节
        """
        import edge_tts

        if not text or not text.strip():
            logger.warning("TTS 收到空文本")
            return b""

        candidate_voices = self._candidate_voices(text)
        if len(candidate_voices) > 1:
            logger.info(
                "TTS 自动选音色: text='{}', candidates={}",
                text[:30] + "..." if len(text) > 30 else text,
                candidate_voices,
            )

        last_error: Exception | None = None
        for selected_voice in candidate_voices:
            try:
                logger.info(
                    "TTS 开始合成: '{}' (voice={})",
                    text[:30] + "..." if len(text) > 30 else text,
                    selected_voice,
                )

                communicate = edge_tts.Communicate(text, selected_voice)
                mp3_buffer = io.BytesIO()

                async for chunk in communicate.stream():
                    if chunk["type"] == "audio":
                        mp3_buffer.write(chunk["data"])

                mp3_data = mp3_buffer.getvalue()
                if not mp3_data:
                    raise edge_tts.exceptions.NoAudioReceived(
                        "edge-tts returned empty audio data",
                    )

                pcm_data = await asyncio.to_thread(_mp3_to_pcm_16k_mono, mp3_data)
                if self.volume_scale < 0.999:
                    pcm_data = await asyncio.to_thread(
                        _scale_pcm_16bit_le,
                        pcm_data,
                        self.volume_scale,
                    )
                duration_s = len(pcm_data) / (16000 * 2)
                logger.info(
                    "TTS 合成完成: {} bytes PCM ({:.1f}s, voice={}, volume_scale={:.2f})",
                    len(pcm_data),
                    duration_s,
                    selected_voice,
                    self.volume_scale,
                )
                return pcm_data
            except edge_tts.exceptions.NoAudioReceived as exc:
                last_error = exc
                logger.warning(
                    "TTS voice={} 未返回音频，尝试下一个音色",
                    selected_voice,
                )
            except Exception as exc:
                last_error = exc
                logger.warning(
                    "TTS voice={} 合成失败: {}，尝试下一个音色",
                    selected_voice,
                    exc,
                )

        if last_error:
            raise last_error
        return b""

    async def synthesize_stream(self, text: str, chunk_size: int = 4096) -> AsyncGenerator[bytes, None]:
        """流式合成：先完整合成，再分块发送 PCM 数据。

        边合成边发的真正流式需要实时解码 MP3 片段，复杂度较高。
        MVP 阶段先用"合成完再分块发"的方案，延迟可接受。

        Args:
            text: 要合成的文字
            chunk_size: 每个 PCM 块的大小（字节），默认 4096

        Yields:
            PCM 16kHz 16bit 单声道字节块
        """
        pcm_data = await self.synthesize(text)
        if not pcm_data:
            return

        # 分块发送
        offset = 0
        while offset < len(pcm_data):
            yield pcm_data[offset:offset + chunk_size]
            offset += chunk_size
