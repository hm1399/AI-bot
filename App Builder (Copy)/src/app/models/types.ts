// Message model for chat conversations
export interface Message {
  id: string;
  text: string;
  source: 'device' | 'app' | 'system';
  timestamp: Date;
  toolResult?: ToolResult;
}

// Tool execution result
export interface ToolResult {
  toolName: string;
  status: 'success' | 'error' | 'pending';
  result: string;
}

// Task model
export interface Task {
  id: string;
  title: string;
  description?: string;
  priority: 'high' | 'medium' | 'low';
  completed: boolean;
  dueDate?: Date;
  createdAt: Date;
}

// Event/Calendar model
export interface Event {
  id: string;
  title: string;
  description?: string;
  startTime: Date;
  endTime: Date;
  location?: string;
  createdAt: Date;
}

// Device status model
export interface DeviceStatus {
  online: boolean;
  battery: number;
  wifiSignal: number;
  state: 'idle' | 'recording' | 'playing' | 'processing';
  lastSeen?: Date;
}

// App configuration model
export interface AppConfig {
  serverUrl: string;
  serverPort: number;
  llmApiKey?: string;
  llmModel: string;
  ttsVoice: string;
  ttsSpeed: number;
  deviceVolume: number;
  ledMode: 'off' | 'breathing' | 'rainbow' | 'solid';
  ledColor?: string;
}

// WebSocket message types
export type WSMessageType = 
  | 'device_status'
  | 'chat_message'
  | 'task_update'
  | 'event_update'
  | 'config_update'
  | 'ping'
  | 'pong';

export interface WSMessage {
  type: WSMessageType;
  data: any;
  timestamp: number;
}
