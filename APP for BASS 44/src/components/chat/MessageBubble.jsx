import ReactMarkdown from "react-markdown";
import { Bot, Smartphone, User, CheckCircle, Calendar, Wrench } from "lucide-react";
import { format } from "date-fns";

const ToolCard = ({ toolName, toolData }) => {
  const icons = {
    Task: <CheckCircle className="w-4 h-4 text-emerald-500" />,
    Event: <Calendar className="w-4 h-4 text-violet-500" />,
    DeviceStatus: <Smartphone className="w-4 h-4 text-blue-500" />,
  };
  const entityName = Object.keys(icons).find(k => toolName?.includes(k)) || "default";
  return (
    <div className="mt-2 bg-white/60 backdrop-blur-sm border border-white/80 rounded-xl p-3 text-xs">
      <div className="flex items-center gap-2 mb-1.5 font-medium text-gray-600">
        {icons[entityName] || <Wrench className="w-4 h-4 text-gray-400" />}
        <span>{toolName}</span>
      </div>
      {toolData && (
        <pre className="text-gray-500 whitespace-pre-wrap break-all font-mono leading-relaxed">
          {typeof toolData === "object" ? JSON.stringify(toolData, null, 2) : String(toolData)}
        </pre>
      )}
    </div>
  );
};

export default function MessageBubble({ message }) {
  const isUser = message.role === "user";
  const isDevice = message.role === "device";
  const isAssistant = message.role === "assistant";

  const avatarConfig = {
    user: { bg: "bg-gradient-to-br from-slate-700 to-slate-900", icon: <User className="w-3.5 h-3.5 text-white" /> },
    assistant: { bg: "bg-gradient-to-br from-violet-500 to-indigo-600", icon: <Bot className="w-3.5 h-3.5 text-white" /> },
    device: { bg: "bg-gradient-to-br from-sky-400 to-blue-500", icon: <Smartphone className="w-3.5 h-3.5 text-white" /> },
  };
  const config = avatarConfig[message.role] || avatarConfig.assistant;

  return (
    <div className={`flex gap-2.5 ${isUser ? "flex-row-reverse" : "flex-row"} group`}>
      <div className={`w-7 h-7 rounded-full ${config.bg} flex items-center justify-center flex-shrink-0 mt-0.5 shadow-sm`}>
        {config.icon}
      </div>
      <div className={`max-w-[78%] ${isUser ? "items-end" : "items-start"} flex flex-col gap-1`}>
        <div
          className={`rounded-2xl px-4 py-2.5 shadow-sm text-sm leading-relaxed ${
            isUser
              ? "bg-gradient-to-br from-slate-800 to-slate-900 text-white rounded-tr-sm"
              : isDevice
              ? "bg-gradient-to-br from-sky-50 to-blue-50 border border-blue-100 text-slate-700 rounded-tl-sm"
              : "bg-white/90 backdrop-blur-sm border border-gray-100 text-slate-800 rounded-tl-sm"
          }`}
        >
          {isUser ? (
            <p>{message.content}</p>
          ) : (
            <ReactMarkdown
              className="prose prose-sm max-w-none prose-p:my-0.5 prose-headings:my-1"
              components={{
                p: ({ children }) => <p className="my-0.5">{children}</p>,
                ul: ({ children }) => <ul className="my-1 ml-4 list-disc space-y-0.5">{children}</ul>,
                ol: ({ children }) => <ol className="my-1 ml-4 list-decimal space-y-0.5">{children}</ol>,
                code: ({ inline, children }) =>
                  inline ? (
                    <code className="bg-gray-100 px-1 py-0.5 rounded text-xs font-mono">{children}</code>
                  ) : (
                    <pre className="bg-gray-50 rounded-lg p-2 text-xs overflow-auto my-1"><code>{children}</code></pre>
                  ),
              }}
            >
              {message.content}
            </ReactMarkdown>
          )}
          {message.message_type === "tool_call" && message.tool_name && (
            <ToolCard toolName={message.tool_name} toolData={message.tool_data} />
          )}
        </div>
        <span className="text-[10px] text-gray-400 px-1">
          {message.created_date ? format(new Date(message.created_date), "HH:mm") : ""}
        </span>
      </div>
    </div>
  );
}