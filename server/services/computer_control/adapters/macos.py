from __future__ import annotations

import asyncio
import shutil
from pathlib import Path
from typing import Any

from ..models import ComputerControlError, now_iso


class MacOSComputerAdapter:
    def __init__(self) -> None:
        self._ensure_runtime_available()

    async def open_app(self, *, app: str) -> dict[str, Any]:
        await self._run(["open", "-a", app])
        return {"opened": app}

    async def focus_app_or_window(
        self,
        *,
        app: str,
        window_title: str | None = None,
    ) -> dict[str, Any]:
        if not window_title:
            await self._run(["open", "-a", app])
            return {"focused_app": app}

        output = await self._osascript([
            f'tell application "{self._as_string(app)}" to activate',
            'tell application "System Events"',
            f'  tell process "{self._as_string(app)}"',
            '    set frontmost to true',
            '    set matchedWindow to ""',
            '    repeat with currentWindow in windows',
            '      try',
            f'        if name of currentWindow contains "{self._as_string(window_title)}" then',
            '          perform action "AXRaise" of currentWindow',
            '          set matchedWindow to name of currentWindow',
            '          exit repeat',
            '        end if',
            '      end try',
            '    end repeat',
            '    return matchedWindow',
            '  end tell',
            'end tell',
        ])
        matched = output.strip()
        if not matched:
            raise ComputerControlError(
                code="target_not_found",
                message=f"window not found for app: {app}",
                status=404,
            )
        return {
            "focused_app": app,
            "focused_window": matched,
        }

    async def open_path(self, *, path: str) -> dict[str, Any]:
        await self._run(["open", path])
        return {"opened_path": path}

    async def open_url(self, *, url: str) -> dict[str, Any]:
        await self._run(["open", url])
        return {"opened_url": url}

    async def run_shortcut(
        self,
        *,
        shortcut: str,
        input: str | None = None,
    ) -> dict[str, Any]:
        command = ["shortcuts", "run", shortcut]
        if input is not None:
            command.extend(["--input", input])
        output = await self._run(command)
        return {
            "shortcut": shortcut,
            "stdout": output,
        }

    async def run_script(
        self,
        *,
        script_id: str,
        command: list[str],
        cwd: str | None = None,
    ) -> dict[str, Any]:
        output = await self._run(command, cwd=cwd)
        return {
            "script_id": script_id,
            "stdout": output,
        }

    async def clipboard_get(self) -> dict[str, Any]:
        content = await self._run(["pbpaste"])
        return {"text": content}

    async def clipboard_set(self, *, text: str) -> dict[str, Any]:
        await self._run(["pbcopy"], input_text=text)
        return {
            "text": text,
            "length": len(text),
        }

    async def active_window(self) -> dict[str, Any]:
        output = await self._osascript([
            'tell application "System Events"',
            '  set frontApp to name of first application process whose frontmost is true',
            '  set frontWindow to ""',
            '  try',
            '    tell process frontApp',
            '      set frontWindow to name of front window',
            '    end tell',
            '  end try',
            '  return frontApp & linefeed & frontWindow',
            'end tell',
        ])
        app_name, _, window_title = output.partition("\n")
        return {
            "app": app_name.strip(),
            "window_title": window_title.strip() or None,
        }

    async def screenshot(self, *, path: str) -> dict[str, Any]:
        target = Path(path).expanduser()
        if target.suffix.lower() != ".png":
            target = target / f"screenshot_{now_iso().replace(':', '').replace('+', '_')}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        await self._run(["screencapture", "-x", str(target)])
        return {"path": str(target)}

    async def system_info(self, *, profile: str) -> dict[str, Any]:
        if profile == "frontmost_app":
            return await self.active_window()
        if profile == "disk":
            return await self._disk_info()
        if profile == "memory":
            total = await self._run(["sysctl", "-n", "hw.memsize"])
            return {"bytes_total": int(total)}
        if profile == "network":
            return await self._network_info()
        if profile == "battery":
            return await self._battery_info()
        if profile == "processes_summary":
            return await self._processes_summary()
        raise ComputerControlError(
            code="invalid_argument",
            message=f"unsupported system_info profile: {profile}",
            status=400,
        )

    async def _disk_info(self) -> dict[str, Any]:
        output = await self._run(["df", "-k", "/"])
        lines = [line for line in output.splitlines() if line.strip()]
        if len(lines) < 2:
            return {"raw": output}
        parts = lines[1].split()
        return {
            "filesystem": parts[0] if len(parts) > 0 else None,
            "size_kb": int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else None,
            "used_kb": int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else None,
            "available_kb": int(parts[3]) if len(parts) > 3 and parts[3].isdigit() else None,
            "capacity": parts[4] if len(parts) > 4 else None,
            "mount": parts[5] if len(parts) > 5 else "/",
        }

    async def _network_info(self) -> dict[str, Any]:
        route_output = await self._run(["route", "-n", "get", "default"])
        interface = None
        gateway = None
        for line in route_output.splitlines():
            if ":" not in line:
                continue
            key, _, value = line.partition(":")
            if key.strip() == "interface":
                interface = value.strip()
            if key.strip() == "gateway":
                gateway = value.strip()

        ip_address = None
        if interface:
            ip_output, _, returncode = await self._run(
                ["ipconfig", "getifaddr", interface],
                allow_failure=True,
            )
            if returncode == 0:
                ip_address = ip_output.strip() or None

        return {
            "interface": interface,
            "gateway": gateway,
            "ip_address": ip_address,
        }

    async def _battery_info(self) -> dict[str, Any]:
        output = await self._run(["pmset", "-g", "batt"])
        percent = None
        power_source = None
        for line in output.splitlines():
            if "%" not in line:
                continue
            parts = line.split(";")
            if parts:
                percentage_part = parts[0].split("\t")[-1].strip()
                if percentage_part.endswith("%"):
                    try:
                        percent = int(percentage_part.rstrip("%"))
                    except ValueError:
                        percent = None
            if len(parts) > 1:
                power_source = parts[1].strip()
            break
        return {
            "percent": percent,
            "power_source": power_source,
            "raw": output,
        }

    async def _processes_summary(self) -> dict[str, Any]:
        output = await self._run(["ps", "-Ao", "comm="])
        seen: list[str] = []
        for line in output.splitlines():
            command = line.strip()
            if not command or command in seen:
                continue
            seen.append(command)
            if len(seen) >= 10:
                break
        return {
            "top_commands": seen,
        }

    async def _osascript(self, lines: list[str]) -> str:
        command = ["osascript"]
        for line in lines:
            command.extend(["-e", line])
        return await self._run(command)

    async def _run(
        self,
        command: list[str],
        *,
        cwd: str | None = None,
        input_text: str | None = None,
        allow_failure: bool = False,
    ) -> Any:
        executable = command[0]
        if shutil.which(executable) is None:
            raise ComputerControlError(
                code="adapter_unavailable",
                message=f"command is not available on this machine: {executable}",
                status=503,
            )

        process = await asyncio.create_subprocess_exec(
            *command,
            cwd=cwd,
            stdin=asyncio.subprocess.PIPE if input_text is not None else None,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout_bytes, stderr_bytes = await process.communicate(
            input_text.encode("utf-8") if input_text is not None else None
        )
        stdout = stdout_bytes.decode("utf-8", errors="replace").strip()
        stderr = stderr_bytes.decode("utf-8", errors="replace").strip()
        if allow_failure:
            return stdout, stderr, process.returncode
        if process.returncode != 0:
            raise self._map_command_error(executable, stderr or stdout)
        return stdout

    @staticmethod
    def _map_command_error(executable: str, message: str) -> ComputerControlError:
        lowered = message.lower()
        if executable == "screencapture":
            return ComputerControlError(
                code="permission_screen_recording",
                message=message or "screen recording permission is required",
                status=403,
            )
        if executable == "osascript":
            if "(-1743)" in lowered or "apple events" in lowered or "not authorized" in lowered:
                return ComputerControlError(
                    code="permission_automation",
                    message=message or "automation permission is required",
                    status=403,
                )
            return ComputerControlError(
                code="permission_accessibility",
                message=message or "accessibility permission is required",
                status=403,
            )
        if "not permitted" in lowered or "operation not permitted" in lowered:
            return ComputerControlError(
                code="permission_files_and_folders",
                message=message or "files and folders permission is required",
                status=403,
            )
        if (
            "not found" in lowered
            or "does not exist" in lowered
            or "unable to find application" in lowered
        ):
            return ComputerControlError(
                code="target_not_found",
                message=message or "target not found",
                status=404,
            )
        return ComputerControlError(
            code="adapter_unavailable",
            message=message or f"command failed: {executable}",
            status=409,
        )

    @staticmethod
    def _as_string(value: str) -> str:
        return value.replace("\\", "\\\\").replace('"', '\\"')

    @staticmethod
    def _ensure_runtime_available() -> None:
        if shutil.which("open") is None:
            raise ComputerControlError(
                code="adapter_unavailable",
                message="macOS control commands are not available on this machine",
                status=503,
            )
