import { useState } from "react";
import { format } from "date-fns";
import { CheckCircle2, Circle, Clock, Trash2 } from "lucide-react";

const priorityConfig = {
  low: { label: "低", color: "bg-gray-100 text-gray-500" },
  medium: { label: "中", color: "bg-blue-50 text-blue-600" },
  high: { label: "高", color: "bg-orange-50 text-orange-600" },
  urgent: { label: "紧急", color: "bg-red-50 text-red-600" },
};

export default function TaskTile({ task, onToggle, onDelete }) {
  const isDone = task.status === "completed";
  const pConfig = priorityConfig[task.priority] || priorityConfig.medium;

  return (
    <div className={`flex items-start gap-3 p-4 rounded-xl border transition-all ${isDone ? "bg-gray-50/50 border-gray-100 opacity-60" : "bg-white border-gray-100 shadow-sm"}`}>
      <button
        onClick={() => onToggle?.(task)}
        aria-label={isDone ? "标记为未完成" : "标记为已完成"}
        className="mt-0.5 flex-shrink-0 min-w-[36px] min-h-[36px] flex items-center justify-center active:scale-90 transition-transform"
      >
        {isDone
          ? <CheckCircle2 className="w-5 h-5 text-emerald-500" />
          : <Circle className="w-5 h-5 text-gray-300 hover:text-violet-400 transition-colors" />
        }
      </button>
      <div className="flex-1 min-w-0">
        <div className="flex items-start gap-2 flex-wrap">
          <span className={`text-sm font-medium ${isDone ? "line-through text-gray-400" : "text-slate-800"}`}>
            {task.title}
          </span>
          <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-medium ${pConfig.color}`}>
            {pConfig.label}
          </span>
          {task.source === "ai" && (
            <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-violet-50 text-violet-500 font-medium">AI</span>
          )}
        </div>
        {task.description && (
          <p className="text-xs text-gray-400 mt-0.5 leading-relaxed line-clamp-2">{task.description}</p>
        )}
        {task.due_date && (
          <div className="flex items-center gap-1 mt-1.5">
            <Clock className="w-3 h-3 text-gray-400" />
            <span className="text-[11px] text-gray-400">
              {format(new Date(task.due_date), "MM/dd HH:mm")}
            </span>
          </div>
        )}
      </div>
      <button
        onClick={() => onDelete?.(task)}
        aria-label={`删除任务：${task.title}`}
        className="flex-shrink-0 p-1 min-w-[36px] min-h-[36px] flex items-center justify-center text-gray-300 hover:text-red-400 active:scale-90 transition-all"
      >
        <Trash2 className="w-4 h-4" aria-hidden="true" />
      </button>
    </div>
  );
}