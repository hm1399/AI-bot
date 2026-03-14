import React, { createContext, useContext, useEffect, useState } from 'react';
import { AppConfig } from '../models/types';
import { wsService } from '../services/websocket';
import { apiService } from '../services/api';
import { toast } from 'sonner';

interface ConfigContextType {
  config: AppConfig;
  updateConfig: (updates: Partial<AppConfig>) => Promise<void>;
  isConnected: boolean;
  connect: (serverUrl: string, port: number) => void;
  disconnect: () => void;
}

const ConfigContext = createContext<ConfigContextType | undefined>(undefined);

const defaultConfig: AppConfig = {
  serverUrl: '',
  serverPort: 8000,
  llmModel: 'gpt-4',
  ttsVoice: 'en-US-AriaNeural',
  ttsSpeed: 1.0,
  deviceVolume: 80,
  ledMode: 'breathing',
};

export const ConfigProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [config, setConfig] = useState<AppConfig>(defaultConfig);
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    const handleConfigUpdate = (data: AppConfig) => {
      setConfig(data);
    };

    wsService.on('config_update', handleConfigUpdate);

    // Check connection status periodically
    const interval = setInterval(() => {
      setIsConnected(wsService.isConnected());
    }, 1000);

    return () => {
      wsService.off('config_update', handleConfigUpdate);
      clearInterval(interval);
    };
  }, []);

  const connect = (serverUrl: string, port: number) => {
    apiService.setBaseUrl(serverUrl, port);
    wsService.connect(serverUrl, port);
    setConfig((prev) => ({ ...prev, serverUrl, serverPort: port }));
    toast.success('Connecting to device...');
    
    // Fetch config after connection
    setTimeout(() => {
      apiService.getConfig().then(setConfig).catch(console.error);
    }, 1000);
  };

  const disconnect = () => {
    wsService.disconnect();
    setIsConnected(false);
    toast.info('Disconnected from device');
  };

  const updateConfig = async (updates: Partial<AppConfig>) => {
    try {
      const updated = await apiService.updateConfig(updates);
      setConfig(updated);
      toast.success('Settings saved successfully');
    } catch (error) {
      toast.error('Failed to save settings');
      throw error;
    }
  };

  return (
    <ConfigContext.Provider value={{ config, updateConfig, isConnected, connect, disconnect }}>
      {children}
    </ConfigContext.Provider>
  );
};

export const useConfig = () => {
  const context = useContext(ConfigContext);
  if (!context) {
    throw new Error('useConfig must be used within ConfigProvider');
  }
  return context;
};