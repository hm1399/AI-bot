from __future__ import annotations

import asyncio
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from services.desktop_voice_service import (
    DESKTOP_VOICE_CHANNEL,
    DESKTOP_VOICE_CHAT_ID,
    DesktopVoiceService,
    MIN_AUDIO_BYTES,
)


class DummyDeviceChannel:
    def __init__(self) -> None:
        self.connected = True
        self.responding_count = 0
        self.delivered_texts: list[str] = []
        self.transcribing_count = 0
        self.failures: list[str] = []

    async def notify_external_voice_responding(self) -> None:
        self.responding_count += 1

    async def notify_external_voice_transcribing(self) -> None:
        self.transcribing_count += 1

    async def deliver_external_text_response(self, text: str) -> None:
        self.delivered_texts.append(text)

    async def fail_external_voice_feedback(self, message: str) -> None:
        self.failures.append(message)


class SlowASR:
    def __init__(self) -> None:
        self.last_emotion = None
        self.started = asyncio.Event()
        self.release = asyncio.Event()
        self.finished = asyncio.Event()
        self.cancelled = False

    async def transcribe(self, audio_bytes: bytes) -> str:
        self.started.set()
        try:
            await self.release.wait()
            return "late transcript"
        except asyncio.CancelledError:
            self.cancelled = True
            raise
        finally:
            self.finished.set()


class DesktopVoiceServiceReplyLanguageTests(unittest.TestCase):
    def test_device_press_defaults_to_english(self) -> None:
        reply_language = DesktopVoiceService._preferred_reply_language_from_transcript(
            "打开微信。",
            interaction_surface="device_press",
        )

        self.assertEqual(reply_language, "English")

    def test_explicit_chinese_request_overrides_device_press_default(self) -> None:
        reply_language = DesktopVoiceService._preferred_reply_language_from_transcript(
            "中文回答我。",
            interaction_surface="device_press",
        )

        self.assertEqual(reply_language, "Chinese")

    def test_non_device_capture_still_follows_transcript_language(self) -> None:
        reply_language = DesktopVoiceService._preferred_reply_language_from_transcript(
            "打开微信。",
            interaction_surface="desktop_manual",
        )

        self.assertEqual(reply_language, "Chinese")


class DesktopVoiceServiceBargeInTests(unittest.IsolatedAsyncioTestCase):
    async def test_cancel_device_push_to_talk_does_not_cancel_asr_in_flight(self) -> None:
        service = DesktopVoiceService(
            bus=MessageBus(),
            asr=None,
            device_channel=DummyDeviceChannel(),
            enable_local_microphone=False,
        )
        task = asyncio.create_task(asyncio.sleep(30))
        service._asr_task = task
        service._state["status"] = "transcribing"

        await service.cancel_device_push_to_talk(reason="barge_in")

        self.assertFalse(task.cancelled())
        self.assertIs(service._asr_task, task)
        self.assertEqual(service.get_snapshot()["status"], "transcribing")
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task

    async def test_asr_timeout_releases_voice_pipeline_without_cancelling_transcribe(self) -> None:
        asr = SlowASR()
        device = DummyDeviceChannel()
        service = DesktopVoiceService(
            bus=MessageBus(),
            asr=asr,
            device_channel=device,
            enable_local_microphone=False,
            asr_timeout_s=0.05,
        )

        await service._run_asr_and_publish(
            {
                "interaction_surface": "device_press",
                "capture_source": "desktop_mic",
                "app_session_id": "app:main",
            },
            b"\x00" * MIN_AUDIO_BYTES,
        )

        self.assertTrue(asr.started.is_set())
        self.assertFalse(asr.cancelled)
        self.assertIsNone(service._asr_task)
        self.assertEqual(service.get_snapshot()["status"], "idle")
        self.assertEqual(service.get_snapshot()["last_error"], "asr_timeout")
        self.assertEqual(device.failures, ["语音识别超时，请再试一次"])

        asr.release.set()
        await asyncio.wait_for(asr.finished.wait(), timeout=0.2)
        await asyncio.sleep(0)
        self.assertFalse(asr.cancelled)

    async def test_old_response_completion_does_not_clear_new_capture_state(self) -> None:
        device = DummyDeviceChannel()
        service = DesktopVoiceService(
            bus=MessageBus(),
            asr=None,
            device_channel=device,
            enable_local_microphone=False,
        )
        service._pending_device_capture = True
        service._state["status"] = "listening"

        await service.send_outbound(
            OutboundMessage(
                channel=DESKTOP_VOICE_CHANNEL,
                chat_id=DESKTOP_VOICE_CHAT_ID,
                content="old response",
                metadata={"interaction_surface": "device_press"},
            )
        )

        snapshot = service.get_snapshot()
        self.assertEqual(snapshot["status"], "listening")
        self.assertTrue(snapshot["capture_active"])
        self.assertEqual(snapshot["last_response"], "old response")
        self.assertEqual(device.delivered_texts, ["old response"])


if __name__ == "__main__":
    unittest.main()
