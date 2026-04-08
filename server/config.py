"""
AI-Bot 服务端配置
读取 config.yaml 和环境变量，同时为 nanobot 生成所需的 config.json
"""
from __future__ import annotations

import importlib.util
import os
import json
from pathlib import Path

import yaml


# 项目根目录
SERVER_DIR = Path(__file__).parent
WORKSPACE_DIR = SERVER_DIR / "workspace"
CONFIG_YAML = SERVER_DIR / "config.yaml"
NANOBOT_CONFIG_JSON = WORKSPACE_DIR / "config.json"
ENV_FILE = SERVER_DIR / ".env"
DEFAULT_PROVIDER_TIMEOUT_SECONDS = 90.0


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


def load_yaml_config() -> dict:
    """加载 config.yaml，环境变量可覆盖 API Key。"""
    _load_dotenv()

    if not CONFIG_YAML.exists():
        raise FileNotFoundError(f"配置文件不存在: {CONFIG_YAML}")

    with open(CONFIG_YAML, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    # weather API key 环境变量覆盖
    weather_cfg = cfg.get("weather", {})
    weather_key = weather_cfg.get("api_key", "")
    if weather_key.startswith("${") and weather_key.endswith("}"):
        env_name = weather_key[2:-1]
        weather_key = os.environ.get(env_name, "")
    cfg.setdefault("weather", {})["api_key"] = weather_key

    # device auth token 环境变量覆盖
    device_cfg = cfg.get("device", {})
    device_token = device_cfg.get("auth_token", "")
    if isinstance(device_token, str) and device_token.startswith("${") and device_token.endswith("}"):
        env_name = device_token[2:-1]
        device_token = os.environ.get(env_name, "")
    cfg.setdefault("device", {})["auth_token"] = device_token

    # app auth token 环境变量覆盖
    app_cfg = cfg.get("app", {})
    app_token = app_cfg.get("auth_token", "")
    if isinstance(app_token, str) and app_token.startswith("${") and app_token.endswith("}"):
        env_name = app_token[2:-1]
        app_token = os.environ.get(env_name, "")
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
    api_key = os.environ.get(env_key) or cfg.get("nanobot", {}).get("api_key", "")
    if api_key.startswith("${") and api_key.endswith("}"):
        env_name = api_key[2:-1]
        api_key = os.environ.get(env_name, "")
    cfg.setdefault("nanobot", {})["api_key"] = api_key
    cfg["nanobot"].setdefault("provider_timeout_seconds", DEFAULT_PROVIDER_TIMEOUT_SECONDS)

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


def generate_nanobot_config(cfg: dict) -> None:
    """根据 config.yaml 生成 nanobot 需要的 config.json。"""
    nanobot_cfg = cfg.get("nanobot", {})
    provider_name = nanobot_cfg.get("provider", "anthropic")
    provider_timeout_seconds = get_provider_timeout_seconds(cfg)

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
            "exec": {
                "timeout": 60,
            }
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

    # 设备认证 token 基本校验
    device_token = cfg.get("device", {}).get("auth_token", "")
    if device_token and (not isinstance(device_token, str) or len(device_token.strip()) < 8):
        errors.append("device.auth_token 至少需要 8 个字符，或留空表示关闭设备认证")

    # App 认证 token 基本校验
    app_token = cfg.get("app", {}).get("auth_token", "")
    if app_token and (not isinstance(app_token, str) or len(app_token.strip()) < 8):
        errors.append("app.auth_token 至少需要 8 个字符，或留空表示关闭 App API 认证")

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
    }
