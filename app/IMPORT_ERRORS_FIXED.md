# ✅ 导入错误已修复

## 🐛 原始错误

```
TypeError: Importing a module script failed.
SyntaxError: Importing binding name 'useEvents' is not found.
```

## 🔍 错误原因

1. **导出名称不匹配**
   - `EventContext.tsx` 导出的是 `useEvent`（单数）
   - `TasksEvents.tsx` 导入的是 `useEvents`（复数）
   - 导致模块加载失败

2. **类型定义不完整**
   - `types.ts` 中的 `AppConfig` 接口缺少必需字段
   - 导致 TypeScript 编译错误

3. **日期类型不一致**
   - 某些接口使用 `Date` 类型
   - 但实际数据使用 `string` (ISO 字符串)

## 🔧 修复内容

### 1. EventContext.tsx
```typescript
// ❌ 之前
export const useEvent = () => { ... }

// ✅ 现在
export const useEvents = () => { ... }
```

### 2. TaskContext.tsx
```typescript
// ❌ 之前
export const useTask = () => { ... }

// ✅ 现在
export const useTasks = () => { ... }
```

### 3. types.ts - AppConfig 接口
```typescript
// ✅ 添加所有缺失的字段
export interface AppConfig {
  serverUrl: string;
  serverPort: number;
  llmProvider: string;
  llmModel: string;
  llmApiKey?: string;
  llmBaseUrl?: string;
  sttProvider: string;
  sttModel: string;
  sttLanguage: string;
  ttsProvider: string;
  ttsModel: string;
  ttsVoice: string;
  ledEnabled: boolean;
  ledBrightness: number;
  wakeWord: string;
  autoListen: boolean;
}
```

### 4. types.ts - 日期类型统一
```typescript
// ❌ 之前
timestamp: Date;
createdAt: Date;
startTime: Date;

// ✅ 现在 (使用 ISO 字符串)
timestamp: string;
createdAt: string;
startTime: string;
```

### 5. Message source 类型
```typescript
// ✅ 添加 'assistant' 选项
source: 'device' | 'app' | 'assistant' | 'system';
```

### 6. 新建索引文件
创建 `/src/app/contexts/index.ts` 集中导出所有 Context：

```typescript
export { ConfigProvider, useConfig } from './ConfigContext';
export { DeviceProvider, useDevice } from './DeviceContext';
export { ChatProvider, useChat } from './ChatContext';
export { TaskProvider, useTasks } from './TaskContext';
export { EventProvider, useEvents } from './EventContext';
```

## 📋 导出命名规范

现在所有 Context hooks 都使用**复数**形式（与数据名称匹配）：

| Context | Provider | Hook | 数据 |
|---------|----------|------|------|
| ConfigContext | ConfigProvider | useConfig | config |
| DeviceContext | DeviceProvider | useDevice | deviceStatus |
| ChatContext | ChatProvider | useChat | messages |
| TaskContext | TaskProvider | **useTasks** ✅ | **tasks** |
| EventContext | EventProvider | **useEvents** ✅ | **events** |

## ✅ 验证清单

- [x] EventContext 导出 `useEvents`
- [x] TaskContext 导出 `useTasks`
- [x] TasksEvents.tsx 正确导入两个 hooks
- [x] types.ts 中的 AppConfig 包含所有字段
- [x] 所有日期字段使用 `string` 类型
- [x] Message.source 包含 'assistant'
- [x] 创建 contexts/index.ts 集中导出

## 🎯 导入示例

### 推荐方式 1: 从各自文件导入
```typescript
import { useConfig } from '../contexts/ConfigContext';
import { useDevice } from '../contexts/DeviceContext';
import { useChat } from '../contexts/ChatContext';
import { useTasks } from '../contexts/TaskContext';
import { useEvents } from '../contexts/EventContext';
```

### 推荐方式 2: 从索引文件导入
```typescript
import { useConfig, useDevice, useChat, useTasks, useEvents } from '../contexts';
```

## 🚀 测试验证

### 测试 1: 导入编译
```bash
# 应该无错误
pnpm run build
```

### 测试 2: TasksEvents 页面
```typescript
// TasksEvents.tsx 应该能正确导入和使用
const { tasks, createTask, toggleTask, deleteTask } = useTasks();
const { events, createEvent, deleteEvent } = useEvents();
```

### 测试 3: 类型检查
```bash
# TypeScript 应该没有类型错误
pnpm run type-check
```

## 📝 相关文件

修改的文件：
1. ✅ `/src/app/contexts/EventContext.tsx`
2. ✅ `/src/app/contexts/TaskContext.tsx`
3. ✅ `/src/app/models/types.ts`

新增的文件：
4. ✅ `/src/app/contexts/index.ts`

## 💡 避免类似错误的最佳实践

### 1. 命名一致性
```typescript
// ✅ 好 - 保持一致
const tasks = [...];
export const useTasks = () => { ... };

// ❌ 坏 - 不一致
const tasks = [...];
export const useTask = () => { ... };  // 单数/复数不匹配
```

### 2. 类型定义完整性
```typescript
// ✅ 好 - 完整定义
export interface AppConfig {
  // 所有必需字段
  serverUrl: string;
  serverPort: number;
  // ... 所有使用到的字段
}

// ❌ 坏 - 缺少字段
export interface AppConfig {
  serverUrl: string;
  // 缺少其他字段
}
```

### 3. 导入导出验证
```typescript
// ✅ 好 - 使用索引文件
// contexts/index.ts
export { useTasks } from './TaskContext';

// 组件中
import { useTasks } from '../contexts';  // 从索引导入

// ❌ 坏 - 没有验证导出
import { useTask } from '../contexts/TaskContext';  // 错误的名称
```

### 4. TypeScript 严格模式
```json
// tsconfig.json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true
  }
}
```

## 🎉 总结

所有导入和类型错误已修复：

1. ✅ **命名统一** - 所有 hooks 使用复数形式
2. ✅ **类型完整** - AppConfig 包含所有字段
3. ✅ **类型一致** - 日期统一使用 string
4. ✅ **集中导出** - 创建索引文件
5. ✅ **代码整洁** - 遵循最佳实践

应用现在应该可以正常编译和运行了！🚀
