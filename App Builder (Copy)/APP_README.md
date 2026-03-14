# AI-Bot Control Web App

A responsive web application for controlling and managing your AI-Bot Desktop Assistant. This app provides a mobile-friendly interface to interact with your ESP32-S3 based voice assistant.

## Features

### 📱 Four Main Screens

1. **Home Dashboard**
   - Real-time device status monitoring
   - Battery level and WiFi signal strength
   - Current device state (idle/recording/playing/processing)
   - Quick action buttons (Mute, LED toggle, Restart)

2. **Chat Interface**
   - Real-time conversation with AI assistant
   - Message bubbles showing source (device/app/system)
   - Tool execution results displayed as cards
   - Text input and voice button support

3. **Tasks & Events**
   - Task list organized by priority (high/medium/low)
   - Calendar view for upcoming events
   - Create, complete, and delete tasks
   - Add events with time and location

4. **Settings**
   - Server connection management
   - LLM configuration (API key, model selection)
   - Voice settings (TTS voice, speech speed, volume)
   - LED light configuration
   - About information

## Technology Stack

- **Framework**: React with TypeScript
- **Routing**: React Router v7 (Data mode)
- **State Management**: React Context API + Hooks
- **UI Components**: Radix UI + Custom components
- **Styling**: Tailwind CSS v4
- **Icons**: Lucide React
- **Real-time Communication**: WebSocket
- **API**: REST API integration

## Architecture

```
src/app/
├── contexts/          # State management
│   ├── ChatContext.tsx
│   ├── ConfigContext.tsx
│   ├── DeviceContext.tsx
│   ├── EventContext.tsx
│   └── TaskContext.tsx
├── screens/           # Main screens
│   ├── Connect.tsx
│   ├── Home.tsx
│   ├── Chat.tsx
│   ├── TasksEvents.tsx
│   └── Settings.tsx
├── components/        # Reusable components
│   ├── ChatBubble.tsx
│   ├── MessageInput.tsx
│   ├── DeviceCard.tsx
│   ├── TaskTile.tsx
│   └── EventTile.tsx
├── services/          # Backend integration
│   ├── websocket.ts   # WebSocket connection management
│   └── api.ts         # REST API service
├── models/            # Data models
│   └── types.ts
└── routes.ts          # Route configuration
```

## Getting Started

### 1. First Time Setup

When you first open the app, you'll see the **Connect** screen:

- **Auto Discovery**: Tap "Scan Network" to automatically find your AI-Bot device on the local network
- **Manual Connection**: Enter the server IP address and port manually (default: port 8000)

### 2. Using the App

Once connected, you'll have access to all features through the bottom navigation bar:

- **Home**: Monitor device status and use quick actions
- **Chat**: Converse with your AI assistant
- **Tasks**: Manage your tasks and events
- **Settings**: Configure device and app settings

## WebSocket Communication

The app maintains a persistent WebSocket connection with your device:

- **Endpoint**: `ws://{serverUrl}:{port}/ws/app`
- **Auto-reconnect**: Automatically reconnects if connection drops
- **Heartbeat**: Sends ping every 30 seconds to keep connection alive
- **Message Types**:
  - `device_status` - Device state updates
  - `chat_message` - New chat messages
  - `task_update` - Task changes
  - `event_update` - Event changes
  - `config_update` - Configuration updates

## REST API Endpoints

### Configuration
- `GET /api/config` - Get current configuration
- `PUT /api/config` - Update configuration

### Device
- `GET /api/device/status` - Get device status
- `POST /api/device/mute` - Mute device
- `POST /api/device/led/toggle` - Toggle LED
- `POST /api/device/restart` - Restart device

### Chat
- `GET /api/history` - Get chat history
- `POST /api/chat` - Send chat message

### Tasks
- `GET /api/tasks` - Get all tasks
- `POST /api/tasks` - Create task
- `PUT /api/tasks/:id` - Update task
- `DELETE /api/tasks/:id` - Delete task

### Events
- `GET /api/events` - Get all events
- `POST /api/events` - Create event
- `PUT /api/events/:id` - Update event
- `DELETE /api/events/:id` - Delete event

## Mobile Optimization

The app is designed mobile-first with:

- Responsive layouts that adapt to screen size
- Touch-friendly UI elements
- Bottom navigation for easy thumb access
- Safe area support for notched devices
- Optimized font sizes for mobile screens

## Development

### Running Locally

```bash
pnpm install
pnpm run dev
```

### Building for Production

```bash
pnpm run build
```

## Browser Support

- Modern browsers (Chrome, Firefox, Safari, Edge)
- Mobile browsers (iOS Safari, Chrome Mobile)
- WebSocket support required

## Notes

- Make sure your device and the web app are on the same network
- The app stores connection settings locally
- API keys are stored securely and masked in the UI
- All timestamps are displayed in local timezone

## Troubleshooting

### Can't connect to device
- Verify device is powered on and connected to WiFi
- Check firewall settings
- Ensure device and phone/computer are on same network

### WebSocket disconnects frequently
- Check network stability
- The app will auto-reconnect after 5 seconds

### Settings not saving
- Ensure you're connected to the server
- Check browser console for errors
