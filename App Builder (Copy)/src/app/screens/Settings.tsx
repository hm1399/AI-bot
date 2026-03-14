import { useState } from 'react';
import { useConfig } from '../contexts/ConfigContext';
import { Settings2, Wifi, Brain, Volume2, Lightbulb, Info } from 'lucide-react';
import { Label } from '../components/ui/label';
import { Input } from '../components/ui/input';
import { Slider } from '../components/ui/slider';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../components/ui/select';
import { Button } from '../components/ui/button';

export function Settings() {
  const { config, updateConfig, isConnected, disconnect } = useConfig();
  const [formData, setFormData] = useState(config);

  const handleSave = async () => {
    await updateConfig(formData);
  };

  return (
    <div className="h-full overflow-y-auto bg-gray-50">
      <div className="bg-white border-b border-gray-200 p-4 sticky top-0 z-10">
        <h1 className="text-xl font-bold text-gray-900">Settings</h1>
      </div>

      <div className="p-4 space-y-4">
        {/* Server Connection */}
        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Wifi className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">Server Connection</h3>
          </div>
          <div className="space-y-3">
            <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
              <span className="text-sm text-gray-600">Status</span>
              <div className="flex items-center gap-2">
                <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-green-500' : 'bg-red-500'}`} />
                <span className="text-sm font-medium text-gray-900">
                  {isConnected ? 'Connected' : 'Disconnected'}
                </span>
              </div>
            </div>
            <div>
              <Label>Server URL</Label>
              <Input
                value={formData.serverUrl}
                onChange={(e) => setFormData({ ...formData, serverUrl: e.target.value })}
                placeholder="192.168.1.100"
                disabled
              />
            </div>
            <div>
              <Label>Port</Label>
              <Input
                type="number"
                value={formData.serverPort}
                onChange={(e) => setFormData({ ...formData, serverPort: parseInt(e.target.value) })}
                placeholder="8000"
                disabled
              />
            </div>
            {isConnected && (
              <Button onClick={disconnect} variant="outline" className="w-full">
                Disconnect
              </Button>
            )}
          </div>
        </div>

        {/* LLM Configuration */}
        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Brain className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">LLM Configuration</h3>
          </div>
          <div className="space-y-3">
            <div>
              <Label>API Key</Label>
              <Input
                type="password"
                value={formData.llmApiKey || ''}
                onChange={(e) => setFormData({ ...formData, llmApiKey: e.target.value })}
                placeholder="sk-••••••••••••••••"
              />
              <p className="text-xs text-gray-500 mt-1">Your API key is securely stored</p>
            </div>
            <div>
              <Label>Model</Label>
              <Select
                value={formData.llmModel}
                onValueChange={(value) => setFormData({ ...formData, llmModel: value })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="gpt-4">GPT-4</SelectItem>
                  <SelectItem value="gpt-4-turbo">GPT-4 Turbo</SelectItem>
                  <SelectItem value="gpt-3.5-turbo">GPT-3.5 Turbo</SelectItem>
                  <SelectItem value="claude-3-opus">Claude 3 Opus</SelectItem>
                  <SelectItem value="claude-3-sonnet">Claude 3 Sonnet</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
        </div>

        {/* Voice Configuration */}
        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Volume2 className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">Voice Configuration</h3>
          </div>
          <div className="space-y-3">
            <div>
              <Label>TTS Voice</Label>
              <Select
                value={formData.ttsVoice}
                onValueChange={(value) => setFormData({ ...formData, ttsVoice: value })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="en-US-AriaNeural">Aria (Female, US)</SelectItem>
                  <SelectItem value="en-US-GuyNeural">Guy (Male, US)</SelectItem>
                  <SelectItem value="en-GB-SoniaNeural">Sonia (Female, UK)</SelectItem>
                  <SelectItem value="en-GB-RyanNeural">Ryan (Male, UK)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Speech Speed: {formData.ttsSpeed}x</Label>
              <Slider
                value={[formData.ttsSpeed]}
                onValueChange={([value]) => setFormData({ ...formData, ttsSpeed: value })}
                min={0.5}
                max={2}
                step={0.1}
                className="mt-2"
              />
            </div>
            <div>
              <Label>Device Volume: {formData.deviceVolume}%</Label>
              <Slider
                value={[formData.deviceVolume]}
                onValueChange={([value]) => setFormData({ ...formData, deviceVolume: value })}
                min={0}
                max={100}
                step={5}
                className="mt-2"
              />
            </div>
          </div>
        </div>

        {/* Device Configuration */}
        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Lightbulb className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">LED Configuration</h3>
          </div>
          <div className="space-y-3">
            <div>
              <Label>LED Mode</Label>
              <Select
                value={formData.ledMode}
                onValueChange={(value) => setFormData({ ...formData, ledMode: value as any })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="off">Off</SelectItem>
                  <SelectItem value="breathing">Breathing</SelectItem>
                  <SelectItem value="rainbow">Rainbow</SelectItem>
                  <SelectItem value="solid">Solid Color</SelectItem>
                </SelectContent>
              </Select>
            </div>
            {formData.ledMode === 'solid' && (
              <div>
                <Label>LED Color</Label>
                <Input
                  type="color"
                  value={formData.ledColor || '#0000ff'}
                  onChange={(e) => setFormData({ ...formData, ledColor: e.target.value })}
                />
              </div>
            )}
          </div>
        </div>

        {/* About */}
        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <div className="flex items-center gap-2 mb-4">
            <Info className="w-5 h-5 text-gray-700" />
            <h3 className="font-semibold text-gray-900">About</h3>
          </div>
          <div className="space-y-2 text-sm text-gray-600">
            <div className="flex justify-between">
              <span>Version</span>
              <span className="font-medium text-gray-900">1.0.0</span>
            </div>
            <div className="flex justify-between">
              <span>Device</span>
              <span className="font-medium text-gray-900">AI-Bot Desktop Assistant</span>
            </div>
            <div className="flex justify-between">
              <span>Hardware</span>
              <span className="font-medium text-gray-900">ESP32-S3</span>
            </div>
          </div>
        </div>

        <Button onClick={handleSave} className="w-full">
          Save Settings
        </Button>
      </div>
    </div>
  );
}
