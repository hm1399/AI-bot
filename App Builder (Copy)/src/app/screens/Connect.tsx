import { useState } from 'react';
import { useNavigate } from 'react-router';
import { useConfig } from '../contexts/ConfigContext';
import { apiService } from '../services/api';
import { Wifi, Search, Loader2 } from 'lucide-react';

export function Connect() {
  const navigate = useNavigate();
  const { connect } = useConfig();
  const [serverUrl, setServerUrl] = useState('');
  const [port, setPort] = useState('8000');
  const [isScanning, setIsScanning] = useState(false);
  const [devices, setDevices] = useState<{ ip: string; port: number; name: string }[]>([]);

  const handleScan = async () => {
    setIsScanning(true);
    try {
      const discovered = await apiService.discoverDevices();
      setDevices(discovered);
    } catch (error) {
      console.error('Discovery failed:', error);
    } finally {
      setIsScanning(false);
    }
  };

  const handleConnect = (ip: string, devicePort: number) => {
    connect(ip, devicePort);
    navigate('/app');
  };

  const handleManualConnect = () => {
    if (serverUrl && port) {
      connect(serverUrl, parseInt(port));
      navigate('/app');
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-blue-50 to-white flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className="w-20 h-20 bg-blue-500 rounded-full flex items-center justify-center mx-auto mb-4">
            <Wifi className="w-10 h-10 text-white" />
          </div>
          <h1 className="text-3xl font-bold text-gray-900 mb-2">AI-Bot Control</h1>
          <p className="text-gray-600">Connect to your desktop assistant</p>
        </div>

        <div className="bg-white rounded-2xl shadow-lg p-6 mb-4">
          <div className="flex items-center justify-between mb-4">
            <h2 className="font-semibold text-gray-900">Auto Discovery</h2>
            <button
              onClick={handleScan}
              disabled={isScanning}
              className="flex items-center gap-2 px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition-colors disabled:bg-gray-300"
            >
              {isScanning ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Scanning...</span>
                </>
              ) : (
                <>
                  <Search className="w-4 h-4" />
                  <span>Scan Network</span>
                </>
              )}
            </button>
          </div>

          {devices.length > 0 && (
            <div className="space-y-2">
              {devices.map((device) => (
                <button
                  key={device.ip}
                  onClick={() => handleConnect(device.ip, device.port)}
                  className="w-full p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors text-left"
                >
                  <div className="font-medium text-gray-900">{device.name}</div>
                  <div className="text-sm text-gray-600">
                    {device.ip}:{device.port}
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>

        <div className="bg-white rounded-2xl shadow-lg p-6">
          <h2 className="font-semibold text-gray-900 mb-4">Manual Connection</h2>
          <div className="space-y-3">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Server IP / Hostname
              </label>
              <input
                type="text"
                value={serverUrl}
                onChange={(e) => setServerUrl(e.target.value)}
                placeholder="192.168.1.100"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Port
              </label>
              <input
                type="text"
                value={port}
                onChange={(e) => setPort(e.target.value)}
                placeholder="8000"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <button
              onClick={handleManualConnect}
              disabled={!serverUrl || !port}
              className="w-full py-3 bg-blue-500 text-white font-medium rounded-lg hover:bg-blue-600 transition-colors disabled:bg-gray-300 disabled:cursor-not-allowed"
            >
              Connect
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}