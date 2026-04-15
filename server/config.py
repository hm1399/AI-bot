"""
AI-Bot 服务端配置
读取 config.yaml 和环境变量，同时为 nanobot 生成所需的 config.json
"""
from __future__ import annotations

import importlib.util
import os
import json
from copy import deepcopy
from pathlib import Path
from typing import Any

import yaml


# 项目根目录
SERVER_DIR = Path(__file__).parent
WORKSPACE_DIR = SERVER_DIR / "workspace"
CONFIG_YAML = SERVER_DIR / "config.yaml"
NANOBOT_CONFIG_JSON = WORKSPACE_DIR / "config.json"
ENV_FILE = SERVER_DIR / ".env"
DEFAULT_PROVIDER_TIMEOUT_SECONDS = 90.0
DEFAULT_EXEC_TOOL_TIMEOUT_SECONDS = 60
_VALID_STORAGE_MODES = {"json", "dual", "sqlite"}
_DEFAULT_TRANSPORT_CONFIG = {
    "bus": {
        "inbound_maxsize": 128,
        "outbound_maxsize": 128,
        "inbound_reserved_slots": 8,
        "outbound_reserved_slots": 8,
    },
    "app_events": {
        "client_queue_maxsize": 64,
    },
    "outbound_lanes": {
        "device_voice_lane": 32,
        "desktop_voice_lane": 32,
        "external_channels_lane": 64,
        "app_realtime_lane": 64,
    },
}


