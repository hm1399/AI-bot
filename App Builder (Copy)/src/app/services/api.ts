import { AppConfig, DeviceStatus, Message, Task, Event } from '../models/types';

class APIService {
  private baseUrl: string = '';

  setBaseUrl(serverUrl: string, port: number) {
    this.baseUrl = `http://${serverUrl}:${port}/api`;
  }

  private async request<T>(endpoint: string, options?: RequestInit): Promise<T> {
    const response = await fetch(`${this.baseUrl}${endpoint}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...options?.headers,
      },
    });

    if (!response.ok) {
      throw new Error(`API Error: ${response.statusText}`);
    }

    return response.json();
  }

  // Configuration
  async getConfig(): Promise<AppConfig> {
    return this.request<AppConfig>('/config');
  }

  async updateConfig(config: Partial<AppConfig>): Promise<AppConfig> {
    return this.request<AppConfig>('/config', {
      method: 'PUT',
      body: JSON.stringify(config),
    });
  }

  // Device status
  async getDeviceStatus(): Promise<DeviceStatus> {
    return this.request<DeviceStatus>('/device/status');
  }

  // Chat history
  async getChatHistory(): Promise<Message[]> {
    return this.request<Message[]>('/history');
  }

  async sendChatMessage(text: string): Promise<Message> {
    return this.request<Message>('/chat', {
      method: 'POST',
      body: JSON.stringify({ text, source: 'app' }),
    });
  }

  // Tasks
  async getTasks(): Promise<Task[]> {
    return this.request<Task[]>('/tasks');
  }

  async createTask(task: Omit<Task, 'id' | 'createdAt'>): Promise<Task> {
    return this.request<Task>('/tasks', {
      method: 'POST',
      body: JSON.stringify(task),
    });
  }

  async updateTask(id: string, updates: Partial<Task>): Promise<Task> {
    return this.request<Task>(`/tasks/${id}`, {
      method: 'PUT',
      body: JSON.stringify(updates),
    });
  }

  async deleteTask(id: string): Promise<void> {
    return this.request<void>(`/tasks/${id}`, {
      method: 'DELETE',
    });
  }

  // Events
  async getEvents(): Promise<Event[]> {
    return this.request<Event[]>('/events');
  }

  async createEvent(event: Omit<Event, 'id' | 'createdAt'>): Promise<Event> {
    return this.request<Event>('/events', {
      method: 'POST',
      body: JSON.stringify(event),
    });
  }

  async updateEvent(id: string, updates: Partial<Event>): Promise<Event> {
    return this.request<Event>(`/events/${id}`, {
      method: 'PUT',
      body: JSON.stringify(updates),
    });
  }

  async deleteEvent(id: string): Promise<void> {
    return this.request<void>(`/events/${id}`, {
      method: 'DELETE',
    });
  }

  // Device control
  async muteDevice(): Promise<void> {
    return this.request<void>('/device/mute', { method: 'POST' });
  }

  async toggleLED(): Promise<void> {
    return this.request<void>('/device/led/toggle', { method: 'POST' });
  }

  async restartDevice(): Promise<void> {
    return this.request<void>('/device/restart', { method: 'POST' });
  }

  // Service discovery
  async discoverDevices(): Promise<{ ip: string; port: number; name: string }[]> {
    // Simulate device discovery
    // In real implementation, this would broadcast and scan the local network
    return new Promise((resolve) => {
      setTimeout(() => {
        resolve([
          { ip: '192.168.1.100', port: 8000, name: 'AI-Bot Desktop Assistant' },
        ]);
      }, 2000);
    });
  }
}

export const apiService = new APIService();
