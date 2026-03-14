import { Message } from '../models/types';
import { Bot, Smartphone, Info } from 'lucide-react';

interface ChatBubbleProps {
  message: Message;
}

export function ChatBubble({ message }: ChatBubbleProps) {
  const isDevice = message.source === 'device';
  const isApp = message.source === 'app';
  const isSystem = message.source === 'system';

  const avatarBg = isDevice ? 'bg-blue-500' : isApp ? 'bg-green-500' : 'bg-gray-500';
  const bubbleBg = isApp ? 'bg-green-500 text-white' : 'bg-gray-100 text-gray-900';
  const statusBg = 
    message.toolResult?.status === 'success' ? 'bg-green-100 text-green-700' :
    message.toolResult?.status === 'error' ? 'bg-red-100 text-red-700' :
    'bg-yellow-100 text-yellow-700';

  return (
    <div className={`flex gap-3 mb-4 ${isApp ? 'flex-row-reverse' : ''}`}>
      <div className={`flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center ${avatarBg}`}>
        {isDevice && <Bot className="w-5 h-5 text-white" />}
        {isApp && <Smartphone className="w-5 h-5 text-white" />}
        {isSystem && <Info className="w-5 h-5 text-white" />}
      </div>
      <div className="flex flex-col max-w-[70%]">
        <div className={`rounded-2xl px-4 py-2 ${bubbleBg}`}>
          <p className="text-sm">{message.text}</p>
        </div>
        {message.toolResult && (
          <div className="mt-2 p-3 bg-gray-50 rounded-lg border border-gray-200">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs font-medium text-gray-600">Tool: {message.toolResult.toolName}</span>
              <span className={`text-xs px-2 py-0.5 rounded ${statusBg}`}>
                {message.toolResult.status}
              </span>
            </div>
            <p className="text-xs text-gray-700">{message.toolResult.result}</p>
          </div>
        )}
        <span className="text-xs text-gray-500 mt-1 px-2">
          {new Date(message.timestamp).toLocaleTimeString()}
        </span>
      </div>
    </div>
  );
}