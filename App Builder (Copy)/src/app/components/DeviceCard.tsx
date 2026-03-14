import { DeviceStatus } from '../models/types';
import { Battery, Wifi, Circle } from 'lucide-react';

interface DeviceCardProps {
  status: DeviceStatus;
}

export function DeviceCard({ status }: DeviceCardProps) {
  const stateColors = {
    idle: 'text-gray-500',
    recording: 'text-red-500',
    playing: 'text-green-500',
    processing: 'text-yellow-500',
  };

  const stateText = {
    idle: 'Standby',
    recording: 'Recording',
    playing: 'Playing',
    processing: 'Processing',
  };

  return (
    <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
      <div className="flex items-center justify-between mb-4">
        <h3 className="font-semibold text-gray-900">Device Status</h3>
        <div className="flex items-center gap-2">
          <Circle className={`w-3 h-3 ${status.online ? 'fill-green-500 text-green-500' : 'fill-gray-300 text-gray-300'}`} />
          <span className="text-sm text-gray-600">{status.online ? 'Online' : 'Offline'}</span>
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Battery className="w-5 h-5 text-gray-600" />
            <span className="text-sm text-gray-600">Battery</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-24 h-2 bg-gray-200 rounded-full overflow-hidden">
              <div 
                className={`h-full ${status.battery > 20 ? 'bg-green-500' : 'bg-red-500'}`}
                style={{ width: `${status.battery}%` }}
              />
            </div>
            <span className="text-sm font-medium text-gray-900">{status.battery}%</span>
          </div>
        </div>

        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Wifi className="w-5 h-5 text-gray-600" />
            <span className="text-sm text-gray-600">WiFi Signal</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-24 h-2 bg-gray-200 rounded-full overflow-hidden">
              <div 
                className="h-full bg-blue-500"
                style={{ width: `${status.wifiSignal}%` }}
              />
            </div>
            <span className="text-sm font-medium text-gray-900">{status.wifiSignal}%</span>
          </div>
        </div>

        <div className="flex items-center justify-between pt-2 border-t border-gray-200">
          <span className="text-sm text-gray-600">Current State</span>
          <span className={`text-sm font-medium ${stateColors[status.state]}`}>
            {stateText[status.state]}
          </span>
        </div>

        {status.lastSeen && (
          <div className="text-xs text-gray-500">
            Last seen: {new Date(status.lastSeen).toLocaleString()}
          </div>
        )}
      </div>
    </div>
  );
}
