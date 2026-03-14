import { useDevice } from '../contexts/DeviceContext';
import { DeviceCard } from '../components/DeviceCard';
import { Volume2, Lightbulb, RotateCw } from 'lucide-react';

export function Home() {
  const { deviceStatus, muteDevice, toggleLED, restartDevice } = useDevice();

  return (
    <div className="p-4 space-y-4">
      <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>

      <DeviceCard status={deviceStatus} />

      <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
        <h3 className="font-semibold text-gray-900 mb-4">Quick Actions</h3>
        <div className="grid grid-cols-3 gap-3">
          <button
            onClick={muteDevice}
            className="flex flex-col items-center gap-2 p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
          >
            <Volume2 className="w-6 h-6 text-gray-700" />
            <span className="text-xs font-medium text-gray-700">Mute</span>
          </button>

          <button
            onClick={toggleLED}
            className="flex flex-col items-center gap-2 p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
          >
            <Lightbulb className="w-6 h-6 text-gray-700" />
            <span className="text-xs font-medium text-gray-700">LED</span>
          </button>

          <button
            onClick={restartDevice}
            className="flex flex-col items-center gap-2 p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
          >
            <RotateCw className="w-6 h-6 text-gray-700" />
            <span className="text-xs font-medium text-gray-700">Restart</span>
          </button>
        </div>
      </div>

      <div className="bg-gradient-to-r from-blue-500 to-purple-600 rounded-lg p-6 text-white">
        <h3 className="text-lg font-semibold mb-2">Welcome to AI-Bot</h3>
        <p className="text-sm text-blue-50">
          Your voice-controlled desktop AI assistant with computer automation.
          Manage tasks, control your device, and chat with AI—all from one place.
        </p>
      </div>
    </div>
  );
}
