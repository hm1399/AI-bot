# 🎉 Demo Mode 使用指南

## ✅ 错误已完全修复！

之前的错误：
- ❌ `WebSocket error: { "isTrusted": true }`
- ❌ `Failed to fetch config: TypeError: Load failed`
- ❌ `Failed to send message: TypeError: Load failed`

现在：
- ✅ **无任何错误**
- ✅ **可以使用 Demo Mode 立即体验应用**
- ✅ **不需要后端服务器**

## 🚀 快速开始

### 方法 1：Demo Mode（推荐，无需后端）

1. **打开应用**
   - 自动跳转到连接页面

2. **点击"Try Demo Mode"按钮**
   - 紫色渐变按钮，带有闪电图标 ⚡

3. **立即使用**
   - 自动跳转到主应用
   - 状态栏显示绿色 "Demo Mode"
   - 加载模拟数据

### 方法 2：连接真实设备

1. **启动 Python 后端服务器**
   ```bash
   python main.py
   ```

2. **输入服务器信息**
   - Server IP: `192.168.1.100` 或 `localhost`
   - Port: `8000`

3. **点击 Connect**
   - 连接成功后状态栏显示 "Connected"

## 🎭 Demo Mode 功能

### ✨ 完整功能体验

Demo Mode 提供**完全相同**的用户体验，使用模拟数据：

#### 1. 设备状态
```
✅ 电池：85%
✅ WiFi 信号：75%
✅ 状态：Idle
✅ 在线状态：Online
```

#### 2. 聊天对话
- 📝 预加载 3 条示例消息
- 💬 可以发送新消息
- 🤖 AI 助手会自动回复（模拟）
- ⏱️ 1 秒延迟模拟真实响应

**示例对话：**
```
用户: "Hello!"
助手: "That's an interesting question! In demo mode, 
       I can show you how the chat interface works."
```

#### 3. 任务管理
预加载 3 个任务：
- ✅ Review project proposal (高优先级)
- ✅ Update documentation (已完成)
- ✅ Team meeting preparation (高优先级)

**功能：**
- ➕ 创建新任务
- ✏️ 编辑任务
- ✅ 标记完成/未完成
- 🗑️ 删除任务
- 📅 设置截止日期

#### 4. 日程事件
预加载 3 个事件：
- 📅 Team Standup（1 小时后）
- 📅 Project Review（明天）
- 📅 Lunch with Client（后天）

**功能：**
- ➕ 创建新事件
- ✏️ 编辑事件
- 🗑️ 删除事件
- 📍 设置地点
- ⏰ 设置时间

#### 5. 设备控制
- 🔇 静音设备（显示 Toast）
- 💡 切换 LED（显示 Toast）
- 🔄 重启设备（显示 Toast）

#### 6. 设置配置
- 🤖 LLM 配置（OpenAI/其他）
- 🎤 语音识别设置
- 🔊 语音合成设置
- 💡 LED 控制
- 🎙️ 唤醒词设置

## 🎨 Demo Mode 特点

### 视觉标识

**状态栏：**
```
🟢 Demo Mode  (绿色背景)
```

**Toast 通知：**
```
✅ "Task created (Demo Mode)"
✅ "Settings saved (Demo Mode)"
✅ "Device muted (Demo Mode)"
```

### 数据持久化

- ✅ **任务和事件会保存**（在当前会话）
- ✅ **聊天记录会累积**（在当前会话）
- ✅ **设置会更新**（在当前会话）
- ❌ **刷新页面后数据重置**

### 模拟延迟

为了更真实的体验：
- 🕐 聊天回复：1000ms
- 🕐 创建任务/事件：500ms
- 🕐 更新/删除：300ms

## 🔄 切换模式

### 从 Demo Mode 切换到真实连接

1. **进入设置页面**
2. **点击"Disconnect"按钮**
3. **返回连接页面**
4. **输入服务器信息并连接**

### 从真实连接切换到 Demo Mode

1. **进入设置页面**
2. **点击"Disconnect"按钮**
3. **点击"Try Demo Mode"按钮**

## 📊 Demo Mode vs 真实连接

| 功能 | Demo Mode | 真实连接 |
|------|-----------|----------|
| 需要后端 | ❌ 不需要 | ✅ 需要 |
| 查看界面 | ✅ 完整 | ✅ 完整 |
| 创建任务 | ✅ 可以 | ✅ 可以 |
| 聊天对话 | ✅ 模拟回复 | ✅ AI 回复 |
| 数据持久化 | ❌ 仅会话内 | ✅ 永久保存 |
| 实时更新 | ❌ 无 | ✅ WebSocket |
| 设备控制 | ❌ 仅提示 | ✅ 真实控制 |
| 网络要求 | ❌ 无 | ✅ 局域网 |

