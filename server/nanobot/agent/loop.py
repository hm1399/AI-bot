"""Agent loop: the core processing engine."""

from __future__ import annotations

import asyncio
import json
import re
import weakref
from contextlib import AsyncExitStack
from copy import deepcopy
from pathlib import Path
from typing import TYPE_CHECKING, Any, Awaitable, Callable
from urllib.parse import quote_plus

from loguru import logger

from nanobot.agent.context import ContextBuilder
from nanobot.agent.memory import MemoryStore
from nanobot.agent.subagent import SubagentManager
from nanobot.agent.tools.computer_control import ComputerControlTool
from nanobot.agent.tools.cron import CronTool
from nanobot.agent.tools.filesystem import EditFileTool, ListDirTool, ReadFileTool, WriteFileTool
from nanobot.agent.tools.message import MessageTool
from nanobot.agent.tools.planning import PlanningTool
from nanobot.agent.tools.registry import ToolRegistry
from nanobot.agent.tools.shell import ExecTool
from nanobot.agent.tools.spawn import SpawnTool
from nanobot.agent.tools.web import WebFetchTool, WebSearchTool
from nanobot.bus.events import InboundMessage, OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.providers.base import LLMProvider
from nanobot.session.manager import Session, SessionManager

if TYPE_CHECKING:
    from nanobot.config.schema import ChannelsConfig, ExecToolConfig
    from nanobot.cron.service import CronService
    from nanobot.agent.tools.computer_control import ComputerControlBackend
    from nanobot.agent.tools.planning import PlanningBackend


_DIRECT_OPEN_APP_EN_RE = re.compile(
    r"^\s*(?:please\s+)?(?:(?:can|could|would)\s+you\s+)?"
    r"(?:help\s+me\s+)?(?:to\s+)?"
    r"(?P<verb>open(?:\s+up)?|launch|start|bring\s+up|focus)\s+"
    r"(?:the\s+)?(?P<target>.+?)\s*$",
    re.IGNORECASE,
)
_DIRECT_OPEN_APP_ZH_RE = re.compile(
    r"(?:帮我|請|请|麻烦你|麻煩你|可以)?\s*"
    r"(?:打开|打開|开启|開啟|启动|啟動|开一下|開一下|唤起|喚起)\s*(?P<target>.+)"
)
_DIRECT_OPEN_APP_NEGATIVE_RE = re.compile(
    r"\b(?:why|how|what|where|when|failed|failure|timeout|timed\s+out)\b"
    r"|(?:为什么|為什麼|为何|為何|怎么|怎麼|没打开|沒打開|打不开|打不開|无法|無法|不能|失败|失敗|超时|超時)"
)
_DIRECT_OPEN_APP_SCHEDULE_RE = re.compile(
    r"\b(?:remind|schedule|later|tomorrow|tonight|today\s+at|at\s+\d|after\s+\d|in\s+\d|every)\b"
    r"|(?:提醒|定时|定時|安排|稍后|稍後|等会|等會|待会|待會|明天|后天|後天|今晚|每天|每周|每週|\d+\s*点|\d+\s*點|分钟后|分鐘後|小时后|小時後)"
)
_DIRECT_GOOGLE_SEARCH_EN_RE = re.compile(
    r"\bopen\s+"
    r"(?:google(?:\s+com|\.com)?|go\s*com|gocom|google\s+chrome|chrome|browser|safari)\b"
    r".*?\b(?:help\s*m(?:e|i)|helpme|helpmi)?\s*"
    r"search(?:\s+(?:for|about))?\s+(?P<query>.+?)\s*$",
    re.IGNORECASE,
)
_DIRECT_ANY_SEARCH_EN_RE = re.compile(
    r"\b(?:help\s*m(?:e|i)|helpme|helpmi)?\s*"
    r"(?:search|research|look\s+up|google)"
    r"(?:\s+(?:for|about))?\s+(?P<query>.+?)\s*$",
    re.IGNORECASE,
)
_DIRECT_GOOGLE_AND_QUERY_EN_RE = re.compile(
    r"\bopen\s+"
    r"(?:google(?:\s+com|\.com)?|go\s*com|gocom|google\s+chrome|chrome|browser|safari)\b"
    r"\s+(?:and|for|to)\s+(?P<query>.+?)\s*$",
    re.IGNORECASE,
)
_DIRECT_GOOGLE_SEARCH_ZH_RE = re.compile(
    r"(?:打开|打開|开启|開啟|启动|啟動)\s*"
    r"(?:google|谷歌|浏览器|瀏覽器|chrome|safari|网页|網頁).*?"
    r"(?:搜索|搜一下|查一下|查询|查詢)\s*(?P<query>.+?)\s*$",
    re.IGNORECASE,
)


