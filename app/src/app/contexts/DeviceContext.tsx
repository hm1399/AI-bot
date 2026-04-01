import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { DeviceStatus, RuntimeState } from '../models/types';
import { apiService } from '../services/api';
import { wsService } from '../services/websocket';
import { useConfig } from './ConfigContext';
import { mockRuntimeState } from '../utils/mockData';

interface DeviceContextType {
  deviceStatus: DeviceStatus;
  runtimeState: RuntimeState | null;
  refreshRuntime: () => Promise<void>;
  stopCurrentTask: () => Promise<void>;
  speakTestPhrase: () => Promise<void>;
}

const DeviceContext = createContext<DeviceContextType | undefined>(undefined);

const normalizeSignalStrength = (wifiRssi: number) => {
  if (wifiRssi === 0) {
    return 0;
  }
  const normalized = Math.round(((wifiRssi + 100) / 60) * 100);
  return Math.max(0, Math.min(100, normalized));
};

const defaultRuntimeState: RuntimeState = {
  currentTask: null,
  taskQueue: [],
  device: {
    connected: false,
    state: 'unknown',
    battery: -1,
    wifiRssi: 0,
    wifiSignal: 0,
    charging: false,
    reconnectCount: 0,
  },
  todoSummary: {
    enabled: false,
    pendingCount: 0,
    overdueCount: 0,
    nextDueAt: null,
  },
  calendarSummary: {
    enabled: false,
    todayCount: 0,
    nextEventAt: null,
    nextEventTitle: null,
  },
};

export const useDevice = () => {
  const context = useContext(DeviceContext);
  if (!context) {
    throw new Error('useDevice must be used within DeviceProvider');
  }
  return context;
};

