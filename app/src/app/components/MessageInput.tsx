import { useState } from 'react';
import { Mic, Send } from 'lucide-react';

interface MessageInputProps {
  onSend: (text: string) => Promise<void> | void;
  onVoiceClick?: () => void;
  disabled?: boolean;
  voiceEnabled?: boolean;
}

export function MessageInput({ onSend, onVoiceClick, disabled, voiceEnabled }: MessageInputProps) {
  const [text, setText] = useState('');

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!text.trim() || disabled) {
      return;
    }
    const next = text;
    setText('');
    await onSend(next);
  };

  return (
    <form onSubmit={handleSubmit} className="flex gap-2 p-4 bg-white border-t border-gray-200">
      <input
        type="text"
        value={text}
        onChange={(event) => setText(event.target.value)}
        placeholder="Send a message through the backend event pipeline"
        disabled={disabled}
        className="flex-1 px-4 py-2 border border-gray-300 rounded-full focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100"
      />
      <button
        type="button"
        onClick={onVoiceClick}
        className="w-10 h-10 rounded-full bg-gray-100 flex items-center justify-center hover:bg-gray-200 transition-colors disabled:bg-gray-200 disabled:text-gray-400"
        disabled={disabled || !voiceEnabled}
        title={voiceEnabled ? 'Voice input entry' : 'Voice pipeline unavailable'}
      >
        <Mic className="w-5 h-5 text-gray-600" />
      </button>
      <button
        type="submit"
        disabled={disabled || !text.trim()}
        className="w-10 h-10 rounded-full bg-blue-500 flex items-center justify-center hover:bg-blue-600 transition-colors disabled:bg-gray-300 disabled:cursor-not-allowed"
      >
        <Send className="w-5 h-5 text-white" />
      </button>
    </form>
  );
}
