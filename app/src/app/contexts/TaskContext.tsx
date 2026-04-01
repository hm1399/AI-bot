import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Task } from '../models/types';
import { apiService, isBackendNotReadyError } from '../services/api';
import { useConfig } from './ConfigContext';
import { generateId, mockTasks, simulateDelay } from '../utils/mockData';

type BackendStatus = 'idle' | 'loading' | 'ready' | 'not-ready' | 'error' | 'demo';

interface TaskContextType {
  tasks: Task[];
  backendStatus: BackendStatus;
  statusMessage: string | null;
  createTask: (task: Omit<Task, 'id' | 'createdAt' | 'updatedAt'>) => Promise<void>;
  updateTask: (id: string, updates: Partial<Task>) => Promise<void>;
  deleteTask: (id: string) => Promise<void>;
  toggleTask: (id: string) => Promise<void>;
}

const TaskContext = createContext<TaskContextType | undefined>(undefined);

export const useTasks = () => {
  const context = useContext(TaskContext);
  if (!context) {
    throw new Error('useTasks must be used within TaskProvider');
  }
  return context;
};

export const TaskProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { config, isConnected, isDemoMode } = useConfig();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [backendStatus, setBackendStatus] = useState<BackendStatus>('idle');
  const [statusMessage, setStatusMessage] = useState<string | null>(null);

  useEffect(() => {
    if (isDemoMode) {
      setTasks(mockTasks);
      setBackendStatus('demo');
      setStatusMessage('Demo mode uses local task data and does not touch production APIs.');
      return;
    }

    if (!isConnected) {
      setTasks([]);
      setBackendStatus('idle');
      setStatusMessage(null);
      return;
    }

    setBackendStatus('loading');
    setStatusMessage(null);
    apiService.setConnection(config);
    apiService
      .listTasks()
      .then((items) => {
        setTasks(items);
        setBackendStatus('ready');
      })
      .catch((error) => {
        if (isBackendNotReadyError(error)) {
          setBackendStatus('not-ready');
          setStatusMessage('后端任务接口尚未提供，当前前端仅保留入口与错误提示。');
          return;
        }
        setBackendStatus('error');
        setStatusMessage(error instanceof Error ? error.message : 'Failed to load tasks');
      });
  }, [config, isConnected, isDemoMode]);

  const createTask = async (task: Omit<Task, 'id' | 'createdAt' | 'updatedAt'>) => {
    if (isDemoMode) {
      await simulateDelay();
      const next: Task = {
        ...task,
        id: generateId(),
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };
      setTasks((previous) => [...previous, next]);
      toast.success('Task created in demo mode.');
      return;
    }
    apiService.setConnection(config);
    const next = await apiService.createTask(task);
    setTasks((previous) => [...previous, next]);
  };

  const updateTask = async (id: string, updates: Partial<Task>) => {
    if (isDemoMode) {
      await simulateDelay(300);
      setTasks((previous) =>
        previous.map((task) => (task.id === id ? { ...task, ...updates, updatedAt: new Date().toISOString() } : task)),
      );
      return;
    }
    apiService.setConnection(config);
    const next = await apiService.updateTask(id, updates);
    setTasks((previous) => previous.map((task) => (task.id === id ? next : task)));
  };

  const deleteTask = async (id: string) => {
    if (isDemoMode) {
      await simulateDelay(300);
      setTasks((previous) => previous.filter((task) => task.id !== id));
      return;
    }
    apiService.setConnection(config);
    await apiService.deleteTask(id);
    setTasks((previous) => previous.filter((task) => task.id !== id));
  };

  const toggleTask = async (id: string) => {
    const task = tasks.find((item) => item.id === id);
    if (!task) {
      return;
    }
    await updateTask(id, { completed: !task.completed });
  };

  const value = useMemo(
    () => ({
      tasks,
      backendStatus,
      statusMessage,
      createTask,
      updateTask,
      deleteTask,
      toggleTask,
    }),
    [backendStatus, statusMessage, tasks],
  );

  return <TaskContext.Provider value={value}>{children}</TaskContext.Provider>;
};
