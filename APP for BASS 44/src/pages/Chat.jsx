const db = globalThis.__B44_DB__ || { auth:{ isAuthenticated: async()=>false, me: async()=>null }, entities:new Proxy({}, { get:()=>({ filter:async()=>[], get:async()=>null, create:async()=>({}), update:async()=>({}), delete:async()=>({}) }) }), integrations:{ Core:{ UploadFile:async()=>({ file_url:'' }) } } };

import { useState, useEffect, useRef, memo } from "react";

import MessageBubble from "../components/chat/MessageBubble";
import MessageInput from "../components/chat/MessageInput";
import { Bot, Sparkles, RefreshCw } from "lucide-react";

const Chat = memo(function Chat() {
  const [conversation, setConversation] = useState(null);
  const [messages, setMessages] = useState([]);
  const [loading, setLoading] = useState(false);
  const [initializing, setInitializing] = useState(true);
  const bottomRef = useRef(null);

  useEffect(() => {
    initConversation();
  }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const initConversation = async () => {
    setInitializing(true);
    const convs = await db.agents.listConversations({ agent_name: "ai_assistant" });
    let conv;
    if (convs?.length > 0) {
      conv = await db.agents.getConversation(convs[0].id);
      setMessages(conv.messages || []);
    } else {
      conv = await db.agents.createConversation({
        agent_name: "ai_assistant",
        metadata: { name: "AI助手对话" },
      });
    }
    setConversation(conv);
    setInitializing(false);
  };

  useEffect(() => {
    if (!conversation?.id) return;
    const unsubscribe = db.agents.subscribeToConversation(conversation.id, (data) => {
      setMessages(data.messages || []);
      const last = data.messages?.[data.messages.length - 1];
      if (last?.role === "assistant" && last?.status !== "streaming") {
        setLoading(false);
      }
    });
    return () => unsubscribe();
  }, [conversation?.id]);

  const handleSend = async (text) => {
    if (!conversation) return;
    setLoading(true);
    await db.agents.addMessage(conversation, { role: "user", content: text });
  };

  const handleNewConversation = async () => {
    const conv = await db.agents.createConversation({
      agent_name: "ai_assistant",
      metadata: { name: "AI助手对话" },
    });
    setConversation(conv);
    setMessages([]);
  };

  const displayMessages = messages.filter(m => m.role === "user" || m.role === "assistant");

  return (
    <div className="flex flex-col h-full bg-gradient-to-b from-slate-50 to-gray-50">
      {/* Header */}
      <div className="flex items-center justify-between px-5 pt-5 pb-3 border-b border-gray-100 bg-white/80 backdrop-blur-sm">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-violet-500 to-indigo-600 flex items-center justify-center shadow-sm">
            <Bot className="w-5 h-5 text-white" />
          </div>
          <div>
            <h1 className="font-semibold text-slate-800 text-base leading-none">AI 助手</h1>
            <p className="text-[11px] text-gray-400 mt-0.5">管理任务、日程、设备</p>
          </div>
        </div>
        <button
          onClick={handleNewConversation}
          className="p-2 rounded-xl text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-all"
        >
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        {initializing ? (
          <div className="flex flex-col items-center justify-center h-full gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-violet-500 to-indigo-600 flex items-center justify-center animate-pulse">
              <Bot className="w-5 h-5 text-white" />
            </div>
            <p className="text-sm text-gray-400">正在连接 AI 助手...</p>
          </div>
        ) : displayMessages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full gap-4 px-6 text-center">
            <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-violet-100 to-indigo-100 flex items-center justify-center">
              <Sparkles className="w-7 h-7 text-violet-500" />
            </div>
            <div>
              <h3 className="font-semibold text-slate-700 text-base">你好！我是 AI 助手</h3>
              <p className="text-sm text-gray-400 mt-1 leading-relaxed">
                我可以帮你管理任务、安排日程、控制设备。<br />试着对我说：
              </p>
            </div>
            <div className="space-y-2 w-full">
              {["安排明天下午3点的团队会议", "帮我创建一个高优先级任务", "总结一下设备当前状态"].map(s => (
                <button
                  key={s}
                  onClick={() => handleSend(s)}
                  className="w-full text-left text-sm px-4 py-3 rounded-xl bg-white border border-gray-100 text-slate-600 hover:border-violet-200 hover:bg-violet-50 hover:text-violet-700 transition-all shadow-sm"
                >
                  "{s}"
                </button>
              ))}
            </div>
          </div>
        ) : (
          displayMessages.map((msg, i) => (
            <MessageBubble key={msg.id || i} message={msg} />
          ))
        )}
        {loading && (
          <div className="flex gap-2.5">
            <div className="w-7 h-7 rounded-full bg-gradient-to-br from-violet-500 to-indigo-600 flex items-center justify-center flex-shrink-0 mt-0.5">
              <Bot className="w-3.5 h-3.5 text-white" />
            </div>
            <div className="bg-white/90 border border-gray-100 rounded-2xl rounded-tl-sm px-4 py-3 shadow-sm">
              <div className="flex gap-1">
                <span className="w-1.5 h-1.5 bg-gray-300 rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
                <span className="w-1.5 h-1.5 bg-gray-300 rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
                <span className="w-1.5 h-1.5 bg-gray-300 rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
              </div>
            </div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      <MessageInput onSend={handleSend} loading={loading} disabled={initializing} />
      </div>
      );
      });

      export default Chat;