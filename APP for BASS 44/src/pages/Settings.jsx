const db = globalThis.__B44_DB__ || { auth:{ isAuthenticated: async()=>false, me: async()=>null }, entities:new Proxy({}, { get:()=>({ filter:async()=>[], get:async()=>null, create:async()=>({}), update:async()=>({}), delete:async()=>({}) }) }), integrations:{ Core:{ UploadFile:async()=>({ file_url:'' }) } } };

import { useState } from "react";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Volume2, Lightbulb, ChevronRight, Info } from "lucide-react";
import DeleteAccountDialog from "../components/settings/DeleteAccountDialog";

const Section = ({ title, children }) => (
  <div className="mb-6">
    <p className="text-[13px] font-semibold text-gray-400 uppercase tracking-wider px-5 mb-2">{title}</p>
    <div className="bg-white border border-gray-100 rounded-2xl overflow-hidden shadow-sm mx-5">{children}</div>
  </div>
);

const Row = ({ icon: Icon, iconBg, label, value, last }) => (
  <div className={`flex items-center gap-3 px-4 min-h-[52px] ${!last ? "border-b border-gray-50" : ""}`}>
    <div className={`w-8 h-8 rounded-lg ${iconBg} flex items-center justify-center flex-shrink-0`}>
      <Icon aria-hidden="true" className="w-4 h-4 text-white" />
    </div>
    <span className="text-sm text-slate-700 flex-1">{label}</span>
    <div className="flex items-center gap-1 text-gray-400">
      <span className="text-[13px]">{value}</span>
      <ChevronRight aria-hidden="true" className="w-3.5 h-3.5" />
    </div>
  </div>
);

export default function Settings() {
  const qc = useQueryClient();

  // ── Fetch device ────────────────────────────────────────────────────────────
  const { data: device } = useQuery({
    queryKey: ["device"],
    queryFn: async () => {
      const list = await db.entities.DeviceStatus.list("-updated_date", 1);
      return list?.[0] ?? null;
    },
  });

  // Local controlled inputs – seeded from query data
  const [ipInput,   setIpInput]   = useState("");
  const [portInput, setPortInput] = useState("8080");
  const [inputsSeeded, setInputsSeeded] = useState(false);

  // Seed inputs once device loads
  if (device && !inputsSeeded) {
    setIpInput(device.ip_address || "");
    setPortInput(String(device.port || 8080));
    setInputsSeeded(true);
  }

  // ── Save connection (optimistic) ────────────────────────────────────────────
  const [saved, setSaved] = useState(false);

  const saveConnection = useMutation({
    mutationFn: async () => {
      if (device) {
        return db.entities.DeviceStatus.update(device.id, {
          ip_address: ipInput,
          port: Number(portInput),
        });
      } else {
        return db.entities.DeviceStatus.create({
          device_id: "main",
          device_name: "AI助手设备",
          ip_address: ipInput,
          port: Number(portInput),
        });
      }
    },
    onMutate: async () => {
      await qc.cancelQueries({ queryKey: ["device"] });
      const prev = qc.getQueryData(["device"]);
      qc.setQueryData(["device"], old => ({
        ...(old ?? {}),
        ip_address: ipInput,
        port: Number(portInput),
      }));
      return { prev };
    },
    onError: (_e, _v, ctx) => qc.setQueryData(["device"], ctx.prev),
    onSuccess: (data) => {
      qc.setQueryData(["device"], data);
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ["device"] }),
  });

  return (
    <div className="min-h-full bg-gradient-to-b from-slate-50 to-gray-50 pb-24">
      <div className="px-5 pt-8 pb-6">
        <h1 className="text-xl font-bold text-slate-800">设置</h1>
      </div>

      {/* Connection */}
      <Section title="设备连接">
        <div className="px-4 py-4 space-y-3">
          <div className="flex items-center gap-2 mb-1">
            <div className={`w-2 h-2 rounded-full ${device?.online ? "bg-emerald-400" : "bg-gray-300"}`} />
            <span className={`text-[13px] ${device?.online ? "text-emerald-600" : "text-gray-400"}`}>
              {device?.online ? "已连接" : "未连接"}
            </span>
          </div>
          <div>
            <label className="text-[13px] text-gray-400 mb-1 block">IP 地址</label>
            <input
              value={ipInput}
              onChange={e => setIpInput(e.target.value)}
              placeholder="192.168.1.100"
              aria-label="设备 IP 地址"
              className="w-full text-sm px-3 py-2 rounded-xl border border-gray-200 bg-gray-50 outline-none focus:border-violet-300 focus:bg-white transition-all"
            />
          </div>
          <div>
            <label className="text-[13px] text-gray-400 mb-1 block">端口</label>
            <input
              value={portInput}
              onChange={e => setPortInput(e.target.value)}
              placeholder="8080"
              aria-label="设备端口"
              className="w-full text-sm px-3 py-2 rounded-xl border border-gray-200 bg-gray-50 outline-none focus:border-violet-300 focus:bg-white transition-all"
            />
          </div>
          <button
            onClick={() => saveConnection.mutate()}
            disabled={saveConnection.isPending || !ipInput}
            aria-label="保存设备连接配置"
            className={`w-full py-2.5 rounded-xl text-sm font-medium transition-all active:scale-95 ${
              saved
                ? "bg-emerald-500 text-white"
                : "bg-gradient-to-r from-violet-500 to-indigo-500 text-white hover:shadow-md"
            } disabled:opacity-50`}
          >
            {saveConnection.isPending ? "保存中..." : saved ? "✓ 已保存" : "保存连接"}
          </button>
        </div>
      </Section>

      {/* Device Settings */}
      <Section title="设备配置">
        <Row icon={Volume2} iconBg="bg-blue-400" label="音量"   value={device ? `${device.volume}%` : "--"} />
        <Row icon={Lightbulb} iconBg="bg-amber-400" label="LED 灯效" value={device?.led_mode || "--"} last />
      </Section>

      {/* About */}
      <Section title="关于">
        <Row icon={Info} iconBg="bg-gray-400" label="版本" value="1.0.0" last />
      </Section>

      {/* Danger Zone */}
      <div className="px-5 mb-6">
        <DeleteAccountDialog />
      </div>

      <p className="text-center text-[13px] text-gray-300 mt-2 pb-4">AI 助手 · 智能设备管理平台</p>
    </div>
  );
}