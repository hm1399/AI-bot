import express from 'express';
import http from 'http';
import { WebSocketServer } from 'ws';

const app = express();
const PORT = process.env.PORT ? Number(process.env.PORT) : 8000;

app.use(express.json());
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(204);
  }
  next();
});

let config = {
  serverUrl: 'localhost',
  serverPort: PORT,
  llmProvider: 'openai',
  llmModel: 'gpt-4',
  llmApiKey: '',
  llmBaseUrl: '',
  sttProvider: 'openai',
  sttModel: 'whisper-1',
  sttLanguage: 'en',
  ttsProvider: 'openai',
  ttsModel: 'tts-1',
  ttsVoice: 'alloy',
  ledEnabled: true,
  ledBrightness: 80,
  wakeWord: 'Hey Assistant',
  autoListen: true,
};

let deviceStatus = {
  online: true,
  battery: 88,
  wifiSignal: 82,
  state: 'idle',
  lastSeen: new Date().toISOString(),
};

let messages = [
  { id: '1', text: 'Hello! How can I help you today?', source: 'assistant', timestamp: new Date(Date.now() - 3600000).toISOString() },
  { id: '2', text: "What's the weather like?", source: 'app', timestamp: new Date(Date.now() - 3500000).toISOString() },
  { id: '3', text: 'The weather is sunny with a high of 72°F today.', source: 'assistant', timestamp: new Date(Date.now() - 3400000).toISOString() },
];

let tasks = [
  { id: '1', title: 'Review project proposal', completed: false, priority: 'high', dueDate: new Date(Date.now() + 86400000).toISOString(), createdAt: new Date(Date.now() - 86400000).toISOString() },
  { id: '2', title: 'Update documentation', completed: true, priority: 'medium', createdAt: new Date(Date.now() - 172800000).toISOString() },
  { id: '3', title: 'Team meeting preparation', completed: false, priority: 'high', dueDate: new Date(Date.now() + 43200000).toISOString(), createdAt: new Date(Date.now() - 43200000).toISOString() },
];

let events = [
  { id: '1', title: 'Team Standup', startTime: new Date(Date.now() + 3600000).toISOString(), endTime: new Date(Date.now() + 5400000).toISOString(), description: 'Daily team standup meeting', location: 'Conference Room A', createdAt: new Date(Date.now() - 86400000).toISOString() },
  { id: '2', title: 'Project Review', startTime: new Date(Date.now() + 86400000).toISOString(), endTime: new Date(Date.now() + 90000000).toISOString(), description: 'Q1 project review with stakeholders', createdAt: new Date(Date.now() - 172800000).toISOString() },
  { id: '3', title: 'Lunch with Client', startTime: new Date(Date.now() + 172800000).toISOString(), endTime: new Date(Date.now() + 176400000).toISOString(), location: 'Downtown Restaurant', createdAt: new Date(Date.now() - 259200000).toISOString() },
];

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws/app' });

function broadcast(type, data) {
  const message = JSON.stringify({ type, data, timestamp: Date.now() });
  wss.clients.forEach((client) => {
    if (client.readyState === 1) {
      client.send(message);
    }
  });
}

wss.on('connection', (ws) => {
  ws.send(JSON.stringify({ type: 'config_update', data: config, timestamp: Date.now() }));
  ws.send(JSON.stringify({ type: 'device_status', data: deviceStatus, timestamp: Date.now() }));

  ws.on('message', (raw) => {
    try {
      const message = JSON.parse(raw.toString());
      if (message.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong', data: {}, timestamp: Date.now() }));
      }
    } catch (err) {
      console.error('ws parse error', err);
    }
  });

  ws.on('close', () => {
    console.log('WebSocket client disconnected');
  });
});

app.get('/api/config', (req, res) => res.json(config));
app.put('/api/config', (req, res) => {
  config = { ...config, ...req.body };
  broadcast('config_update', config);
  return res.json(config);
});

app.get('/api/device/status', (req, res) => {
  deviceStatus.lastSeen = new Date().toISOString();
  return res.json(deviceStatus);
});

app.post('/api/device/mute', (req, res) => {
  deviceStatus.state = 'idle';
  broadcast('device_status', deviceStatus);
  return res.json({ message: 'Device muted' });
});

app.post('/api/device/led/toggle', (req, res) => {
  config.ledEnabled = !config.ledEnabled;
  broadcast('config_update', config);
  return res.json({ ledEnabled: config.ledEnabled });
});

app.post('/api/device/restart', (req, res) => {
  deviceStatus.state = 'processing';
  broadcast('device_status', deviceStatus);
  setTimeout(() => {
    deviceStatus.state = 'idle';
    deviceStatus.lastSeen = new Date().toISOString();
    broadcast('device_status', deviceStatus);
  }, 1000);
  return res.json({ message: 'Device restarting' });
});

