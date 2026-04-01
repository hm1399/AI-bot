import {
  AiConnectionTestResult,
  ApiEnvelope,
  AppConfig,
  BootstrapData,
  CalendarSummary,
  Capabilities,
  DeviceStatus,
  Event,
  Message,
  MessagePage,
  PostMessageResult,
  RuntimeState,
  RuntimeTask,
  SessionSummary,
  SettingsData,
  SettingsUpdateInput,
  Task,
  TodoSummary,
} from '../models/types';

type RequestOptions = RequestInit & {
  skipEnvelope?: boolean;
  timeoutMs?: number;
};

type ConnectionInput = Pick<AppConfig, 'serverUrl' | 'serverPort' | 'appToken'>;

export class ApiClientError extends Error {
  code: string;
  status: number;
  requestId?: string;
  isBackendNotReady: boolean;

  constructor(
    message: string,
    {
      code = 'UNKNOWN_ERROR',
      status = 500,
      requestId,
      isBackendNotReady = false,
    }: {
      code?: string;
      status?: number;
      requestId?: string;
      isBackendNotReady?: boolean;
    } = {},
  ) {
    super(message);
    this.name = 'ApiClientError';
    this.code = code;
    this.status = status;
    this.requestId = requestId;
    this.isBackendNotReady = isBackendNotReady;
  }
}

const DEFAULT_TIMEOUT_MS = 12000;

const isBackendNotReady = (status: number, code?: string) =>
  status === 404 || status === 501 || code === 'NOT_IMPLEMENTED';

const normalizeSignalStrength = (wifiRssi: number) => {
  if (wifiRssi === 0) {
    return 0;
  }
  const normalized = Math.round(((wifiRssi + 100) / 60) * 100);
  return Math.max(0, Math.min(100, normalized));
};

const mapCapabilities = (payload: any): Capabilities => ({
  chat: Boolean(payload?.chat),
  deviceControl: Boolean(payload?.device_control),
  voicePipeline: Boolean(payload?.voice_pipeline),
  whatsappBridge: Boolean(payload?.whatsapp_bridge),
  todoSummary: Boolean(payload?.todo_summary),
  calendarSummary: Boolean(payload?.calendar_summary),
  appEvents: Boolean(payload?.app_events),
  eventReplay: Boolean(payload?.event_replay),
  appAuthEnabled: Boolean(payload?.app_auth_enabled),
});

const mapSession = (payload: any): SessionSummary => ({
  sessionId: String(payload?.session_id ?? ''),
  channel: String(payload?.channel ?? 'app'),
  title: String(payload?.title ?? 'Untitled session'),
  summary: String(payload?.summary ?? ''),
  lastMessageAt: payload?.last_message_at ? String(payload.last_message_at) : null,
  messageCount: Number(payload?.message_count ?? 0),
  pinned: Boolean(payload?.pinned),
  archived: Boolean(payload?.archived),
});

const mapMessage = (payload: any): Message => ({
  id: String(payload?.message_id ?? ''),
  sessionId: String(payload?.session_id ?? ''),
  role: payload?.role === 'assistant' || payload?.role === 'system' ? payload.role : 'user',
  text: String(payload?.content ?? ''),
  status:
    payload?.status === 'pending' ||
    payload?.status === 'failed' ||
    payload?.status === 'streaming'
      ? payload.status
      : 'completed',
  createdAt: String(payload?.created_at ?? new Date().toISOString()),
  metadata: payload?.metadata && typeof payload.metadata === 'object' ? payload.metadata : {},
});

const mapRuntimeTask = (payload: any): RuntimeTask => ({
  taskId: String(payload?.task_id ?? ''),
  kind: String(payload?.kind ?? 'chat'),
  sourceChannel: String(payload?.source_channel ?? 'app'),
  sourceSessionId: String(payload?.source_session_id ?? ''),
  summary: String(payload?.summary ?? ''),
  stage: String(payload?.stage ?? 'queued'),
  cancellable: Boolean(payload?.cancellable),
  startedAt: payload?.started_at ? String(payload.started_at) : null,
});

const mapDevice = (payload: any): DeviceStatus => {
  const wifiRssi = Number(payload?.wifi_rssi ?? 0);
  return {
    connected: Boolean(payload?.connected),
    state: String(payload?.state ?? 'UNKNOWN').toLowerCase(),
    battery: Number(payload?.battery ?? -1),
    wifiRssi,
    wifiSignal: normalizeSignalStrength(wifiRssi),
    charging: Boolean(payload?.charging),
    reconnectCount: Number(payload?.reconnect_count ?? 0),
  };
};

