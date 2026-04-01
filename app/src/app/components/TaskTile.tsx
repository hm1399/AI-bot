import { CheckCircle2, Circle, Flag, Trash2 } from 'lucide-react';
import { Task } from '../models/types';

interface TaskTileProps {
  task: Task;
  onToggle: (id: string) => void;
  onDelete: (id: string) => void;
}

export function TaskTile({ task, onToggle, onDelete }: TaskTileProps) {
  const priorityColors = {
    high: 'text-red-500',
    medium: 'text-yellow-500',
    low: 'text-green-500',
  };

  return (
    <div className="flex items-center gap-3 p-4 bg-white border border-gray-200 rounded-lg hover:shadow-sm transition-shadow">
      <button onClick={() => onToggle(task.id)} className="flex-shrink-0">
        {task.completed ? (
          <CheckCircle2 className="w-6 h-6 text-green-500" />
        ) : (
          <Circle className="w-6 h-6 text-gray-300" />
        )}
      </button>

      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <h4 className={`font-medium ${task.completed ? 'line-through text-gray-400' : 'text-gray-900'}`}>
            {task.title}
          </h4>
          <Flag className={`w-4 h-4 flex-shrink-0 ${priorityColors[task.priority]}`} />
        </div>
        {task.description && (
          <p className={`text-sm mt-1 ${task.completed ? 'line-through text-gray-400' : 'text-gray-600'}`}>
            {task.description}
          </p>
        )}
        {task.dueAt && (
          <p className="text-xs text-gray-500 mt-1">
            Due: {new Date(task.dueAt).toLocaleString()}
          </p>
        )}
      </div>

      <button
        onClick={() => onDelete(task.id)}
        className="flex-shrink-0 p-2 text-gray-400 hover:text-red-500 transition-colors"
      >
        <Trash2 className="w-5 h-5" />
      </button>
    </div>
  );
}
