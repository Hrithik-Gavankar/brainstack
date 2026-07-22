import { CheckCircle2, Circle } from "lucide-react";
import type { GrowthItem } from "../types";

interface GrowthTrackerProps {
  items: GrowthItem[];
}

export function GrowthTracker({ items }: GrowthTrackerProps) {
  const categories = [...new Set(items.map((i) => i.category))];
  const completed = items.filter((i) => i.completed).length;
  const total = items.length;
  const pct = Math.round((completed / total) * 100);

  return (
    <div className="rounded-xl border border-border-dim bg-surface-card p-5">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-medium text-text-secondary">
          Growth Roadmap
        </h3>
        <span className="text-xs text-text-muted">
          {completed}/{total} complete
        </span>
      </div>

      <div className="mb-5">
        <div className="flex items-center justify-between mb-1.5">
          <span className="text-xs text-text-muted">Overall Progress</span>
          <span className="text-xs font-medium text-brain-400">{pct}%</span>
        </div>
        <div className="h-2 rounded-full bg-surface overflow-hidden">
          <div
            className="h-full rounded-full bg-gradient-to-r from-brain-600 to-brain-400 transition-all duration-500"
            style={{ width: `${pct}%` }}
          />
        </div>
      </div>

      <div className="space-y-5">
        {categories.map((category) => {
          const catItems = items.filter((i) => i.category === category);
          const catDone = catItems.filter((i) => i.completed).length;
          return (
            <div key={category}>
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                  {category}
                </span>
                <span className="text-[10px] text-text-muted">
                  {catDone}/{catItems.length}
                </span>
              </div>
              <div className="space-y-1.5">
                {catItems.map((item) => (
                  <div
                    key={item.id}
                    className={`flex items-start gap-2.5 rounded-lg px-2.5 py-2 ${
                      item.completed
                        ? "bg-green-accent/5"
                        : "hover:bg-surface-hover"
                    } transition-colors`}
                  >
                    {item.completed ? (
                      <CheckCircle2 className="w-4 h-4 text-green-accent flex-shrink-0 mt-0.5" />
                    ) : (
                      <Circle className="w-4 h-4 text-text-muted flex-shrink-0 mt-0.5" />
                    )}
                    <span
                      className={`text-sm ${
                        item.completed
                          ? "text-text-muted line-through"
                          : "text-text-primary"
                      }`}
                    >
                      {item.goal}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