const mapTodoSummary = (payload: any): TodoSummary => ({
  enabled: Boolean(payload?.enabled),
  pendingCount: Number(payload?.pending_count ?? 0),
  overdueCount: Number(payload?.overdue_count ?? 0),
  nextDueAt: payload?.next_due_at ? String(payload.next_due_at) : null,
});

const mapCalendarSummary = (payload: any): CalendarSummary => ({
  enabled: Boolean(payload?.enabled),
  todayCount: Number(payload?.today_count ?? 0),
  nextEventAt: payload?.next_event_at ? String(payload.next_event_at) : null,
  nextEventTitle: payload?.next_event_title ? String(payload.next_event_title) : null,
});

const mapRuntimeState = (payload: any): RuntimeState => ({
  currentTask: payload?.current_task ? mapRuntimeTask(payload.current_task) : null,
  taskQueue: Array.isArray(payload?.task_queue) ? payload.task_queue.map(mapRuntimeTask) : [],
  device: mapDevice(payload?.device),
  todoSummary: mapTodoSummary(payload?.todo_summary),
  calendarSummary: mapCalendarSummary(payload?.calendar_summary),
});

const mapBootstrap = (payload: any): BootstrapData => ({
  serverVersion: String(payload?.server_version ?? ''),
  capabilities: mapCapabilities(payload?.capabilities),
  runtime: mapRuntimeState(payload?.runtime),
  sessions: Array.isArray(payload?.sessions) ? payload.sessions.map(mapSession) : [],
  eventStream: {
    type: String(payload?.event_stream?.type ?? 'websocket'),
    path: String(payload?.event_stream?.path ?? '/ws/app/v1/events'),
    resume: {
      query: payload?.event_stream?.resume?.query ? String(payload.event_stream.resume.query) : undefined,
      replayLimit: Number(payload?.event_stream?.resume?.replay_limit ?? 200),
      latestEventId: String(payload?.event_stream?.resume?.latest_event_id ?? ''),
    },
  },
});

const mapTask = (payload: any): Task => ({
  id: String(payload?.task_id ?? payload?.id ?? ''),
  title: String(payload?.title ?? ''),
  description: payload?.description ? String(payload.description) : undefined,
  priority: payload?.priority === 'high' || payload?.priority === 'low' ? payload.priority : 'medium',
  completed: Boolean(payload?.completed),
  dueAt: payload?.due_at ? String(payload.due_at) : null,
  createdAt: String(payload?.created_at ?? new Date().toISOString()),
  updatedAt: payload?.updated_at ? String(payload.updated_at) : null,
});

const mapEvent = (payload: any): Event => ({
  id: String(payload?.event_id ?? payload?.id ?? ''),
  title: String(payload?.title ?? ''),
  description: payload?.description ? String(payload.description) : undefined,
  startAt: String(payload?.start_at ?? payload?.start_time ?? new Date().toISOString()),
  endAt: String(payload?.end_at ?? payload?.end_time ?? new Date().toISOString()),
  location: payload?.location ? String(payload.location) : undefined,
  createdAt: String(payload?.created_at ?? new Date().toISOString()),
  updatedAt: payload?.updated_at ? String(payload.updated_at) : null,
});

const mapSettings = (payload: any): SettingsData => ({
  serverUrl: String(payload?.server_url ?? ''),
  serverPort: Number(payload?.server_port ?? 8000),
  llmProvider: String(payload?.llm_provider ?? 'server-managed'),
  llmModel: String(payload?.llm_model ?? ''),
  llmApiKeyConfigured: Boolean(payload?.llm_api_key_configured),
  llmBaseUrl: payload?.llm_base_url ? String(payload.llm_base_url) : null,
  sttProvider: String(payload?.stt_provider ?? 'server-managed'),
  sttModel: String(payload?.stt_model ?? ''),
  sttLanguage: String(payload?.stt_language ?? 'en-US'),
  ttsProvider: String(payload?.tts_provider ?? 'server-managed'),
  ttsModel: String(payload?.tts_model ?? ''),
  ttsVoice: String(payload?.tts_voice ?? 'alloy'),
  ttsSpeed: Number(payload?.tts_speed ?? 1),
  deviceVolume: Number(payload?.device_volume ?? 70),
  ledEnabled: Boolean(payload?.led_enabled),
  ledBrightness: Number(payload?.led_brightness ?? 50),
  ledMode:
    payload?.led_mode === 'off' || payload?.led_mode === 'rainbow' || payload?.led_mode === 'solid'
      ? payload.led_mode
      : 'breathing',
  ledColor: String(payload?.led_color ?? '#2563eb'),
  wakeWord: String(payload?.wake_word ?? 'Hey Assistant'),
  autoListen: Boolean(payload?.auto_listen),
});

