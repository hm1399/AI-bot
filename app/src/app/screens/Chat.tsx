import { useEffect, useRef } from 'react';
import { ChatBubble } from '../components/ChatBubble';
import { MessageInput } from '../components/MessageInput';
import { useChat } from '../contexts/ChatContext';
import { useConfig } from '../contexts/ConfigContext';

export function Chat() {
  const { messages, sendMessage, isLoading, triggerVoiceInput, voiceAvailable } = useChat();
  const { currentSessionId, eventStreamConnected, isDemoMode } = useConfig();
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  return (
    <div className="flex flex-col h-full">
      <div className="bg-white border-b border-gray-200 p-4">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-xl font-bold text-gray-900">Conversation</h1>
            <p className="text-sm text-gray-600">
              Session: {currentSessionId || 'No active session'}
            </p>
          </div>
          <div
            className={`text-xs font-medium px-3 py-1 rounded-full ${
              isDemoMode
                ? 'bg-amber-100 text-amber-700'
                : eventStreamConnected
                  ? 'bg-green-100 text-green-700'
                  : 'bg-yellow-100 text-yellow-700'
            }`}
          >
            {isDemoMode ? 'Demo' : eventStreamConnected ? 'Events Live' : 'Events Reconnecting'}
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4 bg-gray-50">
        {messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <div className="w-16 h-16 bg-gray-200 rounded-full flex items-center justify-center mb-4">
              <span className="text-3xl">AI</span>
            </div>
            <h3 className="text-lg font-medium text-gray-900 mb-2">No messages yet</h3>
            <p className="text-sm text-gray-600 max-w-sm">
              User messages are posted once. Assistant progress and completion arrive later through the backend event stream.
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

      <MessageInput
        onSend={sendMessage}
        onVoiceClick={triggerVoiceInput}
        disabled={isLoading}
        voiceEnabled={voiceAvailable || isDemoMode}
      />
    </div>
  );
}
