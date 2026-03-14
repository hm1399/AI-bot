import React, { createContext, useContext, useEffect, useState } from 'react';
import { Event } from '../models/types';
import { wsService } from '../services/websocket';
import { apiService } from '../services/api';
import { toast } from 'sonner';

interface EventContextType {
  events: Event[];
  createEvent: (event: Omit<Event, 'id' | 'createdAt'>) => Promise<void>;
  updateEvent: (id: string, updates: Partial<Event>) => Promise<void>;
  deleteEvent: (id: string) => Promise<void>;
}

const EventContext = createContext<EventContextType | undefined>(undefined);

export const EventProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [events, setEvents] = useState<Event[]>([]);

  useEffect(() => {
    const handleEventUpdate = (data: Event) => {
      setEvents((prev) => {
        const index = prev.findIndex((e) => e.id === data.id);
        if (index >= 0) {
          const updated = [...prev];
          updated[index] = data;
          return updated;
        }
        return [...prev, data];
      });
    };

    wsService.on('event_update', handleEventUpdate);

    // Fetch events
    apiService.getEvents().then(setEvents).catch(console.error);

    return () => {
      wsService.off('event_update', handleEventUpdate);
    };
  }, []);

  const createEvent = async (event: Omit<Event, 'id' | 'createdAt'>) => {
    try {
      const newEvent = await apiService.createEvent(event);
      setEvents((prev) => [...prev, newEvent]);
      toast.success('Event created successfully');
    } catch (error) {
      toast.error('Failed to create event');
      throw error;
    }
  };

  const updateEvent = async (id: string, updates: Partial<Event>) => {
    try {
      const updated = await apiService.updateEvent(id, updates);
      setEvents((prev) => prev.map((e) => (e.id === id ? updated : e)));
    } catch (error) {
      toast.error('Failed to update event');
      throw error;
    }
  };

  const deleteEvent = async (id: string) => {
    try {
      await apiService.deleteEvent(id);
      setEvents((prev) => prev.filter((e) => e.id !== id));
      toast.success('Event deleted');
    } catch (error) {
      toast.error('Failed to delete event');
      throw error;
    }
  };

  return (
    <EventContext.Provider value={{ events, createEvent, updateEvent, deleteEvent }}>
      {children}
    </EventContext.Provider>
  );
};

export const useEvents = () => {
  const context = useContext(EventContext);
  if (!context) {
    throw new Error('useEvents must be used within EventProvider');
  }
  return context;
};