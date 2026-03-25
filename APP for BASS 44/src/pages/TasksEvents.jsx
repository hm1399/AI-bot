const db = globalThis.__B44_DB__ || { auth:{ isAuthenticated: async()=>false, me: async()=>null }, entities:new Proxy({}, { get:()=>({ filter:async()=>[], get:async()=>null, create:async()=>({}), update:async()=>({}), delete:async()=>({}) }) }), integrations:{ Core:{ UploadFile:async()=>({ file_url:'' }) } } };

import { useState, memo } from "react";

import { useQueryClient, useMutation, useQuery } from "@tanstack/react-query";
import TaskTile from "../components/tasks/TaskTile";
import EventTile from "../components/tasks/EventTile";
import { CheckSquare, CalendarDays, Sparkles } from "lucide-react";
import PullToRefresh from "../components/PullToRefresh";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";

const TasksEvents = memo(function TasksEvents() {
  const [tab, setTab] = useState("tasks");
  const qc = useQueryClient();

  const { data: tasks = [], isLoading: tasksLoading } = useQuery({
    queryKey: ["tasks"],
    queryFn: () => db.entities.Task.list("-created_date", 50),
  });

  const { data: events = [], isLoading: eventsLoading } = useQuery({
    queryKey: ["events"],
    queryFn: () => db.entities.Event.list("-start_time", 50),
  });

  const loading = tasksLoading || eventsLoading;

  const loadData = async () => {
    await Promise.all([
      qc.invalidateQueries({ queryKey: ["tasks"] }),
      qc.invalidateQueries({ queryKey: ["events"] }),
    ]);
  };

  const toggleTaskMutation = useMutation({
    mutationFn: ({ task, newStatus }) =>
      db.entities.Task.update(task.id, { status: newStatus }),
    onMutate: async ({ task, newStatus }) => {
      await qc.cancelQueries({ queryKey: ["tasks"] });
      const prev = qc.getQueryData(["tasks"]);
      qc.setQueryData(["tasks"], old =>
        (old || []).map(t => t.id === task.id ? { ...t, status: newStatus } : t)
      );
      return { prev };
    },
    onError: (_e, _v, ctx) => qc.setQueryData(["tasks"], ctx.prev),
    onSettled: () => qc.invalidateQueries({ queryKey: ["tasks"] }),
  });

  const deleteTaskMutation = useMutation({
    mutationFn: (task) => db.entities.Task.delete(task.id),
    onMutate: async (task) => {
      await qc.cancelQueries({ queryKey: ["tasks"] });
      const prev = qc.getQueryData(["tasks"]);
      qc.setQueryData(["tasks"], old => (old || []).filter(t => t.id !== task.id));
      return { prev };
    },
    onError: (_e, _v, ctx) => qc.setQueryData(["tasks"], ctx.prev),
    onSettled: () => qc.invalidateQueries({ queryKey: ["tasks"] }),
  });

  const deleteEventMutation = useMutation({
    mutationFn: (event) => db.entities.Event.delete(event.id),
    onMutate: async (event) => {
      await qc.cancelQueries({ queryKey: ["events"] });
      const prev = qc.getQueryData(["events"]);
      qc.setQueryData(["events"], old => (old || []).filter(e => e.id !== event.id));
      return { prev };
    },
    onError: (_e, _v, ctx) => qc.setQueryData(["events"], ctx.prev),
    onSettled: () => qc.invalidateQueries({ queryKey: ["events"] }),
  });

  const toggleTask = (task) => {
    const newStatus = task.status === "completed" ? "pending" : "completed";
    toggleTaskMutation.mutate({ task, newStatus });
  };
  const deleteTask = (task) => deleteTaskMutation.mutate(task);
  const deleteEvent = (event) => deleteEventMutation.mutate(event);

  const priorityOrder = { urgent: 0, high: 1, medium: 2, low: 3 };
  const pendingTasks = tasks.filter(t => t.status !== "completed").sort((a, b) => (priorityOrder[a.priority] ?? 2) - (priorityOrder[b.priority] ?? 2));
  const doneTasks = tasks.filter(t => t.status === "completed");

  return (
    <PullToRefresh onRefresh={loadData}>
      <div className="min-h-full bg-gradient-to-b from-slate-50 to-gray-50 pb-24">
        {/* Header */}
        <div className="px-5 pt-8 pb-4 bg-white/80 backdrop-blur-sm border-b border-gray-100">
          <h1 className="text-xl font-bold text-slate-800 mb-4">任务 & 日程</h1>
          <div className="flex gap-1 bg-gray-100 rounded-xl p-1">
            <button
              onClick={() => setTab("tasks")}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2 rounded-lg text-sm font-medium transition-all ${
                tab === "tasks" ? "bg-white shadow-sm text-slate-800" : "text-gray-400"
              }`}
            >
              <CheckSquare className="w-4 h-4" /> 任务
            </button>
            <button
              onClick={() => setTab("events")}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2 rounded-lg text-sm font-medium transition-all ${
                tab === "events" ? "bg-white shadow-sm text-slate-800" : "text-gray-400"
              }`}
            >
              <CalendarDays className="w-4 h-4" /> 日程
            </button>
          </div>
        </div>

        {/* AI Hint */}
        <div className="px-5 py-3">
          <Link to={createPageUrl("Chat")}>
            <div className="flex items-center gap-2 px-3 py-2 bg-violet-50 rounded-xl border border-violet-100">
              <Sparkles className="w-3.5 h-3.5 text-violet-500 flex-shrink-0" />
              <p className="text-[13px] text-violet-600">用 AI 助手快速创建任务或日程 →</p>
            </div>
          </Link>
        </div>

        <div className="px-5">
          {tab === "tasks" && (
            <div className="space-y-3">
              {loading ? (
                <div className="space-y-2">
                  {[1, 2, 3].map(i => <div key={i} className="h-16 bg-gray-100 rounded-xl animate-pulse" />)}
                </div>
              ) : (
                <>
                  {pendingTasks.length === 0 && doneTasks.length === 0 ? (
                    <div className="text-center py-12 text-gray-400">
                      <CheckSquare className="w-10 h-10 mx-auto mb-3 opacity-30" />
                      <p className="text-sm">暂无任务，试试让 AI 帮你创建</p>
                    </div>
                  ) : (
                    <>
                      {pendingTasks.map(t => (
                        <TaskTile key={t.id} task={t} onToggle={toggleTask} onDelete={deleteTask} />
                      ))}
                      {doneTasks.length > 0 && (
                        <>
                          <p className="text-[13px] text-gray-400 pt-2 pb-1">已完成 ({doneTasks.length})</p>
                          {doneTasks.map(t => (
                            <TaskTile key={t.id} task={t} onToggle={toggleTask} onDelete={deleteTask} />
                          ))}
                        </>
                      )}
                    </>
                  )}
                </>
              )}
            </div>
          )}

          {tab === "events" && (
            <div className="space-y-3">
              {loading ? (
                <div className="space-y-2">
                  {[1, 2, 3].map(i => <div key={i} className="h-20 bg-gray-100 rounded-xl animate-pulse" />)}
                </div>
              ) : events.length === 0 ? (
                <div className="text-center py-12 text-gray-400">
                  <CalendarDays className="w-10 h-10 mx-auto mb-3 opacity-30" />
                  <p className="text-sm">暂无日程，试试让 AI 帮你安排</p>
                </div>
              ) : (
                events.map(e => (
                  <EventTile key={e.id} event={e} onDelete={deleteEvent} />
                ))
              )}
            </div>
          )}
        </div>
      </div>
    </PullToRefresh>
  );
});

export default TasksEvents;