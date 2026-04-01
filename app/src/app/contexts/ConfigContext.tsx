import React, { createContext, ReactNode, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { toast } from 'sonner';
import { apiService } from '../services/api';
import { wsService } from '../services/websocket';
import { AppConfig, BootstrapData, Capabilities, RuntimeState, SessionSummary } from '../models/types';
import { mockBootstrap, mockConfig } from '../utils/mockData';

interface ConfigContextType {
  config: AppConfig;
  isConnected: boolean;
  isConnecting: boolean;
  isDemoMode: boolean;
  eventStreamConnected: boolean;
  sessions: SessionSummary[];
  currentSessionId: string;
  capabilities: Capabilities | null;
  runtimeState: RuntimeState | null;
  connect: (serverUrl: string, port: number, token?: string) => Promise<void>;
  connectDemo: () => void;
  disconnect: () => void;
  setCurrentSessionId: (sessionId: string) => void;
  refreshBootstrap: () => Promise<void>;
}

const STORAGE_KEY = 'ai-bot.app.connection';

const defaultConfig: AppConfig = {
  serverUrl: '',
  serverPort: 8000,
  appToken: '',
  currentSessionId: '',
  latestEventId: '',
};

const ConfigContext = createContext<ConfigContextType | undefined>(undefined);

const readStoredConfig = (): AppConfig => {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return defaultConfig;
    }
    const parsed = JSON.parse(raw);
    return {
      serverUrl: typeof parsed.serverUrl === 'string' ? parsed.serverUrl : '',
      serverPort: typeof parsed.serverPort === 'number' ? parsed.serverPort : 8000,
      appToken: typeof parsed.appToken === 'string' ? parsed.appToken : '',
      currentSessionId: typeof parsed.currentSessionId === 'string' ? parsed.currentSessionId : '',
      latestEventId: typeof parsed.latestEventId === 'string' ? parsed.latestEventId : '',
    };
  } catch {
    return defaultConfig;
  }
};

const persistConfig = (config: AppConfig) => {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
};

const selectSessionId = (bootstrap: BootstrapData, preferredSessionId?: string) => {
  if (preferredSessionId && bootstrap.sessions.some((session) => session.sessionId === preferredSessionId)) {
    return preferredSessionId;
  }
  return bootstrap.sessions[0]?.sessionId ?? '';
};

export const useConfig = () => {
  const context = useContext(ConfigContext);
  if (!context) {
    throw new Error('useConfig must be used within ConfigProvider');
  }
  return context;
};

