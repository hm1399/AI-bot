import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { Event } from '../models/types';
import { apiService, isBackendNotReadyError } from '../services/api';
import { useConfig } from './ConfigContext';
import { generateId, mockEvents, simulateDelay } from '../utils/mockData';

type BackendStatus = 'idle' | 'loading' | 'ready' | 'not-ready' | 'error' | 'demo';

interface EventContextType {
  events: Event[];
  backendStatus: BackendStatus;
  statusMessage: string | null;
  createEvent: (event: Omit<Event, 'id' | 'createdAt' | 'updatedAt'>) => Promise<void>;
  updateEvent: (id: string, updates: Partial<Event>) => Promise<void>;
  deleteEvent: (id: string) => Promise<void>;
}

const EventContext = createContext<EventContextType | undefined>(undefined);

export const useEvents = () => {
  const context = useContext(EventContext);
  if (!context) {
    throw new Error('useEvents must be used within EventProvider');
  }
  return context;
};

export const EventProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { config, isConnected, isDemoMode } = useConfig();
  const [events, setEvents] = useState<Event[]>([]);
  const [backendStatus, setBackendStatus] = useState<BackendStatus>('idle');
  const [statusMessage, setStatusMessage] = useState<string | null>(null);

  useEffect(() => {
    if (isDemoMode) {
      setEvents(mockEvents);
      setBackendStatus('demo');
      setStatusMessage('Demo mode uses local calendar data and does not touch production APIs.');
      return;
    }

    if (!isConnected) {
      setEvents([]);
      setBackendStatus('idle');
      setStatusMessage(null);
      return;
    }

    setBackendStatus('loading');
    setStatusMessage(null);
    apiService.setConnection(config);
    apiService
      .listEvents()
      .then((items) => {
        setEvents(items);
        setBackendStatus('ready');
      })
      .catch((error) => {
        if (isBackendNotReadyError(error)) {
          setBackendStatus('not-ready');
          setStatusMessage('后端日程接口尚未提供，当前前端仅保留入口与错误提示。');
          return;
        }
        setBackendStatus('error');
        setStatusMessage(error instanceof Error ? error.message : 'Failed to load events');
      });
  }, [config, isConnected, isDemoMode]);

  const createEvent = async (event: Omit<Event, 'id' | 'createdAt' | 'updatedAt'>) => {
    if (isDemoMode) {
      await simulateDelay();
      setEvents((previous) => [
        ...previous,
        {
          ...event,
          id: generateId(),
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        },
      ]);
      return;
    }
    apiService.setConnection(config);
    const next = await apiService.createEvent(event);
    setEvents((previous) => [...previous, next]);
  };

  const updateEvent = async (id: string, updates: Partial<Event>) => {
    if (isDemoMode) {
      await simulateDelay(300);
      setEvents((previous) =>
        previous.map((event) => (event.id === id ? { ...event, ...updates, updatedAt: new Date().toISOString() } : event)),
      );
      return;
    }
    apiService.setConnection(config);
    const next = await apiService.updateEvent(id, updates);
    setEvents((previous) => previous.map((event) => (event.id === id ? next : event)));
  };

  const deleteEvent = async (id: string) => {
    if (isDemoMode) {
      await simulateDelay(300);
      setEvents((previous) => previous.filter((event) => event.id !== id));
      return;
    }
    apiService.setConnection(config);
    await apiService.deleteEvent(id);
    setEvents((previous) => previous.filter((event) => event.id !== id));
  };

  const value = useMemo(
    () => ({
      events,
      backendStatus,
      statusMessage,
      createEvent,
      updateEvent,
      deleteEvent,
    }),
    [backendStatus, events, statusMessage],
  );

  return <EventContext.Provider value={value}>{children}</EventContext.Provider>;
};
