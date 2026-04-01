export interface AppConfig {
  serverUrl: string;
  serverPort: number;
  appToken: string;
  currentSessionId: string;
  latestEventId: string;
}

export interface ApiErrorPayload {
  code: string;
  message: string;
}

export interface ApiEnvelope<T> {
  ok: boolean;
  data?: T;
  error?: ApiErrorPayload;
  request_id?: string;
  ts?: string;
}

export interface Capabilities {
  chat: boolean;
  deviceControl: boolean;
  voicePipeline: boolean;
  whatsappBridge: boolean;
  todoSummary: boolean;
  calendarSummary: boolean;
  appEvents: boolean;
  eventReplay: boolean;
  appAuthEnabled: boolean;
}

export interface SessionSummary {
  sessionId: string;
  channel: string;
  title: string;
  summary: string;
  lastMessageAt: string | null;
  messageCount: number;
  pinned: boolean;
  archived: boolean;
}

export type MessageRole = 'user' | 'assistant' | 'system';
export type MessageStatus = 'pending' | 'streaming' | 'completed' | 'failed';

export interface Message {
  id: string;
  sessionId: string;
  role: MessageRole;
  text: string;
  status: MessageStatus;
  createdAt: string;
  metadata?: Record<string, unknown>;
  errorReason?: string;
}

export interface RuntimeTask {
  taskId: string;
  kind: string;
  sourceChannel: string;
  sourceSessionId: string;
  summary: string;
  stage: string;
  cancellable: boolean;
  startedAt?: string | null;
}

export interface DeviceStatus {
  connected: boolean;
  state: string;
  battery: number;
  wifiRssi: number;
  wifiSignal: number;
  charging: boolean;
  reconnectCount: number;
}

export interface TodoSummary {
  enabled: boolean;
  pendingCount: number;
  overdueCount: number;
  nextDueAt: string | null;
}

export interface CalendarSummary {
  enabled: boolean;
  todayCount: number;
  nextEventAt: string | null;
  nextEventTitle: string | null;
}

export interface RuntimeState {
  currentTask: RuntimeTask | null;
  taskQueue: RuntimeTask[];
  device: DeviceStatus;
  todoSummary: TodoSummary;
  calendarSummary: CalendarSummary;
}

export interface EventStreamResume {
  query?: string;
  replayLimit: number;
  latestEventId: string;
}

export interface EventStreamDescriptor {
  type: string;
  path: string;
  resume: EventStreamResume;
}

export interface BootstrapData {
  serverVersion: string;
  capabilities: Capabilities;
  runtime: RuntimeState;
  sessions: SessionSummary[];
  eventStream: EventStreamDescriptor;
}

export interface MessagePage {
  items: Message[];
  hasMoreBefore: boolean;
  hasMoreAfter: boolean;
}

export interface PostMessageResult {
  acceptedMessage: Message;
  taskId: string;
  queued: boolean;
}

export interface SettingsData {
  serverUrl: string;
  serverPort: number;
  llmProvider: string;
  llmModel: string;
  llmApiKeyConfigured: boolean;
  llmBaseUrl: string | null;
  sttProvider: string;
  sttModel: string;
  sttLanguage: string;
  ttsProvider: string;
  ttsModel: string;
  ttsVoice: string;
  ttsSpeed: number;
  deviceVolume: number;
  ledEnabled: boolean;
  ledBrightness: number;
  ledMode: 'off' | 'breathing' | 'rainbow' | 'solid';
  ledColor: string;
  wakeWord: string;
  autoListen: boolean;
}

export interface SettingsUpdateInput {
  llmProvider: string;
  llmModel: string;
  llmApiKey?: string;
  llmBaseUrl: string | null;
  sttLanguage: string;
  ttsVoice: string;
  ttsSpeed: number;
  deviceVolume: number;
  ledMode: 'off' | 'breathing' | 'rainbow' | 'solid';
  ledColor: string;
  wakeWord: string;
  autoListen: boolean;
}

export interface AiConnectionTestResult {
  success: boolean;
  provider: string;
  model: string;
  message: string;
}

export interface Task {
  id: string;
  title: string;
  description?: string;
  priority: 'high' | 'medium' | 'low';
  completed: boolean;
  dueAt?: string | null;
  createdAt: string;
  updatedAt?: string | null;
}

export interface Event {
  id: string;
  title: string;
  description?: string;
  startAt: string;
  endAt: string;
  location?: string;
  createdAt: string;
  updatedAt?: string | null;
}

export interface Notification {
  id: string;
  title: string;
  body: string;
  type: 'info' | 'warning' | 'error' | 'success';
  read: boolean;
  timestamp: string;
}

export interface AppEvent<T = Record<string, unknown>> {
  eventId: string;
  eventType: string;
  scope: string;
  occurredAt: string;
  sessionId: string | null;
  taskId: string | null;
  payload: T;
}

export interface SystemHelloPayload {
  serverVersion: string;
  protocolVersion: string;
  ts: string;
  resume: {
    requested: boolean;
    accepted: boolean;
    replayedCount: number;
    replayLimit: number;
    latestEventId: string | null;
    historySize: number;
    shouldRefetchBootstrap: boolean;
    reason: string | null;
  };
}
