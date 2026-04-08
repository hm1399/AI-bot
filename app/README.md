# AI Bot App

Flutter frontend for `AI-bot/server` using the `app-v1` HTTP and WebSocket contract.

## Features

- Connect with `host`, `port`, and optional `app token`
- Bootstrap + event stream resume using `/api/app/v1/bootstrap` and `/ws/app/v1/events`
- Backend-driven chat
- Runtime, device, todo, and calendar dashboard
- Settings through backend APIs
- Tasks, events, notifications, and reminders placeholders with backend-not-ready handling
- Demo mode separated from real backend mode

## Desktop Targets

```bash
Windows + macOS + Linux
```

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
- Unrelated directories in the repository are kept, but they are not required for running the desktop app.
