import { format } from "date-fns";
import { MapPin, Users, Clock, Trash2 } from "lucide-react";

export default function EventTile({ event, onDelete }) {
  return (
    <div className="flex gap-3 p-4 rounded-xl bg-white border border-gray-100 shadow-sm">
      <div className="flex flex-col items-center w-10 flex-shrink-0">
        <div className="text-lg font-bold text-violet-600 leading-none">
          {format(new Date(event.start_time), "dd")}
        </div>
        <div className="text-[10px] text-gray-400 uppercase">
          {format(new Date(event.start_time), "MMM")}
        </div>
      </div>
      <div className="w-px bg-violet-100 flex-shrink-0" />
      <div className="flex-1 min-w-0">
        <div className="flex items-start justify-between gap-2">
          <span className="text-sm font-medium text-slate-800">{event.title}</span>
          {event.source === "ai" && (
            <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-violet-50 text-violet-500 font-medium flex-shrink-0">AI</span>
          )}
        </div>
        {event.description && (
          <p className="text-xs text-gray-400 mt-0.5 line-clamp-1">{event.description}</p>
        )}
        <div className="flex flex-wrap gap-2 mt-1.5">
          <div className="flex items-center gap-1">
            <Clock className="w-3 h-3 text-gray-400" />
            <span className="text-[11px] text-gray-400">
              {format(new Date(event.start_time), "HH:mm")}
              {event.end_time && ` - ${format(new Date(event.end_time), "HH:mm")}`}
            </span>
          </div>
          {event.location && (
            <div className="flex items-center gap-1">
              <MapPin className="w-3 h-3 text-gray-400" />
              <span className="text-[11px] text-gray-400">{event.location}</span>
            </div>
          )}
          {event.attendees?.length > 0 && (
            <div className="flex items-center gap-1">
              <Users className="w-3 h-3 text-gray-400" />
              <span className="text-[11px] text-gray-400">{event.attendees.length}人</span>
            </div>
          )}
        </div>
      </div>
      <button onClick={() => onDelete?.(event)} className="flex-shrink-0 p-1 text-gray-300 hover:text-red-400 transition-colors">
        <Trash2 className="w-4 h-4" />
      </button>
    </div>
  );
}