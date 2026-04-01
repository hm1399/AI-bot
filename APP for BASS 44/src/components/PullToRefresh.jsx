import { useState, useEffect, useRef } from "react";
import { RefreshCw } from "lucide-react";

const THRESHOLD = 80;

export default function PullToRefresh({ onRefresh, children }) {
  const [pullProgress, setPullProgress] = useState(0); // 0–1
  const [refreshing, setRefreshing] = useState(false);
  const touchStartY = useRef(null);
  const isPulling = useRef(false);

  useEffect(() => {
    const mainEl = document.querySelector("main");
    if (!mainEl) return;

    const onTouchStart = (e) => {
      if (mainEl.scrollTop === 0) {
        touchStartY.current = e.touches[0].clientY;
        isPulling.current = false;
      }
    };

    const onTouchMove = (e) => {
      if (touchStartY.current === null) return;
      const delta = e.touches[0].clientY - touchStartY.current;
      if (delta > 0) {
        isPulling.current = true;
        setPullProgress(Math.min(delta / THRESHOLD, 1));
      }
    };

    const onTouchEnd = async () => {
      if (isPulling.current && pullProgress >= 1) {
        setRefreshing(true);
        setPullProgress(0);
        await onRefresh?.();
        setRefreshing(false);
      } else {
        setPullProgress(0);
      }
      touchStartY.current = null;
      isPulling.current = false;
    };

    mainEl.addEventListener("touchstart", onTouchStart, { passive: true });
    mainEl.addEventListener("touchmove", onTouchMove, { passive: true });
    mainEl.addEventListener("touchend", onTouchEnd);
    return () => {
      mainEl.removeEventListener("touchstart", onTouchStart);
      mainEl.removeEventListener("touchmove", onTouchMove);
      mainEl.removeEventListener("touchend", onTouchEnd);
    };
  }, [pullProgress, onRefresh]);

  const indicatorHeight = refreshing ? 44 : pullProgress * 44;
  const rotation = refreshing ? undefined : pullProgress * 360;

  return (
    <div>
      {(pullProgress > 0.05 || refreshing) && (
        <div
          className="flex items-center justify-center overflow-hidden transition-all duration-150"
          style={{ height: `${indicatorHeight}px` }}
        >
          <RefreshCw
            className={`w-5 h-5 text-violet-400 ${refreshing ? "animate-spin" : ""}`}
            style={{ opacity: Math.max(pullProgress, refreshing ? 1 : 0), transform: `rotate(${rotation ?? 0}deg)` }}
          />
        </div>
      )}
      {children}
    </div>
  );
}