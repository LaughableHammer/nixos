import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

// A light gray elapsed timer above the editor. It starts the moment a prompt is
// accepted and stops at `agent_settled` — the point where retries, compaction
// and queued follow-ups are finished and Pi is no longer working, so the final
// value covers thinking, every tool call and the complete answer.
//
// The last time stays on screen until the next request replaces it.

const WIDGET_KEY = "run-timing";
const TICK_MS = 250;

interface ActiveTimer {
  startMono: number;
  tick: ReturnType<typeof setInterval>;
  ctx: ExtensionContext;
}

let active: ActiveTimer | undefined;
/** Prompt accepted but not yet handed to the agent; used to include preflight work. */
let pendingStart: number | undefined;

function formatElapsed(ms: number): string {
  const seconds = Math.max(0, ms) / 1000;
  if (seconds < 60) return `${seconds.toFixed(1)}s`;
  const totalSeconds = Math.floor(seconds);
  const minutes = Math.floor(totalSeconds / 60);
  const remainder = totalSeconds % 60;
  if (minutes < 60) return `${minutes}m ${String(remainder).padStart(2, "0")}s`;
  return `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2, "0")}m`;
}

function draw(ctx: ExtensionContext, ms: number): void {
  if (!ctx.hasUI) return;
  ctx.ui.setWidget(
    WIDGET_KEY,
    [ctx.ui.theme.fg("muted", `⏱ ${formatElapsed(ms)}`)],
    { placement: "aboveEditor" },
  );
}

function start(ctx: ExtensionContext): void {
  if (active) return;

  const timer: ActiveTimer = {
    startMono: pendingStart ?? performance.now(),
    ctx,
    tick: setInterval(() => {
      if (active) draw(active.ctx, performance.now() - active.startMono);
    }, TICK_MS),
  };
  pendingStart = undefined;
  active = timer;

  draw(ctx, performance.now() - timer.startMono);
}

function stop(ctx: ExtensionContext): void {
  if (!active) return;

  const elapsed = performance.now() - active.startMono;
  clearInterval(active.tick);
  active = undefined;

  // Leave the final time visible until the next request.
  draw(ctx, elapsed);
}

function clear(ctx: ExtensionContext): void {
  if (active) clearInterval(active.tick);
  active = undefined;
  pendingStart = undefined;
  if (ctx.hasUI) ctx.ui.setWidget(WIDGET_KEY, undefined);
}

export default function runTimingExtension(pi: ExtensionAPI): void {
  // Remember when the prompt was accepted so preflight work (prompt expansion,
  // pre-prompt compaction) is included, but only start the visible clock once
  // the prompt is actually handed to the agent — an invalid prompt or an input
  // another extension handles never starts it.
  pi.on("input", async (event) => {
    if (event.streamingBehavior !== undefined) return; // belongs to the active run
    if (active) return;
    pendingStart = performance.now();
  });

  pi.on("before_agent_start", async (_event, ctx) => {
    start(ctx);
  });

  // Fallback for runs that begin without `before_agent_start`.
  pi.on("agent_start", async (_event, ctx) => {
    start(ctx);
  });

  // Retries, overflow recovery, compaction and queued work can follow
  // `agent_end`; settle is the point where Pi is actually done.
  pi.on("agent_settled", async (_event, ctx) => {
    pendingStart = undefined;
    stop(ctx);
  });

  pi.on("session_start", async (_event, ctx) => {
    clear(ctx);
  });

  pi.on("session_shutdown", async () => {
    if (active) clearInterval(active.tick);
    active = undefined;
    pendingStart = undefined;
  });
}
