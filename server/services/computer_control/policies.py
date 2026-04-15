from __future__ import annotations

from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from .models import ComputerActionRequest, ComputerControlError, PolicyDecision


BASE_ACTIONS = (
    "open_app",
    "focus_app_or_window",
    "open_path",
    "open_url",
    "run_shortcut",
    "run_script",
    "clipboard_get",
    "clipboard_set",
    "active_window",
    "screenshot",
    "system_info",
)

WECHAT_ACTIONS = (
    "wechat_prepare_message",
    "wechat_send_prepared_message",
)

SYSTEM_INFO_PROFILES = {
    "frontmost_app",
    "disk",
    "memory",
    "network",
    "battery",
    "processes_summary",
}

RISK_BY_ACTION = {
    "open_app": "low",
    "focus_app_or_window": "low",
    "open_url": "low",
    "active_window": "low",
    "system_info": "low",
    "clipboard_get": "low",
    "open_path": "medium",
    "clipboard_set": "medium",
    "screenshot": "medium",
    "run_shortcut": "medium",
    "run_script": "medium",
    "wechat_prepare_message": "medium",
    "wechat_send_prepared_message": "high",
}

PENDING_STATUSES = {"requested", "awaiting_confirmation", "running"}


class ComputerControlPolicy:
    def __init__(self, cfg: dict[str, Any], *, runtime_dir: Path) -> None:
        self.cfg = cfg
        self.runtime_dir = runtime_dir
        self.enabled = bool(cfg.get("enabled", False))
        self.confirm_medium_risk = bool(cfg.get("confirm_medium_risk", False))
        self.allowed_apps = {
            str(item).strip()
            for item in list(cfg.get("allowed_apps") or [])
            if str(item).strip()
        }
        self.allowed_shortcuts = {
            str(item).strip()
            for item in list(cfg.get("allowed_shortcuts") or [])
            if str(item).strip()
        }
        self.allowed_scripts = self._parse_scripts(cfg.get("allowed_scripts"))
        self.allowed_path_roots = self._parse_path_roots(cfg.get("allowed_path_roots"))
        default_screenshot_dir = runtime_dir / "computer_control" / "screenshots"
        self.screenshot_dir = Path(
            str(cfg.get("screenshot_dir") or default_screenshot_dir)
        ).expanduser()
        self.screenshot_dir.mkdir(parents=True, exist_ok=True)
        wechat_cfg = dict(cfg.get("wechat") or {})
        self.wechat_enabled = bool(wechat_cfg.get("enabled", False))
        self.wechat_experimental_ui = bool(wechat_cfg.get("experimental_ui", False))
        self.allowed_wechat_contacts = {
            str(item).strip()
            for item in list(wechat_cfg.get("allowed_contacts") or [])
            if str(item).strip()
        }

    def supported_actions(self) -> list[str]:
        actions = list(BASE_ACTIONS)
        if self.wechat_enabled:
            actions.extend(WECHAT_ACTIONS)
        return actions

    @staticmethod
    def permission_hints() -> list[str]:
        return [
            "automation",
            "accessibility",
            "screen_recording",
            "files_and_folders",
        ]

    def evaluate(self, request: ComputerActionRequest) -> PolicyDecision:
        if not self.enabled:
            raise ComputerControlError(
                code="adapter_unavailable",
                message="computer control is disabled",
                status=503,
            )

        kind = request.kind.strip()
        if kind not in self.supported_actions():
            raise ComputerControlError(
                code="unsupported_action",
                message=f"unsupported computer action: {kind}",
                status=400,
            )

        normalized = getattr(self, f"_validate_{kind}")(request.arguments)
        risk_level = RISK_BY_ACTION[kind]
        requires_confirmation = self._resolve_confirmation(
            risk_level,
            request.requires_confirmation,
        )
        return PolicyDecision(
            kind=kind,
            normalized_arguments=normalized,
            risk_level=risk_level,
            requires_confirmation=requires_confirmation,
        )

    def _resolve_confirmation(
        self,
        risk_level: str,
        override: bool | None,
    ) -> bool:
        if risk_level == "high":
            return True
        if override is True:
            return True
        if risk_level == "medium":
            return self.confirm_medium_risk
        return False

    def _validate_open_app(self, arguments: dict[str, Any]) -> dict[str, Any]:
        app = self._require_allowed_app(arguments.get("app"))
        return {"app": app}

    def _validate_focus_app_or_window(self, arguments: dict[str, Any]) -> dict[str, Any]:
        app = self._require_allowed_app(arguments.get("app"))
        window_title = arguments.get("window_title")
        if window_title is None:
            return {"app": app}
        if not isinstance(window_title, str) or not window_title.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="window_title must be a non-empty string",
                status=400,
            )
        return {
            "app": app,
            "window_title": window_title.strip(),
        }

    def _validate_open_path(self, arguments: dict[str, Any]) -> dict[str, Any]:
        path = self._normalize_existing_path(arguments.get("path"))
        self._ensure_path_allowed(path)
        return {"path": str(path)}

    def _validate_open_url(self, arguments: dict[str, Any]) -> dict[str, Any]:
        raw_url = arguments.get("url")
        if not isinstance(raw_url, str) or not raw_url.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="url must be a non-empty string",
                status=400,
            )
        parsed = urlparse(raw_url.strip())
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise ComputerControlError(
                code="invalid_argument",
                message="url must use http or https",
                status=400,
            )
        return {"url": raw_url.strip()}

    def _validate_run_shortcut(self, arguments: dict[str, Any]) -> dict[str, Any]:
        shortcut = arguments.get("shortcut") or arguments.get("shortcut_name")
        if not isinstance(shortcut, str) or not shortcut.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="shortcut must be a non-empty string",
                status=400,
            )
        cleaned = shortcut.strip()
        if cleaned not in self.allowed_shortcuts:
            raise ComputerControlError(
                code="target_not_allowed",
                message=f"shortcut is not allowlisted: {cleaned}",
                status=403,
            )
        input_payload = arguments.get("input")
        if input_payload is not None and not isinstance(input_payload, str):
            raise ComputerControlError(
                code="invalid_argument",
                message="shortcut input must be a string",
                status=400,
            )
        return {
            "shortcut": cleaned,
            "input": input_payload,
        }

    def _validate_run_script(self, arguments: dict[str, Any]) -> dict[str, Any]:
        script_id = arguments.get("script_id")
        if not isinstance(script_id, str) or not script_id.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="script_id must be a non-empty string",
                status=400,
            )
        cleaned = script_id.strip()
        script_cfg = self.allowed_scripts.get(cleaned)
        if not script_cfg:
            raise ComputerControlError(
                code="target_not_allowed",
                message=f"script is not allowlisted: {cleaned}",
                status=403,
            )
        return {
            "script_id": cleaned,
            "command": list(script_cfg["command"]),
            "cwd": script_cfg.get("cwd"),
        }

    def _validate_clipboard_get(self, arguments: dict[str, Any]) -> dict[str, Any]:
        if arguments:
            raise ComputerControlError(
                code="invalid_argument",
                message="clipboard_get does not accept arguments",
                status=400,
            )
        return {}

    def _validate_clipboard_set(self, arguments: dict[str, Any]) -> dict[str, Any]:
        text = arguments.get("text")
        if not isinstance(text, str):
            raise ComputerControlError(
                code="invalid_argument",
                message="text must be a string",
                status=400,
            )
        return {"text": text}

    def _validate_active_window(self, arguments: dict[str, Any]) -> dict[str, Any]:
        if arguments:
            raise ComputerControlError(
                code="invalid_argument",
                message="active_window does not accept arguments",
                status=400,
            )
        return {}

    def _validate_screenshot(self, arguments: dict[str, Any]) -> dict[str, Any]:
        raw_path = arguments.get("path") or arguments.get("output_path")
        if raw_path is None:
            return {"path": str(self.screenshot_dir)}
        if not isinstance(raw_path, str) or not raw_path.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="path must be a non-empty string when provided",
                status=400,
            )
        path = Path(raw_path).expanduser()
        parent = (path if path.suffix == "" else path.parent).resolve(strict=False)
        self._ensure_path_allowed(parent, allow_screenshot_dir=True)
        return {"path": str(path)}

    def _validate_system_info(self, arguments: dict[str, Any]) -> dict[str, Any]:
        profile = arguments.get("profile")
        if not isinstance(profile, str) or not profile.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="profile must be a non-empty string",
                status=400,
            )
        cleaned = profile.strip()
        if cleaned not in SYSTEM_INFO_PROFILES:
            raise ComputerControlError(
                code="invalid_argument",
                message=f"unsupported system_info profile: {cleaned}",
                status=400,
            )
        return {"profile": cleaned}

    def _validate_wechat_prepare_message(self, arguments: dict[str, Any]) -> dict[str, Any]:
        if not self.wechat_enabled:
            raise ComputerControlError(
                code="adapter_unavailable",
                message="wechat adapter is disabled",
                status=409,
            )
        contact_alias = arguments.get("contact_alias")
        if not isinstance(contact_alias, str) or not contact_alias.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="contact_alias must be a non-empty string",
                status=400,
            )
        cleaned_contact = contact_alias.strip()
        if cleaned_contact not in self.allowed_wechat_contacts:
            raise ComputerControlError(
                code="target_not_allowed",
                message=f"contact is not allowlisted: {cleaned_contact}",
                status=403,
            )
        message = arguments.get("message")
        if not isinstance(message, str) or not message.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="message must be a non-empty string",
                status=400,
            )
        return {
            "contact_alias": cleaned_contact,
            "message": message.strip(),
            "experimental_ui": self.wechat_experimental_ui,
        }

    def _validate_wechat_send_prepared_message(self, arguments: dict[str, Any]) -> dict[str, Any]:
        if not self.wechat_enabled:
            raise ComputerControlError(
                code="adapter_unavailable",
                message="wechat adapter is disabled",
                status=409,
            )
        prepared_action_id = arguments.get("prepared_action_id") or arguments.get("action_id")
        if not isinstance(prepared_action_id, str) or not prepared_action_id.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="prepared_action_id must be a non-empty string",
                status=400,
            )
        return {"prepared_action_id": prepared_action_id.strip()}

    def _require_allowed_app(self, value: Any) -> str:
        if not isinstance(value, str) or not value.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="app must be a non-empty string",
                status=400,
            )
        cleaned = value.strip()
        if cleaned not in self.allowed_apps:
            raise ComputerControlError(
                code="target_not_allowed",
                message=f"app is not allowlisted: {cleaned}",
                status=403,
            )
        return cleaned

    def _normalize_existing_path(self, value: Any) -> Path:
        if not isinstance(value, str) or not value.strip():
            raise ComputerControlError(
                code="invalid_argument",
                message="path must be a non-empty string",
                status=400,
            )
        path = Path(value).expanduser().resolve(strict=False)
        if not path.exists():
            raise ComputerControlError(
                code="target_not_found",
                message=f"path does not exist: {path}",
                status=404,
            )
        return path

    def _ensure_path_allowed(
        self,
        path: Path,
        *,
        allow_screenshot_dir: bool = False,
    ) -> None:
        candidate = path.resolve(strict=False)
        allowed_roots = list(self.allowed_path_roots)
        if allow_screenshot_dir:
            allowed_roots.append(self.screenshot_dir.resolve(strict=False))
        for root in allowed_roots:
            try:
                if candidate.is_relative_to(root):
                    return
            except AttributeError:
                candidate_text = str(candidate)
                root_text = str(root)
                if candidate_text == root_text or candidate_text.startswith(f"{root_text}/"):
                    return
        raise ComputerControlError(
            code="target_not_allowed",
            message=f"path is not within an allowlisted root: {candidate}",
            status=403,
        )

    @staticmethod
    def _parse_scripts(raw: Any) -> dict[str, dict[str, Any]]:
        if raw is None:
            return {}
        if not isinstance(raw, dict):
            raise ValueError(
                "computer_control.allowed_scripts must be an object keyed by script_id"
            )

        parsed: dict[str, dict[str, Any]] = {}
        for script_id, payload in raw.items():
            cleaned_id = str(script_id).strip()
            if not cleaned_id:
                continue
            command: list[str] = []
            cwd: str | None = None
            if isinstance(payload, dict):
                raw_command = payload.get("command")
                if isinstance(raw_command, list):
                    command = [str(part).strip() for part in raw_command if str(part).strip()]
                elif isinstance(raw_command, str) and raw_command.strip():
                    command = [raw_command.strip()]
                raw_cwd = payload.get("cwd")
                if isinstance(raw_cwd, str) and raw_cwd.strip():
                    cwd = str(Path(raw_cwd).expanduser())
            elif isinstance(payload, list):
                command = [str(part).strip() for part in payload if str(part).strip()]
            elif isinstance(payload, str) and payload.strip():
                command = [payload.strip()]

            if command:
                parsed[cleaned_id] = {
                    "command": command,
                    "cwd": cwd,
                }
        return parsed

    @staticmethod
    def _parse_path_roots(raw: Any) -> list[Path]:
        roots: list[Path] = []
        for item in list(raw or []):
            cleaned = str(item).strip()
            if not cleaned:
                continue
            roots.append(Path(cleaned).expanduser().resolve(strict=False))
        return roots