export const DeviceProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { config, isConnected, isDemoMode, runtimeState: bootstrapRuntimeState } = useConfig();
  const [runtimeState, setRuntimeState] = useState<RuntimeState>(defaultRuntimeState);

  useEffect(() => {
    if (bootstrapRuntimeState) {
      setRuntimeState(bootstrapRuntimeState);
    }
  }, [bootstrapRuntimeState]);

  useEffect(() => {
    if (isDemoMode) {
      setRuntimeState(mockRuntimeState);
      return;
    }

    if (!isConnected) {
      setRuntimeState(defaultRuntimeState);
      return;
    }

    apiService.setConnection(config);
    void apiService
      .fetchRuntimeState()
      .then((next) => setRuntimeState(next))
      .catch((error) => console.error('Failed to fetch runtime state', error));

    const handleCurrentTask = (event: any) => {
      setRuntimeState((previous) => ({
        ...previous,
        currentTask: event.payload?.current_task
          ? {
              taskId: String(event.payload.current_task.task_id ?? ''),
              kind: String(event.payload.current_task.kind ?? 'chat'),
              sourceChannel: String(event.payload.current_task.source_channel ?? 'app'),
              sourceSessionId: String(event.payload.current_task.source_session_id ?? ''),
              summary: String(event.payload.current_task.summary ?? ''),
              stage: String(event.payload.current_task.stage ?? 'queued'),
              cancellable: Boolean(event.payload.current_task.cancellable),
              startedAt: event.payload.current_task.started_at
                ? String(event.payload.current_task.started_at)
                : null,
            }
          : null,
      }));
    };

    const handleQueue = (event: any) => {
      setRuntimeState((previous) => ({
        ...previous,
        taskQueue: Array.isArray(event.payload?.task_queue)
          ? event.payload.task_queue.map((item: any) => ({
              taskId: String(item?.task_id ?? ''),
              kind: String(item?.kind ?? 'chat'),
              sourceChannel: String(item?.source_channel ?? 'app'),
              sourceSessionId: String(item?.source_session_id ?? ''),
              summary: String(item?.summary ?? ''),
              stage: String(item?.stage ?? 'queued'),
              cancellable: Boolean(item?.cancellable),
            }))
          : [],
      }));
    };

    const handleDeviceConnection = (event: any) => {
      setRuntimeState((previous) => ({
        ...previous,
        device: {
          ...previous.device,
          connected: Boolean(event.payload?.connected),
          reconnectCount: Number(event.payload?.reconnect_count ?? previous.device.reconnectCount),
        },
      }));
    };

    const handleDeviceState = (event: any) => {
      setRuntimeState((previous) => ({
        ...previous,
        device: {
          ...previous.device,
          state: String(event.payload?.state ?? previous.device.state).toLowerCase(),
        },
      }));
    };

    const handleDeviceStatus = (event: any) => {
      setRuntimeState((previous) => {
        const wifiRssi = Number(event.payload?.wifi_rssi ?? previous.device.wifiRssi);
        return {
          ...previous,
          device: {
            ...previous.device,
            battery: Number(event.payload?.battery ?? previous.device.battery),
            wifiRssi,
            wifiSignal: normalizeSignalStrength(wifiRssi),
            charging: Boolean(event.payload?.charging ?? previous.device.charging),
          },
        };
      });
    };

    const handleTodo = (event: any) => {
      setRuntimeState((previous) => ({
        ...previous,
        todoSummary: {
          enabled: Boolean(event.payload?.enabled),
          pendingCount: Number(event.payload?.pending_count ?? 0),
          overdueCount: Number(event.payload?.overdue_count ?? 0),
          nextDueAt: event.payload?.next_due_at ? String(event.payload.next_due_at) : null,
        },
      }));
    };

    const handleCalendar = (event: any) => {
      setRuntimeState((previous) => ({
        ...previous,
        calendarSummary: {
          enabled: Boolean(event.payload?.enabled),
          todayCount: Number(event.payload?.today_count ?? 0),
          nextEventAt: event.payload?.next_event_at ? String(event.payload.next_event_at) : null,
          nextEventTitle: event.payload?.next_event_title ? String(event.payload.next_event_title) : null,
        },
      }));
    };

    wsService.on('runtime.task.current_changed', handleCurrentTask);
    wsService.on('runtime.task.queue_changed', handleQueue);
    wsService.on('device.connection.changed', handleDeviceConnection);
    wsService.on('device.state.changed', handleDeviceState);
    wsService.on('device.status.updated', handleDeviceStatus);
    wsService.on('todo.summary.changed', handleTodo);
    wsService.on('calendar.summary.changed', handleCalendar);

    return () => {
      wsService.off('runtime.task.current_changed', handleCurrentTask);
      wsService.off('runtime.task.queue_changed', handleQueue);
      wsService.off('device.connection.changed', handleDeviceConnection);
      wsService.off('device.state.changed', handleDeviceState);
      wsService.off('device.status.updated', handleDeviceStatus);
      wsService.off('todo.summary.changed', handleTodo);
      wsService.off('calendar.summary.changed', handleCalendar);
    };
  }, [config, isConnected, isDemoMode]);

  const refreshRuntime = async () => {
    if (isDemoMode) {
      setRuntimeState(mockRuntimeState);
      return;
    }
    apiService.setConnection(config);
    const next = await apiService.fetchRuntimeState();
    setRuntimeState(next);
  };

  const stopCurrentTask = async () => {
    if (!runtimeState.currentTask) {
      toast.info('No running task to stop.');
      return;
    }
    if (isDemoMode) {
      setRuntimeState((previous) => ({ ...previous, currentTask: null }));
      toast.success('Demo task cleared.');
      return;
    }
    try {
      apiService.setConnection(config);
      await apiService.stopRuntimeTask(runtimeState.currentTask.taskId);
      toast.success('Stop request sent to backend.');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Failed to stop task');
    }
  };

  const speakTestPhrase = async () => {
    if (isDemoMode) {
      toast.success('Demo device accepted the test phrase.');
      return;
    }
    try {
      apiService.setConnection(config);
      await apiService.speak('Testing speech output from the app.');
      toast.success('Device speech request accepted.');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Failed to trigger speech');
    }
  };

  const value = useMemo(
    () => ({
      deviceStatus: runtimeState.device,
      runtimeState,
      refreshRuntime,
      stopCurrentTask,
      speakTestPhrase,
    }),
    [runtimeState],
  );

  return <DeviceContext.Provider value={value}>{children}</DeviceContext.Provider>;
};
