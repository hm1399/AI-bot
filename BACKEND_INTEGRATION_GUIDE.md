# Backend Integration Guide

## Overview

This document reflects the current implementation in this repository and describes how `AI-bot/server` integrates with `AI-bot/app`.

The active integration path is no longer the old React web app or the legacy `/api/config + /ws/app` contract. The real stack in this repo is:

- Frontend: Flutter desktop app
- Backend: Python `aiohttp` service
- App protocol: `app-v1`
- Device protocol: `/ws/device`
- App realtime stream: `/ws/app/v1/events`

## Current System Shape

```text
Flutter App (app/)
  -> HTTP REST: /api/app/v1/*
  -> WebSocket: /ws/app/v1/events

Python Backend (server/)
  -> aiohttp app
  -> AgentLoop / planning / runtime / computer control / device pairing
  -> optional desktop voice bridge
  -> optional WhatsApp bridge

ESP32 Device
  -> WebSocket: /ws/device
```

## Default Runtime Contract

Based on the current `server/config.yaml`, the repository defaults are:

- Host: `0.0.0.0`
- Port: `8765`
- Secure: `false`
- App bootstrap: `/api/app/v1/bootstrap`
- App event stream: `/ws/app/v1/events`
- Device socket: `/ws/device`

Notes:

- `8765` is the current default port, not `8000`
- HTTPS and WSS depend on `server.secure` and any reverse proxy you place in front of the backend
- WhatsApp is an optional side channel and is off by default

## Authentication

### App Auth

If `app.auth_token` is configured, the app may send it in any of these forms:

- `Authorization: Bearer <APP_AUTH_TOKEN>`
- `X-App-Token: <APP_AUTH_TOKEN>`
- Query parameter: `?token=<APP_AUTH_TOKEN>`

If `app.auth_token` is not configured, the backend currently allows the request.

### Device Auth

If `device.auth_token` is configured, the device may send it in any of these forms when connecting to `/ws/device`:

- `Authorization: Bearer <DEVICE_AUTH_TOKEN>`
- `X-Device-Token: <DEVICE_AUTH_TOKEN>`
- Query parameter: `?token=<DEVICE_AUTH_TOKEN>`

If `device.auth_token` is not configured, the backend currently allows the connection.

### Security Notes

- Do not commit real API keys or tokens into repository docs or source files.
- Repository configuration uses environment placeholders such as `${OPENROUTER_API_KEY}`.
- Runtime-generated local state and config files should stay out of Git.

## App Connection Flow

The real Flutter app connection flow is:

1. The user enters `host`, `port`, an optional token, and the HTTPS/WSS toggle on the `Connect` screen.
2. The app requests `GET /api/app/v1/bootstrap`.
3. The backend returns bootstrap state including:
   - `server_version`
   - `capabilities`
   - `agent_runtime`
   - `experience`
   - `planning`
   - `runtime`
   - `sessions`
   - `event_stream`
4. The app then connects to `/ws/app/v1/events` and can resume with `last_event_id`.
5. The main shell updates its pages from the bootstrap payload plus realtime events.

Notes:

- There is no primary `discoverDevices()` LAN scan flow in the current app
- The web build only offers "use current origin" as a helper, not a separate device discovery system

## Core REST Endpoints

These routes come from the active backend implementation, primarily `server/services/app_runtime.py`.

### Bootstrap and Settings

- `GET /api/app/v1/bootstrap`
- `GET /api/app/v1/settings`
- `PUT /api/app/v1/settings`
- `POST /api/app/v1/settings/llm/test`

### Experience, Persona, and Scene

- `GET /api/app/v1/experience`
- `PATCH /api/app/v1/experience`
- `POST /api/app/v1/experience/interactions`

### Sessions and Messages

- `GET /api/app/v1/sessions`
- `POST /api/app/v1/sessions`
- `POST /api/app/v1/sessions/active`
- `GET /api/app/v1/sessions/{session_id}`
- `PATCH /api/app/v1/sessions/{session_id}`
- `GET /api/app/v1/sessions/{session_id}/messages`
- `POST /api/app/v1/sessions/{session_id}/messages`

### Tasks, Events, Notifications, and Reminders

