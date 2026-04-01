import { Outlet, Link, useLocation } from 'react-router';
import { Home, MessageSquare, Calendar, Settings, Wifi, WifiOff } from 'lucide-react';
import { DeviceProvider } from './contexts/DeviceContext';
import { ChatProvider } from './contexts/ChatContext';
import { TaskProvider } from './contexts/TaskContext';
import { EventProvider } from './contexts/EventContext';
import { useConfig } from './contexts/ConfigContext';

export function Root() {
  const location = useLocation();
  const { isConnected, isDemoMode, eventStreamConnected } = useConfig();

  const navItems = [
    { path: '/app', icon: Home, label: 'Home' },
    { path: '/app/chat', icon: MessageSquare, label: 'Chat' },
    { path: '/app/tasks', icon: Calendar, label: 'Tasks' },
    { path: '/app/settings', icon: Settings, label: 'Settings' },
  ];

  const statusBarBg = isDemoMode
    ? 'bg-amber-600'
    : isConnected && eventStreamConnected
      ? 'bg-green-600'
      : isConnected
        ? 'bg-yellow-600'
        : 'bg-red-600';
  const statusText = isDemoMode
    ? 'Demo Mode'
    : isConnected && eventStreamConnected
      ? 'Connected'
      : isConnected
        ? 'Backend Connected · Event Stream Reconnecting'
        : 'Disconnected';
  const StatusIcon = isConnected || isDemoMode ? Wifi : WifiOff;

  return (
    <DeviceProvider>
      <ChatProvider>
        <TaskProvider>
          <EventProvider>
            <div className="h-screen flex flex-col bg-gray-50">
              {/* Connection status bar */}
              <div className={`px-4 py-2 text-xs font-medium text-white flex items-center justify-center gap-2 ${statusBarBg}`}>
                <StatusIcon className="w-3 h-3" />
                <span>{statusText}</span>
              </div>

              <main className="flex-1 overflow-hidden">
                <Outlet />
              </main>

              <nav className="bg-white border-t border-gray-200 safe-area-inset-bottom">
                <div className="flex justify-around items-center h-16">
                  {navItems.map((item) => {
                    const Icon = item.icon;
                    const isActive = location.pathname === item.path;
                    const linkColor = isActive ? 'text-blue-600' : 'text-gray-600 hover:text-gray-900';
                    const iconFill = isActive ? 'fill-blue-100' : '';
                    
                    return (
                      <Link
                        key={item.path}
                        to={item.path}
                        className={`flex flex-col items-center justify-center flex-1 h-full transition-colors ${linkColor}`}
                      >
                        <Icon className={`w-6 h-6 ${iconFill}`} />
                        <span className="text-xs mt-1 font-medium">{item.label}</span>
                      </Link>
                    );
                  })}
                </div>
              </nav>
            </div>
          </EventProvider>
        </TaskProvider>
      </ChatProvider>
    </DeviceProvider>
  );
}
