import React, { createContext, useContext, useEffect, useState } from 'react';
import { DeviceStatus } from '../models/types';
import { wsService } from '../services/websocket';
import { apiService } from '../services/api';
import { toast } from 'sonner';

interface DeviceContextType {
  deviceStatus: DeviceStatus;
  muteDevice: () => Promise<void>;
  toggleLED: () => Promise<void>;
  restartDevice: () => Promise<void>;
}

const DeviceContext = createContext<DeviceContextType | undefined>(undefined);

export const DeviceProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [deviceStatus, setDeviceStatus] = useState<DeviceStatus>({
    online: false,
    battery: 0,
    wifiSignal: 0,
    state: 'idle',
  });

  useEffect(() => {
    const handleDeviceStatus = (data: DeviceStatus) => {
      setDeviceStatus(data);
    };

    wsService.on('device_status', handleDeviceStatus);

    // Fetch initial status
    apiService.getDeviceStatus().then(setDeviceStatus).catch(console.error);

    return () => {
      wsService.off('device_status', handleDeviceStatus);
    };
  }, []);

  const muteDevice = async () => {
    try {
      await apiService.muteDevice();
      toast.success('Device muted');
    } catch (error) {
      toast.error('Failed to mute device');
    }
  };

  const toggleLED = async () => {
    try {
      await apiService.toggleLED();
      toast.success('LED toggled');
    } catch (error) {
      toast.error('Failed to toggle LED');
    }
  };

  const restartDevice = async () => {
    try {
      await apiService.restartDevice();
      toast.success('Device restarting...');
    } catch (error) {
      toast.error('Failed to restart device');
    }
  };

  return (
    <DeviceContext.Provider value={{ deviceStatus, muteDevice, toggleLED, restartDevice }}>
      {children}
    </DeviceContext.Provider>
  );
};

export const useDevice = () => {
  const context = useContext(DeviceContext);
  if (!context) {
    throw new Error('useDevice must be used within DeviceProvider');
  }
  return context;
};