app.get('/api/history', (req, res) => res.json(messages));
app.post('/api/chat', (req, res) => {
  const { text, source } = req.body;
  if (!text || !source) {
    return res.status(400).json({ message: 'Invalid payload' });
  }
  const newMessage = {
    id: `${Date.now()}`,
    text,
    source,
    timestamp: new Date().toISOString(),
  };
  messages.push(newMessage);
  if (source === 'app') {
    const botReply = {
      id: `${Date.now() + 1}`,
      text: `Echo: ${text}`,
      source: 'assistant',
      timestamp: new Date().toISOString(),
    };
    messages.push(botReply);
    broadcast('chat_message', botReply);
    return res.json(botReply);
  }
  broadcast('chat_message', newMessage);
  return res.json(newMessage);
});

app.get('/api/tasks', (req, res) => res.json(tasks));
app.post('/api/tasks', (req, res) => {
  const newTask = {
    id: `${Date.now()}`,
    createdAt: new Date().toISOString(),
    completed: false,
    ...req.body,
  };
  tasks.push(newTask);
  broadcast('task_update', tasks);
  res.json(newTask);
});
app.put('/api/tasks/:id', (req, res) => {
  const idx = tasks.findIndex((task) => task.id === req.params.id);
  if (idx === -1) return res.status(404).json({ message: 'Task not found' });
  tasks[idx] = { ...tasks[idx], ...req.body };
  broadcast('task_update', tasks);
  res.json(tasks[idx]);
});
app.delete('/api/tasks/:id', (req, res) => {
  tasks = tasks.filter((task) => task.id !== req.params.id);
  broadcast('task_update', tasks);
  res.status(204).send();
});

app.get('/api/events', (req, res) => res.json(events));
app.post('/api/events', (req, res) => {
  const newEvent = {
    id: `${Date.now()}`,
    createdAt: new Date().toISOString(),
    ...req.body,
  };
  events.push(newEvent);
  broadcast('event_update', events);
  res.json(newEvent);
});
app.put('/api/events/:id', (req, res) => {
  const idx = events.findIndex((event) => event.id === req.params.id);
  if (idx === -1) return res.status(404).json({ message: 'Event not found' });
  events[idx] = { ...events[idx], ...req.body };
  broadcast('event_update', events);
  res.json(events[idx]);
});
app.delete('/api/events/:id', (req, res) => {
  events = events.filter((event) => event.id !== req.params.id);
  broadcast('event_update', events);
  res.status(204).send();
});

// Mobile command / remote control
app.post('/api/command', (req, res) => {
  const { command, params } = req.body;
  if (!command) {
    return res.status(400).json({ message: 'Missing command' });
  }

  const result = {
    command,
    params: params || {},
    status: 'success',
    output: `Executed command: ${command}`,
    timestamp: new Date().toISOString(),
  };

  // 同步推送到前端
  broadcast('command', result);
  return res.json(result);
});

// 语音交互
app.post('/api/voice/interpret', (req, res) => {
  const { text } = req.body;
  if (!text) {
    return res.status(400).json({ message: 'Missing voice text' });
  }

  const assistantText = `语音识别结果：${text} -> 已执行。`; // 简单模拟
  const message = { id: `${Date.now()}`, text: assistantText, source: 'assistant', timestamp: new Date().toISOString() };
  messages.push(message);
  broadcast('chat_message', message);

  return res.json({ success: true, reply: assistantText });
});

// 通知系统
let notifications = [];
let notificationId = 1000;

app.get('/api/notifications', (req, res) => res.json(notifications));
app.post('/api/notifications', (req, res) => {
  const { title, body, type = 'info', target = 'all' } = req.body;
  if (!title || !body) {
    return res.status(400).json({ message: 'Missing notification title or body' });
  }

  const n = { id: `${notificationId++}`, title, body, type, target, read: false, timestamp: new Date().toISOString() };
  notifications.unshift(n);
  broadcast('notification', n);
  return res.status(201).json(n);
});
app.put('/api/notifications/:id/read', (req, res) => {
  const idx = notifications.findIndex((item) => item.id === req.params.id);
  if (idx === -1) return res.status(404).json({ message: 'Notification not found' });
  notifications[idx].read = true;
  return res.json(notifications[idx]);
});

// 智能待办（智能计划）
app.post('/api/smart/tasks', (req, res) => {
  const { objective, constraints } = req.body;
  if (!objective) {
    return res.status(400).json({ message: 'Missing objective' });
  }

  // 简单生成 1 条智能任务
  const newTask = {
    id: `${Date.now()}`,
    title: `智能建议: ${objective}`,
    description: constraints ? `约束：${constraints}` : undefined,
    completed: false,
    priority: 'medium',
    createdAt: new Date().toISOString(),
  };
  tasks.push(newTask);
  broadcast('task_update', tasks);
  return res.status(201).json(newTask);
});

app.get('/api/ping', (req, res) => res.json({ message: 'pong' }));

server.listen(PORT, () => {
  console.log(`API server running on http://localhost:${PORT}`);
  console.log(`WebSocket endpoint ws://localhost:${PORT}/ws/app`);
});
