import React, { createContext, useContext, useEffect, useState } from 'react';
import { Message } from '../models/types';
import { wsService } from '../services/websocket';
import { apiService } from '../services/api';
import { toast } from 'sonner';

interface ChatContextType {
  messages: Message[];
  sendMessage: (text: string) => Promise<void>;
  isLoading: boolean;
}

const ChatContext = createContext<ChatContextType | undefined>(undefined);

export const ChatProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [messages, setMessages] = useState<Message[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    const handleChatMessage = (data: Message) => {
      setMessages((prev) => [...prev, data]);
    };

    wsService.on('chat_message', handleChatMessage);

    // Fetch chat history
    apiService.getChatHistory().then(setMessages).catch(console.error);

    return () => {
      wsService.off('chat_message', handleChatMessage);
    };
  }, []);

  const sendMessage = async (text: string) => {
    if (!text.trim()) return;
    
    setIsLoading(true);
    try {
      const message = await apiService.sendChatMessage(text);
      setMessages((prev) => [...prev, message]);
    } catch (error) {
      console.error('Failed to send message:', error);
      toast.error('Failed to send message. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <ChatContext.Provider value={{ messages, sendMessage, isLoading }}>
      {children}
    </ChatContext.Provider>
  );
};

export const useChat = () => {
  const context = useContext(ChatContext);
  if (!context) {
    throw new Error('useChat must be used within ChatProvider');
  }
  return context;
};