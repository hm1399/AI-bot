import React, { createContext, useContext, useEffect, useState } from 'react';
import { Task } from '../models/types';
import { wsService } from '../services/websocket';
import { apiService } from '../services/api';
import { toast } from 'sonner';

interface TaskContextType {
  tasks: Task[];
  createTask: (task: Omit<Task, 'id' | 'createdAt'>) => Promise<void>;
  updateTask: (id: string, updates: Partial<Task>) => Promise<void>;
  deleteTask: (id: string) => Promise<void>;
  toggleTask: (id: string) => Promise<void>;
}

const TaskContext = createContext<TaskContextType | undefined>(undefined);

export const TaskProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [tasks, setTasks] = useState<Task[]>([]);

  useEffect(() => {
    const handleTaskUpdate = (data: Task) => {
      setTasks((prev) => {
        const index = prev.findIndex((t) => t.id === data.id);
        if (index >= 0) {
          const updated = [...prev];
          updated[index] = data;
          return updated;
        }
        return [...prev, data];
      });
    };

    wsService.on('task_update', handleTaskUpdate);

    // Fetch tasks
    apiService.getTasks().then(setTasks).catch(console.error);

    return () => {
      wsService.off('task_update', handleTaskUpdate);
    };
  }, []);

  const createTask = async (task: Omit<Task, 'id' | 'createdAt'>) => {
    try {
      const newTask = await apiService.createTask(task);
      setTasks((prev) => [...prev, newTask]);
      toast.success('Task created successfully');
    } catch (error) {
      toast.error('Failed to create task');
      throw error;
    }
  };

  const updateTask = async (id: string, updates: Partial<Task>) => {
    try {
      const updated = await apiService.updateTask(id, updates);
      setTasks((prev) => prev.map((t) => (t.id === id ? updated : t)));
    } catch (error) {
      toast.error('Failed to update task');
      throw error;
    }
  };

  const deleteTask = async (id: string) => {
    try {
      await apiService.deleteTask(id);
      setTasks((prev) => prev.filter((t) => t.id !== id));
      toast.success('Task deleted');
    } catch (error) {
      toast.error('Failed to delete task');
      throw error;
    }
  };

  const toggleTask = async (id: string) => {
    const task = tasks.find((t) => t.id === id);
    if (task) {
      await updateTask(id, { completed: !task.completed });
    }
  };

  return (
    <TaskContext.Provider value={{ tasks, createTask, updateTask, deleteTask, toggleTask }}>
      {children}
    </TaskContext.Provider>
  );
};

export const useTasks = () => {
  const context = useContext(TaskContext);
  if (!context) {
    throw new Error('useTasks must be used within TaskProvider');
  }
  return context;
};