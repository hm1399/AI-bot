const db = globalThis.__B44_DB__ || { auth:{ isAuthenticated: async()=>false, me: async()=>null }, entities:new Proxy({}, { get:()=>({ filter:async()=>[], get:async()=>null, create:async()=>({}), update:async()=>({}), delete:async()=>({}) }) }), integrations:{ Core:{ UploadFile:async()=>({ file_url:'' }) } } };

import { memo } from "react";

import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import DeviceCard from "../components/home/DeviceCard";
import { Sparkles, CheckSquare, CalendarDays, ArrowRight, Bot, Zap } from "lucide-react";
import { format } from "date-fns";
import PullToRefresh from "../components/PullToRefresh";
import { useQuery, useQueryClient } from "@tanstack/react-query";

function greeting() {
  const h = new Date().getHours();
  if (h < 12) return "早上好";
  if (h < 18) return "下午好";
  return "晚上好";
}

const Home = memo(function Home() {
  const qc = useQueryClient();

  const { data: user } = useQuery({
    queryKey: ["me"],
    queryFn: () => db.auth.me(),
    staleTime: 5 * 60 * 1000,
  });

  const { data: device } = useQuery({
    queryKey: ["device"],
    queryFn: async () => {
      const list = await db.entities.DeviceStatus.list("-updated_date", 1);
      return list?.[0] ?? null;
    },
    staleTime: 30 * 1000,
  });

  const { data: tasks = [] } = useQuery({
    queryKey: ["tasks"],
    queryFn: () => db.entities.Task.list("-created_date", 50),
    staleTime: 30 * 1000,
  });

  const { data: events = [] } = useQuery({
    queryKey: ["events"],
    queryFn: () => db.entities.Event.list("-start_time", 50),
    staleTime: 30 * 1000,
  });

  const handleRefresh = async () => {
    await Promise.all([
      qc.invalidateQueries({ queryKey: ["device"] }),
      qc.invalidateQueries({ queryKey: ["tasks"] }),
      qc.invalidateQueries({ queryKey: ["events"] }),
    ]);
  };

  const now = new Date();
  const upcomingEvents = events.filter(e => new Date(e.start_time) >= now).slice(0, 3);
  const pendingTasks   = tasks.filter(t => t.status === "pending").slice(0, 3);

  return (
    <PullToRefresh onRefresh={handleRefresh}>
      <div className="min-h-full bg-gradient-to-b from-slate-50 to-gray-50 pb-24">
        {/* Header */}
        <div className="px-5 pt-8 pb-6">
          <p className="text-sm text-gray-400 mb-1">{greeting()}，</p>
          <h1 className="text-2xl font-bold text-slate-800">
            {user?.full_name?.split(" ")[0] || "用户"}
          </h1>
          <p className="text-[13px] text-gray-400 mt-1">{format(now, "yyyy年MM月dd日 EEEE")}</p>
        </div>

        {/* AI Quick Action Banner */}
        <div className="mx-5 mb-5">
          <Link to={createPageUrl("Chat")}>
            <div className="bg-gradient-to-r from-violet-500 via-indigo-500 to-blue-500 rounded-2xl p-4 flex items-center gap-3 shadow-lg shadow-violet-200">
              <div className="w-10 h-10 rounded-xl bg-white/20 flex items-center justify-center flex-shrink-0">
                <Bot aria-hidden="true" className="w-5 h-5 text-white" />
              </div>
              <div className="flex-1">
                <p className="text-white font-semibold text-sm">AI 助手</p>
                <p className="text-white/70 text-[13px]">说出你想做的事情</p>
              </div>
              <ArrowRight aria-hidden="true" className="w-4 h-4 text-white/70" />
            </div>
          </Link>
        </div>

        {/* Device Card */}
        <div className="px-5 mb-5">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-wider">设备状态</h2>
          </div>
          <DeviceCard device={device} />
        </div>

        {/* Quick Stats */}
        <div className="px-5 mb-5">
          <div className="grid grid-cols-2 gap-3">
            <Link to={createPageUrl("TasksEvents")}>
              <div className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm hover:shadow-md transition-shadow">
                <div className="flex items-center justify-between mb-3">
                  <div className="w-8 h-8 rounded-xl bg-emerald-50 flex items-center justify-center">
                    <CheckSquare aria-hidden="true" className="w-4 h-4 text-emerald-500" />
                  </div>
                  <span className="text-2xl font-bold text-slate-800">{pendingTasks.length}</span>
                </div>
                <p className="text-[13px] text-gray-400">待完成任务</p>
              </div>
            </Link>
            <Link to={createPageUrl("TasksEvents")}>
              <div className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm hover:shadow-md transition-shadow">
                <div className="flex items-center justify-between mb-3">
                  <div className="w-8 h-8 rounded-xl bg-violet-50 flex items-center justify-center">
                    <CalendarDays aria-hidden="true" className="w-4 h-4 text-violet-500" />
                  </div>
                  <span className="text-2xl font-bold text-slate-800">{upcomingEvents.length}</span>
                </div>
                <p className="text-[13px] text-gray-400">即将日程</p>
              </div>
            </Link>
          </div>
        </div>

        {/* Upcoming Events */}
        {upcomingEvents.length > 0 && (
          <div className="px-5 mb-5">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-wider">即将日程</h2>
              <Link to={createPageUrl("TasksEvents")} className="text-xs text-violet-500">查看全部</Link>
            </div>
            <div className="space-y-2">
              {upcomingEvents.map(e => (
                <div key={e.id} className="bg-white rounded-xl p-3.5 border border-gray-100 shadow-sm flex items-center gap-3">
                  <div className="w-1 h-10 rounded-full bg-gradient-to-b from-violet-400 to-indigo-500 flex-shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-slate-700 truncate">{e.title}</p>
                    <p className="text-[13px] text-gray-400 mt-0.5">{format(new Date(e.start_time), "MM/dd HH:mm")}</p>
                  </div>
                  {e.source === "ai" && <Sparkles aria-hidden="true" className="w-3.5 h-3.5 text-violet-400 flex-shrink-0" />}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Pending Tasks */}
        {pendingTasks.length > 0 && (
          <div className="px-5">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-wider">待办任务</h2>
              <Link to={createPageUrl("TasksEvents")} className="text-xs text-violet-500">查看全部</Link>
            </div>
            <div className="space-y-2">
              {pendingTasks.map(t => (
                <div key={t.id} className="bg-white rounded-xl p-3.5 border border-gray-100 shadow-sm flex items-center gap-3">
                  <div className={`w-2 h-2 rounded-full flex-shrink-0 ${
                    t.priority === "urgent" ? "bg-red-400"
                    : t.priority === "high"   ? "bg-orange-400"
                    : t.priority === "medium" ? "bg-blue-400"
                    : "bg-gray-300"
                  }`} />
                  <p className="text-sm text-slate-700 flex-1 truncate">{t.title}</p>
                  {t.source === "ai" && <Zap aria-hidden="true" className="w-3.5 h-3.5 text-violet-400 flex-shrink-0" />}
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </PullToRefresh>
  );
});

export default Home;