export const ConfigProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [config, setConfig] = useState<AppConfig>(defaultConfig);
  const [isConnected, setIsConnected] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [isDemoMode, setIsDemoMode] = useState(false);
  const [eventStreamConnected, setEventStreamConnected] = useState(false);
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [capabilities, setCapabilities] = useState<Capabilities | null>(null);
  const [runtimeState, setRuntimeState] = useState<RuntimeState | null>(null);
  const bootstrappedRef = useRef(false);

  const applyBootstrap = (bootstrap: BootstrapData, baseConfig: AppConfig, preferredSessionId?: string) => {
    const currentSessionId = selectSessionId(bootstrap, preferredSessionId);
    const nextConfig: AppConfig = {
      ...baseConfig,
      currentSessionId,
      latestEventId: baseConfig.latestEventId || bootstrap.eventStream.resume.latestEventId,
    };

    setConfig(nextConfig);
    setSessions(bootstrap.sessions);
    setCapabilities(bootstrap.capabilities);
    setRuntimeState(bootstrap.runtime);
    setIsConnected(true);
    persistConfig(nextConfig);

    wsService.setLatestEventId(nextConfig.latestEventId);
    wsService.connect({
      serverUrl: nextConfig.serverUrl,
      serverPort: nextConfig.serverPort,
      appToken: nextConfig.appToken,
      lastEventId: nextConfig.latestEventId,
      replayLimit: bootstrap.eventStream.resume.replayLimit,
    });
  };

  const connectInternal = async (
    serverUrl: string,
    port: number,
    token = '',
    {
      silent = false,
      preferredSessionId,
      lastEventId,
    }: {
      silent?: boolean;
      preferredSessionId?: string;
      lastEventId?: string;
    } = {},
  ) => {
    setIsConnecting(true);
    setIsDemoMode(false);

    const baseConfig: AppConfig = {
      serverUrl: serverUrl.trim(),
      serverPort: port,
      appToken: token.trim(),
      currentSessionId: preferredSessionId ?? '',
      latestEventId: lastEventId ?? '',
    };

    try {
      apiService.setConnection(baseConfig);
      await apiService.checkHealth();
      const bootstrap = await apiService.fetchBootstrap();
      applyBootstrap(bootstrap, baseConfig, preferredSessionId);
      if (!silent) {
        toast.success('Connected to AI-Bot backend.');
      }
    } catch (error) {
      wsService.disconnect();
      apiService.clearConnection();
      setIsConnected(false);
      setEventStreamConnected(false);
      setSessions([]);
      setCapabilities(null);
      setRuntimeState(null);
      setConfig(baseConfig);
      persistConfig(baseConfig);
      if (!silent) {
        toast.error(error instanceof Error ? error.message : 'Connection failed');
      }
      throw error;
    } finally {
      setIsConnecting(false);
    }
  };

  useEffect(() => {
    const stored = readStoredConfig();
    setConfig(stored);

    if (!bootstrappedRef.current && stored.serverUrl) {
      bootstrappedRef.current = true;
      void connectInternal(stored.serverUrl, stored.serverPort, stored.appToken, {
        silent: true,
        preferredSessionId: stored.currentSessionId,
        lastEventId: stored.latestEventId,
      }).catch(() => {
        setConfig(stored);
      });
    }
  }, []);

  useEffect(() => {
    const sync = window.setInterval(() => {
      setEventStreamConnected(wsService.isConnected());
      const latestEventId = wsService.getLatestEventId();
      if (!latestEventId) {
        return;
      }
      setConfig((previous) => {
        if (previous.latestEventId === latestEventId) {
          return previous;
        }
        const next = { ...previous, latestEventId };
        persistConfig(next);
        return next;
      });
    }, 1000);

    return () => window.clearInterval(sync);
  }, []);

  useEffect(() => {
    const handleHello = (event: any) => {
      const payload = event.payload;
      if (payload?.resume?.latest_event_id) {
        wsService.setLatestEventId(String(payload.resume.latest_event_id));
      }
      if (payload?.resume?.should_refetch_bootstrap && config.serverUrl) {
        void refreshBootstrap().catch(() => {
          toast.error('Bootstrap refresh failed after event stream resume.');
        });
      }
    };

    wsService.on('system.hello', handleHello);
    return () => {
      wsService.off('system.hello', handleHello);
    };
  }, [config.serverUrl]);

  const refreshBootstrap = async () => {
    if (!config.serverUrl || isDemoMode) {
      return;
    }
    apiService.setConnection(config);
    const bootstrap = await apiService.fetchBootstrap();
    applyBootstrap(bootstrap, config, config.currentSessionId);
  };

  const connect = async (serverUrl: string, port: number, token = '') => {
    await connectInternal(serverUrl, port, token);
  };

  const connectDemo = () => {
    wsService.disconnect();
    apiService.clearConnection();
    setIsDemoMode(true);
    setIsConnected(true);
    setIsConnecting(false);
    setEventStreamConnected(true);
    setConfig(mockConfig);
    setSessions(mockBootstrap.sessions);
    setCapabilities(mockBootstrap.capabilities);
    setRuntimeState(mockBootstrap.runtime);
    toast.success('Demo mode activated.');
  };

  const disconnect = () => {
    wsService.disconnect();
    apiService.clearConnection();
    setIsConnected(false);
    setIsConnecting(false);
    setIsDemoMode(false);
    setEventStreamConnected(false);
    setSessions([]);
    setCapabilities(null);
    setRuntimeState(null);
    setConfig((previous) => {
      const next = {
        ...previous,
        currentSessionId: '',
        latestEventId: '',
      };
      persistConfig(next);
      return next;
    });
    toast.info('Disconnected from AI-Bot backend.');
  };

  const setCurrentSessionId = (sessionId: string) => {
    setConfig((previous) => {
      const next = { ...previous, currentSessionId: sessionId };
      persistConfig(next);
      return next;
    });
  };

  const value = useMemo(
    () => ({
      config,
      isConnected,
      isConnecting,
      isDemoMode,
      eventStreamConnected,
      sessions,
      currentSessionId: config.currentSessionId,
      capabilities,
      runtimeState,
      connect,
      connectDemo,
      disconnect,
      setCurrentSessionId,
      refreshBootstrap,
    }),
    [
      capabilities,
      config,
      eventStreamConnected,
      isConnected,
      isConnecting,
      isDemoMode,
      runtimeState,
      sessions,
    ],
  );

  return <ConfigContext.Provider value={value}>{children}</ConfigContext.Provider>;
};
