# AI-Bot Control App - Architecture Diagram

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER DEVICE                              │
│                    (Phone/Tablet/Desktop)                        │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   Web Application                           │ │
│  │                  (React + TypeScript)                       │ │
│  │                                                             │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │              UI Layer (React Components)              │  │ │
│  │  │                                                       │  │ │
│  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │  │ │
│  │  │  │ Connect │ │  Home   │ │  Chat   │ │  Tasks  │   │  │ │
│  │  │  │ Screen  │ │ Screen  │ │ Screen  │ │ Screen  │   │  │ │
│  │  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘   │  │ │
│  │  │                                                       │  │ │
│  │  │  ┌──────────────────────────────────────────────┐   │  │ │
│  │  │  │         Settings Screen                      │   │  │ │
│  │  │  └──────────────────────────────────────────────┘   │  │ │
│  │  │                                                       │  │ │
│  │  │  ┌──────────────────────────────────────────────┐   │  │ │
│  │  │  │    Reusable Components                       │   │  │ │
│  │  │  │  ChatBubble | DeviceCard | TaskTile | ...    │   │  │ │
│  │  │  └──────────────────────────────────────────────┘   │  │ │
│  │  └───────────────────────┬───────────────────────────┘  │ │
│  │                          │                               │ │
│  │                          ▼                               │ │
│  │  ┌──────────────────────────────────────────────────┐   │ │
│  │  │       State Management (React Contexts)          │   │ │
│  │  │                                                   │   │ │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐         │   │ │
│  │  │  │  Chat    │ │  Device  │ │  Config  │         │   │ │
│  │  │  │ Context  │ │ Context  │ │ Context  │         │   │ │
│  │  │  └──────────┘ └──────────┘ └──────────┘         │   │ │
│  │  │                                                   │   │ │
│  │  │  ┌──────────┐ ┌──────────┐                      │   │ │
│  │  │  │  Task    │ │  Event   │                      │   │ │
│  │  │  │ Context  │ │ Context  │                      │   │ │
│  │  │  └──────────┘ └──────────┘                      │   │ │
│  │  └───────────────────────┬───────────────────────────┘  │ │
│  │                          │                               │ │
│  │                          ▼                               │ │
│  │  ┌──────────────────────────────────────────────────┐   │ │
│  │  │            Services Layer                        │   │ │
│  │  │                                                   │   │ │
│  │  │  ┌─────────────────┐  ┌─────────────────┐       │   │ │
│  │  │  │   WebSocket     │  │   API Service   │       │   │ │
│  │  │  │    Service      │  │   (REST)        │       │   │ │
│  │  │  │                 │  │                 │       │   │ │
│  │  │  │ • Auto-connect  │  │ • HTTP Client   │       │   │ │
│  │  │  │ • Reconnect     │  │ • Type-safe     │       │   │ │
│  │  │  │ • Heartbeat     │  │ • Error handle  │       │   │ │
│  │  │  │ • Event routing │  │ • CRUD ops      │       │   │ │
│  │  │  └─────────────────┘  └─────────────────┘       │   │ │
│  │  └────────────────┬──────────────┬──────────────────┘  │ │
│  └───────────────────┼──────────────┼──────────────────────┘ │
│                      │              │                        │
└──────────────────────┼──────────────┼────────────────────────┘
                       │              │
                       │ WebSocket    │ HTTP
                       │ (Real-time)  │ (REST)
                       ▼              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        BACKEND SERVER                            │