- `GET /api/app/v1/tasks`
- `POST /api/app/v1/tasks`
- `PATCH /api/app/v1/tasks/{task_id}`
- `DELETE /api/app/v1/tasks/{task_id}`
- `GET /api/app/v1/events`
- `POST /api/app/v1/events`
- `PATCH /api/app/v1/events/{event_id}`
- `DELETE /api/app/v1/events/{event_id}`
- `GET /api/app/v1/notifications`
- `PATCH /api/app/v1/notifications/{notification_id}`
- `POST /api/app/v1/notifications/read-all`
- `DELETE /api/app/v1/notifications/{notification_id}`
- `DELETE /api/app/v1/notifications`
- `GET /api/app/v1/reminders`
- `POST /api/app/v1/reminders`
- `PATCH /api/app/v1/reminders/{reminder_id}`
- `POST /api/app/v1/reminders/{reminder_id}/actions`
- `POST /api/app/v1/reminders/{reminder_id}/snooze`
- `POST /api/app/v1/reminders/{reminder_id}/complete`
- `DELETE /api/app/v1/reminders/{reminder_id}`

### Planning and Runtime

- `POST /api/app/v1/planning/bundles`
- `GET /api/app/v1/planning/overview`
- `GET /api/app/v1/planning/timeline`
- `GET /api/app/v1/planning/conflicts`
- `GET /api/app/v1/runtime/state`
- `POST /api/app/v1/runtime/stop`
- `GET /api/app/v1/runtime/todo-summary`
- `POST /api/app/v1/runtime/todo-summary`
- `GET /api/app/v1/runtime/calendar-summary`
- `POST /api/app/v1/runtime/calendar-summary`

### Computer Control, Device, and Capabilities

- `GET /api/app/v1/computer/state`
- `POST /api/app/v1/computer/actions`
- `POST /api/app/v1/computer/actions/{action_id}/confirm`
- `POST /api/app/v1/computer/actions/{action_id}/cancel`
- `GET /api/app/v1/computer/actions/recent`
- `GET /api/app/v1/device`
- `POST /api/app/v1/device/pairing/bundle`
- `POST /api/app/v1/device/speak`
- `POST /api/app/v1/device/commands`
- `GET /api/app/v1/capabilities`

## WebSocket Endpoints

### App Event Stream

- `GET /ws/app/v1/events`

Used for:

- runtime updates
- task, event, reminder, and notification changes
- chat, experience, device, and planning events

Resume support:

- query parameter: `last_event_id`

### Device WebSocket

- `GET /ws/device`

Used for:

- the main device status and voice channel
- device authentication
- device command delivery and text/audio output

### Desktop Voice Debug and Fallback

- `GET /api/desktop-voice/v1/state`
- `GET /ws/desktop-voice`

Notes:

- When `enable_local_microphone=true`, the desktop microphone path is already integrated into `main.py`
- `server/tools/desktop_voice_client.py` is better treated as a debug or fallback tool

## Real Device Pairing Flow

Initial robot pairing is not an auto-discovery flow. The real flow is:

1. The app connects to the live backend first.
2. The user enters the USB pairing flow on the `Connect` screen.
3. The app requests `POST /api/app/v1/device/pairing/bundle`.
4. The backend returns a pairing bundle containing:
   - `server.host`
   - `server.port`
   - `server.path = /ws/device`
   - `server.secure`
   - `auth.device_token`
5. The app sends Wi-Fi, host, and token details to the robot over desktop serial.

This is not LAN scanning and not a fake discovery path.

## Health Check

- `GET /api/health`

The response currently includes fields such as:

- `status`
- `ready`
- `startup_phase`
- `version`
- `uptime_s`
- `model`
- `provider`
- `asr_model`
- `tts_voice`
- `server_port`
- `device_connected`
- `device_state`

Frontend code and management scripts should treat `ready=true` as the actual service-ready signal, not just "the port is open".

## Recommended Local Startup

### Preferred: Repository Helper Script

```bash
./manager.sh doctor
./manager.sh update
./manager.sh dev
```

### Start the Backend Manually

```bash
cd server
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python main.py
```

### Start the Flutter App Manually

```bash
cd app
flutter pub get
flutter run -d macos
```

## Optional Integrations

The following capabilities exist in the repo but are not part of the default primary path:

- WhatsApp bridge
- weather provider
- Brave web search
- MCP servers
- cron service
- computer control

Notes:

- WhatsApp is off by default
- computer control is gated by allowlist rules
- weather, Brave, and provider credentials should always be injected through environment variables

## Document Scope

This guide only describes the backend contract that is currently implemented and connected to the main product flow.

These older assumptions are no longer valid:

- a React + TypeScript + Tailwind frontend
- `/api/config`
- `/ws/app`
- default port `8000`
- FastAPI or Express template implementations
- mDNS or `discoverDevices()` as the primary connection path

If the protocol expands later, the source of truth should remain the current code:

- `server/main.py`
- `server/bootstrap.py`
- `server/services/app_runtime.py`
- `server/channels/device_channel.py`
- `app/lib/config/routes.dart`
- `app/lib/services/api/`
