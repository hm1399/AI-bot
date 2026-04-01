import { AppConfig, AppEvent } from '../models/types';

type EventHandler = (event: AppEvent<any>) => void;
type ConnectionParams = Pick<AppConfig, 'serverUrl' | 'serverPort' | 'appToken'> & {
  lastEventId?: string;
  replayLimit?: number;
};

export class WebSocketService {
  private ws: WebSocket | null = null;
  private handlers = new Map<string, EventHandler[]>();
  private reconnectTimer: number | null = null;
  private reconnectAttempt = 0;
  private latestEventId = '';
  private params: ConnectionParams | null = null;
  private manualClose = false;

  connect(params: ConnectionParams) {
    this.params = params;
    this.latestEventId = params.lastEventId ?? this.latestEventId;
    this.manualClose = false;
    this.open();
  }

  private open() {
    if (!this.params) {
      return;
    }

    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    const url = new URL(`ws://${this.params.serverUrl}:${this.params.serverPort}/ws/app/v1/events`);
    if (this.params.appToken) {
      url.searchParams.set('token', this.params.appToken);
    }
    if (this.latestEventId) {
      url.searchParams.set('last_event_id', this.latestEventId);
    }
    url.searchParams.set('replay_limit', String(this.params.replayLimit ?? 200));

    this.ws = new WebSocket(url.toString());

    this.ws.onopen = () => {
      this.reconnectAttempt = 0;
      this.emit('__connection__', {
        eventId: '',
        eventType: '__connection__',
        scope: 'global',
        occurredAt: new Date().toISOString(),
        sessionId: null,
        taskId: null,
        payload: { status: 'connected' },
      });
    };

    this.ws.onmessage = (message) => {
      try {
        const event = JSON.parse(message.data) as any;
        if (!event?.event_type) {
          return;
        }
        const normalized: AppEvent = {
          eventId: String(event.event_id ?? ''),
          eventType: String(event.event_type),
          scope: String(event.scope ?? 'global'),
          occurredAt: String(event.occurred_at ?? new Date().toISOString()),
          sessionId: event.session_id ? String(event.session_id) : null,
          taskId: event.task_id ? String(event.task_id) : null,
          payload: event.payload ?? {},
        };
        if (normalized.eventId) {
          this.latestEventId = normalized.eventId;
        }
        this.emit(normalized.eventType, normalized);
        this.emit('__all__', normalized);
      } catch (error) {
        console.error('Failed to parse app event', error);
      }
    };

    this.ws.onerror = () => {
      this.emit('__connection__', {
        eventId: '',
        eventType: '__connection__',
        scope: 'global',
        occurredAt: new Date().toISOString(),
        sessionId: null,
        taskId: null,
        payload: { status: 'error' },
      });
    };

    this.ws.onclose = () => {
      this.emit('__connection__', {
        eventId: '',
        eventType: '__connection__',
        scope: 'global',
        occurredAt: new Date().toISOString(),
        sessionId: null,
        taskId: null,
        payload: { status: 'disconnected' },
      });
      if (!this.manualClose) {
        this.scheduleReconnect();
      }
    };
  }

  private scheduleReconnect() {
    if (this.reconnectTimer) {
      window.clearTimeout(this.reconnectTimer);
    }
    const delay = Math.min(30000, 1000 * 2 ** this.reconnectAttempt);
    this.reconnectAttempt += 1;
    this.reconnectTimer = window.setTimeout(() => this.open(), delay);
  }

  on(eventType: string, handler: EventHandler) {
    const existing = this.handlers.get(eventType) ?? [];
    existing.push(handler);
    this.handlers.set(eventType, existing);
  }

  off(eventType: string, handler: EventHandler) {
    const existing = this.handlers.get(eventType);
    if (!existing) {
      return;
    }
    this.handlers.set(
      eventType,
      existing.filter((item) => item !== handler),
    );
  }

  private emit(eventType: string, event: AppEvent<any>) {
    const handlers = this.handlers.get(eventType) ?? [];
    handlers.forEach((handler) => handler(event));
  }

  disconnect() {
    this.manualClose = true;
    if (this.reconnectTimer) {
      window.clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  isConnected() {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  getLatestEventId() {
    return this.latestEventId;
  }

  setLatestEventId(eventId: string) {
    this.latestEventId = eventId;
  }
}

export const wsService = new WebSocketService();
