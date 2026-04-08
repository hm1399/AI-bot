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


class TTSService:
    """基于 edge-tts 的语音合成服务。"""

    def __init__(self, voice: str = "zh-CN-XiaoxiaoNeural"):
        self.voice = voice

    @staticmethod
    def _contains_cjk(text: str) -> bool:
        return bool(_CJK_PATTERN.search(text))

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

        if self.voice.startswith("en-") and self._contains_cjk(text):
            logger.warning(
                "TTS 当前使用英文 voice={}, 但文本仍包含 CJK 字符: '{}'",
                self.voice,
                text[:60],
            )

        logger.info("TTS 开始合成: '{}' (voice={})", text[:30] + "..." if len(text) > 30 else text, self.voice)

        # edge-tts 生成 MP3
        communicate = edge_tts.Communicate(text, self.voice)
        mp3_buffer = io.BytesIO()

        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                mp3_buffer.write(chunk["data"])

        mp3_data = mp3_buffer.getvalue()
        if not mp3_data:
            logger.error("TTS 合成失败: edge-tts 返回空数据")
            return b""

        # MP3 → PCM (在线程池中运行，避免阻塞)
        pcm_data = await asyncio.to_thread(_mp3_to_pcm_16k_mono, mp3_data)

        duration_s = len(pcm_data) / (16000 * 2)  # 16kHz, 16bit = 2 bytes/sample
        logger.info("TTS 合成完成: {} bytes PCM ({:.1f}s)", len(pcm_data), duration_s)
        return pcm_data

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
