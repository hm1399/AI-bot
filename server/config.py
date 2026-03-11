"""
AI-Bot 服务端配置
读取 config.yaml 和环境变量，同时为 nanobot 生成所需的 config.json
"""
from __future__ import annotations

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

    return cfg


def generate_nanobot_config(cfg: dict) -> None:
    """根据 config.yaml 生成 nanobot 需要的 config.json。"""
    nanobot_cfg = cfg.get("nanobot", {})
    provider_name = nanobot_cfg.get("provider", "anthropic")

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
            }
        },
        "tools": {
            "exec": {
                "timeout": 60,
            }
        },
    }

    WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)
    with open(NANOBOT_CONFIG_JSON, "w", encoding="utf-8") as f:
        json.dump(config_json, f, indent=2, ensure_ascii=False)


def get_server_config(cfg: dict) -> dict:
    """提取服务端配置（host, port 等）。"""
    server = cfg.get("server", {})
    return {
        "host": server.get("host", "0.0.0.0"),
        "port": server.get("port", 8765),
    }
