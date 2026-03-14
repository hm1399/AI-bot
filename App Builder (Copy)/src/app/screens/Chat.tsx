import { useEffect, useRef } from 'react';
import { useChat } from '../contexts/ChatContext';
import { ChatBubble } from '../components/ChatBubble';
import { MessageInput } from '../components/MessageInput';

export function Chat() {
  const { messages, sendMessage, isLoading } = useChat();
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  return (
    <div className="flex flex-col h-full">
      <div className="bg-white border-b border-gray-200 p-4">
        <h1 className="text-xl font-bold text-gray-900">Conversation</h1>
        <p className="text-sm text-gray-600">Chat with your AI assistant</p>
      </div>

      <div className="flex-1 overflow-y-auto p-4 bg-gray-50">
        {messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <div className="w-16 h-16 bg-gray-200 rounded-full flex items-center justify-center mb-4">
              <span className="text-3xl">💬</span>
            </div>
            <h3 className="text-lg font-medium text-gray-900 mb-2">No messages yet</h3>
            <p className="text-sm text-gray-600 max-w-sm">
              Start a conversation with your AI assistant. You can ask questions, request tasks, or control your device.
            </p>
          </div>
        ) : (
          <>
            {messages.map((message) => (
              <ChatBubble key={message.id} message={message} />
            ))}
            <div ref={messagesEndRef} />
          </>
        )}
      </div>

      <MessageInput onSend={sendMessage} disabled={isLoading} />
    </div>
  );
}