class APIService {
  private origin = '';
  private token = '';

  setConnection({ serverUrl, serverPort, appToken }: ConnectionInput) {
    this.origin = `http://${serverUrl}:${serverPort}`;
    this.token = appToken.trim();
  }

  clearConnection() {
    this.origin = '';
    this.token = '';
  }

  private async request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    if (!this.origin) {
      throw new ApiClientError('API origin not set. Connect to a server first.', {
        status: 400,
        code: 'NOT_CONNECTED',
      });
    }

    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), options.timeoutMs ?? DEFAULT_TIMEOUT_MS);

    try {
      const response = await fetch(`${this.origin}${path}`, {
        ...options,
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          ...(this.token ? { Authorization: `Bearer ${this.token}`, 'X-App-Token': this.token } : {}),
          ...options.headers,
        },
      });

      const contentType = response.headers.get('content-type') ?? '';
      const payload = contentType.includes('application/json') ? await response.json() : null;

      if (!response.ok) {
        const envelope = payload as ApiEnvelope<unknown> | null;
        const code = envelope?.error?.code ?? (response.status === 404 ? 'NOT_IMPLEMENTED' : 'HTTP_ERROR');
        const message = envelope?.error?.message ?? response.statusText ?? 'Request failed';
        throw new ApiClientError(message, {
          code,
          status: response.status,
          requestId: envelope?.request_id,
          isBackendNotReady: isBackendNotReady(response.status, code),
        });
      }

      if (options.skipEnvelope) {
        return payload as T;
      }

      const envelope = payload as ApiEnvelope<T>;
      if (!envelope?.ok) {
        const code = envelope?.error?.code ?? 'UNKNOWN_ERROR';
        const message = envelope?.error?.message ?? 'Request failed';
        throw new ApiClientError(message, {
          code,
          status: response.status,
          requestId: envelope?.request_id,
          isBackendNotReady: isBackendNotReady(response.status, code),
        });
      }

      return envelope.data as T;
    } catch (error) {
      if (error instanceof ApiClientError) {
        throw error;
      }
      if (error instanceof DOMException && error.name === 'AbortError') {
        throw new ApiClientError('Request timed out', {
          status: 408,
          code: 'TIMEOUT',
        });
      }
      throw new ApiClientError(
        error instanceof Error ? error.message : 'Network request failed',
        {
          status: 0,
          code: 'NETWORK_ERROR',
        },
      );
    } finally {
      window.clearTimeout(timeout);
    }
  }

  async checkHealth(): Promise<Record<string, unknown>> {
    return this.request<Record<string, unknown>>('/api/health', { skipEnvelope: true, timeoutMs: 5000 });
  }

  async fetchBootstrap(): Promise<BootstrapData> {
    const data = await this.request<any>('/api/app/v1/bootstrap');
    return mapBootstrap(data);
  }

  async listSessions(): Promise<SessionSummary[]> {
    const data = await this.request<any[]>('/api/app/v1/sessions?limit=20&pinned_first=true');
    return data.map(mapSession);
  }

  async getMessages(sessionId: string): Promise<MessagePage> {
    const data = await this.request<any>(`/api/app/v1/sessions/${encodeURIComponent(sessionId)}/messages?limit=50`);
    return {
      items: Array.isArray(data?.items) ? data.items.map(mapMessage) : [],
      hasMoreBefore: Boolean(data?.page_info?.has_more_before),
      hasMoreAfter: Boolean(data?.page_info?.has_more_after),
    };
  }

  async postMessage(sessionId: string, content: string, clientMessageId: string): Promise<PostMessageResult> {
    const data = await this.request<any>(`/api/app/v1/sessions/${encodeURIComponent(sessionId)}/messages`, {
      method: 'POST',
      body: JSON.stringify({
        content,
        client_message_id: clientMessageId,
      }),
    });
    return {
      acceptedMessage: mapMessage(data?.accepted_message),
      taskId: String(data?.task_id ?? ''),
      queued: Boolean(data?.queued),
    };
  }

  async fetchRuntimeState(): Promise<RuntimeState> {
    const data = await this.request<any>('/api/app/v1/runtime/state');
    return mapRuntimeState(data);
  }

  async stopRuntimeTask(taskId?: string): Promise<{ taskId: string; stopping: boolean }> {
    const data = await this.request<any>('/api/app/v1/runtime/stop', {
      method: 'POST',
      body: JSON.stringify(taskId ? { task_id: taskId } : {}),
    });
    return {
      taskId: String(data?.task_id ?? ''),
      stopping: Boolean(data?.stopping),
    };
  }

  async fetchDevice(): Promise<DeviceStatus> {
    const data = await this.request<any>('/api/app/v1/device');
    return mapDevice(data);
  }

  async speak(text: string): Promise<{ accepted: boolean; text: string }> {
    return this.request<{ accepted: boolean; text: string }>('/api/app/v1/device/speak', {
      method: 'POST',
      body: JSON.stringify({ text }),
    });
  }

  async fetchSettings(): Promise<SettingsData> {
    const data = await this.request<any>('/api/app/v1/settings');
    return mapSettings(data);
  }

  async updateSettings(input: SettingsUpdateInput): Promise<SettingsData> {
    const data = await this.request<any>('/api/app/v1/settings', {
      method: 'PUT',
      body: JSON.stringify({
        llm_provider: input.llmProvider,
        llm_model: input.llmModel,
        ...(input.llmApiKey ? { llm_api_key: input.llmApiKey } : {}),
        llm_base_url: input.llmBaseUrl,
        stt_language: input.sttLanguage,
        tts_voice: input.ttsVoice,
        tts_speed: input.ttsSpeed,
        device_volume: input.deviceVolume,
        led_mode: input.ledMode,
        led_color: input.ledColor,
        wake_word: input.wakeWord,
        auto_listen: input.autoListen,
      }),
    });
    return mapSettings(data);
  }

  async testAiConnection(): Promise<AiConnectionTestResult> {
    return this.request<AiConnectionTestResult>('/api/app/v1/settings/llm/test', {
      method: 'POST',
    });
  }

  async listTasks(): Promise<Task[]> {
    const data = await this.request<any>('/api/app/v1/tasks');
    const items = Array.isArray(data?.items) ? data.items : Array.isArray(data) ? data : [];
    return items.map(mapTask);
  }

  async createTask(task: Omit<Task, 'id' | 'createdAt' | 'updatedAt'>): Promise<Task> {
    const data = await this.request<any>('/api/app/v1/tasks', {
      method: 'POST',
      body: JSON.stringify({
        title: task.title,
        description: task.description,
        priority: task.priority,
        completed: task.completed,
        due_at: task.dueAt ?? null,
      }),
    });
    return mapTask(data);
  }

  async updateTask(id: string, updates: Partial<Task>): Promise<Task> {
    const data = await this.request<any>(`/api/app/v1/tasks/${encodeURIComponent(id)}`, {
      method: 'PATCH',
      body: JSON.stringify({
        ...(updates.title !== undefined ? { title: updates.title } : {}),
        ...(updates.description !== undefined ? { description: updates.description } : {}),
        ...(updates.priority !== undefined ? { priority: updates.priority } : {}),
        ...(updates.completed !== undefined ? { completed: updates.completed } : {}),
        ...(updates.dueAt !== undefined ? { due_at: updates.dueAt } : {}),
      }),
    });
    return mapTask(data);
  }

  async deleteTask(id: string): Promise<void> {
    await this.request(`/api/app/v1/tasks/${encodeURIComponent(id)}`, {
      method: 'DELETE',
    });
  }

  async listEvents(): Promise<Event[]> {
    const data = await this.request<any>('/api/app/v1/events');
    const items = Array.isArray(data?.items) ? data.items : Array.isArray(data) ? data : [];
    return items.map(mapEvent);
  }

  async createEvent(event: Omit<Event, 'id' | 'createdAt' | 'updatedAt'>): Promise<Event> {
    const data = await this.request<any>('/api/app/v1/events', {
      method: 'POST',
      body: JSON.stringify({
        title: event.title,
        description: event.description,
        start_at: event.startAt,
        end_at: event.endAt,
        location: event.location,
      }),
    });
    return mapEvent(data);
  }

  async updateEvent(id: string, updates: Partial<Event>): Promise<Event> {
    const data = await this.request<any>(`/api/app/v1/events/${encodeURIComponent(id)}`, {
      method: 'PATCH',
      body: JSON.stringify({
        ...(updates.title !== undefined ? { title: updates.title } : {}),
        ...(updates.description !== undefined ? { description: updates.description } : {}),
        ...(updates.startAt !== undefined ? { start_at: updates.startAt } : {}),
        ...(updates.endAt !== undefined ? { end_at: updates.endAt } : {}),
        ...(updates.location !== undefined ? { location: updates.location } : {}),
      }),
    });
    return mapEvent(data);
  }

  async deleteEvent(id: string): Promise<void> {
    await this.request(`/api/app/v1/events/${encodeURIComponent(id)}`, {
      method: 'DELETE',
    });
  }
}

export const apiService = new APIService();

export const isBackendNotReadyError = (error: unknown) =>
  error instanceof ApiClientError && error.isBackendNotReady;
