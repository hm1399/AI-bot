# Development Guide

## Project Structure

```
src/app/
├── contexts/              # React Context for state management
│   ├── ChatContext.tsx    # Chat messages state
│   ├── ConfigContext.tsx  # App configuration & connection
│   ├── DeviceContext.tsx  # Device status & control
│   ├── EventContext.tsx   # Calendar events state
│   └── TaskContext.tsx    # Task management state
│
├── screens/               # Main application screens
│   ├── Connect.tsx        # Initial connection screen
│   ├── Home.tsx          # Dashboard with device status
│   ├── Chat.tsx          # Chat interface
│   ├── TasksEvents.tsx   # Tasks and events management
│   └── Settings.tsx      # Configuration settings
│
├── components/            # Reusable components
│   ├── ChatBubble.tsx    # Chat message bubble
│   ├── MessageInput.tsx  # Message input field
│   ├── DeviceCard.tsx    # Device status card
│   ├── TaskTile.tsx      # Task list item
│   ├── EventTile.tsx     # Event list item
│   └── ui/               # UI component library
│
├── services/              # External service integrations
│   ├── websocket.ts      # WebSocket connection manager
│   └── api.ts            # REST API client
│
├── models/                # TypeScript type definitions
│   └── types.ts          # All data models
│
├── hooks/                 # Custom React hooks
│   └── useToast.ts       # Toast notification hook
│
├── routes.ts             # React Router configuration
├── Root.tsx              # Root layout with navigation
└── App.tsx               # Application entry point
```

## Key Features

### 1. State Management (Contexts)

Each context provides:
- State for its domain (messages, tasks, events, etc.)
- CRUD operations
- WebSocket event handlers
- Toast notifications for user feedback

**Usage Example:**
```tsx
import { useChat } from '../contexts/ChatContext';

function ChatScreen() {
  const { messages, sendMessage, isLoading } = useChat();
  
  const handleSend = async (text: string) => {
    await sendMessage(text);
  };
  
  return (
    // ... UI
  );
}
```

### 2. WebSocket Communication

The WebSocket service provides:
- Auto-connect/reconnect logic
- Heartbeat (ping/pong) every 30 seconds
- Message type routing
- Event subscription system

**Message Flow:**
1. Device sends WebSocket message with `type` field
2. WebSocket service dispatches to registered handlers
3. Context handlers update state
4. UI re-renders automatically

### 3. REST API

The API service provides:
- Centralized HTTP client
- Type-safe endpoints
- Error handling

**Adding a new endpoint:**
```typescript
// In api.ts
async getNewData(): Promise<NewDataType> {
  return this.request<NewDataType>('/new-endpoint');
}
```

### 4. Routing

Uses React Router v7 with data mode:
- `/connect` - Initial connection screen (no layout)
- `/` - Home dashboard (with bottom nav)
- `/chat` - Chat interface (with bottom nav)
- `/tasks` - Tasks and events (with bottom nav)
- `/settings` - Settings (with bottom nav)

## Backend API Requirements

### WebSocket Endpoint

**URL:** `ws://{host}:{port}/ws/app`

**Message Format:**
```json
{
  "type": "device_status" | "chat_message" | "task_update" | "event_update" | "config_update" | "ping" | "pong",
  "data": { ... },
  "timestamp": 1234567890
}
```

### REST API Endpoints

#### Configuration
- `GET /api/config` → AppConfig
- `PUT /api/config` ← Partial<AppConfig> → AppConfig

#### Device
- `GET /api/device/status` → DeviceStatus
- `POST /api/device/mute` → void
- `POST /api/device/led/toggle` → void
- `POST /api/device/restart` → void

#### Chat
- `GET /api/history` → Message[]
- `POST /api/chat` ← { text: string, source: 'app' } → Message

#### Tasks
- `GET /api/tasks` → Task[]
- `POST /api/tasks` ← TaskData → Task
- `PUT /api/tasks/:id` ← Partial<Task> → Task
- `DELETE /api/tasks/:id` → void

#### Events
- `GET /api/events` → Event[]
- `POST /api/events` ← EventData → Event
- `PUT /api/events/:id` ← Partial<Event> → Event
- `DELETE /api/events/:id` → void

## Development Workflow

### Running the App

```bash
# Install dependencies
pnpm install

# Start development server
pnpm run dev

# Build for production
pnpm run build
```

### Adding a New Feature

1. **Define types** in `models/types.ts`
2. **Create API methods** in `services/api.ts`
3. **Create context** in `contexts/` if needed
4. **Build UI components** in `components/`
5. **Create screen** in `screens/`
6. **Add route** in `routes.ts`

### Testing with Mock Backend

For development without a real backend, you can:

1. Modify `api.ts` to return mock data
2. Comment out WebSocket connection in contexts
3. Use static data in state

Example:
```typescript
// In api.ts - development mode
async getDeviceStatus(): Promise<DeviceStatus> {
  // return this.request<DeviceStatus>('/device/status');
  return {
    online: true,
    battery: 85,
    wifiSignal: 70,
    state: 'idle',
  };
}
```

## Styling

- **Framework**: Tailwind CSS v4
- **UI Library**: Radix UI components
- **Theme**: Defined in `/src/styles/theme.css`
- **Mobile-first**: All layouts are responsive

### Using Tailwind

```tsx
<div className="flex flex-col gap-4 p-4 bg-white rounded-lg shadow-sm">
  <h2 className="text-xl font-semibold text-gray-900">Title</h2>
  <p className="text-sm text-gray-600">Description</p>
</div>
```

## Best Practices

### 1. Error Handling
Always wrap API calls with try-catch and show toast notifications:

```tsx
try {
  await someApiCall();
  toast.success('Success message');
} catch (error) {
  toast.error('Error message');
}
```

### 2. Loading States
Show loading indicators for async operations:

```tsx
const [isLoading, setIsLoading] = useState(false);

const handleAction = async () => {
  setIsLoading(true);
  try {
    await apiCall();
  } finally {
    setIsLoading(false);
  }
};
```

### 3. Type Safety
Always use TypeScript types from `models/types.ts`:

```tsx
import { Task } from '../models/types';

const MyComponent: React.FC<{ task: Task }> = ({ task }) => {
  // task is fully typed
};
```

### 4. Context Usage
Only use contexts in components that need them (avoid unnecessary re-renders):

```tsx
// Good - only used where needed
function TaskList() {
  const { tasks } = useTasks();
  return <div>{/* ... */}</div>;
}

// Avoid - don't use all contexts everywhere
```

## Troubleshooting

### WebSocket won't connect
- Check server URL and port
- Verify backend is running
- Check browser console for errors
- Ensure CORS is configured on backend

### API calls failing
- Verify backend endpoints match `/api/*` pattern
- Check network tab in browser dev tools
- Ensure JSON content-type headers

### State not updating
- Check WebSocket message `type` matches context handler
- Verify data structure matches TypeScript types
- Check React DevTools for context values

## Performance Tips

1. **Lazy load screens** if app grows large
2. **Memoize expensive calculations** with `useMemo`
3. **Debounce input** for search/filter operations
4. **Virtualize long lists** with react-window if needed

## Deployment

### Environment Variables
Create `.env` for configuration:

```env
VITE_DEFAULT_SERVER_URL=192.168.1.100
VITE_DEFAULT_SERVER_PORT=8000
```

Access in code:
```typescript
const defaultUrl = import.meta.env.VITE_DEFAULT_SERVER_URL || '';
```

### Build
```bash
pnpm run build
# Output in dist/
```

Deploy `dist/` folder to any static hosting service.
