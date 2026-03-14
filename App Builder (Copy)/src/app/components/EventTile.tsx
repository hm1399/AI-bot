import { Event } from '../models/types';
import { Calendar, Clock, MapPin, Trash2 } from 'lucide-react';

interface EventTileProps {
  event: Event;
  onDelete: (id: string) => void;
}

export function EventTile({ event, onDelete }: EventTileProps) {
  return (
    <div className="flex items-start gap-3 p-4 bg-white border border-gray-200 rounded-lg hover:shadow-sm transition-shadow">
      <div className="flex-shrink-0 w-12 h-12 bg-blue-100 rounded-lg flex flex-col items-center justify-center">
        <span className="text-xs text-blue-600 font-medium">
          {new Date(event.startTime).toLocaleDateString('en', { month: 'short' })}
        </span>
        <span className="text-lg font-bold text-blue-700">
          {new Date(event.startTime).getDate()}
        </span>
      </div>

      <div className="flex-1 min-w-0">
        <h4 className="font-medium text-gray-900">{event.title}</h4>
        {event.description && (
          <p className="text-sm text-gray-600 mt-1">{event.description}</p>
        )}
        <div className="flex flex-col gap-1 mt-2">
          <div className="flex items-center gap-2 text-xs text-gray-500">
            <Clock className="w-4 h-4" />
            <span>
              {new Date(event.startTime).toLocaleTimeString()} - {new Date(event.endTime).toLocaleTimeString()}
            </span>
          </div>
          {event.location && (
            <div className="flex items-center gap-2 text-xs text-gray-500">
              <MapPin className="w-4 h-4" />
              <span>{event.location}</span>
            </div>
          )}
        </div>
      </div>

      <button
        onClick={() => onDelete(event.id)}
        className="flex-shrink-0 p-2 text-gray-400 hover:text-red-500 transition-colors"
      >
        <Trash2 className="w-5 h-5" />
      </button>
    </div>
  );
}