def _load_dotenv() -> None:
    """加载 .env 文件到环境变量（不覆盖已有变量）。"""
    if not ENV_FILE.exists():
        return
    with open(ENV_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key, value = key.strip(), value.strip()
            if key and key not in os.environ:
                os.environ[key] = value


def _resolve_env_string(
    value: object,
    *,
    fallback_env_names: tuple[str, ...] = (),
) -> str:
    """Resolve ${ENV_NAME} placeholders and optional fallback env vars."""
    if isinstance(value, str):
        candidate = value.strip()
        if candidate.startswith("${") and candidate.endswith("}"):
            return os.environ.get(candidate[2:-1], "")
        if candidate:
            return candidate

    for env_name in fallback_env_names:
        resolved = os.environ.get(env_name, "").strip()
        if resolved:
            return resolved
    return ""


def _normalize_optional_string(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        cleaned = value.strip()
        return cleaned or None
    return str(value).strip() or None


def load_yaml_config() -> dict:
    """加载 config.yaml，环境变量可覆盖 API Key。"""
    _load_dotenv()

    if not CONFIG_YAML.exists():
        raise FileNotFoundError(f"配置文件不存在: {CONFIG_YAML}")

    with open(CONFIG_YAML, encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}

    server_cfg = cfg.setdefault("server", {})
    server_cfg.setdefault("host", "0.0.0.0")
    server_cfg.setdefault("port", 8765)
    server_cfg.setdefault("secure", False)

    # weather API key 环境变量覆盖
    weather_cfg = cfg.get("weather", {})
    weather_key = _resolve_env_string(weather_cfg.get("api_key", ""))
    cfg.setdefault("weather", {})["api_key"] = weather_key

    # device auth token 环境变量覆盖
    device_cfg = cfg.get("device", {})
    device_token = _resolve_env_string(device_cfg.get("auth_token", ""))
    cfg.setdefault("device", {})["auth_token"] = device_token

    # app auth token 环境变量覆盖
    app_cfg = cfg.get("app", {})
    app_token = _resolve_env_string(app_cfg.get("auth_token", ""))
    cfg.setdefault("app", {})["auth_token"] = app_token

    # 环境变量覆盖
    provider = cfg.get("nanobot", {}).get("provider", "anthropic")
    # 根据 provider 选择对应的环境变量名
    env_key_map = {
        "anthropic": "ANTHROPIC_API_KEY",
        "openrouter": "OPENROUTER_API_KEY",
        "openai": "OPENAI_API_KEY",
    }
    env_key = env_key_map.get(provider, f"{provider.upper()}_API_KEY")
    api_key = os.environ.get(env_key) or _resolve_env_string(
        cfg.get("nanobot", {}).get("api_key", ""),
    )
    cfg.setdefault("nanobot", {})["api_key"] = api_key
    cfg["nanobot"].setdefault("provider_timeout_seconds", DEFAULT_PROVIDER_TIMEOUT_SECONDS)

    computer_cfg = cfg.setdefault("computer_control", {})
    computer_cfg.setdefault("enabled", False)
    computer_cfg.setdefault("allowed_apps", [])
    computer_cfg.setdefault("allowed_shortcuts", [])
    computer_cfg.setdefault("allowed_scripts", {})
    computer_cfg.setdefault("allowed_path_roots", [])
    computer_cfg.setdefault("confirm_medium_risk", False)
    wechat_cfg = computer_cfg.setdefault("wechat", {})
    wechat_cfg.setdefault("enabled", False)
    wechat_cfg.setdefault("experimental_ui", False)
    wechat_cfg.setdefault("allowed_contacts", [])

    storage_cfg = cfg.setdefault("storage", {})
    storage_cfg.setdefault("session_storage_mode", "dual")
    storage_cfg.setdefault("planning_storage_mode", "dual")
    storage_cfg.setdefault("experience_storage_mode", "json")
    storage_cfg.setdefault("computer_action_storage_mode", "json")
    storage_cfg.setdefault("sqlite_path", str(WORKSPACE_DIR / "state.sqlite3"))

    tools_cfg = cfg.setdefault("tools", {})
    tools_cfg.setdefault("restrict_to_workspace", False)
    exec_cfg = tools_cfg.setdefault("exec", {})
    exec_cfg.setdefault("timeout", DEFAULT_EXEC_TOOL_TIMEOUT_SECONDS)
    exec_cfg.setdefault("path_append", "")
    web_cfg = tools_cfg.setdefault("web", {})
    web_cfg["proxy"] = _normalize_optional_string(web_cfg.get("proxy"))
    search_cfg = web_cfg.setdefault("search", {})
    search_cfg["api_key"] = _resolve_env_string(
        search_cfg.get("api_key", ""),
        fallback_env_names=("BRAVE_API_KEY", "BRAVE_SEARCH_API_KEY"),
    )
    tools_cfg.setdefault("mcp_servers", {})

    cron_cfg = cfg.setdefault("cron", {})
    cron_cfg.setdefault("enabled", False)
    cron_cfg.setdefault("store_path", str(WORKSPACE_DIR / "runtime" / "cron_jobs.json"))

    transport_cfg = cfg.setdefault("transport", {})
    bus_cfg = transport_cfg.setdefault("bus", {})
    bus_cfg.setdefault(
        "inbound_maxsize",
        _DEFAULT_TRANSPORT_CONFIG["bus"]["inbound_maxsize"],
    )
    bus_cfg.setdefault(
        "outbound_maxsize",
        _DEFAULT_TRANSPORT_CONFIG["bus"]["outbound_maxsize"],
    )
    bus_cfg.setdefault(
        "inbound_reserved_slots",
        _DEFAULT_TRANSPORT_CONFIG["bus"]["inbound_reserved_slots"],
    )
    bus_cfg.setdefault(
        "outbound_reserved_slots",
        _DEFAULT_TRANSPORT_CONFIG["bus"]["outbound_reserved_slots"],
    )
    app_events_cfg = transport_cfg.setdefault("app_events", {})
    app_events_cfg.setdefault(
        "client_queue_maxsize",
        _DEFAULT_TRANSPORT_CONFIG["app_events"]["client_queue_maxsize"],
    )
    outbound_lanes_cfg = transport_cfg.setdefault("outbound_lanes", {})
    outbound_lanes_cfg.setdefault(
        "device_voice_lane",
        _DEFAULT_TRANSPORT_CONFIG["outbound_lanes"]["device_voice_lane"],
    )
    outbound_lanes_cfg.setdefault(
        "desktop_voice_lane",
        _DEFAULT_TRANSPORT_CONFIG["outbound_lanes"]["desktop_voice_lane"],
    )
    outbound_lanes_cfg.setdefault(
        "external_channels_lane",
        _DEFAULT_TRANSPORT_CONFIG["outbound_lanes"]["external_channels_lane"],
    )
    outbound_lanes_cfg.setdefault(
        "app_realtime_lane",
        _DEFAULT_TRANSPORT_CONFIG["outbound_lanes"]["app_realtime_lane"],
    )

    return cfg


def _parse_provider_timeout_seconds(value: object) -> float:
    """Parse and validate the provider timeout value."""
    if isinstance(value, bool):
        raise ValueError

    timeout = float(value)
    if timeout <= 0:
        raise ValueError

    return timeout


def get_provider_timeout_seconds(cfg: dict) -> float:
    """Return the configured provider request timeout in seconds."""
    timeout = cfg.get("nanobot", {}).get(
        "provider_timeout_seconds",
        DEFAULT_PROVIDER_TIMEOUT_SECONDS,
    )
    return _parse_provider_timeout_seconds(timeout)


def _parse_exec_tool_timeout_seconds(value: object) -> int:
    """Parse and validate the exec tool timeout value."""
    if isinstance(value, bool):
        raise ValueError

    timeout = int(value)
    if timeout <= 0:
        raise ValueError

    return timeout


def _parse_positive_int(value: object, *, default: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    return parsed if parsed > 0 else default


def get_tools_config(cfg: dict) -> dict[str, Any]:
    """Return normalized tool runtime config."""
    tools_cfg = cfg.get("tools", {}) if isinstance(cfg.get("tools", {}), dict) else {}
    exec_cfg = tools_cfg.get("exec", {}) if isinstance(tools_cfg.get("exec", {}), dict) else {}
    web_cfg = tools_cfg.get("web", {}) if isinstance(tools_cfg.get("web", {}), dict) else {}
    search_cfg = web_cfg.get("search", {}) if isinstance(web_cfg.get("search", {}), dict) else {}

    timeout = exec_cfg.get("timeout", DEFAULT_EXEC_TOOL_TIMEOUT_SECONDS)
    try:
        exec_timeout = _parse_exec_tool_timeout_seconds(timeout)
    except (TypeError, ValueError):
        exec_timeout = DEFAULT_EXEC_TOOL_TIMEOUT_SECONDS

    return {
        "restrict_to_workspace": bool(tools_cfg.get("restrict_to_workspace", False)),
        "exec": {
            "timeout": exec_timeout,
            "path_append": str(exec_cfg.get("path_append", "") or "").strip(),
        },
        "web": {
            "proxy": _normalize_optional_string(web_cfg.get("proxy")),
            "search": {
                "api_key": _resolve_env_string(
                    search_cfg.get("api_key", ""),
                    fallback_env_names=("BRAVE_API_KEY", "BRAVE_SEARCH_API_KEY"),
                ),
            },
        },
        "mcp_servers": deepcopy(tools_cfg.get("mcp_servers", {}))
        if isinstance(tools_cfg.get("mcp_servers", {}), dict)
        else {},
    }


def get_cron_config(cfg: dict) -> dict[str, Any]:
    """Return normalized cron runtime config."""
    cron_cfg = cfg.get("cron", {}) if isinstance(cfg.get("cron", {}), dict) else {}
    default_store_path = str(WORKSPACE_DIR / "runtime" / "cron_jobs.json")
    return {
        "enabled": bool(cron_cfg.get("enabled", False)),
        "store_path": str(cron_cfg.get("store_path") or default_store_path),
    }


def get_transport_config(cfg: dict) -> dict[str, Any]:
    """Return normalized transport runtime config."""
    transport_cfg = cfg.get("transport", {}) if isinstance(cfg.get("transport", {}), dict) else {}
    bus_cfg = transport_cfg.get("bus", {}) if isinstance(transport_cfg.get("bus", {}), dict) else {}
    app_events_cfg = (
        transport_cfg.get("app_events", {})
        if isinstance(transport_cfg.get("app_events", {}), dict)
        else {}
    )
    outbound_lanes_cfg = (
        transport_cfg.get("outbound_lanes", {})
        if isinstance(transport_cfg.get("outbound_lanes", {}), dict)
        else {}
    )
    return {
        "bus": {
            "inbound_maxsize": _parse_positive_int(
                bus_cfg.get("inbound_maxsize"),
                default=_DEFAULT_TRANSPORT_CONFIG["bus"]["inbound_maxsize"],
            ),
            "outbound_maxsize": _parse_positive_int(
                bus_cfg.get("outbound_maxsize"),
                default=_DEFAULT_TRANSPORT_CONFIG["bus"]["outbound_maxsize"],
            ),
            "inbound_reserved_slots": _parse_positive_int(
                bus_cfg.get("inbound_reserved_slots"),
                default=_DEFAULT_TRANSPORT_CONFIG["bus"]["inbound_reserved_slots"],
            ),
            "outbound_reserved_slots": _parse_positive_int(
                bus_cfg.get("outbound_reserved_slots"),
                default=_DEFAULT_TRANSPORT_CONFIG["bus"]["outbound_reserved_slots"],
            ),
        },
        "app_events": {
            "client_queue_maxsize": _parse_positive_int(
                app_events_cfg.get("client_queue_maxsize"),
                default=_DEFAULT_TRANSPORT_CONFIG["app_events"]["client_queue_maxsize"],
            ),
        },
        "outbound_lanes": {
            "device_voice_lane": _parse_positive_int(
                outbound_lanes_cfg.get("device_voice_lane"),
                default=_DEFAULT_TRANSPORT_CONFIG["outbound_lanes"]["device_voice_lane"],
            ),
            "desktop_voice_lane": _parse_positive_int(
                outbound_lanes_cfg.get("desktop_voice_lane"),
                default=_DEFAULT_TRANSPORT_CONFIG["outbound_lanes"]["desktop_voice_lane"],
            ),
            "external_channels_lane": _parse_positive_int(
                outbound_lanes_cfg.get("external_channels_lane"),
                default=_DEFAULT_TRANSPORT_CONFIG["outbound_lanes"]["external_channels_lane"],
            ),
            "app_realtime_lane": _parse_positive_int(
                outbound_lanes_cfg.get("app_realtime_lane"),
                default=_DEFAULT_TRANSPORT_CONFIG["outbound_lanes"]["app_realtime_lane"],
            ),
        },
    }


def generate_nanobot_config(cfg: dict) -> None:
    """根据 config.yaml 生成 nanobot 需要的 config.json。"""
    nanobot_cfg = cfg.get("nanobot", {})
    provider_name = nanobot_cfg.get("provider", "anthropic")
    provider_timeout_seconds = get_provider_timeout_seconds(cfg)
    tools_cfg = get_tools_config(cfg)

    config_json = {
        "agents": {
            "defaults": {
                "workspace": str(WORKSPACE_DIR),
                "model": nanobot_cfg.get("model", "claude-sonnet-4-6"),
                "provider": nanobot_cfg.get("provider", "anthropic"),
                "maxTokens": nanobot_cfg.get("max_tokens", 8192),
                "temperature": nanobot_cfg.get("temperature", 0.1),
                "maxToolIterations": nanobot_cfg.get("max_tool_iterations", 20),
                "memoryWindow": nanobot_cfg.get("memory_window", 50),
            }
        },
        "providers": {
            provider_name: {
                "apiKey": nanobot_cfg.get("api_key", ""),
                "timeoutSeconds": provider_timeout_seconds,
            }
        },
        "channels": {
            "whatsapp": {
                "bridgeUrl": cfg.get("whatsapp", {}).get("bridge_url", "ws://localhost:3001"),
                "bridgeToken": cfg.get("whatsapp", {}).get("bridge_token", ""),
                "allowFrom": cfg.get("whatsapp", {}).get("allow_from", ["*"]),
            }
        } if cfg.get("whatsapp", {}).get("enabled", False) else {},
        "tools": {
            "web": {
                "proxy": tools_cfg["web"]["proxy"],
                "search": {
                    "apiKey": tools_cfg["web"]["search"]["api_key"],
                },
            },
            "exec": {
                "timeout": tools_cfg["exec"]["timeout"],
                "pathAppend": tools_cfg["exec"]["path_append"],
            },
            "restrictToWorkspace": tools_cfg["restrict_to_workspace"],
            "mcpServers": tools_cfg["mcp_servers"],
        },
    }

    WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)
    with open(NANOBOT_CONFIG_JSON, "w", encoding="utf-8") as f:
        json.dump(config_json, f, indent=2, ensure_ascii=False)


def validate_config(cfg: dict) -> list[str]:
    """启动时验证配置，返回错误列表（空列表 = 通过）。"""
    errors = []

    # API Key 必填
    api_key = cfg.get("nanobot", {}).get("api_key", "")
    if not api_key:
        provider = cfg.get("nanobot", {}).get("provider", "anthropic")
        env_key_map = {
            "anthropic": "ANTHROPIC_API_KEY",
            "openrouter": "OPENROUTER_API_KEY",
            "openai": "OPENAI_API_KEY",
        }
        env_key = env_key_map.get(provider, f"{provider.upper()}_API_KEY")
        errors.append(
            f"API Key 未设置！请在 config.yaml 的 nanobot.api_key 或环境变量 {env_key} 中配置"
        )

    provider_timeout_seconds = cfg.get("nanobot", {}).get(
        "provider_timeout_seconds",
        DEFAULT_PROVIDER_TIMEOUT_SECONDS,
    )
    try:
        _parse_provider_timeout_seconds(provider_timeout_seconds)
    except (TypeError, ValueError):
        errors.append(
            "nanobot.provider_timeout_seconds 必须是大于 0 的数字"
        )

    # SOUL.md 存在性检查
    soul_md = WORKSPACE_DIR / "SOUL.md"
    if not soul_md.exists():
        errors.append(f"SOUL.md 不存在: {soul_md}")

    # 端口范围
    port = cfg.get("server", {}).get("port", 8765)
    if not isinstance(port, int) or port < 1 or port > 65535:
        errors.append(f"端口无效: {port}（应为 1-65535）")
    if not isinstance(cfg.get("server", {}).get("secure", False), bool):
        errors.append("server.secure 必须是布尔值")

    # 设备认证 token 基本校验
    device_token = cfg.get("device", {}).get("auth_token", "")
    if device_token and (not isinstance(device_token, str) or len(device_token.strip()) < 8):
        errors.append("device.auth_token 至少需要 8 个字符，或留空表示关闭设备认证")

    # App 认证 token 基本校验
    app_token = cfg.get("app", {}).get("auth_token", "")
    if app_token and (not isinstance(app_token, str) or len(app_token.strip()) < 8):
        errors.append("app.auth_token 至少需要 8 个字符，或留空表示关闭 App API 认证")

    computer_cfg = cfg.get("computer_control", {})
    if computer_cfg and not isinstance(computer_cfg, dict):
        errors.append("computer_control 必须是对象")
    else:
        if "enabled" in computer_cfg and not isinstance(computer_cfg.get("enabled"), bool):
            errors.append("computer_control.enabled 必须是布尔值")
        if "confirm_medium_risk" in computer_cfg and not isinstance(computer_cfg.get("confirm_medium_risk"), bool):
            errors.append("computer_control.confirm_medium_risk 必须是布尔值")
        for key in ("allowed_apps", "allowed_shortcuts", "allowed_path_roots"):
            value = computer_cfg.get(key, [])
            if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
                errors.append(f"computer_control.{key} 必须是字符串数组")
        allowed_scripts = computer_cfg.get("allowed_scripts", {})
        if not isinstance(allowed_scripts, dict):
            errors.append(
                "computer_control.allowed_scripts 必须是对象映射；迁移示例: "
                "allowed_scripts: {script_id: {command: ['/bin/echo', 'ok']}}"
            )
        else:
            for script_id, payload in allowed_scripts.items():
                if not isinstance(script_id, str) or not script_id.strip():
                    errors.append("computer_control.allowed_scripts 的 key 必须是非空字符串")
                    continue
                if not isinstance(payload, (str, list, dict)):
                    errors.append(
                        f"computer_control.allowed_scripts.{script_id} 必须是字符串、数组或对象"
                    )
        wechat_cfg = computer_cfg.get("wechat", {})
        if not isinstance(wechat_cfg, dict):
            errors.append("computer_control.wechat 必须是对象")
        else:
            if "enabled" in wechat_cfg and not isinstance(wechat_cfg.get("enabled"), bool):
                errors.append("computer_control.wechat.enabled 必须是布尔值")
            if "experimental_ui" in wechat_cfg and not isinstance(wechat_cfg.get("experimental_ui"), bool):
                errors.append("computer_control.wechat.experimental_ui 必须是布尔值")
            allowed_contacts = wechat_cfg.get("allowed_contacts", [])
            if not isinstance(allowed_contacts, list) or any(not isinstance(item, str) for item in allowed_contacts):
                errors.append("computer_control.wechat.allowed_contacts 必须是字符串数组")

    storage_cfg = cfg.get("storage", {})
    if storage_cfg and not isinstance(storage_cfg, dict):
        errors.append("storage 必须是对象")
    else:
        for key in (
            "session_storage_mode",
            "planning_storage_mode",
            "experience_storage_mode",
            "computer_action_storage_mode",
        ):
            value = str(storage_cfg.get(key, "json")).strip().lower()
            if value not in _VALID_STORAGE_MODES:
                allowed = ", ".join(sorted(_VALID_STORAGE_MODES))
                errors.append(f"storage.{key} 必须是以下之一: {allowed}")
        sqlite_path = storage_cfg.get("sqlite_path")
        if sqlite_path is not None and not isinstance(sqlite_path, str):
            errors.append("storage.sqlite_path 必须是字符串")

    tools_cfg = cfg.get("tools", {})
    if tools_cfg and not isinstance(tools_cfg, dict):
        errors.append("tools 必须是对象")
    else:
        if "restrict_to_workspace" in tools_cfg and not isinstance(
            tools_cfg.get("restrict_to_workspace"),
            bool,
        ):
            errors.append("tools.restrict_to_workspace 必须是布尔值")

        exec_cfg = tools_cfg.get("exec", {})
        if exec_cfg and not isinstance(exec_cfg, dict):
            errors.append("tools.exec 必须是对象")
        else:
            timeout = exec_cfg.get("timeout", DEFAULT_EXEC_TOOL_TIMEOUT_SECONDS)
            try:
                _parse_exec_tool_timeout_seconds(timeout)
            except (TypeError, ValueError):
                errors.append("tools.exec.timeout 必须是大于 0 的整数")
            if "path_append" in exec_cfg and not isinstance(exec_cfg.get("path_append"), str):
                errors.append("tools.exec.path_append 必须是字符串")

        web_cfg = tools_cfg.get("web", {})
        if web_cfg and not isinstance(web_cfg, dict):
            errors.append("tools.web 必须是对象")
        else:
            proxy = web_cfg.get("proxy")
            if proxy is not None and not isinstance(proxy, str):
                errors.append("tools.web.proxy 必须是字符串或 null")
            search_cfg = web_cfg.get("search", {})
            if search_cfg and not isinstance(search_cfg, dict):
                errors.append("tools.web.search 必须是对象")
            elif search_cfg.get("api_key") is not None and not isinstance(search_cfg.get("api_key"), str):
                errors.append("tools.web.search.api_key 必须是字符串")

        mcp_servers = tools_cfg.get("mcp_servers", {})
        if mcp_servers and not isinstance(mcp_servers, dict):
            errors.append("tools.mcp_servers 必须是对象")
        elif isinstance(mcp_servers, dict):
            for name, payload in mcp_servers.items():
                if not isinstance(name, str) or not name.strip():
                    errors.append("tools.mcp_servers 的 key 必须是非空字符串")
                    continue
                if not isinstance(payload, dict):
                    errors.append(f"tools.mcp_servers.{name} 必须是对象")
                    continue
                if "command" in payload and not isinstance(payload.get("command"), str):
                    errors.append(f"tools.mcp_servers.{name}.command 必须是字符串")
                if "url" in payload and not isinstance(payload.get("url"), str):
                    errors.append(f"tools.mcp_servers.{name}.url 必须是字符串")
                args = payload.get("args", [])
                if not isinstance(args, list) or any(not isinstance(item, str) for item in args):
                    errors.append(f"tools.mcp_servers.{name}.args 必须是字符串数组")
                env = payload.get("env", {})
                if not isinstance(env, dict) or any(
                    not isinstance(key, str) or not isinstance(value, str)
                    for key, value in env.items()
                ):
                    errors.append(f"tools.mcp_servers.{name}.env 必须是字符串映射")
                headers = payload.get("headers", {})
                if not isinstance(headers, dict) or any(
                    not isinstance(key, str) or not isinstance(value, str)
                    for key, value in headers.items()
                ):
                    errors.append(f"tools.mcp_servers.{name}.headers 必须是字符串映射")
                tool_timeout = payload.get("tool_timeout", 30)
                if not isinstance(tool_timeout, int) or tool_timeout <= 0:
                    errors.append(f"tools.mcp_servers.{name}.tool_timeout 必须是大于 0 的整数")

    cron_cfg = cfg.get("cron", {})
    if cron_cfg and not isinstance(cron_cfg, dict):
        errors.append("cron 必须是对象")
    else:
        if "enabled" in cron_cfg and not isinstance(cron_cfg.get("enabled"), bool):
            errors.append("cron.enabled 必须是布尔值")
        if "store_path" in cron_cfg and not isinstance(cron_cfg.get("store_path"), str):
            errors.append("cron.store_path 必须是字符串")

    transport_cfg = cfg.get("transport", {})
    if transport_cfg and not isinstance(transport_cfg, dict):
        errors.append("transport 必须是对象")
    else:
        for section, keys in (
            (
                "bus",
                (
                    "inbound_maxsize",
                    "outbound_maxsize",
                    "inbound_reserved_slots",
                    "outbound_reserved_slots",
                ),
            ),
            ("app_events", ("client_queue_maxsize",)),
            (
                "outbound_lanes",
                (
                    "device_voice_lane",
                    "desktop_voice_lane",
                    "external_channels_lane",
                    "app_realtime_lane",
                ),
            ),
        ):
            payload = transport_cfg.get(section, {})
            if payload and not isinstance(payload, dict):
                errors.append(f"transport.{section} 必须是对象")
                continue
            if not isinstance(payload, dict):
                continue
            for key in keys:
                if key not in payload:
                    continue
                value = payload.get(key)
                if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
                    errors.append(f"transport.{section}.{key} 必须是大于 0 的整数")

    # 运行时依赖检查（在真正实例化服务前先给出明确错误）
    dependency_requirements = [
        ("numpy", "ASR 依赖缺失：请安装 numpy"),
        ("funasr", "ASR 依赖缺失：请安装 funasr"),
        ("torch", "ASR 依赖缺失：请安装 torch"),
        ("torchaudio", "ASR 依赖缺失：请安装 torchaudio"),
        ("edge_tts", "TTS 依赖缺失：请安装 edge-tts"),
        ("miniaudio", "TTS 依赖缺失：请安装 miniaudio"),
    ]
    if cfg.get("whatsapp", {}).get("enabled", False):
        dependency_requirements.append(
            ("websockets", "WhatsApp 通道依赖缺失：请安装 websockets")
        )
    if cfg.get("desktop_voice", {}).get("enable_local_microphone", True):
        dependency_requirements.append(
            ("sounddevice", "桌面麦克风依赖缺失：请安装 sounddevice")
        )

    for module_name, error_message in dependency_requirements:
        if importlib.util.find_spec(module_name) is None:
            errors.append(error_message)

    return errors


def get_server_config(cfg: dict) -> dict:
    """提取服务端配置（host, port 等）。"""
    server = cfg.get("server", {})
    return {
        "host": server.get("host", "0.0.0.0"),
        "port": server.get("port", 8765),
        "secure": server.get("secure", False),
    }
