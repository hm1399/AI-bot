from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
from typing import Any, Callable

from loguru import logger

from services.app_api.resource_service import AppResourceService


_REPEAT_DAILY = "daily"
_REPEAT_ONCE = "once"
_REPEAT_WEEKDAYS = "weekdays"
_REPEAT_WEEKENDS = "weekends"
_SUPPORTED_REPEATS = {
    _REPEAT_DAILY,
    _REPEAT_ONCE,
    _REPEAT_WEEKDAYS,
    _REPEAT_WEEKENDS,
}
_STATUS_COMPLETED = "completed"
_STATUS_SCHEDULED = "scheduled"
_STATUS_SNOOZED = "snoozed"
_STATUS_TRIGGERED = "triggered"


class ReminderScheduler:
    """Turns persisted reminder items into runtime notification events."""

    def __init__(
        self,
        resources: AppResourceService,
        *,
        event_observer: Any | None = None,
        poll_interval_s: float = 15.0,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self.resources = resources
        self.event_observer = event_observer
        self.poll_interval_s = poll_interval_s
        self.now_provider = now_provider or (lambda: datetime.now().astimezone())
        self._task: asyncio.Task | None = None
        self._lock = asyncio.Lock()

    def set_event_observer(self, observer: Any) -> None:
        self.event_observer = observer

    def is_running(self) -> bool:
        return bool(self._task and not self._task.done())

    async def start(self) -> None:
        if self.is_running():
            return
        await self.sync_all()
        self._task = asyncio.create_task(self._run_loop())
        logger.info("ReminderScheduler started")

    async def stop(self) -> None:
        if not self._task:
            return
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass
        self._task = None

    async def sync_all(self) -> None:
        async with self._lock:
            now = self.now_provider()
            items = self.resources.reminder_store.list_items()
            for item in items:
                await self._sync_reminder_unlocked(item, now=now)

    async def sync_reminder(self, reminder_id: str) -> dict[str, Any] | None:
        async with self._lock:
            item = self.resources.reminder_store.get(reminder_id)
            if item is None:
                return None
            return await self._sync_reminder_unlocked(item, now=self.now_provider())

    async def snooze_reminder(
        self,
        reminder_id: str,
        *,
        snoozed_until: str | None = None,
        delay_minutes: int = 10,
    ) -> dict[str, Any] | None:
        async with self._lock:
            item = self.resources.reminder_store.get(reminder_id)
            if item is None:
                return None
            now = self.now_provider()
            target = self._parse_iso_datetime(snoozed_until)
            if target is None:
                target = now + timedelta(minutes=max(delay_minutes, 1))
            updated = self.resources.reminder_store.update(
                reminder_id,
                {
                    "enabled": True,
                    "completed_at": None,
                    "snoozed_until": self._format_dt(target),
                    "status": _STATUS_SNOOZED,
                },
            )
            if updated is None:
                return None
            return await self._sync_reminder_unlocked(updated, now=now)

    async def complete_reminder(self, reminder_id: str) -> dict[str, Any] | None:
        async with self._lock:
            item = self.resources.reminder_store.get(reminder_id)
            if item is None:
                return None
            return self.resources.reminder_store.update(
                reminder_id,
                {
                    "enabled": False,
                    "completed_at": self._format_dt(self.now_provider()),
                    "snoozed_until": None,
                    "next_trigger_at": None,
                    "last_error": None,
                    "status": _STATUS_COMPLETED,
                },
            )

    async def _run_loop(self) -> None:
        while True:
            try:
                await asyncio.sleep(self.poll_interval_s)
                await self._process_due_reminders()
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("ReminderScheduler loop failed")

    async def _process_due_reminders(self) -> None:
        async with self._lock:
            now = self.now_provider()
            items = self.resources.reminder_store.list_items()
            for item in items:
                updated = await self._sync_reminder_unlocked(item, now=now)
                if not updated.get("enabled", False):
                    continue
                next_trigger_at = self._parse_iso_datetime(updated.get("next_trigger_at"))
                if next_trigger_at is None or next_trigger_at > now:
                    continue
                await self._deliver_due_reminder_unlocked(updated, now=now)

    async def _sync_reminder_unlocked(
        self,
        reminder: dict[str, Any],
        *,
        now: datetime,
    ) -> dict[str, Any]:
        patch = self._build_schedule_patch(reminder, now=now)
        if not patch:
            return reminder
        updated = self.resources.reminder_store.update(reminder["reminder_id"], patch)
        return updated or reminder

    async def _deliver_due_reminder_unlocked(
        self,
        reminder: dict[str, Any],
        *,
        now: datetime,
    ) -> None:
        reminder_id = reminder["reminder_id"]
        title = str(reminder.get("title") or "").strip() or "Reminder"
        message = str(reminder.get("message") or "").strip() or title
        scheduled_for = reminder.get("next_trigger_at")

        notification = self.resources.create_notification(
            {
                "type": "reminder_due",
                "priority": "high",
                "title": title,
                "message": message,
                "metadata": {
                    "reminder_id": reminder_id,
                    "scheduled_for": scheduled_for,
                    "repeat": reminder.get("repeat"),
                },
            }
        )

        patch = {
            "last_triggered_at": self._format_dt(now),
            "last_error": None,
            "snoozed_until": None,
            "completed_at": None,
        }
        next_dt = self._compute_next_trigger(reminder, now=now, after_trigger=True)
        if next_dt is None:
            patch["enabled"] = False
            patch["next_trigger_at"] = None
            patch["status"] = _STATUS_TRIGGERED
        else:
            patch["next_trigger_at"] = self._format_dt(next_dt)
            patch["status"] = _STATUS_SCHEDULED

        updated = self.resources.reminder_store.update(reminder_id, patch) or reminder
        await self._notify_event_observer(
            "on_reminder_triggered",
            reminder=updated,
            notification=notification,
        )

    def _build_schedule_patch(self, reminder: dict[str, Any], *, now: datetime) -> dict[str, Any]:
        patch: dict[str, Any] = {}
        if reminder.get("completed_at") is not None:
            if reminder.get("enabled", True):
                patch["enabled"] = False
            if reminder.get("next_trigger_at") is not None:
                patch["next_trigger_at"] = None
            if reminder.get("snoozed_until") is not None:
                patch["snoozed_until"] = None
            if reminder.get("last_error") is not None:
                patch["last_error"] = None
            if reminder.get("status") != _STATUS_COMPLETED:
                patch["status"] = _STATUS_COMPLETED
            return patch

        enabled = bool(reminder.get("enabled", True))
        if not enabled:
            if reminder.get("next_trigger_at") is not None:
                patch["next_trigger_at"] = None
            if reminder.get("last_error") is not None:
                patch["last_error"] = None
            return patch

        snoozed_until = self._parse_iso_datetime(reminder.get("snoozed_until"))
        if snoozed_until is not None:
            next_trigger_at = self._format_dt(snoozed_until)
            if reminder.get("next_trigger_at") != next_trigger_at:
                patch["next_trigger_at"] = next_trigger_at
            if reminder.get("status") != _STATUS_SNOOZED:
                patch["status"] = _STATUS_SNOOZED
            if reminder.get("last_error") is not None:
                patch["last_error"] = None
            return patch

        try:
            next_dt = self._compute_next_trigger(reminder, now=now)
        except ValueError as exc:
            logger.warning("Reminder {} schedule invalid: {}", reminder.get("reminder_id"), exc)
            patch["last_error"] = str(exc)
            patch["next_trigger_at"] = None
            return patch

        next_trigger_at = self._format_dt(next_dt) if next_dt else None
        if reminder.get("next_trigger_at") != next_trigger_at:
            patch["next_trigger_at"] = next_trigger_at
        if reminder.get("status") != _STATUS_SCHEDULED:
            patch["status"] = _STATUS_SCHEDULED
        if reminder.get("last_error") is not None:
            patch["last_error"] = None
        return patch

    def _compute_next_trigger(
        self,
        reminder: dict[str, Any],
        *,
        now: datetime,
        after_trigger: bool = False,
    ) -> datetime | None:
        repeat = str(reminder.get("repeat") or _REPEAT_DAILY).strip().lower()
        if repeat not in _SUPPORTED_REPEATS:
            repeat = _REPEAT_DAILY

        raw_time = str(reminder.get("time") or "").strip()
        if not raw_time:
            raise ValueError("time is required")

        if "T" in raw_time:
            exact = self._parse_iso_datetime(raw_time)
            if exact is None:
                raise ValueError("time must be a valid ISO datetime or HH:MM")
            if repeat == _REPEAT_ONCE:
                if exact <= now and not after_trigger:
                    return exact
                return None if after_trigger else exact
            return self._compute_repeating_from_time(exact.timetz(), repeat, now, after_trigger=after_trigger)

        hour, minute, second = self._parse_clock_time(raw_time)
        candidate = now.replace(hour=hour, minute=minute, second=second, microsecond=0)
        if candidate < now or (after_trigger and candidate <= now):
            candidate += timedelta(days=1)

        if repeat == _REPEAT_ONCE:
            return candidate if not after_trigger else None
        return self._advance_to_valid_day(candidate, repeat)

    def _compute_repeating_from_time(
        self,
        time_part: Any,
        repeat: str,
        now: datetime,
        *,
        after_trigger: bool,
    ) -> datetime:
        candidate = now.replace(
            hour=int(time_part.hour),
            minute=int(time_part.minute),
            second=int(time_part.second),
            microsecond=0,
        )
        if candidate < now or (after_trigger and candidate <= now):
            candidate += timedelta(days=1)
        return self._advance_to_valid_day(candidate, repeat)

    def _advance_to_valid_day(self, candidate: datetime, repeat: str) -> datetime:
        if repeat == _REPEAT_DAILY:
            return candidate
        while True:
            weekday = candidate.weekday()
            if repeat == _REPEAT_WEEKDAYS and weekday < 5:
                return candidate
            if repeat == _REPEAT_WEEKENDS and weekday >= 5:
                return candidate
            candidate += timedelta(days=1)

    async def _notify_event_observer(self, method_name: str, **kwargs: Any) -> None:
        if not self.event_observer:
            return
        callback = getattr(self.event_observer, method_name, None)
        if callback is None:
            return
        try:
            await callback(**kwargs)
        except Exception:
            logger.exception("ReminderScheduler observer callback failed: {}", method_name)

    @staticmethod
    def _parse_clock_time(value: str) -> tuple[int, int, int]:
        parts = value.split(":")
        if len(parts) not in {2, 3}:
            raise ValueError("time must use HH:MM or HH:MM:SS")
        hour = int(parts[0])
        minute = int(parts[1])
        second = int(parts[2]) if len(parts) == 3 else 0
        if hour not in range(24) or minute not in range(60) or second not in range(60):
            raise ValueError("time must be a valid clock time")
        return hour, minute, second

    @staticmethod
    def _parse_iso_datetime(value: Any) -> datetime | None:
        if not isinstance(value, str) or not value.strip():
            return None
        try:
            dt = datetime.fromisoformat(value.strip())
        except ValueError:
            return None
        if dt.tzinfo is None:
            return dt.astimezone()
        return dt.astimezone()

    @staticmethod
    def _format_dt(value: datetime) -> str:
        return value.astimezone().isoformat(timespec="seconds")