class AgentLoop:
    """
    The agent loop is the core processing engine.

    It:
    1. Receives messages from the bus
    2. Builds context with history, memory, skills
    3. Calls the LLM
    4. Executes tool calls
    5. Sends responses back
    """

    _TOOL_RESULT_MAX_CHARS = 500

    def __init__(
        self,
        bus: MessageBus,
        provider: LLMProvider,
        workspace: Path,
        model: str | None = None,
        max_iterations: int = 40,
        temperature: float = 0.1,
        max_tokens: int = 4096,
        memory_window: int = 100,
        reasoning_effort: str | None = None,
        brave_api_key: str | None = None,
        web_proxy: str | None = None,
        exec_config: ExecToolConfig | None = None,
        cron_service: CronService | None = None,
        restrict_to_workspace: bool = False,
        session_manager: SessionManager | None = None,
        mcp_servers: dict | None = None,
        channels_config: ChannelsConfig | None = None,
        planning_backend: PlanningBackend | None = None,
        computer_control_backend: ComputerControlBackend | None = None,
    ):
        from nanobot.config.schema import ExecToolConfig
        self.bus = bus
        self.channels_config = channels_config
        self.provider = provider
        self.workspace = workspace
        self.model = model or provider.get_default_model()
        self.max_iterations = max_iterations
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.memory_window = memory_window
        self.reasoning_effort = reasoning_effort
        self.brave_api_key = brave_api_key
        self.web_proxy = web_proxy
        self.exec_config = exec_config or ExecToolConfig()
        self.cron_service = cron_service
        self.restrict_to_workspace = restrict_to_workspace
        self.planning_backend = planning_backend
        self.computer_control_backend = computer_control_backend

        self.context = ContextBuilder(workspace)
        self.sessions = session_manager or SessionManager(workspace)
        self.tools = ToolRegistry()
        self.subagents = SubagentManager(
            provider=provider,
            workspace=workspace,
            bus=bus,
            model=self.model,
            temperature=self.temperature,
            max_tokens=self.max_tokens,
            reasoning_effort=reasoning_effort,
            brave_api_key=brave_api_key,
            web_proxy=web_proxy,
            exec_config=self.exec_config,
            restrict_to_workspace=restrict_to_workspace,
        )

        self._running = False
        self.task_observer: Any | None = None
        self._mcp_servers = mcp_servers or {}
        self._mcp_stack: AsyncExitStack | None = None
        self._mcp_connected = False
        self._mcp_connecting = False
        self._consolidating: set[str] = set()  # Session keys with consolidation in progress
        self._consolidation_tasks: set[asyncio.Task] = set()  # Strong refs to in-flight tasks
        self._consolidation_locks: weakref.WeakValueDictionary[str, asyncio.Lock] = weakref.WeakValueDictionary()
        self._active_tasks: dict[str, set[asyncio.Task]] = {}  # session_key -> tasks
        self._session_locks: weakref.WeakValueDictionary[str, asyncio.Lock] = weakref.WeakValueDictionary()
        self._register_default_tools()

    def _register_default_tools(self) -> None:
        """Register the default set of tools."""
        allowed_dir = self.workspace if self.restrict_to_workspace else None
        for cls in (ReadFileTool, WriteFileTool, EditFileTool, ListDirTool):
            self.tools.register(cls(workspace=self.workspace, allowed_dir=allowed_dir))
        self.tools.register(ExecTool(
            working_dir=str(self.workspace),
            timeout=self.exec_config.timeout,
            restrict_to_workspace=self.restrict_to_workspace,
            path_append=self.exec_config.path_append,
        ))
        if self.computer_control_backend is not None:
            self.tools.register(ComputerControlTool(self.computer_control_backend))
        self.tools.register(WebSearchTool(api_key=self.brave_api_key, proxy=self.web_proxy))
        self.tools.register(WebFetchTool(proxy=self.web_proxy))
        self.tools.register(MessageTool(send_callback=self.bus.publish_outbound))
        self.tools.register(SpawnTool(manager=self.subagents))
        if self.cron_service:
            self.tools.register(CronTool(self.cron_service))
        if self.planning_backend is not None:
            self.tools.register(PlanningTool(self.planning_backend))

    async def _connect_mcp(self) -> None:
        """Connect to configured MCP servers (one-time, lazy)."""
        if self._mcp_connected or self._mcp_connecting or not self._mcp_servers:
            return
        self._mcp_connecting = True
        from nanobot.agent.tools.mcp import connect_mcp_servers
        try:
            self._mcp_stack = AsyncExitStack()
            await self._mcp_stack.__aenter__()
            await connect_mcp_servers(self._mcp_servers, self.tools, self._mcp_stack)
            self._mcp_connected = True
        except Exception as e:
            logger.error("Failed to connect MCP servers (will retry next message): {}", e)
            if self._mcp_stack:
                try:
                    await self._mcp_stack.aclose()
                except Exception:
                    pass
                self._mcp_stack = None
        finally:
            self._mcp_connecting = False

    def _set_tool_context(
        self,
        channel: str,
        chat_id: str,
        message_id: str | None = None,
        task_id: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        """Update context for all tools that need routing info."""
        runtime_metadata = ContextBuilder.extract_runtime_metadata(metadata)
        for name in ("message", "spawn", "cron", "planning", "computer_control"):
            if tool := self.tools.get(name):
                if hasattr(tool, "set_context"):
                    if name in {"planning", "computer_control"}:
                        tool.set_context(
                            channel,
                            chat_id,
                            message_id,
                            task_id,
                            metadata=runtime_metadata,
                        )
                    elif name == "message":
                        tool.set_context(channel, chat_id, message_id, task_id)
                    elif name == "spawn":
                        tool.set_context(channel, chat_id)
                    else:
                        tool.set_context(channel, chat_id)

    def _start_turn_tools(self) -> None:
        """Reset any tool-local per-turn state before an agent turn."""
        for tool_name in self.tools.tool_names:
            tool = self.tools.get(tool_name)
            start_turn = getattr(tool, "start_turn", None)
            if callable(start_turn):
                start_turn()

    def _collect_turn_tool_results(self) -> dict[str, list[dict[str, Any]]]:
        """Collect structured per-turn tool metadata for outbound/session persistence."""
        results: dict[str, list[dict[str, Any]]] = {}
        for tool_name in self.tools.tool_names:
            tool = self.tools.get(tool_name)
            consume = getattr(tool, "consume_turn_results", None)
            if not callable(consume):
                continue
            payload = consume()
            if payload:
                results[tool_name] = payload
        return results

    @staticmethod
    def _merge_outbound_metadata(
        metadata: dict[str, Any] | None,
        tool_results: dict[str, list[dict[str, Any]]] | None = None,
    ) -> dict[str, Any]:
        merged = dict(metadata or {})
        for key, value in ContextBuilder.extract_runtime_metadata(metadata).items():
            merged.setdefault(key, value)
        if not tool_results:
            return merged

        existing = merged.get("tool_results")
        combined: dict[str, Any] = {}
        if isinstance(existing, dict):
            combined.update(deepcopy(existing))
        for tool_name, payload in tool_results.items():
            combined[tool_name] = deepcopy(payload)
        merged["tool_results"] = combined
        return merged

    async def _notify_task_observer(self, method_name: str, **kwargs: Any) -> None:
        """Safely notify the optional task observer."""
        if not self.task_observer:
            return
        callback = getattr(self.task_observer, method_name, None)
        if callback is None:
            return
        try:
            await callback(**kwargs)
        except Exception:
            logger.exception("Task observer callback failed: {}", method_name)

    def _resolve_session_key(self, msg: InboundMessage, session_key: str | None = None) -> str:
        """Return the canonical session key used for locking and task tracking."""
        if session_key:
            return session_key
        if msg.channel == "system":
            channel, chat_id = (
                msg.chat_id.split(":", 1)
                if ":" in msg.chat_id
                else ("cli", msg.chat_id)
            )
            return f"{channel}:{chat_id}"
        return msg.session_key

    def _get_session_lock(self, session_key: str) -> asyncio.Lock:
        """Get or create the processing lock for a session."""
        lock = self._session_locks.get(session_key)
        if lock is None:
            lock = asyncio.Lock()
            self._session_locks[session_key] = lock
        return lock

    def _track_active_task(self, session_key: str, task: asyncio.Task) -> None:
        """Track a task so /stop can cancel it by session."""
        self._active_tasks.setdefault(session_key, set()).add(task)

        def _cleanup(done_task: asyncio.Task, key: str = session_key) -> None:
            tasks = self._active_tasks.get(key)
            if not tasks:
                return
            tasks.discard(done_task)
            if not tasks:
                self._active_tasks.pop(key, None)

        task.add_done_callback(_cleanup)

    @staticmethod
    def _strip_think(text: str | None) -> str | None:
        """Remove <think>…</think> blocks that some models embed in content."""
        if not text:
            return None
        return re.sub(r"<think>[\s\S]*?</think>", "", text).strip() or None

    @staticmethod
    def _tool_hint(tool_calls: list) -> str:
        """Format tool calls as concise hint, e.g. 'web_search("query")'."""
        def _fmt(tc):
            args = (tc.arguments[0] if isinstance(tc.arguments, list) else tc.arguments) or {}
            val = next(iter(args.values()), None) if isinstance(args, dict) else None
            if not isinstance(val, str):
                return tc.name
            return f'{tc.name}("{val[:40]}…")' if len(val) > 40 else f'{tc.name}("{val}")'
        return ", ".join(_fmt(tc) for tc in tool_calls)

    async def _maybe_handle_direct_computer_control(
        self,
        msg: InboundMessage,
        *,
        session: Session,
        session_key: str,
    ) -> OutboundMessage | None:
        """Handle low-risk, explicit computer-control commands before the LLM."""
        command = self._parse_direct_computer_control_command(msg.content)
        if command is None:
            return None

        backend = self.computer_control_backend
        if backend is None:
            response_text = self._direct_computer_control_reply(
                app=str(command.get("app") or "app"),
                action=command["action"],
                search_query=command.get("search_query"),
                status="failed",
                metadata=msg.metadata,
                error_message="computer control is not available",
            )
            result = {
                "action": command["action"],
                "status": "failed",
                "error": {
                    "code": "adapter_unavailable",
                    "message": "computer control is not available",
                },
                "metadata": ContextBuilder.extract_runtime_metadata(msg.metadata),
            }
            return self._persist_direct_computer_control_turn(
                msg,
                session=session,
                response_text=response_text,
                result=result,
            )

        runtime_metadata = ContextBuilder.extract_runtime_metadata(msg.metadata)
        request_metadata = {
            **runtime_metadata,
            "direct_intent": command["action"],
            "direct_intent_source": "agent_pre_llm",
        }
        app = str(command.get("app") or "").strip()
        if app:
            request_metadata["target_app"] = app
        url = str(command.get("url") or "").strip()
        if url:
            request_metadata["target_url"] = url
        search_query = str(command.get("search_query") or "").strip()
        if search_query:
            request_metadata["search_query"] = search_query

        target: dict[str, Any] = {}
        if command["action"] == "open_app" and app:
            target["app"] = app
        elif command["action"] == "open_url" and url:
            target["url"] = url
        payload = {
            "action": command["action"],
            "target": target,
            "created_via": "agent_direct_intent",
            "requested_via": self._direct_computer_control_requested_via(msg),
            "source_channel": msg.channel,
            "source_session_id": session_key,
            "source_message_id": msg.metadata.get("message_id"),
            "task_id": msg.metadata.get("task_id"),
            "reason": msg.content,
            "metadata": request_metadata,
        }

        try:
            result = await backend.request_action(payload)
        except Exception as exc:  # noqa: BLE001 - adapters surface product errors as exceptions.
            result = {
                "action": command["action"],
                "status": "failed",
                "error": self._computer_control_exception_payload(exc),
                "metadata": request_metadata,
            }

        if not isinstance(result, dict):
            result = {
                "action": command["action"],
                "status": "failed",
                "error": {
                    "code": "invalid_backend_response",
                    "message": "computer control backend returned an invalid response",
                },
                "metadata": request_metadata,
            }

        resolved_app = self._app_name_from_computer_control_result(result, fallback=app)
        response_text = self._direct_computer_control_reply(
            app=resolved_app or app or "app",
            action=command["action"],
            search_query=command.get("search_query"),
            target_url=url or None,
            status=str(result.get("status") or ""),
            metadata=msg.metadata,
            error_message=self._computer_control_error_message(result),
        )
        return self._persist_direct_computer_control_turn(
            msg,
            session=session,
            response_text=response_text,
            result=result,
        )

    def _parse_direct_computer_control_command(self, content: str) -> dict[str, str] | None:
        search_command = self._parse_direct_web_search_command(content)
        if search_command is not None:
            return search_command

        if not self._looks_like_direct_open_app_request(content):
            return None
        app = self._resolve_direct_open_app_target(content)
        if app is None:
            return None
        return {
            "action": "open_app",
            "app": app,
        }

    def _parse_direct_web_search_command(self, content: str) -> dict[str, str] | None:
        if not self._looks_like_direct_control_request(content):
            return None
        for pattern in (
            _DIRECT_GOOGLE_SEARCH_EN_RE,
            _DIRECT_ANY_SEARCH_EN_RE,
            _DIRECT_GOOGLE_AND_QUERY_EN_RE,
            _DIRECT_GOOGLE_SEARCH_ZH_RE,
        ):
            match = pattern.search(content)
            if not match:
                continue
            query = self._clean_direct_search_query(match.group("query"))
            if not query:
                continue
            return {
                "action": "open_url",
                "url": f"https://www.google.com/search?q={quote_plus(query)}",
                "search_query": query,
            }
        return None

    def _looks_like_direct_control_request(self, content: str) -> bool:
        cleaned = str(content or "").strip()
        if not cleaned:
            return False
        lowered = cleaned.casefold()
        if _DIRECT_OPEN_APP_NEGATIVE_RE.search(lowered):
            return False
        if _DIRECT_OPEN_APP_SCHEDULE_RE.search(lowered):
            return False
        return True

    def _looks_like_direct_open_app_request(self, content: str) -> bool:
        if not self._looks_like_direct_control_request(content):
            return False
        return bool(
            _DIRECT_OPEN_APP_EN_RE.search(content)
            or _DIRECT_OPEN_APP_ZH_RE.search(content)
        )

    def _resolve_direct_open_app_target(self, content: str) -> str | None:
        backend = self.computer_control_backend
        policy = getattr(backend, "policy", None)
        infer_allowed_app = getattr(policy, "infer_allowed_app", None)
        if callable(infer_allowed_app):
            inferred = infer_allowed_app(content)
            if isinstance(inferred, str) and inferred.strip():
                return inferred.strip()

        candidate = self._direct_open_app_candidate(content)
        resolve_allowed_app = getattr(policy, "resolve_allowed_app", None)
        if candidate and callable(resolve_allowed_app):
            resolved = resolve_allowed_app(candidate)
            if isinstance(resolved, str) and resolved.strip():
                return resolved.strip()
        return candidate

    @staticmethod
    def _clean_direct_search_query(value: Any) -> str | None:
        query = str(value or "").strip()
        query = re.sub(r"(?i)\s+(?:for\s+me|please|now)\s*$", "", query).strip()
        query = query.strip(" \t\r\n\"'“”‘’.,!?！？。")
        return query or None

    @staticmethod
    def _direct_open_app_candidate(content: str) -> str | None:
        for pattern in (_DIRECT_OPEN_APP_EN_RE, _DIRECT_OPEN_APP_ZH_RE):
            match = pattern.search(content)
            if not match:
                continue
            candidate = str(match.group("target") or "").strip()
            candidate = re.sub(
                r"(?i)\s+(?:for\s+me|please|now|app|application)\s*$",
                "",
                candidate,
            ).strip()
            candidate = candidate.strip(" \t\r\n\"'“”‘’.,!?！？。")
            if candidate:
                return candidate
        return None

    @staticmethod
    def _direct_computer_control_requested_via(msg: InboundMessage) -> str:
        source = str(msg.metadata.get("source") or "").strip()
        if source:
            return source
        if msg.channel in {"device", "desktop_voice"}:
            return "voice"
        return msg.channel or "agent"

    @staticmethod
    def _computer_control_exception_payload(exc: Exception) -> dict[str, Any]:
        to_dict = getattr(exc, "to_dict", None)
        if callable(to_dict):
            payload = to_dict()
            if isinstance(payload, dict):
                return payload
        return {
            "code": getattr(exc, "code", exc.__class__.__name__),
            "message": str(exc) or "computer control action failed",
        }

    @staticmethod
    def _app_name_from_computer_control_result(
        result: dict[str, Any],
        *,
        fallback: str | None = None,
    ) -> str | None:
        for container_key in ("arguments", "target"):
            container = result.get(container_key)
            if isinstance(container, dict):
                app = str(container.get("app") or "").strip()
                if app:
                    return app
        result_payload = result.get("result")
        if isinstance(result_payload, dict):
            for key in ("opened", "focused_app", "app"):
                app = str(result_payload.get(key) or "").strip()
                if app:
                    return app
        return str(fallback or "").strip() or None

    @staticmethod
    def _computer_control_error_message(result: dict[str, Any]) -> str | None:
        error = result.get("error")
        if isinstance(error, dict):
            return str(error.get("message") or error.get("code") or "").strip() or None
        if isinstance(error, str):
            return error.strip() or None
        return None

    @classmethod
    def _direct_computer_control_reply(
        cls,
        *,
        app: str,
        action: str | None = None,
        search_query: str | None = None,
        target_url: str | None = None,
        status: str,
        metadata: dict[str, Any] | None = None,
        error_message: str | None = None,
    ) -> str:
        prefer_english = cls._prefers_english_reply(metadata)
        normalized_status = status.strip().lower()
        normalized_action = str(action or "").strip()
        query = str(search_query or "").strip()
        app_name = app.strip() or ("the app" if prefer_english else "应用")
        if normalized_status == "completed":
            if normalized_action == "open_url" and query:
                return (
                    f"Opened Google search for {query}."
                    if prefer_english
                    else f"已打开 Google 搜索：{query}。"
                )
            if normalized_action == "open_url":
                target = str(target_url or "").strip() or "the page"
                return f"Opened {target}." if prefer_english else f"已打开 {target}。"
            return f"Opened {app_name}." if prefer_english else f"已打开 {app_name}。"
        if normalized_status == "awaiting_confirmation":
            if normalized_action == "open_url" and query:
                return (
                    f"Ready to search Google for {query}. Please confirm first."
                    if prefer_english
                    else f"已准备搜索 {query}，请先确认。"
                )
            return (
                f"Ready to open {app_name}. Please confirm first."
                if prefer_english
                else f"已准备打开 {app_name}，请先确认。"
            )
        detail = error_message or (
            "computer control action failed"
            if prefer_english
            else "电脑控制动作失败"
        )
        if normalized_action == "open_url" and query:
            return (
                f"I couldn't open Google search for {query}: {detail}."
                if prefer_english
                else f"没能打开 Google 搜索 {query}：{detail}。"
            )
        return (
            f"I couldn't open {app_name}: {detail}."
            if prefer_english
            else f"没能打开 {app_name}：{detail}。"
        )

    @staticmethod
    def _prefers_english_reply(metadata: dict[str, Any] | None = None) -> bool:
        reply_language = str((metadata or {}).get("reply_language") or "").strip().lower()
        if reply_language.startswith("en") or reply_language.startswith("english"):
            return True
        if reply_language.startswith("zh") or reply_language.startswith("chinese"):
            return False
        return False

    def _persist_direct_computer_control_turn(
        self,
        msg: InboundMessage,
        *,
        session: Session,
        response_text: str,
        result: dict[str, Any],
    ) -> OutboundMessage:
        tool_results = {"computer_control": [deepcopy(result)]}
        self._save_turn(
            session,
            [
                {"role": "user", "content": msg.content},
                {"role": "assistant", "content": response_text},
            ],
            0,
            msg_metadata=msg.metadata,
            assistant_tool_results=tool_results,
        )
        self.sessions.save(session)
        return OutboundMessage(
            channel=msg.channel,
            chat_id=msg.chat_id,
            content=response_text,
            metadata=self._merge_outbound_metadata(msg.metadata, tool_results),
        )

    async def _run_agent_loop(
        self,
        initial_messages: list[dict],
        on_progress: Callable[..., Awaitable[None]] | None = None,
    ) -> tuple[str | None, list[str], list[dict]]:
        """Run the agent iteration loop. Returns (final_content, tools_used, messages)."""
        messages = initial_messages
        iteration = 0
        final_content = None
        tools_used: list[str] = []

        while iteration < self.max_iterations:
            iteration += 1

            response = await self.provider.chat(
                messages=messages,
                tools=self.tools.get_definitions(),
                model=self.model,
                temperature=self.temperature,
                max_tokens=self.max_tokens,
                reasoning_effort=self.reasoning_effort,
            )

            if response.has_tool_calls:
                if on_progress:
                    clean = self._strip_think(response.content)
                    if clean:
                        await on_progress(clean)
                    await on_progress(self._tool_hint(response.tool_calls), tool_hint=True)

                tool_call_dicts = [
                    {
                        "id": tc.id,
                        "type": "function",
                        "function": {
                            "name": tc.name,
                            "arguments": json.dumps(tc.arguments, ensure_ascii=False)
                        }
                    }
                    for tc in response.tool_calls
                ]
                messages = self.context.add_assistant_message(
                    messages, response.content, tool_call_dicts,
                    reasoning_content=response.reasoning_content,
                    thinking_blocks=response.thinking_blocks,
                )

                for tool_call in response.tool_calls:
                    tools_used.append(tool_call.name)
                    args_str = json.dumps(tool_call.arguments, ensure_ascii=False)
                    logger.info("Tool call: {}({})", tool_call.name, args_str[:200])
                    result = await self.tools.execute(tool_call.name, tool_call.arguments)
                    messages = self.context.add_tool_result(
                        messages, tool_call.id, tool_call.name, result
                    )
            else:
                clean = self._strip_think(response.content)
                # Don't persist error responses to session history — they can
                # poison the context and cause permanent 400 loops (#1303).
                if response.finish_reason == "error":
                    logger.error("LLM returned error: {}", (clean or "")[:200])
                    final_content = clean or "Sorry, I encountered an error calling the AI model."
                    break
                messages = self.context.add_assistant_message(
                    messages, clean, reasoning_content=response.reasoning_content,
                    thinking_blocks=response.thinking_blocks,
                )
                final_content = clean
                break

        if final_content is None and iteration >= self.max_iterations:
            logger.warning("Max iterations ({}) reached", self.max_iterations)
            final_content = (
                f"I reached the maximum number of tool call iterations ({self.max_iterations}) "
                "without completing the task. You can try breaking the task into smaller steps."
            )

        return final_content, tools_used, messages

    async def run(self) -> None:
        """Run the agent loop, dispatching messages as tasks to stay responsive to /stop."""
        self._running = True
        await self._connect_mcp()
        logger.info("Agent loop started")

        while self._running:
            try:
                msg = await asyncio.wait_for(self.bus.consume_inbound(), timeout=1.0)
            except asyncio.TimeoutError:
                continue

            session_key = self._resolve_session_key(msg)
            if msg.content.strip().lower() == "/stop":
                await self._handle_stop(msg, session_key=session_key)
            else:
                task = asyncio.create_task(self._dispatch(msg, session_key=session_key))
                self._track_active_task(session_key, task)

    async def _handle_stop(self, msg: InboundMessage, session_key: str | None = None) -> None:
        """Cancel all active tasks and subagents for the session."""
        target_session_key = self._resolve_session_key(msg, session_key=session_key)
        tasks = list(self._active_tasks.pop(target_session_key, set()))
        cancelled = sum(1 for t in tasks if not t.done() and t.cancel())
        for t in tasks:
            try:
                await t
            except (asyncio.CancelledError, Exception):
                pass
        sub_cancelled = await self.subagents.cancel_by_session(target_session_key)
        total = cancelled + sub_cancelled
        content = f"⏹ Stopped {total} task(s)." if total else "No active task to stop."
        await self.bus.publish_outbound(OutboundMessage(
            channel=msg.channel, chat_id=msg.chat_id, content=content,
        ))

    async def _dispatch(self, msg: InboundMessage, session_key: str | None = None) -> None:
        """Process a message under a session-scoped lock."""
        target_session_key = self._resolve_session_key(msg, session_key=session_key)
        lock = self._get_session_lock(target_session_key)
        async with lock:
            try:
                await self._notify_task_observer(
                    "on_task_started",
                    msg=msg,
                    session_key=target_session_key,
                )
                response = await self._process_message(msg, session_key=target_session_key)
                if response is not None:
                    await self.bus.publish_outbound(response)
                elif msg.channel == "cli":
                    await self.bus.publish_outbound(OutboundMessage(
                        channel=msg.channel, chat_id=msg.chat_id,
                        content="", metadata=msg.metadata or {},
                    ))
                await self._notify_task_observer(
                    "on_task_finished",
                    msg=msg,
                    session_key=target_session_key,
                    response=response,
                )
            except asyncio.CancelledError:
                await self._notify_task_observer(
                    "on_task_cancelled",
                    msg=msg,
                    session_key=target_session_key,
                )
                logger.info("Task cancelled for session {}", msg.session_key)
                raise
            except Exception:
                await self._notify_task_observer(
                    "on_task_failed",
                    msg=msg,
                    session_key=target_session_key,
                    error="processing_error",
                )
                logger.exception("Error processing message for session {}", msg.session_key)
                await self.bus.publish_outbound(OutboundMessage(
                    channel=msg.channel, chat_id=msg.chat_id,
                    content="Sorry, I encountered an error.",
                    metadata=msg.metadata or {},
                ))

    async def close_mcp(self) -> None:
        """Close MCP connections."""
        if self._mcp_stack:
            try:
                await self._mcp_stack.aclose()
            except (RuntimeError, BaseExceptionGroup):
                pass  # MCP SDK cancel scope cleanup is noisy but harmless
            self._mcp_stack = None

    def stop(self) -> None:
        """Stop the agent loop."""
        self._running = False
        logger.info("Agent loop stopping")

    async def _process_message(
        self,
        msg: InboundMessage,
        session_key: str | None = None,
        on_progress: Callable[[str], Awaitable[None]] | None = None,
    ) -> OutboundMessage | None:
        """Process a single inbound message and return the response."""
        resolved_session_key = self._resolve_session_key(msg, session_key=session_key)
        # System messages: parse origin from chat_id ("channel:chat_id")
        if msg.channel == "system":
            channel, chat_id = (msg.chat_id.split(":", 1) if ":" in msg.chat_id
                                else ("cli", msg.chat_id))
            logger.info("Processing system message from {}", msg.sender_id)
            session = self.sessions.get_or_create(resolved_session_key)
            self._set_tool_context(
                channel,
                chat_id,
                msg.metadata.get("message_id"),
                msg.metadata.get("task_id"),
                msg.metadata,
            )
            self._start_turn_tools()
            history = session.get_history(max_messages=self.memory_window)
            messages = self.context.build_messages(
                history=history,
                current_message=msg.content, channel=channel, chat_id=chat_id,
                metadata=msg.metadata,
            )
            final_content, _, all_msgs = await self._run_agent_loop(messages)
            tool_results = self._collect_turn_tool_results()
            self._save_turn(
                session,
                all_msgs,
                1 + len(history),
                msg_metadata=msg.metadata,
                assistant_tool_results=tool_results,
            )
            self.sessions.save(session)
            return OutboundMessage(
                channel=channel,
                chat_id=chat_id,
                content=final_content or "Background task completed.",
                metadata=self._merge_outbound_metadata(msg.metadata, tool_results),
            )

        preview = msg.content[:80] + "..." if len(msg.content) > 80 else msg.content
        logger.info("Processing message from {}:{}: {}", msg.channel, msg.sender_id, preview)

        session = self.sessions.get_or_create(resolved_session_key)

        # Slash commands
        cmd = msg.content.strip().lower()
        if cmd == "/new":
            lock = self._consolidation_locks.setdefault(session.key, asyncio.Lock())
            self._consolidating.add(session.key)
            try:
                async with lock:
                    snapshot = session.messages[session.last_consolidated:]
                    if snapshot:
                        temp = Session(key=session.key)
                        temp.messages = list(snapshot)
                        if not await self._consolidate_memory(temp, archive_all=True):
                            return OutboundMessage(
                                channel=msg.channel, chat_id=msg.chat_id,
                                content="Memory archival failed, session not cleared. Please try again.",
                            )
            except Exception:
                logger.exception("/new archival failed for {}", session.key)
                return OutboundMessage(
                    channel=msg.channel, chat_id=msg.chat_id,
                    content="Memory archival failed, session not cleared. Please try again.",
                )
            finally:
                self._consolidating.discard(session.key)

            session.clear()
            self.sessions.save(session)
            self.sessions.invalidate(session.key)
            return OutboundMessage(channel=msg.channel, chat_id=msg.chat_id,
                                  content="New session started.")
        if cmd == "/help":
            return OutboundMessage(channel=msg.channel, chat_id=msg.chat_id,
                                  content="🐈 nanobot commands:\n/new — Start a new conversation\n/stop — Stop the current task\n/help — Show available commands")

        direct_response = await self._maybe_handle_direct_computer_control(
            msg,
            session=session,
            session_key=resolved_session_key,
        )
        if direct_response is not None:
            return direct_response

        unconsolidated = len(session.messages) - session.last_consolidated
        if (unconsolidated >= self.memory_window and session.key not in self._consolidating):
            self._consolidating.add(session.key)
            lock = self._consolidation_locks.setdefault(session.key, asyncio.Lock())

            async def _consolidate_and_unlock():
                try:
                    async with lock:
                        await self._consolidate_memory(session)
                finally:
                    self._consolidating.discard(session.key)
                    _task = asyncio.current_task()
                    if _task is not None:
                        self._consolidation_tasks.discard(_task)

            _task = asyncio.create_task(_consolidate_and_unlock())
            self._consolidation_tasks.add(_task)

        self._set_tool_context(
            msg.channel,
            msg.chat_id,
            msg.metadata.get("message_id"),
            msg.metadata.get("task_id"),
            msg.metadata,
        )
        self._start_turn_tools()

        history = session.get_history(max_messages=self.memory_window)
        initial_messages = self.context.build_messages(
            history=history,
            current_message=msg.content,
            media=msg.media if msg.media else None,
            channel=msg.channel, chat_id=msg.chat_id, metadata=msg.metadata,
        )

        async def _bus_progress(content: str, *, tool_hint: bool = False) -> None:
            meta = dict(msg.metadata or {})
            meta["_progress"] = True
            meta["_tool_hint"] = tool_hint
            await self.bus.publish_outbound(OutboundMessage(
                channel=msg.channel, chat_id=msg.chat_id, content=content, metadata=meta,
            ))

        final_content, _, all_msgs = await self._run_agent_loop(
            initial_messages, on_progress=on_progress or _bus_progress,
        )

        if final_content is None:
            final_content = "I've completed processing but have no response to give."

        tool_results = self._collect_turn_tool_results()
        self._save_turn(
            session,
            all_msgs,
            1 + len(history),
            msg_metadata=msg.metadata,
            assistant_tool_results=tool_results,
        )
        self.sessions.save(session)

        if (mt := self.tools.get("message")) and isinstance(mt, MessageTool) and mt.sent_in_turn:
            return None

        preview = final_content[:120] + "..." if len(final_content) > 120 else final_content
        logger.info("Response to {}:{}: {}", msg.channel, msg.sender_id, preview)
        return OutboundMessage(
            channel=msg.channel, chat_id=msg.chat_id, content=final_content,
            metadata=self._merge_outbound_metadata(msg.metadata, tool_results),
        )

    def _save_turn(
        self,
        session: Session,
        messages: list[dict],
        skip: int,
        *,
        msg_metadata: dict[str, Any] | None = None,
        assistant_tool_results: dict[str, list[dict[str, Any]]] | None = None,
    ) -> None:
        """Save new-turn messages into session, truncating large tool results."""
        from datetime import datetime
        msg_metadata = msg_metadata or {}
        runtime_metadata = ContextBuilder.extract_runtime_metadata(msg_metadata)
        user_message_id = msg_metadata.get("message_id")
        assistant_message_id = msg_metadata.get("assistant_message_id")
        task_id = msg_metadata.get("task_id")
        client_message_id = msg_metadata.get("client_message_id")
        user_id_assigned = False
        assistant_id_assigned = False
        assistant_tool_results_assigned = False
        for m in messages[skip:]:
            entry = dict(m)
            role, content = entry.get("role"), entry.get("content")
            if role == "assistant" and not content and not entry.get("tool_calls"):
                continue  # skip empty assistant messages — they poison session context
            if role == "tool" and isinstance(content, str) and len(content) > self._TOOL_RESULT_MAX_CHARS:
                entry["content"] = content[:self._TOOL_RESULT_MAX_CHARS] + "\n... (truncated)"
            elif role == "user":
                if isinstance(content, str) and content.startswith(ContextBuilder._RUNTIME_CONTEXT_TAG):
                    # Strip the runtime-context prefix, keep only the user text.
                    parts = content.split("\n\n", 1)
                    if len(parts) > 1 and parts[1].strip():
                        entry["content"] = parts[1]
                    else:
                        continue
                if isinstance(content, list):
                    filtered = []
                    for c in content:
                        if c.get("type") == "text" and isinstance(c.get("text"), str) and c["text"].startswith(ContextBuilder._RUNTIME_CONTEXT_TAG):
                            continue  # Strip runtime context from multimodal messages
                        if (c.get("type") == "image_url"
                                and c.get("image_url", {}).get("url", "").startswith("data:image/")):
                            filtered.append({"type": "text", "text": "[image]"})
                        else:
                            filtered.append(c)
                    if not filtered:
                        continue
                    entry["content"] = filtered
            if role == "user" and not user_id_assigned:
                if user_message_id:
                    entry.setdefault("message_id", user_message_id)
                if client_message_id:
                    entry.setdefault("client_message_id", client_message_id)
                if task_id:
                    entry.setdefault("task_id", task_id)
                for key, value in runtime_metadata.items():
                    entry.setdefault(key, value)
                user_id_assigned = True
            elif (
                role == "assistant"
                and not entry.get("tool_calls")
                and content
                and not assistant_id_assigned
            ):
                if assistant_message_id:
                    entry.setdefault("message_id", assistant_message_id)
                if task_id:
                    entry.setdefault("task_id", task_id)
                for key, value in runtime_metadata.items():
                    entry.setdefault(key, value)
                assistant_id_assigned = True
                if assistant_tool_results and not assistant_tool_results_assigned:
                    entry["tool_results"] = deepcopy(assistant_tool_results)
                    assistant_tool_results_assigned = True
            entry.setdefault("timestamp", datetime.now().isoformat())
            session.messages.append(entry)
        session.updated_at = datetime.now()

    async def _consolidate_memory(self, session, archive_all: bool = False) -> bool:
        """Delegate to MemoryStore.consolidate(). Returns True on success."""
        return await MemoryStore(self.workspace).consolidate(
            session, self.provider, self.model,
            archive_all=archive_all, memory_window=self.memory_window,
        )

    async def process_direct(
        self,
        content: str,
        session_key: str = "cli:direct",
        channel: str = "cli",
        chat_id: str = "direct",
        on_progress: Callable[[str], Awaitable[None]] | None = None,
    ) -> str:
        """Process a message directly (for CLI or cron usage)."""
        await self._connect_mcp()
        msg = InboundMessage(channel=channel, sender_id="user", chat_id=chat_id, content=content)
        resolved_session_key = self._resolve_session_key(msg, session_key=session_key)
        lock = self._get_session_lock(resolved_session_key)
        async with lock:
            response = await self._process_message(
                msg, session_key=resolved_session_key, on_progress=on_progress
            )
        return response.content if response else ""
