import { Wifi, Battery, Mic, Volume2, Zap, Circle } from "lucide-react";

const stateConfig = {
  idle: { label: "待机", color: "text-gray-400", dot: "bg-gray-300" },
  recording: { label: "录音中", color: "text-red-500", dot: "bg-red-400 animate-pulse" },
  playing: { label: "播放中", color: "text-blue-500", dot: "bg-blue-400 animate-pulse" },
  processing: { label: "处理中", color: "text-amber-500", dot: "bg-amber-400 animate-pulse" },
};

export default function DeviceCard({ device }) {
  if (!device) return (
    <div className="bg-white/60 backdrop-blur-sm rounded-2xl p-5 border border-gray-100 shadow-sm">
      <div className="flex items-center gap-2 text-gray-400 text-sm">
        <Circle className="w-4 h-4" />
        <span>未连接设备</span>
      </div>
    </div>
  );

  const state = stateConfig[device.current_state] || stateConfig.idle;
  const batteryColor = device.battery > 50 ? "text-emerald-500" : device.battery > 20 ? "text-amber-500" : "text-red-500";

  return (
    <div className="bg-gradient-to-br from-white to-gray-50/80 backdrop-blur-sm rounded-2xl p-5 border border-gray-100 shadow-sm">
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="font-semibold text-slate-800 text-base">{device.device_name || "AI助手设备"}</h3>
          <div className="flex items-center gap-1.5 mt-1">
            <div className={`w-2 h-2 rounded-full ${device.online ? "bg-emerald-400" : "bg-gray-300"}`} />
            <span className={`text-xs ${device.online ? "text-emerald-600" : "text-gray-400"}`}>
              {device.online ? "在线" : "离线"}
            </span>
          </div>
        </div>
        <div className="flex items-center gap-1.5">
          <div className={`w-2 h-2 rounded-full ${state.dot}`} />
          <span className={`text-xs font-medium ${state.color}`}>{state.label}</span>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <div className="bg-gray-50 rounded-xl p-2.5 text-center">
          <Battery className={`w-4 h-4 mx-auto mb-1 ${batteryColor}`} />
          <div className="text-xs font-semibold text-slate-700">{device.battery ?? "--"}%</div>
          <div className="text-[10px] text-gray-400">电量</div>
        </div>
        <div className="bg-gray-50 rounded-xl p-2.5 text-center">
          <Wifi className="w-4 h-4 mx-auto mb-1 text-blue-400" />
          <div className="text-xs font-semibold text-slate-700">{device.wifi_strength ?? "--"}%</div>
          <div className="text-[10px] text-gray-400">WiFi</div>
        </div>
        <div className="bg-gray-50 rounded-xl p-2.5 text-center">
          <Volume2 className="w-4 h-4 mx-auto mb-1 text-violet-400" />
          <div className="text-xs font-semibold text-slate-700">{device.volume ?? "--"}</div>
          <div className="text-[10px] text-gray-400">音量</div>
        </div>
      </div>

      {device.ip_address && (
        <div className="mt-3 text-[11px] text-gray-400 font-mono">
          {device.ip_address}:{device.port || 8080}
        </div>
      )}
    </div>
  );
}