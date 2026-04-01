import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Message } from '../models/types';
import { apiService } from '../services/api';
import { wsService } from '../services/websocket';
import { useConfig } from './ConfigContext';
import { generateId, mockMessages, simulateDelay } from '../utils/mockData';

interface ChatContextType {
  messages: Message[];
  sendMessage: (text: string) => Promise<void>;
  isLoading: boolean;
  voiceAvailable: boolean;
  triggerVoiceInput: () => void;
}

const ChatContext = createContext<ChatContextType | undefined>(undefined);

const normalizeMessage = (payload: any): Message => ({
  id: String(payload?.message_id ?? ''),
  sessionId: String(payload?.session_id ?? ''),
  role: payload?.role === 'assistant' || payload?.role === 'system' ? payload.role : 'user',
  text: String(payload?.content ?? ''),
  status:
    payload?.status === 'pending' ||
    payload?.status === 'failed' ||
    payload?.status === 'streaming'
      ? payload.status
      : 'completed',
  createdAt: String(payload?.created_at ?? new Date().toISOString()),
  metadata: payload?.metadata && typeof payload.metadata === 'object' ? payload.metadata : {},
});

const upsertMessage = (items: Message[], message: Message) => {
  const index = items.findIndex((item) => item.id === message.id);
  if (index === -1) {
    return [...items, message].sort((left, right) => left.createdAt.localeCompare(right.createdAt));
  }
  const next = [...items];
  next[index] = { ...next[index], ...message };
  return next.sort((left, right) => left.createdAt.localeCompare(right.createdAt));
};

export const useChat = () => {
  const context = useContext(ChatContext);
  if (!context) {
    throw new Error('useChat must be used within ChatProvider');
  }
  return context;
};

export const ChatProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { config, currentSessionId, isConnected, isDemoMode, capabilities } = useConfig();
  const [messages, setMessages] = useState<Message[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (!currentSessionId) {
      setMessages([]);
      return;
    }

    if (isDemoMode) {
      setMessages(mockMessages.filter((message) => message.sessionId === currentSessionId));
      return;
    }

    if (!isConnected) {
      setMessages([]);
      return;
    }

    let active = true;

    apiService.setConnection(config);
    apiService
      .getMessages(currentSessionId)
      .then((page) => {
        if (active) {
          setMessages(page.items);
        }
      })
      .catch((error) => {
        if (active) {
          console.error('Failed to fetch messages', error);
        }
      });

    const handleCreated = (event: any) => {
      const next = normalizeMessage(event.payload?.message);
      if (next.sessionId !== currentSessionId) {
        return;
      }
      setMessages((previous) => upsertMessage(previous, next));
    };

    const handleProgress = (event: any) => {
      if (event.sessionId !== currentSessionId) {
        return;
      }
      const messageId = String(event.payload?.message_id ?? `assistant-${event.taskId ?? generateId()}`);
      setMessages((previous) =>
        upsertMessage(previous, {
          id: messageId,
          sessionId: currentSessionId,
          role: 'assistant',
          text: String(event.payload?.content ?? ''),
          status: 'streaming',
          createdAt: new Date().toISOString(),
          metadata: {
            taskId: event.taskId,
            kind: event.payload?.kind,
          },
        }),
      );
    };

    const handleCompleted = (event: any) => {
      const next = normalizeMessage(event.payload?.message);
      if (next.sessionId !== currentSessionId) {
        return;
      }
      setMessages((previous) => upsertMessage(previous, next));
    };

    const handleFailed = (event: any) => {
      if (event.sessionId !== currentSessionId) {
        return;
      }
      const messageId = String(event.payload?.message_id ?? `assistant-${event.taskId ?? generateId()}`);
      setMessages((previous) =>
        upsertMessage(previous, {
          id: messageId,
          sessionId: currentSessionId,
          role: 'assistant',
          text: 'Assistant response failed.',
          status: 'failed',
          createdAt: new Date().toISOString(),
          errorReason: String(event.payload?.reason ?? 'unknown_error'),
          metadata: {
            taskId: event.taskId,
          },
        }),
      );
      toast.error(`Assistant response failed: ${String(event.payload?.reason ?? 'unknown_error')}`);
    };

    wsService.on('session.message.created', handleCreated);
    wsService.on('session.message.progress', handleProgress);
    wsService.on('session.message.completed', handleCompleted);
    wsService.on('session.message.failed', handleFailed);

    return () => {
      active = false;
      wsService.off('session.message.created', handleCreated);
      wsService.off('session.message.progress', handleProgress);
      wsService.off('session.message.completed', handleCompleted);
      wsService.off('session.message.failed', handleFailed);
    };
  }, [config, currentSessionId, isConnected, isDemoMode]);

  const sendMessage = async (text: string) => {
    if (!text.trim() || !currentSessionId) {
      return;
    }

    setIsLoading(true);

    if (isDemoMode) {
      try {
        const userMessage: Message = {
          id: generateId(),
          sessionId: currentSessionId,
          role: 'user',
          text,
          status: 'completed',
          createdAt: new Date().toISOString(),
        };

        setMessages((previous) => upsertMessage(previous, userMessage));
        await simulateDelay(700);

        const assistantMessage: Message = {
          id: generateId(),
          sessionId: currentSessionId,
          role: 'assistant',
          text: 'Demo mode keeps all messages local. Real mode sends the user message to the backend and waits for server events.',
          status: 'completed',
          createdAt: new Date().toISOString(),
        };

        setMessages((previous) => upsertMessage(previous, assistantMessage));
      } catch {
        toast.error('Failed to simulate demo reply.');
      } finally {
        setIsLoading(false);
      }
      return;
    }

    if (!isConnected) {
      toast.error('Connect to the backend before sending messages.');
      setIsLoading(false);
      return;
    }

    try {
      apiService.setConnection(config);
      const result = await apiService.postMessage(currentSessionId, text, `web_${Date.now()}`);
      setMessages((previous) => upsertMessage(previous, result.acceptedMessage));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Failed to send message');
    } finally {
      setIsLoading(false);
    }
  };

  const triggerVoiceInput = () => {
    if (isDemoMode) {
      toast.info('Demo mode keeps the voice entry visible, but capture is not connected.');
      return;
    }
    toast.info('Voice capture entry is reserved for the backend-aligned pipeline.');
  };

  const value = useMemo(
    () => ({
      messages,
      sendMessage,
      isLoading,
      voiceAvailable: Boolean(capabilities?.voicePipeline),
      triggerVoiceInput,
    }),
    [capabilities?.voicePipeline, isLoading, messages],
  );

  return <ChatContext.Provider value={value}>{children}</ChatContext.Provider>;
};