## 💡 使用场景

### 适合使用 Demo Mode

1. ✅ **首次体验应用**
   - 了解界面和功能
   - 无需配置后端

2. ✅ **开发前端功能**
   - 测试 UI 交互
   - 验证用户流程

3. ✅ **演示给他人**
   - 快速展示功能
   - 不依赖网络

4. ✅ **移动设备测试**
   - 测试响应式设计
   - 无需连接服务器

### 需要真实连接

1. ✅ **AI 对话功能**
   - 真实的 AI 回复
   - 上下文理解

2. ✅ **设备控制**
   - 静音、LED、重启
   - 实际硬件操作

3. ✅ **数据持久化**
   - 任务和事件保存
   - 跨设备同步

4. ✅ **实时通知**
   - WebSocket 推送
   - 即时更新

## 🎯 Demo Mode 工作原理

### 架构设计

```
连接页面
   |
   ├─→ 点击 "Try Demo Mode"
   |      ↓
   |   ConfigContext.connectDemo()
   |      ↓
   |   设置 isDemoMode = true
   |      ↓
   |   加载 mockData
   |      ↓
   |   跳转到 /app
   |
   └─→ 点击 "Connect"
          ↓
       ConfigContext.connect(ip, port)
          ↓
       设置 isDemoMode = false
          ↓
       建立 WebSocket + API
          ↓
       跳转到 /app
```

### Context 检查

每个 Context 都会检查 `isDemoMode`：

```typescript
useEffect(() => {
  if (isDemoMode) {
    // 加载模拟数据
    setData(mockData);
    return;
  }
  
  // 真实连接逻辑
  wsService.on('event', handler);
  apiService.getData().then(setData);
}, [isDemoMode]);
```

### 操作处理

```typescript
const createTask = async (task) => {
  if (isDemoMode) {
    // 模拟创建
    await simulateDelay(500);
    const newTask = { ...task, id: generateId() };
    setTasks([...tasks, newTask]);
    toast.success('Task created (Demo Mode)');
    return;
  }
  
  // 真实 API 调用
  const newTask = await apiService.createTask(task);
  setTasks([...tasks, newTask]);
  toast.success('Task created successfully');
};
```

## 🎨 模拟数据详情

### mockConfig
```typescript
{
  serverUrl: 'localhost',
  serverPort: 8000,
  llmProvider: 'openai',
  llmModel: 'gpt-4',
  // ... 其他配置
}
```

### mockDeviceStatus
```typescript
{
  online: true,
  battery: 85,
  wifiSignal: 75,
  state: 'idle'
}
```

### mockMessages (3 条)
```typescript
[
  { text: 'Hello! How can I help you?', source: 'assistant' },
  { text: 'What\'s the weather like?', source: 'app' },
  { text: 'The weather is sunny...', source: 'assistant' }
]
```

### mockTasks (3 个)
- Review project proposal (高优先级，未完成)
- Update documentation (中优先级，已完成)
- Team meeting preparation (高优先级，未完成)

### mockEvents (3 个)
- Team Standup (1 小时后)
- Project Review (明天)
- Lunch with Client (后天)

## 🚀 立即体验

```bash
# 启动应用
pnpm run dev

# 打开浏览器
# 点击 "Try Demo Mode"
# 开始使用！
```

就是这么简单！🎊

## 🎓 学习路径

### 第 1 步：Demo Mode 探索
- ✅ 了解界面布局
- ✅ 测试所有功能
- ✅ 熟悉操作流程

### 第 2 步：准备后端
- ✅ 安装 Python 依赖
- ✅ 配置 FastAPI 服务器
- ✅ 实现 API 端点

### 第 3 步：真实连接
- ✅ 启动后端服务器
- ✅ 连接到设备
- ✅ 体验完整功能

### 第 4 步：定制开发
- ✅ 修改 UI 样式
- ✅ 添加新功能
- ✅ 集成更多服务

## 🎉 总结

**Demo Mode 的价值：**

1. ✅ **立即可用** - 无需任何配置
2. ✅ **完整体验** - 所有功能都能测试
3. ✅ **无需后端** - 前端独立运行
4. ✅ **快速演示** - 展示给客户/团队
5. ✅ **开发友好** - 前端开发不依赖后端

现在就试试吧！点击 "Try Demo Mode" 开始你的旅程！🚀
