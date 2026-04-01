import { Toaster } from "@/components/ui/toaster"
import { QueryClientProvider } from '@tanstack/react-query'
import { queryClientInstance } from '@/lib/query-client'
import { BrowserRouter as Router, Route, Routes, useLocation, useNavigationType, Navigate } from 'react-router-dom';
import PageNotFound from './lib/PageNotFound';
import { AuthProvider, useAuth } from '@/lib/AuthContext';
import UserNotRegisteredError from '@/components/UserNotRegisteredError';
import { AnimatePresence, motion } from 'framer-motion';
import { useEffect, useRef, lazy, Suspense } from 'react';
import Layout from './Layout.jsx';

// ── Code-split all pages ──────────────────────────────────────────────────────
const Home        = lazy(() => import('./pages/Home'));
const Chat        = lazy(() => import('./pages/Chat'));
const TasksEvents = lazy(() => import('./pages/TasksEvents'));
const Settings    = lazy(() => import('./pages/Settings'));

// ── Tab order drives slide direction ─────────────────────────────────────────
const TAB_ORDER = ["Home", "Chat", "TasksEvents", "Settings"];

// ── Theme listener ────────────────────────────────────────────────────────────
function ThemeListener() {
  useEffect(() => {
    const apply = (e) => document.documentElement.classList.toggle("dark", e.matches);
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    document.documentElement.classList.toggle("dark", mq.matches);
    mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, []);
  return null;
}

// ── Page suspense fallback ────────────────────────────────────────────────────
function PageLoader() {
  return (
    <div className="flex items-center justify-center h-full">
      <div className="w-8 h-8 border-4 border-slate-200 border-t-violet-500 rounded-full animate-spin" />
    </div>
  );
}

// ── Persistent tab stacks ─────────────────────────────────────────────────────
// Each tab keeps its own rendered subtree alive via CSS visibility so scroll
// position and component state are preserved when switching tabs.
function PersistentTabs({ currentPage }) {
  const tabs = TAB_ORDER;

  return (
    <div style={{ position: "relative", height: "100%", width: "100%" }}>
      {tabs.map(tab => {
        const isActive = currentPage === tab || (currentPage === "" && tab === "Home");
        const PageComponent = { Home, Chat, TasksEvents, Settings }[tab];
        return (
          <div
            key={tab}
            aria-hidden={!isActive}
            style={{
              position: "absolute",
              inset: 0,
              visibility: isActive ? "visible" : "hidden",
              // Keep rendered but hidden — preserves scroll + state
              pointerEvents: isActive ? "auto" : "none",
              zIndex: isActive ? 1 : 0,
            }}
          >
            <Suspense fallback={<PageLoader />}>
              <PageComponent />
            </Suspense>
          </div>
        );
      })}
    </div>
  );
}

// ── Animated route wrapper ────────────────────────────────────────────────────
function AnimatedRoutes() {
  const location = useLocation();
  const navType = useNavigationType();
  const prevPageRef = useRef(null);

  const currentPage = location.pathname.replace("/", "") || "Home";
  const currentIdx  = TAB_ORDER.indexOf(currentPage);
  const prevIdx     = TAB_ORDER.indexOf(prevPageRef.current);

  // Direction: back nav or lower tab index → slide from left
  const isTabNav = currentIdx >= 0 && prevIdx >= 0;
  const direction = navType === "POP" || (isTabNav && currentIdx < prevIdx) ? -1 : 1;

  useEffect(() => { prevPageRef.current = currentPage; }, [currentPage]);

  const isTabPage = TAB_ORDER.includes(currentPage) || currentPage === "";

  return (
    <AnimatePresence mode="wait" initial={false}>
      <motion.div
        key={isTabPage ? "tabs" : location.pathname}
        initial={{ x: `${60 * direction}%`, opacity: 0 }}
        animate={{ x: 0, opacity: 1 }}
        exit={{ x: `${-60 * direction}%`, opacity: 0 }}
        transition={{ type: "tween", duration: 0.2, ease: "easeInOut" }}
        style={{ position: "absolute", inset: 0, overflow: "hidden" }}
      >
        <Routes location={location}>
          {/* Root redirect */}
          <Route path="/" element={<Navigate to="/Home" replace />} />

          {/* All tab pages share one persistent layer — no re-mount on tab switch */}
          {TAB_ORDER.map(tab => (
            <Route
              key={tab}
              path={`/${tab}`}
              element={
                <Layout currentPageName={tab}>
                  <PersistentTabs currentPage={tab} />
                </Layout>
              }
            />
          ))}

          <Route path="*" element={<PageNotFound />} />
        </Routes>
      </motion.div>
    </AnimatePresence>
  );
}

// ── Auth shell ────────────────────────────────────────────────────────────────
const AuthenticatedApp = () => {
  const { isLoadingAuth, isLoadingPublicSettings, authError, navigateToLogin } = useAuth();

  if (isLoadingPublicSettings || isLoadingAuth) {
    return (
      <div className="fixed inset-0 flex items-center justify-center">
        <div className="w-8 h-8 border-4 border-slate-200 border-t-slate-800 rounded-full animate-spin" />
      </div>
    );
  }

  if (authError) {
    if (authError.type === 'user_not_registered') return <UserNotRegisteredError />;
    if (authError.type === 'auth_required') { navigateToLogin(); return null; }
  }

  return (
    <div style={{ position: "relative", height: "100vh", overflow: "hidden" }}>
      <AnimatedRoutes />
    </div>
  );
};

// ── Root ──────────────────────────────────────────────────────────────────────
export default function App() {
  return (
    <AuthProvider>
      <QueryClientProvider client={queryClientInstance}>
        <Router>
          <ThemeListener />
          <AuthenticatedApp />
        </Router>
        <Toaster />
      </QueryClientProvider>
    </AuthProvider>
  );
}