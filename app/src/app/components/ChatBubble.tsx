import { Bot, Info, Smartphone } from 'lucide-react';
import { Message } from '../models/types';

interface ChatBubbleProps {
  message: Message;
}

export function ChatBubble({ message }: ChatBubbleProps) {
  const isUser = message.role === 'user';
  const isAssistant = message.role === 'assistant';
  const isSystem = message.role === 'system';

  const avatarBg = isAssistant ? 'bg-blue-500' : isUser ? 'bg-green-500' : 'bg-gray-500';
  const bubbleBg = isUser ? 'bg-green-500 text-white' : 'bg-gray-100 text-gray-900';
  const statusClass =
    message.status === 'completed'
      ? 'bg-green-100 text-green-700'
      : message.status === 'failed'
        ? 'bg-red-100 text-red-700'
        : 'bg-yellow-100 text-yellow-700';

  return (
    <div className={`flex gap-3 mb-4 ${isUser ? 'flex-row-reverse' : ''}`}>
      <div className={`flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center ${avatarBg}`}>
        {isAssistant && <Bot className="w-5 h-5 text-white" />}
        {isUser && <Smartphone className="w-5 h-5 text-white" />}
        {isSystem && <Info className="w-5 h-5 text-white" />}
      </div>
      <div className="flex flex-col max-w-[78%]">
        <div className={`rounded-2xl px-4 py-3 ${bubbleBg}`}>
          <p className="text-sm whitespace-pre-wrap">{message.text}</p>
        </div>
        <div className="flex items-center gap-2 mt-1 px-2">
          <span className={`text-[11px] px-2 py-0.5 rounded-full ${statusClass}`}>
            {message.status}
          </span>
          <span className="text-xs text-gray-500">
            {new Date(message.createdAt).toLocaleTimeString()}
          </span>
        </div>
        {message.errorReason && (
          <p className="text-xs text-red-600 mt-1 px-2">
            Failure reason: {message.errorReason}
          </p>
        )}
      </div>
    </div>
  );
}
