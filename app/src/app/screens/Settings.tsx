import { useEffect, useMemo, useState } from 'react';
import { Brain, Info, Lightbulb, Settings2, Volume2, Wifi } from 'lucide-react';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';
import { Label } from '../components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../components/ui/select';
import { Slider } from '../components/ui/slider';
import { useConfig } from '../contexts/ConfigContext';
import { apiService, isBackendNotReadyError } from '../services/api';
import { SettingsData, SettingsUpdateInput } from '../models/types';
import { mockSettings } from '../utils/mockData';

type ScreenStatus = 'idle' | 'loading' | 'ready' | 'not-ready' | 'error' | 'demo';

const buildDraft = (settings: SettingsData): SettingsUpdateInput => ({
  llmProvider: settings.llmProvider,
  llmModel: settings.llmModel,
  llmBaseUrl: settings.llmBaseUrl,
  sttLanguage: settings.sttLanguage,
  ttsVoice: settings.ttsVoice,
  ttsSpeed: settings.ttsSpeed,
  deviceVolume: settings.deviceVolume,
  ledMode: settings.ledMode,
  ledColor: settings.ledColor,
  wakeWord: settings.wakeWord,
  autoListen: settings.autoListen,
});

export function Settings() {
  const { config, isConnected, isDemoMode, disconnect } = useConfig();
  const [settings, setSettings] = useState<SettingsData | null>(null);
  const [draft, setDraft] = useState<SettingsUpdateInput>(buildDraft(mockSettings));
  const [pendingApiKey, setPendingApiKey] = useState('');
  const [screenStatus, setScreenStatus] = useState<ScreenStatus>('idle');
  const [screenMessage, setScreenMessage] = useState<string | null>(null);
  const [testResult, setTestResult] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [isTesting, setIsTesting] = useState(false);

  useEffect(() => {
    if (isDemoMode) {
      setSettings(mockSettings);
      setDraft(buildDraft(mockSettings));
      setScreenStatus('demo');
      setScreenMessage('Demo mode keeps a local copy of backend-style settings.');
      setPendingApiKey('');
      return;
    }

    if (!isConnected) {
      setSettings(null);
      setScreenStatus('idle');
      setScreenMessage('Connect to the backend to load server-managed settings.');
      setPendingApiKey('');
      return;
    }

    setScreenStatus('loading');
    setScreenMessage(null);
    setTestResult(null);
    apiService.setConnection(config);
    apiService
      .fetchSettings()
      .then((next) => {
        setSettings(next);
        setDraft(buildDraft(next));
        setPendingApiKey('');
        setScreenStatus('ready');
      })
      .catch((error) => {
        if (isBackendNotReadyError(error)) {
          setSettings(null);
          setScreenStatus('not-ready');
          setScreenMessage('后端设置接口尚未提供，当前页面只保留连接信息和预留入口。');
          return;
        }
        setSettings(null);
        setScreenStatus('error');
        setScreenMessage(error instanceof Error ? error.message : 'Failed to load settings');
      });
  }, [config, isConnected, isDemoMode]);

  const handleSave = async () => {
    setTestResult(null);
    if (isDemoMode) {
      const next: SettingsData = {
        ...mockSettings,
        ...draft,
        llmApiKeyConfigured: Boolean(mockSettings.llmApiKeyConfigured || pendingApiKey),
      };
      setSettings(next);
      setDraft(buildDraft(next));
      setPendingApiKey('');
      setScreenMessage('Demo settings updated locally.');
      return;
    }
    if (screenStatus !== 'ready') {
      return;
    }
    setIsSaving(true);
    try {
      apiService.setConnection(config);
      const next = await apiService.updateSettings({
        ...draft,
        ...(pendingApiKey ? { llmApiKey: pendingApiKey } : {}),
      });
      setSettings(next);
      setDraft(buildDraft(next));
      setPendingApiKey('');
      setScreenMessage('Settings saved through the backend.');
    } catch (error) {
      setScreenMessage(error instanceof Error ? error.message : 'Failed to save settings');
    } finally {
      setIsSaving(false);
    }
  };

  const handleTestConnection = async () => {
    setTestResult(null);
    if (isDemoMode) {
      setTestResult('Demo mode: backend test endpoint not called.');
      return;
    }
    if (screenStatus !== 'ready') {
      return;
    }
    setIsTesting(true);
    try {
      apiService.setConnection(config);
      const result = await apiService.testAiConnection();
      setTestResult(`${result.provider}/${result.model}: ${result.message}`);
    } catch (error) {
      setTestResult(error instanceof Error ? error.message : 'AI connection test failed');
    } finally {
      setIsTesting(false);
    }
  };

  const canEdit = screenStatus === 'ready' || screenStatus === 'demo';

  const headerBadge = useMemo(() => {
    if (screenStatus === 'demo') {
      return 'Demo';
    }
    if (screenStatus === 'ready') {
      return 'Backend';
    }
    if (screenStatus === 'not-ready') {
      return 'Pending';
    }
    return 'Read Only';
  }, [screenStatus]);

  return (
    <div className="h-full overflow-y-auto bg-gray-50">
      <div className="bg-white border-b border-gray-200 p-4 sticky top-0 z-10 flex items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-gray-900">Settings</h1>
          <p className="text-sm text-gray-600">Server-managed configuration only.</p>
        </div>
        <div className="text-xs font-medium px-3 py-1 rounded-full bg-gray-100 text-gray-700">{headerBadge}</div>
      </div>

      <div className="p-4 space-y-4">
        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Wifi className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">Server Connection</h3>
          </div>
          <div className="space-y-3">
            <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
              <span className="text-sm text-gray-600">Status</span>
              <span className="text-sm font-medium text-gray-900">
                {isDemoMode ? 'Demo' : isConnected ? 'Connected' : 'Disconnected'}
              </span>
            </div>
            <div>
              <Label>Server URL</Label>
              <Input value={config.serverUrl} disabled />
            </div>
            <div>
              <Label>Port</Label>
              <Input value={String(config.serverPort)} disabled />
            </div>
            <div>
              <Label>App Token</Label>
              <Input value={config.appToken ? 'Configured' : 'Not set'} disabled />
            </div>
            {isConnected && (
              <Button onClick={disconnect} variant="outline" className="w-full">
                Disconnect
              </Button>
            )}
          </div>
        </div>

        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Brain className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">Backend AI Settings</h3>
          </div>
          <div className="space-y-3">
            <div>
              <Label>Provider</Label>
              <Select value={draft.llmProvider} onValueChange={(value) => setDraft({ ...draft, llmProvider: value })} disabled={!canEdit}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="server-managed">Server Managed</SelectItem>
                  <SelectItem value="openai">OpenAI</SelectItem>
                  <SelectItem value="anthropic">Anthropic</SelectItem>
                  <SelectItem value="gemini">Gemini</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Model</Label>
              <Input
                value={draft.llmModel}
                onChange={(event) => setDraft({ ...draft, llmModel: event.target.value })}
                disabled={!canEdit}
                placeholder="gpt-4o"
              />
            </div>
            <div>
              <Label>Send New API Key To Backend</Label>
              <Input
                type="password"
                value={pendingApiKey}
                onChange={(event) => setPendingApiKey(event.target.value)}
                disabled={!canEdit}
                placeholder="Only forwarded to backend on save"
              />
              <p className="text-xs text-gray-500 mt-1">
                The frontend no longer stores or uses provider SDK clients directly.
              </p>
            </div>
            <div>
              <Label>Base URL</Label>
              <Input
                value={draft.llmBaseUrl ?? ''}
                onChange={(event) => setDraft({ ...draft, llmBaseUrl: event.target.value || null })}
                disabled={!canEdit}
                placeholder="Optional backend-managed upstream URL"
              />
            </div>
            {settings && (
              <p className="text-xs text-gray-500">
                API key configured on backend: {settings.llmApiKeyConfigured ? 'Yes' : 'No'}
              </p>
            )}
          </div>
        </div>

        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Volume2 className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">Voice Output</h3>
          </div>
          <div className="space-y-3">
            <div>
              <Label>TTS Voice</Label>
              <Select value={draft.ttsVoice} onValueChange={(value) => setDraft({ ...draft, ttsVoice: value })} disabled={!canEdit}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="alloy">Alloy</SelectItem>
                  <SelectItem value="aria">Aria</SelectItem>
                  <SelectItem value="nova">Nova</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Speech Speed: {draft.ttsSpeed.toFixed(1)}x</Label>
              <Slider
                value={[draft.ttsSpeed]}
                onValueChange={([value]) => setDraft({ ...draft, ttsSpeed: value })}
                min={0.5}
                max={2}
                step={0.1}
                disabled={!canEdit}
                className="mt-2"
              />
            </div>
            <div>
              <Label>Device Volume: {draft.deviceVolume}%</Label>
              <Slider
                value={[draft.deviceVolume]}
                onValueChange={([value]) => setDraft({ ...draft, deviceVolume: value })}
                min={0}
                max={100}
                step={5}
                disabled={!canEdit}
                className="mt-2"
              />
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Lightbulb className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">Device Preferences</h3>
          </div>
          <div className="space-y-3">
            <div>
              <Label>LED Mode</Label>
              <Select value={draft.ledMode} onValueChange={(value) => setDraft({ ...draft, ledMode: value as SettingsUpdateInput['ledMode'] })} disabled={!canEdit}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="off">Off</SelectItem>
                  <SelectItem value="breathing">Breathing</SelectItem>
                  <SelectItem value="rainbow">Rainbow</SelectItem>
                  <SelectItem value="solid">Solid</SelectItem>
                </SelectContent>
              </Select>
            </div>
            {draft.ledMode === 'solid' && (
              <div>
                <Label>LED Color</Label>
                <Input
                  type="color"
                  value={draft.ledColor}
                  onChange={(event) => setDraft({ ...draft, ledColor: event.target.value })}
                  disabled={!canEdit}
                />
              </div>
            )}
            <div>
              <Label>Wake Word</Label>
              <Input
                value={draft.wakeWord}
                onChange={(event) => setDraft({ ...draft, wakeWord: event.target.value })}
                disabled={!canEdit}
              />
            </div>
          </div>
        </div>

        {(screenMessage || testResult) && (
          <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
            <div className="flex items-center gap-2 mb-3">
              <Info className="w-5 h-5 text-gray-700" />
              <h3 className="font-semibold text-gray-900">Status</h3>
            </div>
            {screenMessage && <p className="text-sm text-gray-700">{screenMessage}</p>}
            {testResult && <p className="text-sm text-gray-700 mt-2">AI test: {testResult}</p>}
          </div>
        )}

        <div className="flex gap-3">
          <Button onClick={handleSave} className="flex-1" disabled={!canEdit || isSaving}>
            {isSaving ? 'Saving...' : 'Save Settings'}
          </Button>
          <Button onClick={handleTestConnection} variant="outline" className="flex-1" disabled={!canEdit || isTesting}>
            {isTesting ? 'Testing...' : 'Test AI Connection'}
          </Button>
        </div>

        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Settings2 className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">Contract Notes</h3>
          </div>
          <p className="text-sm text-gray-600">
            This screen no longer treats model vendors as frontend dependencies. All production AI behavior must be tested through backend endpoints.
          </p>
        </div>
      </div>
    </div>
  );
}