│                  (Python + FastAPI + ESP32-S3)                   │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    FastAPI Application                      │ │
│  │                                                             │ │
│  │  ┌──────────────────┐        ┌──────────────────┐         │ │
│  │  │  WebSocket       │        │   REST API       │         │ │
│  │  │  Handler         │        │   Endpoints      │         │ │
│  │  │                  │        │                  │         │ │
│  │  │  /ws/app         │        │  /api/*          │         │ │
│  │  └──────────────────┘        └──────────────────┘         │ │
│  │           │                           │                     │ │
│  │           ▼                           ▼                     │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │              Business Logic                          │  │ │
│  │  │                                                       │  │ │
│  │  │  • Whisper (Speech-to-Text)                          │  │ │
│  │  │  • LLM Engine (GPT-4 / Claude)                       │  │ │
│  │  │  • Edge-TTS (Text-to-Speech)                         │  │ │
│  │  │  • NanoBot (Computer Control)                        │  │ │
│  │  │  • Task/Event Manager                                │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  │                          │                                  │ │
│  │                          ▼                                  │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │              Database / Storage                      │  │ │
│  │  │                                                       │  │ │
│  │  │  • Configuration                                      │  │ │
│  │  │  • Chat History                                       │  │ │
│  │  │  • Tasks                                              │  │ │
│  │  │  • Events                                             │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └─────────────────────────┬───────────────────────────────────┘ │
│                            │                                     │
│                            ▼                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Hardware Interface                             │ │
│  │                                                             │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐      │ │
│  │  │ INMP441  │ │MAX98357A │ │ ST7789   │ │ MPU6050  │      │ │
│  │  │   Mic    │ │ Speaker  │ │  LCD     │ │   IMU    │      │ │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘      │ │
│  │                                                             │ │
│  │  ┌──────────┐ ┌──────────┐                                 │ │
│  │  │ WS2812B  │ │  Touch   │                                 │ │
│  │  │   LEDs   │ │   Pad    │                                 │ │
│  │  └──────────┘ └──────────┘                                 │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

## Data Flow Diagram

### Real-Time Updates (WebSocket)

```
ESP32-S3 Device
      │
      │ (WiFi)
      ▼
Python Server
      │
      │ WebSocket Message
      │ { type: "device_status", data: {...} }
      ▼
WebSocket Service (Frontend)
      │
      │ Dispatch by type
      ▼
Context Handler (DeviceContext)
      │
      │ Update state
      ▼
React Component Re-render
      │
      ▼
User sees update
```

### User Action Flow (REST API)

```
User clicks "Mute" button
      │
      ▼
Home Screen calls useDevice()
      │
      ▼
DeviceContext.muteDevice()
      │
      ▼
API Service
      │
      │ POST /api/device/mute
      ▼
Python Server
      │
      ▼
ESP32-S3 Command
      │
      ▼
Device mutes
      │
      │ WebSocket update
      ▼
Frontend receives status update
      │
      ▼
Toast notification shown
```

## Component Tree

```
App
└── ConfigProvider
    └── Toaster (Toast Notifications)
    └── RouterProvider
        ├── Connect Route (/connect)
        │   └── Connect Screen
        │       ├── Auto Discovery
        │       └── Manual Input
        │
        └── Root Route (/)
            ├── DeviceProvider
            │   ├── ChatProvider
            │   │   ├── TaskProvider
            │   │   │   └── EventProvider
            │   │   │       │
            │   │   │       ├── Connection Status Bar
            │   │   │       │   └── WiFi Icon + Status
            │   │   │       │
            │   │   │       ├── Main Content (Outlet)
            │   │   │       │   ├── Home (/)
            │   │   │       │   │   ├── DeviceCard
            │   │   │       │   │   └── Quick Actions
            │   │   │       │   │
            │   │   │       │   ├── Chat (/chat)
            │   │   │       │   │   ├── ChatBubble (multiple)
            │   │   │       │   │   └── MessageInput
            │   │   │       │   │
            │   │   │       │   ├── TasksEvents (/tasks)
            │   │   │       │   │   ├── Tab Switcher
            │   │   │       │   │   ├── Task List
            │   │   │       │   │   │   └── TaskTile (multiple)
            │   │   │       │   │   ├── Event List
            │   │   │       │   │   │   └── EventTile (multiple)
            │   │   │       │   │   └── Create Dialogs
            │   │   │       │   │
            │   │   │       │   └── Settings (/settings)
            │   │   │       │       ├── Connection Settings
            │   │   │       │       ├── LLM Config
            │   │   │       │       ├── Voice Config
            │   │   │       │       ├── LED Config
            │   │   │       │       └── About
            │   │   │       │
            │   │   │       └── Bottom Navigation
            │   │   │           ├── Home Tab
            │   │   │           ├── Chat Tab
            │   │   │           ├── Tasks Tab
            │   │   │           └── Settings Tab
```

## Message Flow Patterns

### Pattern 1: Real-Time Device Status
```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│  ESP32-S3   │────────▶│    Python    │────────▶│   Browser   │
│   Device    │  WiFi   │    Server    │  WebSocket│   (React)   │
└─────────────┘         └──────────────┘         └─────────────┘
                                                         │
                                                         ▼
                                                  DeviceContext
                                                         │
                                                         ▼
                                                    DeviceCard
                                                         │
                                                         ▼
                                                   User sees status
```

### Pattern 2: User Command
```
User Action (Tap Button)
         │
         ▼
  React Component
         │
         ▼
    Context Method
         │
         ▼
   API Service (POST)
         │
         ▼
   Python Server
         │
         ▼
    ESP32-S3 Hardware
         │
         ▼
  Action Executed
         │
         ▼
  Status Update (WebSocket)
         │
         ▼
   Frontend Updates
         │
         ▼
  Toast Notification
```

### Pattern 3: Chat Flow
```
User types message
         │
         ▼
  MessageInput Component
         │
         ▼
  ChatContext.sendMessage()
         │
         ▼
  API Service POST /api/chat
         │
         ▼
    Python Server
         │
    ┌────┴────┐
    ▼         ▼
Whisper      LLM
(if voice)  (GPT-4)
    │         │
    └────┬────┘
         ▼
   Edge-TTS (response)
         │
         ▼
WebSocket Message
         │
         ▼
  ChatContext receives
         │
         ▼
  Chat Screen updates
         │
         ▼
  ChatBubble appears
```

## State Management Pattern

```
┌──────────────────────────────────────────────────────────┐
│                     ConfigContext                         │
│  • serverUrl, serverPort, isConnected                    │
│  • connect(), disconnect()                               │
│  • Used by: All screens, Root component                  │
└──────────────────────────────────────────────────────────┘
                            │
    ┌───────────────────────┼───────────────────────┐
    ▼                       ▼                       ▼
┌─────────┐          ┌─────────┐            ┌─────────┐
│ Device  │          │  Chat   │            │  Task   │
│ Context │          │ Context │            │ Context │
└─────────┘          └─────────┘            └─────────┘
    │                     │                       │
    ▼                     ▼                       ▼
┌─────────┐          ┌─────────┐            ┌─────────┐
│  Home   │          │  Chat   │            │ Tasks   │
│ Screen  │          │ Screen  │            │ Screen  │
└─────────┘          └─────────┘            └─────────┘
```

## Network Protocol

### WebSocket Messages (Server → Client)
```json
{
  "type": "device_status",
  "data": {
    "online": true,
    "battery": 85,
    "wifiSignal": 70,
    "state": "idle"
  },
  "timestamp": 1234567890
}
```

### REST API Calls (Client → Server)
```http
POST /api/chat HTTP/1.1
Content-Type: application/json

{
  "text": "Open VS Code",
  "source": "app"
}
```

## File Organization

```
src/app/
├── contexts/          → State management
├── screens/           → Full-page views
├── components/        → Reusable UI pieces
├── services/          → External integrations
├── models/            → Type definitions
├── hooks/             → Custom React hooks
├── routes.ts          → Route configuration
├── Root.tsx           → Layout wrapper
└── App.tsx            → Entry point
```

This architecture ensures:
- **Separation of Concerns**: UI, State, Services are separate
- **Type Safety**: TypeScript throughout
- **Maintainability**: Clear structure and patterns
- **Scalability**: Easy to add new features
- **Real-time**: WebSocket for live updates
- **Reliability**: Auto-reconnect, error handling
