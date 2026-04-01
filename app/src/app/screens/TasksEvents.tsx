import { useMemo, useState } from 'react';
import { Calendar as CalendarIcon, CheckSquare, Plus } from 'lucide-react';
import { EventTile } from '../components/EventTile';
import { TaskTile } from '../components/TaskTile';
import { Button } from '../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from '../components/ui/dialog';
import { Input } from '../components/ui/input';
import { Label } from '../components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../components/ui/select';
import { Textarea } from '../components/ui/textarea';
import { useEvents } from '../contexts/EventContext';
import { useTasks } from '../contexts/TaskContext';

type Tab = 'tasks' | 'events';

export function TasksEvents() {
  const [activeTab, setActiveTab] = useState<Tab>('tasks');
  const { tasks, createTask, toggleTask, deleteTask, backendStatus: taskStatus, statusMessage: taskMessage } = useTasks();
  const { events, createEvent, deleteEvent, backendStatus: eventStatus, statusMessage: eventMessage } = useEvents();

  const [taskDialogOpen, setTaskDialogOpen] = useState(false);
  const [eventDialogOpen, setEventDialogOpen] = useState(false);

  const [taskForm, setTaskForm] = useState({
    title: '',
    description: '',
    priority: 'medium' as 'high' | 'medium' | 'low',
    dueAt: '',
  });

  const [eventForm, setEventForm] = useState({
    title: '',
    description: '',
    startAt: '',
    endAt: '',
    location: '',
  });

  const taskActionsEnabled = taskStatus === 'ready' || taskStatus === 'demo';
  const eventActionsEnabled = eventStatus === 'ready' || eventStatus === 'demo';

  const handleCreateTask = async () => {
    await createTask({
      title: taskForm.title,
      description: taskForm.description,
      priority: taskForm.priority,
      completed: false,
      dueAt: taskForm.dueAt ? new Date(taskForm.dueAt).toISOString() : null,
    });
    setTaskForm({ title: '', description: '', priority: 'medium', dueAt: '' });
    setTaskDialogOpen(false);
  };

  const handleCreateEvent = async () => {
    await createEvent({
      title: eventForm.title,
      description: eventForm.description,
      startAt: new Date(eventForm.startAt).toISOString(),
      endAt: new Date(eventForm.endAt).toISOString(),
      location: eventForm.location,
    });
    setEventForm({ title: '', description: '', startAt: '', endAt: '', location: '' });
    setEventDialogOpen(false);
  };

  const tasksByPriority = useMemo(
    () => ({
      high: tasks.filter((task) => task.priority === 'high' && !task.completed),
      medium: tasks.filter((task) => task.priority === 'medium' && !task.completed),
      low: tasks.filter((task) => task.priority === 'low' && !task.completed),
      completed: tasks.filter((task) => task.completed),
    }),
    [tasks],
  );

  const upcomingEvents = useMemo(
    () =>
      events
        .filter((event) => new Date(event.startAt) >= new Date())
        .sort((left, right) => new Date(left.startAt).getTime() - new Date(right.startAt).getTime()),
    [events],
  );

  const notice = activeTab === 'tasks' ? taskMessage : eventMessage;

  return (
    <div className="flex flex-col h-full">
      <div className="bg-white border-b border-gray-200">
        <div className="p-4">
          <h1 className="text-xl font-bold text-gray-900">Tasks & Events</h1>
          <p className="text-sm text-gray-600">If the backend has not shipped these endpoints yet, the UI keeps the entry points visible and explains why actions are disabled.</p>
        </div>
        <div className="flex border-t border-gray-200">
          <button
            onClick={() => setActiveTab('tasks')}
            className={`flex-1 flex items-center justify-center gap-2 py-3 font-medium transition-colors ${
              activeTab === 'tasks' ? 'text-blue-600 border-b-2 border-blue-600' : 'text-gray-600 hover:text-gray-900'
            }`}
          >
            <CheckSquare className="w-5 h-5" />
            <span>Tasks</span>
          </button>
          <button
            onClick={() => setActiveTab('events')}
            className={`flex-1 flex items-center justify-center gap-2 py-3 font-medium transition-colors ${
              activeTab === 'events' ? 'text-blue-600 border-b-2 border-blue-600' : 'text-gray-600 hover:text-gray-900'
            }`}
          >
            <CalendarIcon className="w-5 h-5" />
            <span>Events</span>
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4 bg-gray-50 space-y-4">
        {notice && (
          <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
            {notice}
          </div>
        )}

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
                <p className="text-gray-600">
                  {taskStatus === 'not-ready' ? 'Task API not ready yet.' : 'No tasks yet.'}
                </p>
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
                <p className="text-gray-600">
                  {eventStatus === 'not-ready' ? 'Event API not ready yet.' : 'No upcoming events.'}
                </p>
              </div>
            )}
          </div>
        )}
      </div>

      <div className="p-4 bg-white border-t border-gray-200">
        {activeTab === 'tasks' ? (
          <Dialog open={taskDialogOpen} onOpenChange={setTaskDialogOpen}>
            <DialogTrigger asChild>
              <Button className="w-full" disabled={!taskActionsEnabled}>
                <Plus className="w-5 h-5 mr-2" />
                {taskActionsEnabled ? 'New Task' : 'Task API Pending'}
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Create New Task</DialogTitle>
                <DialogDescription>When the backend endpoint is available, this form posts to `/api/app/v1/tasks`.</DialogDescription>
              </DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label htmlFor="task-title">Title</Label>
                  <Input
                    id="task-title"
                    value={taskForm.title}
                    onChange={(event) => setTaskForm({ ...taskForm, title: event.target.value })}
                    placeholder="Enter task title"
                  />
                </div>
                <div>
                  <Label htmlFor="task-desc">Description</Label>
                  <Textarea
                    id="task-desc"
                    value={taskForm.description}
                    onChange={(event) => setTaskForm({ ...taskForm, description: event.target.value })}
                    placeholder="Enter task description"
                  />
                </div>
                <div>
                  <Label htmlFor="task-priority">Priority</Label>
                  <Select value={taskForm.priority} onValueChange={(value) => setTaskForm({ ...taskForm, priority: value as 'high' | 'medium' | 'low' })}>
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
                    type="datetime-local"
                    value={taskForm.dueAt}
                    onChange={(event) => setTaskForm({ ...taskForm, dueAt: event.target.value })}
                  />
                </div>
                <Button onClick={() => void handleCreateTask()} className="w-full" disabled={!taskForm.title}>
                  Create Task
                </Button>
              </div>
            </DialogContent>
          </Dialog>
        ) : (
          <Dialog open={eventDialogOpen} onOpenChange={setEventDialogOpen}>
            <DialogTrigger asChild>
              <Button className="w-full" disabled={!eventActionsEnabled}>
                <Plus className="w-5 h-5 mr-2" />
                {eventActionsEnabled ? 'New Event' : 'Event API Pending'}
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Create New Event</DialogTitle>
                <DialogDescription>When the backend endpoint is available, this form posts to `/api/app/v1/events`.</DialogDescription>
              </DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label htmlFor="event-title">Title</Label>
                  <Input
                    id="event-title"
                    value={eventForm.title}
                    onChange={(event) => setEventForm({ ...eventForm, title: event.target.value })}
                    placeholder="Enter event title"
                  />
                </div>
                <div>
                  <Label htmlFor="event-desc">Description</Label>
                  <Textarea
                    id="event-desc"
                    value={eventForm.description}
                    onChange={(event) => setEventForm({ ...eventForm, description: event.target.value })}
                    placeholder="Enter event description"
                  />
                </div>
                <div>
                  <Label htmlFor="event-start">Start Time</Label>
                  <Input
                    id="event-start"
                    type="datetime-local"
                    value={eventForm.startAt}
                    onChange={(event) => setEventForm({ ...eventForm, startAt: event.target.value })}
                  />
                </div>
                <div>
                  <Label htmlFor="event-end">End Time</Label>
                  <Input
                    id="event-end"
                    type="datetime-local"
                    value={eventForm.endAt}
                    onChange={(event) => setEventForm({ ...eventForm, endAt: event.target.value })}
                  />
                </div>
                <div>
                  <Label htmlFor="event-location">Location</Label>
                  <Input
                    id="event-location"
                    value={eventForm.location}
                    onChange={(event) => setEventForm({ ...eventForm, location: event.target.value })}
                    placeholder="Enter location"
                  />
                </div>
                <Button
                  onClick={() => void handleCreateEvent()}
                  className="w-full"
                  disabled={!eventForm.title || !eventForm.startAt || !eventForm.endAt}
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
