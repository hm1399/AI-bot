# AI-Bot

AI-Bot is a hardware-plus-software desktop assistant project built around an ESP32-S3 device, a Python backend, and a Flutter control app. The current main path in this repository is:

- `firmware/arduino/demo/` for the robot firmware
- `server/` for the Python runtime, app API, voice pipeline, and agent logic
- `app/` for the Flutter operator app

The repository also contains course artifacts, hardware design files, planning documents, and older reference snapshots. Those are useful for context, but they are not the current runtime entry path.

## What Is Implemented Now

### Flutter app

The Flutter app is no longer just a placeholder. The current app ships a multi-page desktop workspace backed by the `app-v1` HTTP and WebSocket contract.

- `Connect`: backend connection form, HTTPS/WSS toggle, and desktop USB pairing flow for the robot
- `Home`: runtime overview, quick actions, device status, queue state, todo/calendar summaries, and capability snapshots
- `Chat`: session-based chat, scene/persona switching, voice trigger entry points, and session management
- `Agenda`: month calendar plus day schedule for agenda-facing events and reminder slots
- `Tasks`: planning workbench for tasks, events, reminders, conflicts, and timeline editing
- `Control`: device controls, reminder and notification panels, physical interaction history, and computer-action approvals
- `Settings`: theme mode, LLM settings, voice/device options, runtime flags, and scene/persona settings
- `Demo mode`: separate from the live backend flow

### Python backend

The backend is an `aiohttp` application, not a React/Node app server and not FastAPI. It currently provides:

- `app-v1` REST endpoints for bootstrap, settings, sessions, chat messages, tasks, events, reminders, planning, runtime state, computer control, device pairing, and capabilities
- WebSocket event streaming at `/ws/app/v1/events`
- Device WebSocket handling for the ESP32 at `/ws/device`
- Embedded desktop microphone support in the main backend process when enabled
- A Nanobot-derived agent runtime backed by LiteLLM-compatible providers
- Local planning/task/reminder/event storage under `server/workspace/`
- Optional computer control with allowlists and macOS-focused permission guidance
- Optional weather, web search, MCP server wiring, cron wiring, and WhatsApp bridge integration

### Firmware and hardware

The firmware directory contains the active Arduino demo sketch and a set of hardware test sketches:

- `firmware/arduino/demo/`: the current demo firmware
- `firmware/arduino/test*`: focused diagnostic sketches used during bring-up

Hardware design and reference material are kept in:

- `原理图设计/`
- `硬件设计文件/`
- `元件资料区/`
- `images/`

## Current Architecture

```text
ESP32-S3 device
  -> streams audio/events over WebSocket
Python backend (server/)
  -> ASR + agent loop + planning/runtime services + device/app APIs
Flutter app (app/)
  -> connects over HTTP + WebSocket to monitor and control the system

Optional side channels
  -> desktop microphone path
  -> WhatsApp bridge
  -> computer control
```

## Tech Stack

### App

- Flutter
- Hook Riverpod
- GoRouter
- `http`
- `web_socket_channel`
- `flutter_libserialport` for desktop pairing

### Backend

- Python 3
- `aiohttp`
- LiteLLM-backed agent provider integration
- FunASR / SenseVoice for ASR
- `edge-tts` and `miniaudio` for speech synthesis/playback handling
- JSON + SQLite-backed workspace persistence

### Optional bridge

- Node.js 20+
- TypeScript
- Baileys-based WhatsApp bridge

## Repository Layout

| Path | Purpose |
| --- | --- |
| `app/` | Flutter app used to connect to the backend and operate the system |
| `server/` | Python backend, agent runtime, voice pipeline, app API, and workspace data |
| `firmware/` | Arduino firmware and hardware test sketches |
| `功能讨论区/` | Internal planning and implementation notes |
| `presentation/` | Presentation drafts and requirement material |
| `原理图设计/`, `硬件设计文件/`, `元件资料区/` | Hardware design exports and component references |
| `nanobot-src/` | Upstream/reference snapshot, not the current runtime path |

## Local-Only Directories

Some repository-root directories are intentionally machine-local and should not be uploaded to GitHub:

