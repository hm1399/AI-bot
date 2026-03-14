import { Message, Task, Event, DeviceStatus, AppConfig } from '../models/types';

export const mockDeviceStatus: DeviceStatus = {
  online: true,
  battery: 85,
  wifiSignal: 70,
  state: 'idle',
  lastSeen: new Date(),
};

export const mockMessages: Message[] = [
  {
    id: '1',
    text: 'Hello! How can I help you today?',
    source: 'device',
    timestamp: new Date(Date.now() - 3600000),
  },
  {
    id: '2',
    text: 'Open VS Code',
    source: 'app',
    timestamp: new Date(Date.now() - 3000000),
    toolResult: {
      toolName: 'open_application',
      status: 'success',
      result: 'VS Code opened successfully',
    },
  },
];

export const mockTasks: Task[] = [
  {
    id: '1',
    title: 'Complete project documentation',
    description: 'Write README and API docs',
    priority: 'high',
    completed: false,
    dueDate: new Date(Date.now() + 86400000),
    createdAt: new Date(),
  },
  {
    id: '2',
    title: 'Review pull requests',
    priority: 'medium',
    completed: false,
    createdAt: new Date(),
  },
];

export const mockEvents: Event[] = [
  {
    id: '1',
    title: 'Team Meeting',
    description: 'Weekly sync',
    startTime: new Date(Date.now() + 7200000),
    endTime: new Date(Date.now() + 10800000),
    location: 'Conference Room A',
    createdAt: new Date(),
  },
];

export const mockConfig: AppConfig = {
  serverUrl: '192.168.1.100',
  serverPort: 8000,
  llmModel: 'gpt-4',
  ttsVoice: 'en-US-AriaNeural',
  ttsSpeed: 1.0,
  deviceVolume: 80,
  ledMode: 'breathing',
};
