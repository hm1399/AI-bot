import { RefreshCw, Square, Volume2 } from 'lucide-react';
import { DeviceCard } from '../components/DeviceCard';
import { useDevice } from '../contexts/DeviceContext';
import { useConfig } from '../contexts/ConfigContext';

export function Home() {
  const { deviceStatus, runtimeState, refreshRuntime, stopCurrentTask, speakTestPhrase } = useDevice();
  const { isDemoMode } = useConfig();

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
          <p className="text-sm text-gray-600">
            Runtime state, device snapshot, todo summary and calendar summary all align with the backend app contract.
          </p>
        </div>
        <button
          onClick={() => void refreshRuntime()}
          className="inline-flex items-center gap-2 px-4 py-2 rounded-lg border border-gray-300 bg-white text-sm text-gray-700 hover:bg-gray-50"
        >
          <RefreshCw className="w-4 h-4" />
          Refresh
        </button>
      </div>

      <DeviceCard status={deviceStatus} />

      <div className="grid gap-4 md:grid-cols-2">
        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <h3 className="font-semibold text-gray-900 mb-3">Current Runtime Task</h3>
          {runtimeState?.currentTask ? (
            <div className="space-y-2">
              <p className="text-sm text-gray-900">{runtimeState.currentTask.summary}</p>
              <p className="text-xs text-gray-500">Stage: {runtimeState.currentTask.stage}</p>
              <p className="text-xs text-gray-500">Queue length: {runtimeState.taskQueue.length}</p>
            </div>
          ) : (
            <p className="text-sm text-gray-600">No active task.</p>
          )}
        </div>

        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <h3 className="font-semibold text-gray-900 mb-3">Quick Actions</h3>
          <div className="grid grid-cols-3 gap-3">
            <button
              onClick={() => void speakTestPhrase()}
              className="flex flex-col items-center gap-2 p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
            >
              <Volume2 className="w-6 h-6 text-gray-700" />
              <span className="text-xs font-medium text-gray-700">Speak</span>
            </button>

            <button
              onClick={() => void stopCurrentTask()}
              className="flex flex-col items-center gap-2 p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
            >
              <Square className="w-6 h-6 text-gray-700" />
              <span className="text-xs font-medium text-gray-700">Stop</span>
            </button>

            <button
              onClick={() => void refreshRuntime()}
              className="flex flex-col items-center gap-2 p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
            >
              <RefreshCw className="w-6 h-6 text-gray-700" />
              <span className="text-xs font-medium text-gray-700">Sync</span>
            </button>
          </div>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <h3 className="font-semibold text-gray-900 mb-3">Todo Summary</h3>
          {runtimeState?.todoSummary.enabled ? (
            <div className="space-y-2 text-sm text-gray-700">
              <p>Pending: {runtimeState.todoSummary.pendingCount}</p>
              <p>Overdue: {runtimeState.todoSummary.overdueCount}</p>
              <p>
                Next due: {runtimeState.todoSummary.nextDueAt ? new Date(runtimeState.todoSummary.nextDueAt).toLocaleString() : 'Not set'}
              </p>
            </div>
          ) : (
            <p className="text-sm text-gray-600">Todo summary is not enabled on the backend.</p>
          )}
        </div>

        <div className="bg-white rounded-lg p-6 shadow-sm border border-gray-200">
          <h3 className="font-semibold text-gray-900 mb-3">Calendar Summary</h3>
          {runtimeState?.calendarSummary.enabled ? (
            <div className="space-y-2 text-sm text-gray-700">
              <p>Today: {runtimeState.calendarSummary.todayCount}</p>
              <p>Next event: {runtimeState.calendarSummary.nextEventTitle || 'Not set'}</p>
              <p>
                Next start: {runtimeState.calendarSummary.nextEventAt ? new Date(runtimeState.calendarSummary.nextEventAt).toLocaleString() : 'Not set'}
              </p>
            </div>
          ) : (
            <p className="text-sm text-gray-600">Calendar summary is not enabled on the backend.</p>
          )}
        </div>
      </div>

      <div className="bg-gradient-to-r from-blue-600 to-cyan-600 rounded-lg p-6 text-white">
        <h3 className="text-lg font-semibold mb-2">{isDemoMode ? 'Demo Runtime' : 'Backend-Aligned Runtime'}</h3>
        <p className="text-sm text-blue-50">
          Legacy mute, LED toggle and restart shortcuts were removed because they did not exist in the current `app-v1` contract. The dashboard now only surfaces actions the backend already supports.
        </p>
      </div>
    </div>
  );
}
