import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router';
import { AlertCircle, Wifi, Zap } from 'lucide-react';
import { useConfig } from '../contexts/ConfigContext';

export function Connect() {
  const navigate = useNavigate();
  const { config, connect, connectDemo, isConnecting } = useConfig();
  const [serverUrl, setServerUrl] = useState(config.serverUrl);
  const [port, setPort] = useState(String(config.serverPort || 8000));
  const [appToken, setAppToken] = useState(config.appToken);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setServerUrl(config.serverUrl);
    setPort(String(config.serverPort || 8000));
    setAppToken(config.appToken);
  }, [config.appToken, config.serverPort, config.serverUrl]);

  const handleManualConnect = async () => {
    if (!serverUrl.trim() || !port.trim()) {
      return;
    }

    setError(null);
    try {
      await connect(serverUrl.trim(), Number(port), appToken.trim());
      navigate('/app');
    } catch (connectionError) {
      setError(connectionError instanceof Error ? connectionError.message : 'Connection failed');
    }
  };

  const handleDemoMode = () => {
    setError(null);
    connectDemo();
    navigate('/app');
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-100 via-blue-50 to-cyan-100 flex items-center justify-center p-4">
      <div className="max-w-md w-full">
        <div className="bg-white rounded-2xl shadow-xl p-8 border border-white/70">
          <div className="text-center mb-8">
            <div className="inline-flex items-center justify-center w-16 h-16 bg-blue-100 rounded-full mb-4">
              <Wifi className="w-8 h-8 text-blue-600" />
            </div>
            <h1 className="text-2xl font-bold text-gray-900 mb-2">Connect to AI-Bot</h1>
            <p className="text-gray-600">
              Validate health, fetch bootstrap, then attach to the app event stream.
            </p>
          </div>

          <div className="space-y-6">
            <button
              onClick={handleDemoMode}
              className="w-full flex items-center justify-center gap-2 px-6 py-3 bg-gradient-to-r from-amber-500 to-orange-500 text-white rounded-lg hover:from-amber-600 hover:to-orange-600 transition-all shadow-md hover:shadow-lg"
            >
              <Zap className="w-5 h-5" />
              Try Demo Mode
            </button>

            <div className="relative">
              <div className="absolute inset-0 flex items-center">
                <div className="w-full border-t border-gray-300" />
              </div>
              <div className="relative flex justify-center text-sm">
                <span className="px-2 bg-white text-gray-500">or connect to the real backend</span>
              </div>
            </div>

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Server Host</label>
                <input
                  type="text"
                  value={serverUrl}
                  onChange={(event) => setServerUrl(event.target.value)}
                  placeholder="192.168.1.100 or localhost"
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Port</label>
                <input
                  type="number"
                  value={port}
                  onChange={(event) => setPort(event.target.value)}
                  placeholder="8000"
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">App Token (optional)</label>
                <input
                  type="password"
                  value={appToken}
                  onChange={(event) => setAppToken(event.target.value)}
                  placeholder="Bearer token or X-App-Token"
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
                <p className="text-xs text-gray-500 mt-1">
                  Used for both HTTP and WebSocket auth when the backend enables app auth.
                </p>
              </div>

              <button
                onClick={handleManualConnect}
                disabled={!serverUrl.trim() || !port.trim() || isConnecting}
                className="w-full px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
              >
                {isConnecting ? 'Validating connection...' : 'Validate Connection'}
              </button>
            </div>

            <div className="rounded-lg border border-dashed border-gray-300 bg-gray-50 p-4">
              <p className="text-sm font-medium text-gray-800 mb-1">LAN scan</p>
              <p className="text-sm text-gray-600">
                The old fake network scan was removed. Discovery should come back later as a real mDNS/zeroconf feature.
              </p>
            </div>

            {error && (
              <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700 flex gap-2">
                <AlertCircle className="w-5 h-5 flex-shrink-0" />
                <span>{error}</span>
              </div>
            )}
          </div>

          <div className="mt-6 p-4 bg-blue-50 rounded-lg">
            <p className="text-sm text-blue-800">
              Real mode follows `/api/app/v1` plus `/ws/app/v1/events`. AI replies are server-driven, not fetched directly from model vendors.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
