import { useState, useRef } from "react";
import { Send, Mic, Loader2 } from "lucide-react";

const QUICK_COMMANDS = [
  "总结设备状态",
  "安排一个明天的会议",
  "帮我创建一个任务",
  "查看今日日程",
];

export default function MessageInput({ onSend, loading, disabled }) {
  const [text, setText] = useState("");
  const [showQuick, setShowQuick] = useState(false);
  const textareaRef = useRef(null);

  const handleSend = () => {
    if (!text.trim() || loading) return;
    onSend(text.trim());
    setText("");
    setShowQuick(false);
    if (textareaRef.current) textareaRef.current.style.height = "auto";
  };

  const handleKeyDown = (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleInput = (e) => {
    setText(e.target.value);
    e.target.style.height = "auto";
    e.target.style.height = Math.min(e.target.scrollHeight, 120) + "px";
  };

  return (
    <div className="p-4 pb-safe">
      {showQuick && (
        <div className="flex gap-2 flex-wrap mb-3">
          {QUICK_COMMANDS.map((cmd) => (
            <button
              key={cmd}
              onClick={() => { setText(cmd); setShowQuick(false); textareaRef.current?.focus(); }}
              className="text-xs bg-white/80 border border-gray-200 rounded-full px-3 py-1.5 text-gray-600 hover:bg-violet-50 hover:border-violet-200 hover:text-violet-700 transition-all"
            >
              {cmd}
            </button>
          ))}
        </div>
      )}
      <div className="flex items-end gap-2 bg-white/80 backdrop-blur-sm border border-gray-200 rounded-2xl px-3 py-2 shadow-sm focus-within:border-violet-300 focus-within:shadow-md transition-all">
        <button
          onClick={() => setShowQuick(v => !v)}
          className={`p-1.5 rounded-full transition-colors flex-shrink-0 mb-0.5 ${showQuick ? "bg-violet-100 text-violet-600" : "text-gray-400 hover:text-gray-600"}`}
        >
          <Mic className="w-4 h-4" />
        </button>
        <textarea
          ref={textareaRef}
          value={text}
          onChange={handleInput}
          onKeyDown={handleKeyDown}
          placeholder="输入指令，例如：安排一个会议..."
          disabled={disabled || loading}
          rows={1}
          className="flex-1 bg-transparent text-sm text-slate-800 placeholder-gray-400 resize-none outline-none leading-relaxed py-1 max-h-[120px] disabled:opacity-50"
        />
        <button
          onClick={handleSend}
          disabled={!text.trim() || loading || disabled}
          className="w-8 h-8 rounded-full bg-gradient-to-br from-violet-500 to-indigo-600 flex items-center justify-center flex-shrink-0 mb-0.5 shadow-sm disabled:opacity-40 disabled:cursor-not-allowed hover:shadow-md active:scale-95 transition-all"
        >
          {loading ? (
            <Loader2 className="w-4 h-4 text-white animate-spin" />
          ) : (
            <Send className="w-4 h-4 text-white" />
          )}
        </button>
      </div>
    </div>
  );
}