import { useState } from 'react';
import { useTasks } from '../contexts/TaskContext';
import { useEvents } from '../contexts/EventContext';
import { TaskTile } from '../components/TaskTile';
import { EventTile } from '../components/EventTile';
import { Plus, Calendar as CalendarIcon, CheckSquare } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '../components/ui/dialog';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';
import { Label } from '../components/ui/label';
import { Textarea } from '../components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../components/ui/select';

type Tab = 'tasks' | 'events';

export function TasksEvents() {
  const [activeTab, setActiveTab] = useState<Tab>('tasks');
  const { tasks, createTask, toggleTask, deleteTask } = useTasks();
  const { events, createEvent, deleteEvent } = useEvents();
  
  const [taskDialogOpen, setTaskDialogOpen] = useState(false);
  const [eventDialogOpen, setEventDialogOpen] = useState(false);
  
  const [taskForm, setTaskForm] = useState({
    title: '',
    description: '',
    priority: 'medium' as 'high' | 'medium' | 'low',
    dueDate: '',
  });
  
  const [eventForm, setEventForm] = useState({
    title: '',
    description: '',
    startTime: '',
    endTime: '',
    location: '',
  });

  const handleCreateTask = async () => {
    await createTask({
      title: taskForm.title,
      description: taskForm.description,
      priority: taskForm.priority,
      completed: false,
      dueDate: taskForm.dueDate ? new Date(taskForm.dueDate) : undefined,
    });
    setTaskForm({ title: '', description: '', priority: 'medium', dueDate: '' });
    setTaskDialogOpen(false);
  };

  const handleCreateEvent = async () => {
    await createEvent({
      title: eventForm.title,
      description: eventForm.description,
      startTime: new Date(eventForm.startTime),
      endTime: new Date(eventForm.endTime),
      location: eventForm.location,
    });
    setEventForm({ title: '', description: '', startTime: '', endTime: '', location: '' });
    setEventDialogOpen(false);
  };

  const tasksByPriority = {
    high: tasks.filter((t) => t.priority === 'high' && !t.completed),
    medium: tasks.filter((t) => t.priority === 'medium' && !t.completed),
    low: tasks.filter((t) => t.priority === 'low' && !t.completed),
    completed: tasks.filter((t) => t.completed),
  };

  const upcomingEvents = events
    .filter((e) => new Date(e.startTime) >= new Date())
    .sort((a, b) => new Date(a.startTime).getTime() - new Date(b.startTime).getTime());

  return (
    <div className="flex flex-col h-full">
      <div className="bg-white border-b border-gray-200">
        <div className="p-4">
          <h1 className="text-xl font-bold text-gray-900">Tasks & Events</h1>
        </div>
        <div className="flex border-t border-gray-200">
          <button
            onClick={() => setActiveTab('tasks')}
            className={`flex-1 flex items-center justify-center gap-2 py-3 font-medium transition-colors ${
              activeTab === 'tasks'
                ? 'text-blue-600 border-b-2 border-blue-600'
                : 'text-gray-600 hover:text-gray-900'
            }`}
          >
            <CheckSquare className="w-5 h-5" />
            <span>Tasks</span>
          </button>
          <button
            onClick={() => setActiveTab('events')}
            className={`flex-1 flex items-center justify-center gap-2 py-3 font-medium transition-colors ${
              activeTab === 'events'
                ? 'text-blue-600 border-b-2 border-blue-600'
                : 'text-gray-600 hover:text-gray-900'
            }`}
          >
            <CalendarIcon className="w-5 h-5" />
            <span>Events</span>
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4 bg-gray-50">
        {activeTab === 'tasks' && (
          <div className="space-y-6">
            {tasksByPriority.high.length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-red-600 mb-2">High Priority</h3>
                <div className="space-y-2">
                  {tasksByPriority.high.map((task) => (
                    <TaskTile key={task.id} task={task} onToggle={toggleTask} onDelete={deleteTask} />
                  ))}
                </div>
              </div>
            )}

            {tasksByPriority.medium.length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-yellow-600 mb-2">Medium Priority</h3>
                <div className="space-y-2">
                  {tasksByPriority.medium.map((task) => (
                    <TaskTile key={task.id} task={task} onToggle={toggleTask} onDelete={deleteTask} />
                  ))}
                </div>
              </div>
            )}

            {tasksByPriority.low.length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-green-600 mb-2">Low Priority</h3>
                <div className="space-y-2">
                  {tasksByPriority.low.map((task) => (
                    <TaskTile key={task.id} task={task} onToggle={toggleTask} onDelete={deleteTask} />
                  ))}
                </div>
              </div>
            )}

            {tasksByPriority.completed.length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-gray-600 mb-2">Completed</h3>
                <div className="space-y-2">
                  {tasksByPriority.completed.map((task) => (
                    <TaskTile key={task.id} task={task} onToggle={toggleTask} onDelete={deleteTask} />
                  ))}
                </div>
              </div>
            )}

            {tasks.length === 0 && (
              <div className="text-center py-12">
                <CheckSquare className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                <p className="text-gray-600">No tasks yet. Create your first task!</p>
              </div>
            )}
          </div>
        )}

        {activeTab === 'events' && (
          <div className="space-y-2">
            {upcomingEvents.map((event) => (
              <EventTile key={event.id} event={event} onDelete={deleteEvent} />
            ))}
            {upcomingEvents.length === 0 && (
              <div className="text-center py-12">
                <CalendarIcon className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                <p className="text-gray-600">No upcoming events. Create your first event!</p>
              </div>
            )}
          </div>
        )}
      </div>

      <div className="p-4 bg-white border-t border-gray-200">
        {activeTab === 'tasks' ? (
          <Dialog open={taskDialogOpen} onOpenChange={setTaskDialogOpen}>
            <DialogTrigger asChild>
              <Button className="w-full">
                <Plus className="w-5 h-5 mr-2" />
                New Task
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Create New Task</DialogTitle>
              </DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label htmlFor="task-title">Title</Label>
                  <Input
                    id="task-title"
                    value={taskForm.title}
                    onChange={(e) => setTaskForm({ ...taskForm, title: e.target.value })}
                    placeholder="Enter task title"
                  />
                </div>
                <div>
                  <Label htmlFor="task-desc">Description</Label>
                  <Textarea
                    id="task-desc"
                    value={taskForm.description}
                    onChange={(e) => setTaskForm({ ...taskForm, description: e.target.value })}
                    placeholder="Enter task description"
                  />
                </div>
                <div>
                  <Label htmlFor="task-priority">Priority</Label>
                  <Select
                    value={taskForm.priority}
                    onValueChange={(value) => setTaskForm({ ...taskForm, priority: value as any })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="high">High</SelectItem>
                      <SelectItem value="medium">Medium</SelectItem>
                      <SelectItem value="low">Low</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label htmlFor="task-due">Due Date</Label>
                  <Input
                    id="task-due"
                    type="date"
                    value={taskForm.dueDate}
                    onChange={(e) => setTaskForm({ ...taskForm, dueDate: e.target.value })}
                  />
                </div>
                <Button onClick={handleCreateTask} className="w-full" disabled={!taskForm.title}>
                  Create Task
                </Button>
              </div>
            </DialogContent>
          </Dialog>
        ) : (
          <Dialog open={eventDialogOpen} onOpenChange={setEventDialogOpen}>
            <DialogTrigger asChild>
              <Button className="w-full">
                <Plus className="w-5 h-5 mr-2" />
                New Event
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Create New Event</DialogTitle>
              </DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label htmlFor="event-title">Title</Label>
                  <Input
                    id="event-title"
                    value={eventForm.title}
                    onChange={(e) => setEventForm({ ...eventForm, title: e.target.value })}
                    placeholder="Enter event title"
                  />
                </div>
                <div>
                  <Label htmlFor="event-desc">Description</Label>
                  <Textarea
                    id="event-desc"
                    value={eventForm.description}
                    onChange={(e) => setEventForm({ ...eventForm, description: e.target.value })}
                    placeholder="Enter event description"
                  />
                </div>
                <div>
                  <Label htmlFor="event-start">Start Time</Label>
                  <Input
                    id="event-start"
                    type="datetime-local"
                    value={eventForm.startTime}
                    onChange={(e) => setEventForm({ ...eventForm, startTime: e.target.value })}
                  />
                </div>
                <div>
                  <Label htmlFor="event-end">End Time</Label>
                  <Input
                    id="event-end"
                    type="datetime-local"
                    value={eventForm.endTime}
                    onChange={(e) => setEventForm({ ...eventForm, endTime: e.target.value })}
                  />
                </div>
                <div>
                  <Label htmlFor="event-location">Location</Label>
                  <Input
                    id="event-location"
                    value={eventForm.location}
                    onChange={(e) => setEventForm({ ...eventForm, location: e.target.value })}
                    placeholder="Enter location"
                  />
                </div>
                <Button
                  onClick={handleCreateEvent}
                  className="w-full"
                  disabled={!eventForm.title || !eventForm.startTime || !eventForm.endTime}
                >
                  Create Event
                </Button>
              </div>
            </DialogContent>
          </Dialog>
        )}
      </div>
    </div>
  );
}