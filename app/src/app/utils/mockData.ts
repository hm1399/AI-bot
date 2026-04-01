import {
  AppConfig,
  BootstrapData,
  Capabilities,
  DeviceStatus,
  Event,
  Message,
  RuntimeState,
  SessionSummary,
  SettingsData,
  Task,
} from '../models/types';

export const mockConfig: AppConfig = {
  serverUrl: 'demo.local',
  serverPort: 8000,
  appToken: '',
  currentSessionId: 'app:demo',
  latestEventId: 'evt_demo_latest',
};

export const mockCapabilities: Capabilities = {
  chat: true,
  deviceControl: true,
  voicePipeline: true,
  whatsappBridge: false,
  todoSummary: true,
  calendarSummary: true,
  appEvents: true,
  eventReplay: true,
  appAuthEnabled: false,
};

export const mockSessions: SessionSummary[] = [
  {
    sessionId: 'app:demo',
    channel: 'app',
    title: 'Demo Session',
    summary: 'Explore the app without a live backend.',
    lastMessageAt: new Date(Date.now() - 20 * 60 * 1000).toISOString(),
    messageCount: 3,
    pinned: true,
    archived: false,
  },
];

export const mockDeviceStatus: DeviceStatus = {
  connected: true,
  state: 'idle',
  battery: 85,
  wifiRssi: -54,
  wifiSignal: 77,
  charging: false,
  reconnectCount: 0,
};

export const mockRuntimeState: RuntimeState = {
  currentTask: {
    taskId: 'task_demo_current',
    kind: 'chat',
    sourceChannel: 'app',
    sourceSessionId: 'app:demo',
    summary: 'Preparing a short demo reply',
    stage: 'thinking',
    cancellable: true,
    startedAt: new Date(Date.now() - 90 * 1000).toISOString(),
  },
  taskQueue: [
    {
      taskId: 'task_demo_queue',
      kind: 'chat',
      sourceChannel: 'app',
      sourceSessionId: 'app:demo',
      summary: 'Summarise the latest status',
      stage: 'queued',
      cancellable: true,
    },
  ],
  device: mockDeviceStatus,
  todoSummary: {
    enabled: true,
    pendingCount: 5,
    overdueCount: 1,
    nextDueAt: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(),
  },
  calendarSummary: {
    enabled: true,
    todayCount: 3,
    nextEventAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    nextEventTitle: 'Team sync',
  },
};

export const mockBootstrap: BootstrapData = {
  serverVersion: 'demo',
  capabilities: mockCapabilities,
  runtime: mockRuntimeState,
  sessions: mockSessions,
  eventStream: {
    type: 'websocket',
    path: '/ws/app/v1/events',
    resume: {
      replayLimit: 200,
      latestEventId: 'evt_demo_latest',
    },
  },
};

export const mockSettings: SettingsData = {
  serverUrl: 'demo.local',
  serverPort: 8000,
  llmProvider: 'server-managed',
  llmModel: 'demo-model',
  llmApiKeyConfigured: true,
  llmBaseUrl: null,
  sttProvider: 'server-managed',
  sttModel: 'demo-stt',
  sttLanguage: 'en-US',
  ttsProvider: 'server-managed',
  ttsModel: 'demo-tts',
  ttsVoice: 'alloy',
  ttsSpeed: 1,
  deviceVolume: 70,
  ledEnabled: true,
  ledBrightness: 80,
  ledMode: 'breathing',
  ledColor: '#2563eb',
  wakeWord: 'Hey Assistant',
  autoListen: true,
};

export const mockMessages: Message[] = [
  {
    id: 'msg_demo_1',
    sessionId: 'app:demo',
    role: 'assistant',
    text: 'Hello. Demo mode is running entirely locally so you can inspect the UI safely.',
    status: 'completed',
    createdAt: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
  },
  {
    id: 'msg_demo_2',
    sessionId: 'app:demo',
    role: 'user',
    text: 'What changes when I connect to the real backend?',
    status: 'completed',
    createdAt: new Date(Date.now() - 58 * 60 * 1000).toISOString(),
  },
  {
    id: 'msg_demo_3',
    sessionId: 'app:demo',
    role: 'assistant',
    text: 'Real mode uses /api/app/v1 plus /ws/app/v1/events, and all AI replies come from the server event stream.',
    status: 'completed',
    createdAt: new Date(Date.now() - 57 * 60 * 1000).toISOString(),
  },
];

export const mockTasks: Task[] = [
  {
    id: 'task_demo_1',
    title: 'Review project proposal',
    completed: false,
    priority: 'high',
    dueAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    createdAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
    updatedAt: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
  },
  {
    id: 'task_demo_2',
    title: 'Update documentation',
    completed: true,
    priority: 'medium',
    createdAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
    updatedAt: new Date(Date.now() - 12 * 60 * 60 * 1000).toISOString(),
  },
  {
    id: 'task_demo_3',
    title: 'Prepare team meeting notes',
    completed: false,
    priority: 'low',
    dueAt: new Date(Date.now() + 10 * 60 * 60 * 1000).toISOString(),
    createdAt: new Date(Date.now() - 12 * 60 * 60 * 1000).toISOString(),
    updatedAt: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
  },
];

export const mockEvents: Event[] = [
  {
    id: 'event_demo_1',
    title: 'Team Standup',
    startAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    endAt: new Date(Date.now() + 90 * 60 * 1000).toISOString(),
    description: 'Daily team sync',
    location: 'Conference Room A',
    createdAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
    updatedAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
  },
  {
    id: 'event_demo_2',
    title: 'Project Review',
    startAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    endAt: new Date(Date.now() + 25 * 60 * 60 * 1000).toISOString(),
    description: 'Stakeholder review',
    createdAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
    updatedAt: new Date(Date.now() - 12 * 60 * 60 * 1000).toISOString(),
  },
];

let idCounter = 1000;
export const generateId = () => `mock-${idCounter++}`;

export const simulateDelay = (ms = 500) =>
  new Promise((resolve) => setTimeout(resolve, ms));
