import { Battery, Circle, Wifi } from 'lucide-react';
import { DeviceStatus } from '../models/types';

interface DeviceCardProps {
  status: DeviceStatus;
}

export function DeviceCard({ status }: DeviceCardProps) {
  const stateLabel = status.state.replace(/_/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());

  return (
    <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
      <div className="flex items-center justify-between mb-4">
        <h3 className="font-semibold text-gray-900">Device Snapshot</h3>
        <div className="flex items-center gap-2">
          <Circle className={`w-3 h-3 ${status.connected ? 'fill-green-500 text-green-500' : 'fill-gray-300 text-gray-300'}`} />
          <span className="text-sm text-gray-600">{status.connected ? 'Connected' : 'Offline'}</span>
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
                style={{ width: `${Math.max(0, status.battery)}%` }}
              />
            </div>
            <span className="text-sm font-medium text-gray-900">
              {status.battery >= 0 ? `${status.battery}%` : 'Unknown'}
            </span>
          </div>
        </div>

        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Wifi className="w-5 h-5 text-gray-600" />
            <span className="text-sm text-gray-600">Signal</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-24 h-2 bg-gray-200 rounded-full overflow-hidden">
              <div className="h-full bg-blue-500" style={{ width: `${status.wifiSignal}%` }} />
            </div>
            <span className="text-sm font-medium text-gray-900">{status.wifiSignal}%</span>
          </div>
        </div>

        <div className="flex items-center justify-between pt-2 border-t border-gray-200">
          <span className="text-sm text-gray-600">State</span>
          <span className="text-sm font-medium text-gray-900">{stateLabel}</span>
        </div>

        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-600">Charging</span>
          <span className="text-sm font-medium text-gray-900">{status.charging ? 'Yes' : 'No'}</span>
        </div>

        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-600">Reconnect Count</span>
          <span className="text-sm font-medium text-gray-900">{status.reconnectCount}</span>
        </div>
      </div>
    </div>
  );
}
