from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
from typing import Any, Callable

from loguru import logger

from services.app_api.resource_service import (
    AppResourceService,
    PLANNING_METADATA_FIELDS,
)


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
_STATUS_OVERDUE = "overdue"
_STATUS_SCHEDULED = "scheduled"
_STATUS_SNOOZED = "snoozed"


class ReminderScheduler:
    """Turns persisted reminder items into runtime notification events."""

    def __init__(
        self,
        resources: AppResourceService,
        *,
        event_observer: Any | None = None,
        poll_interval_s: float = 15.0,
        reconcile_interval_s: float | None = None,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self.resources = resources
        self.event_observer = event_observer
        self.poll_interval_s = poll_interval_s
        self.reconcile_interval_s = max(
            float(reconcile_interval_s if reconcile_interval_s is not None else max(poll_interval_s * 20.0, 300.0)),
            30.0,
        )
        self.now_provider = now_provider or (lambda: datetime.now().astimezone())
        self._task: asyncio.Task | None = None
        self._reconcile_task: asyncio.Task | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._lock = asyncio.Lock()
        self._reschedule_event = asyncio.Event()
        self._listener_registered = False
        self._reschedule_count = 0
        self._next_fire_wakeup_count = 0
        self._reconcile_count = 0
        self._last_reschedule_reason: str | None = None
        self._last_reschedule_at: str | None = None
        self._last_due_scan_at: str | None = None
        self._last_reconcile_at: str | None = None
        self._last_schedule_evaluated_at: str | None = None
        self._scheduled_next_fire_at: str | None = None

        register_listener = getattr(self.resources, "register_reminder_change_listener", None)
        if callable(register_listener):
            register_listener(self._handle_resource_reminder_change)
            self._listener_registered = True

    def set_event_observer(self, observer: Any) -> None:
        self.event_observer = observer

    def is_running(self) -> bool:
        return bool(
            (self._task and not self._task.done())
            or (self._reconcile_task and not self._reconcile_task.done())
        )

    def runtime_state(self) -> dict[str, Any]:
        return {
            "running": self.is_running(),
            "model": "next_fire",
            "poll_interval_s": float(self.poll_interval_s),
            "reconcile_interval_s": float(self.reconcile_interval_s),
            "listener_registered": self._listener_registered,
            "next_fire_at": self._scheduled_next_fire_at,
            "last_schedule_evaluated_at": self._last_schedule_evaluated_at,
            "last_reschedule_at": self._last_reschedule_at,
            "last_reschedule_reason": self._last_reschedule_reason,
            "last_due_scan_at": self._last_due_scan_at,
            "last_reconcile_at": self._last_reconcile_at,
            "reschedule_count": self._reschedule_count,
            "next_fire_wakeup_count": self._next_fire_wakeup_count,
            "reconcile_count": self._reconcile_count,
        }

    def request_reschedule(
        self,
        *,
        reason: str,
        reminder_id: str | None = None,
    ) -> None:
        now = self._format_dt(self.now_provider())
        self._reschedule_count += 1
        self._last_reschedule_reason = (
            f"{reason}:{reminder_id}" if reminder_id else reason
        )
        self._last_reschedule_at = now
        if self._loop is not None and not self._loop.is_closed():
            self._loop.call_soon_threadsafe(self._reschedule_event.set)

    async def start(self) -> None:
        if self.is_running():
            return
        self._loop = asyncio.get_running_loop()
        self._reschedule_event.clear()
        await self.sync_all(reschedule=False)
        self._task = asyncio.create_task(self._run_schedule_loop())
        self._reconcile_task = asyncio.create_task(self._run_reconcile_loop())
        logger.info("ReminderScheduler started")

    async def stop(self) -> None:
        tasks = [task for task in (self._task, self._reconcile_task) if task is not None]
        if not tasks:
            return
        for task in tasks:
            task.cancel()
        for task in tasks:
            try:
                await task
            except asyncio.CancelledError:
                pass
        self._task = None
        self._reconcile_task = None
        self._loop = None
        self._scheduled_next_fire_at = None

    async def sync_all(self, *, reschedule: bool = True) -> None:
        async with self._lock:
            now = self.now_provider()
            items = self.resources.list_reminder_items()
            for item in items:
                await self._sync_reminder_unlocked(item, now=now)
        if reschedule:
            self.request_reschedule(reason="sync_all")

    async def sync_reminder(
        self,
        reminder_id: str,
        *,
        reschedule: bool = True,
    ) -> dict[str, Any] | None:
        async with self._lock:
            item = self.resources.get_reminder(reminder_id)
            if item is None:
                return None
            updated = await self._sync_reminder_unlocked(item, now=self.now_provider())
        if reschedule:
            self.request_reschedule(reason="sync_reminder", reminder_id=reminder_id)
        return updated

    async def snooze_reminder(
        self,
        reminder_id: str,
        *,
        snoozed_until: str | None = None,
        delay_minutes: int = 10,
    ) -> dict[str, Any] | None:
        async with self._lock:
            item = self.resources.get_reminder(reminder_id)
            if item is None:
                return None
            now = self.now_provider()
            target = None
            if snoozed_until is not None:
                target = self._parse_iso_datetime(snoozed_until)
                if target is None:
                    raise ValueError("snoozed_until must be a valid ISO datetime")
                if target <= now:
                    raise ValueError("snoozed_until must be in the future")
            else:
                if delay_minutes < 1:
                    raise ValueError("delay_minutes must be at least 1")
                target = now + timedelta(minutes=delay_minutes)
            updated = self.resources.update_reminder(
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
            updated = await self._sync_reminder_unlocked(updated, now=now)
        self.request_reschedule(reason="snooze", reminder_id=reminder_id)
        return updated

    async def complete_reminder(self, reminder_id: str) -> dict[str, Any] | None:
        async with self._lock:
            item = self.resources.get_reminder(reminder_id)
            if item is None:
                return None
            updated = self.resources.update_reminder(
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
        self.request_reschedule(reason="complete", reminder_id=reminder_id)
        return updated

    async def _run_schedule_loop(self) -> None:
        while True:
            try:
                next_fire_at = self.resources.get_next_reminder_fire_at()
                self._last_schedule_evaluated_at = self._format_dt(self.now_provider())
                self._scheduled_next_fire_at = next_fire_at
                if next_fire_at is None:
                    await self._wait_for_reschedule()
                    continue

                next_fire_dt = self._parse_iso_datetime(next_fire_at)
                if next_fire_dt is None:
                    await self._wait_for_reschedule()
                    continue

                wait_seconds = max((next_fire_dt - self.now_provider()).total_seconds(), 0.0)
                if wait_seconds > 0 and await self._wait_for_reschedule(timeout=wait_seconds):
                    continue

                self._next_fire_wakeup_count += 1
                await self._process_due_reminders()
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("ReminderScheduler next-fire loop failed")
                await asyncio.sleep(1.0)

    async def _run_reconcile_loop(self) -> None:
        while True:
            try:
                await asyncio.sleep(self.reconcile_interval_s)
                self._reconcile_count += 1
                self._last_reconcile_at = self._format_dt(self.now_provider())
                await self.sync_all(reschedule=False)
                self.request_reschedule(reason="reconcile")
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("ReminderScheduler reconcile loop failed")
                await asyncio.sleep(1.0)

    async def _wait_for_reschedule(self, timeout: float | None = None) -> bool:
        if timeout is None:
            await self._reschedule_event.wait()
            self._reschedule_event.clear()
            return True
        try:
            await asyncio.wait_for(self._reschedule_event.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            return False
        self._reschedule_event.clear()
        return True

    def _handle_resource_reminder_change(self, payload: dict[str, Any]) -> None:
        reminder_id = None
        raw_reminder_id = payload.get("reminder_id")
        if isinstance(raw_reminder_id, str) and raw_reminder_id.strip():
            reminder_id = raw_reminder_id.strip()
        action = str(payload.get("action") or "resource_change")
        self.request_reschedule(reason=f"resource_{action}", reminder_id=reminder_id)

    async def _process_due_reminders(self) -> None:
        async with self._lock:
            now = self.now_provider()
            self._last_due_scan_at = self._format_dt(now)
            items = self.resources.list_due_reminders(
                due_before=self._format_dt(now),
                deliverable_only=True,
            )
            for item in items:
                updated = await self._sync_reminder_unlocked(item, now=now)
                if not updated.get("enabled", False):
                    continue
                next_trigger_at = self._parse_iso_datetime(updated.get("next_trigger_at"))
                if next_trigger_at is None or next_trigger_at > now:
                    continue
                if not self._should_deliver(updated, scheduled_for=next_trigger_at):
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
        updated = self.resources.update_reminder(reminder["reminder_id"], patch)
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

        notification_payload = {
            "type": "reminder_due",
            "priority": "high",
            "title": title,
            "message": message,
            "metadata": {
                "reminder_id": reminder_id,
                "scheduled_for": scheduled_for,
                "repeat": reminder.get("repeat"),
                **{
                    field: reminder.get(field)
                    for field in PLANNING_METADATA_FIELDS
                    if reminder.get(field) is not None
                },
            },
        }
        delivery_mode = reminder.get("delivery_mode")
        if delivery_mode is not None:
            notification_payload["metadata"]["delivery_mode"] = delivery_mode

        patch = {
            "last_triggered_at": self._format_dt(now),
            "last_error": None,
            "snoozed_until": None,
            "completed_at": None,
        }
        next_dt = self._compute_next_trigger(reminder, now=now, after_trigger=True)
        if next_dt is None:
            patch["enabled"] = True
            patch["next_trigger_at"] = scheduled_for or reminder.get("next_trigger_at") or reminder.get("time")
            patch["status"] = _STATUS_OVERDUE
        else:
            patch["next_trigger_at"] = self._format_dt(next_dt)
            patch["status"] = _STATUS_SCHEDULED

        notification, updated = self.resources.create_notification_and_update_reminder(
            reminder_id=reminder_id,
            notification_payload=notification_payload,
            reminder_patch=patch,
        )

        if notification is None:
            return

        updated = updated or reminder
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
            is_overdue = str(reminder.get("status") or "").strip().lower() == _STATUS_OVERDUE
            if reminder.get("next_trigger_at") is not None and not is_overdue:
                patch["next_trigger_at"] = None
            if reminder.get("last_error") is not None:
                patch["last_error"] = None
            return patch

        snoozed_until = self._parse_iso_datetime(reminder.get("snoozed_until"))
        if snoozed_until is not None:
            next_trigger_at = self._format_dt(snoozed_until)
            if reminder.get("next_trigger_at") != next_trigger_at:
                patch["next_trigger_at"] = next_trigger_at
            status = _STATUS_SNOOZED if snoozed_until > now else _STATUS_OVERDUE
            if reminder.get("status") != status:
                patch["status"] = status
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

        repeat = self._repeat_value(reminder)
        existing_due = self._parse_iso_datetime(reminder.get("next_trigger_at"))
        if repeat == _REPEAT_ONCE and existing_due is not None and existing_due <= now:
            if reminder.get("status") != _STATUS_OVERDUE:
                patch["status"] = _STATUS_OVERDUE
            if reminder.get("last_error") is not None:
                patch["last_error"] = None
            return patch

        next_trigger_at = self._format_dt(next_dt) if next_dt else None
        if reminder.get("next_trigger_at") != next_trigger_at:
            patch["next_trigger_at"] = next_trigger_at
        status = _STATUS_OVERDUE if repeat == _REPEAT_ONCE and next_dt is not None and next_dt <= now else _STATUS_SCHEDULED
        if reminder.get("status") != status:
            patch["status"] = status
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
        repeat = self._repeat_value(reminder)

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

    def _repeat_value(self, reminder: dict[str, Any]) -> str:
        repeat = str(reminder.get("repeat") or _REPEAT_DAILY).strip().lower()
        if repeat not in _SUPPORTED_REPEATS:
            raise ValueError(f"repeat must be one of: {', '.join(sorted(_SUPPORTED_REPEATS))}")
        return repeat

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

    def _should_deliver(self, reminder: dict[str, Any], *, scheduled_for: datetime) -> bool:
        last_triggered_at = self._parse_iso_datetime(reminder.get("last_triggered_at"))
        if last_triggered_at is None:
            return True
        return last_triggered_at < scheduled_for

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
