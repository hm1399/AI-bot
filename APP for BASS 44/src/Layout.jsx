import { Link, useNavigate, useLocation } from "react-router-dom";
import { createPageUrl } from "@/utils";
import { Home, MessageCircle, CalendarDays, Settings, ChevronLeft } from "lucide-react";
import { useRef, useEffect, memo } from "react";

// Map each child page back to its parent tab
const PARENT_TAB = {};  // all current pages are root tabs — extend here for sub-pages

const navItems = [
  { name: "Home", label: "首页", icon: Home },
  { name: "Chat", label: "对话", icon: MessageCircle },
  { name: "TasksEvents", label: "任务", icon: CalendarDays },
  { name: "Settings", label: "设置", icon: Settings },
];

const ROOT_PAGES = navItems.map(n => n.name);

const pageTitles = {
  Home: "首页",
  Chat: "AI 对话",
  TasksEvents: "任务 & 日程",
  Settings: "设置",
};

// Store scroll positions per tab
const scrollPositions = {};

const Layout = memo(function Layout({ children, currentPageName }) {
  const navigate = useNavigate();
  const location = useLocation();
  const mainRef = useRef(null);
  const isRootPage = ROOT_PAGES.includes(currentPageName);

  const handleBack = () => {
    const parent = PARENT_TAB[currentPageName];
    if (parent) {
      navigate(createPageUrl(parent), { replace: false });
    } else if (window.history.length > 1) {
      navigate(-1, { state: { back: true } });
    } else {
      navigate(createPageUrl("Home"));
    }
  };

  // Save/restore scroll position when switching tabs
  useEffect(() => {
    const el = mainRef.current;
    if (!el || !isRootPage) return;
    // Restore saved position
    el.scrollTop = scrollPositions[currentPageName] ?? 0;
    // Save on scroll
    const onScroll = () => { scrollPositions[currentPageName] = el.scrollTop; };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => el.removeEventListener("scroll", onScroll);
  }, [currentPageName, isRootPage]);

  return (
    <div className="flex flex-col h-screen bg-gray-50 max-w-md mx-auto relative">
      <style>{`
        :root { --font-sans: 'Inter', 'PingFang SC', 'Helvetica Neue', sans-serif; }
        body { font-family: var(--font-sans); }
        * { -webkit-tap-highlight-color: transparent; }
        .pb-safe { padding-bottom: max(1rem, env(safe-area-inset-bottom)); }
        .pt-safe { padding-top: max(0px, env(safe-area-inset-top)); }
        html, body { overscroll-behavior: none; -webkit-overflow-scrolling: touch; }
        button, a, [role="button"] { user-select: none; -webkit-user-select: none; }
        svg { pointer-events: none; user-select: none; -webkit-user-select: none; }
        input, textarea { user-select: text !important; -webkit-user-select: text !important; }
      `}</style>

      {/* Top header — shown on child (non-nav) routes */}
      {!isRootPage && (
        <header className="flex items-center gap-2 px-3 py-2 bg-white/90 backdrop-blur-xl border-b border-gray-100 pt-safe flex-shrink-0">
          <button
            onClick={handleBack}
            aria-label="返回上一页"
            className="min-w-[44px] min-h-[44px] flex items-center justify-center rounded-xl text-slate-600 hover:bg-gray-100 transition-colors active:scale-95"
          >
            <ChevronLeft className="w-5 h-5" aria-hidden="true" />
          </button>
          <h1 className="text-base font-semibold text-slate-800 flex-1">
            {pageTitles[currentPageName] || currentPageName}
          </h1>
        </header>
      )}

      {/* Page content */}
      <main ref={mainRef} className="flex-1 overflow-y-auto">
        {children}
      </main>

      {/* Bottom Navigation */}
      <nav className="bg-white/90 backdrop-blur-xl border-t border-gray-100 px-2 pt-1 pb-safe flex-shrink-0 shadow-[0_-1px_0_rgba(0,0,0,0.05)]">
        <div className="flex">
          {navItems.map(({ name, label, icon: Icon }) => {
            const isActive = currentPageName === name;
            return (
              <Link
                key={name}
                to={createPageUrl(name)}
                aria-label={label}
                aria-current={isActive ? "page" : undefined}
                className="flex-1 flex flex-col items-center justify-center gap-0.5 min-h-[44px] py-1 px-2 rounded-xl transition-all active:scale-95 select-none"
              >
                <div className={`w-10 h-8 flex items-center justify-center rounded-xl transition-all ${
                  isActive ? "bg-violet-100" : ""
                }`}>
                  <Icon aria-hidden="true" className={`w-5 h-5 transition-colors ${
                    isActive ? "text-violet-600" : "text-gray-400"
                  }`} />
                </div>
                <span className={`text-xs font-medium transition-colors leading-none ${
                  isActive ? "text-violet-600" : "text-gray-400"
                }`}>
                  {label}
                </span>
              </Link>
            );
          })}
        </div>
      </nav>
    </div>
  );
});

export default Layout;