- `.claude/` stores local Claude command metadata used on a specific workstation
- `.manager/` stores local manager runtime state such as PID and log files

These directories are not part of the runtime source of truth. For active development and execution, use `app/`, `server/`, `firmware/arduino/demo/`, and `manager.sh`.

## Runtime Defaults In This Checkout

The checked `server/config.yaml` currently uses:

- backend host `0.0.0.0`
- backend port `8765`
- LLM provider `openrouter`
- model `x-ai/grok-4.1-fast`
- ASR model `FunAudioLLM/SenseVoiceSmall`
- TTS voice `en-US-AriaNeural`
- `computer_control.enabled = true`
- `whatsapp.enabled = false`
- `cron.enabled = false`
- `storage.session_storage_mode = dual`
- `storage.planning_storage_mode = dual`

Treat those as the repository defaults, not as hard architectural limits.

## Prerequisites

### Main local workflow

The repository ships a macOS-first manager script at `./manager.sh`. That is the most complete local workflow right now.

Required for the standard path:

- Python 3
- Flutter
- macOS for `./manager.sh`

Optional depending on features you enable:

- Node.js 20+ for the WhatsApp bridge
- valid provider/API tokens in `server/.env` or `server/config.yaml`

Common environment-backed values in the current server config include:

- `OPENROUTER_API_KEY`
- `APP_AUTH_TOKEN`
- `DEVICE_AUTH_TOKEN`
- `OPENWEATHERMAP_API_KEY`
- `BRAVE_API_KEY`

## Quick Start

### Recommended: macOS manager flow

```bash
./manager.sh doctor
./manager.sh update
./manager.sh dev
```

Useful manager commands:

- `./manager.sh app-dev`
- `./manager.sh server-dev`
- `./manager.sh server-start`
- `./manager.sh backend-restart`
- `./manager.sh bridge-start`
- `./manager.sh logs server`
- `./manager.sh stop`
- `./manager.sh build-macos`

The manager script:

- creates and uses `server/.venv`
- installs Python dependencies from `server/requirements.txt`
- runs `flutter pub get` in `app/`
- treats the WhatsApp bridge as optional
- waits for `/api/health` to report `ready=true`

### Manual backend startup

```bash
cd server
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python main.py
```

Important backend endpoints:

- health: `http://127.0.0.1:8765/api/health`
- app bootstrap: `http://127.0.0.1:8765/api/app/v1/bootstrap`
- app events: `ws://127.0.0.1:8765/ws/app/v1/events`
- device socket: `ws://127.0.0.1:8765/ws/device`

### Manual Flutter app startup

```bash
cd app
flutter pub get
flutter run -d macos
```

Other desktop targets are scaffolded in the Flutter project as well:

```bash
flutter run -d windows
flutter run -d linux
```

The desktop USB pairing workflow is currently the most complete operator flow.

### Optional WhatsApp bridge

```bash
cd server/bridge
npm install
npm run build
npm start
```

This bridge is optional. The repository's current main path does not depend on WhatsApp being enabled.

## Configuration Notes

- Main backend config lives in `server/config.yaml`
- `server/.env` is loaded before config placeholders are resolved
- Startup validation also expects `server/workspace/SOUL.md`
- Session, planning, and runtime data are stored under `server/workspace/`
- The checked configuration uses dual storage for sessions and planning, so JSON/JSONL files and SQLite can coexist

Relevant workspace areas:

- `server/workspace/sessions/`
- `server/workspace/runtime/`
- `server/workspace/state.sqlite3`
- `server/workspace/config.json`

## Testing

Test suites exist, even though this README update did not run them:

- Flutter tests: `app/test/`
- Backend tests: `server/tests/`

Typical commands:

```bash
cd app
flutter test
```

```bash
cd server
.venv/bin/python -m unittest discover tests
```

## Notes About Legacy Material

Some repository content reflects earlier prototypes or upstream reference code:

- `nanobot-src/` is useful as an upstream/reference snapshot
- several planning and hardware directories use Chinese names because they are internal project artifacts

When in doubt, use `app/`, `server/`, `firmware/arduino/demo/`, and `manager.sh` as the current source of truth for the running system.
