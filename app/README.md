# AI Bot App

Flutter frontend for `AI-bot/server` using the `app-v1` HTTP and WebSocket contract.

## Features

- Connect to a live backend with `host`, `port`, HTTPS/WSS toggle, and optional app token
- Bootstrap + realtime event resume using `/api/app/v1/bootstrap` and `/ws/app/v1/events`
- Desktop USB robot pairing through the `Connect` flow and backend-issued pairing bundle
- Multi-session backend-driven chat with scene/persona controls
- Runtime dashboard with device status, queue state, todo summary, calendar summary, and capability snapshots
- `Agenda` view for month/day schedule browsing
- `Tasks` workbench for tasks, events, reminders, conflicts, and planning timeline management
- `Control` workspace for device commands, notifications, reminders, physical interaction debug, and computer-action approvals
- `Settings` for theme mode, scene/persona defaults, LLM settings, voice/device options, and runtime flags
- Demo mode separated from the real backend flow

## Main Navigation

The current main shell has six areas:

- `Home`
- `Chat`
- `Agenda`
- `Tasks`
- `Control`
- `Settings`

The app also keeps two entry routes outside the main shell:

- `Connect`
- `Demo`

## Platform Status

```bash
Windows + macOS + Linux
```

The Flutter project still includes Android, iOS, and web scaffolding, but the current product flow is desktop-first. Robot pairing is intentionally desktop-oriented because it depends on USB serial access.

## Run On Desktop

```bash
flutter run -d windows
```

On macOS or Linux, run the matching desktop device instead:

```bash
flutter run -d macos
flutter run -d linux
```

Build a Windows desktop executable:

```bash
flutter build windows
```

Notes:

- The main Flutter desktop project is `app/`.
- The primary backend contract lives in `AI-bot/server` and uses `app-v1` REST + WebSocket paths.
- `Robot Pairing` is intentionally desktop-focused and uses USB serial plus a backend-issued pairing bundle.
- Pairing is not a fake LAN scan or automatic LAN discovery flow. The operator connects the backend first, then enters a reachable LAN host for the robot when needed.
- Wide layouts use a left sidebar shell; compact layouts use a bottom dock for the same six main sections.
- Unrelated directories in the repository are kept, but they are not required for running the desktop app.
