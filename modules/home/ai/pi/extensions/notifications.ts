import { spawn } from "node:child_process";
import { basename } from "node:path";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

// Desktop notifications for long-running Pi sessions. `agent_settled` fires
// only once Pi has stopped retrying/compacting and has no queued follow-ups,
// so a single notification means "your turn". `ui_prompt_start` covers
// extension dialogs such as plan approval, which block until the user answers.

const SUMMARY_LIMIT = 180;
const APP_NAME = "Pi";

let enabled = process.env.PI_NOTIFICATIONS !== "0";

function notificationsAvailable(): boolean {
  return enabled;
}

function notify(
  title: string,
  body: string,
  urgency: "low" | "normal" | "critical" = "normal",
): void {
  if (!notificationsAvailable()) return;

  const child = spawn(
    "notify-send",
    [
      `--app-name=${APP_NAME}`,
      `--urgency=${urgency}`,
      "--icon=utilities-terminal",
      title,
      body,
    ],
    { detached: true, stdio: "ignore" },
  );
  child.on("error", () => {
    // No notify-send or no session bus: notifications are best-effort.
  });
  child.unref();
}

function truncate(text: string): string {
  const compact = text.replace(/\s+/g, " ").trim();
  if (compact.length <= SUMMARY_LIMIT) return compact;
  return `${compact.slice(0, SUMMARY_LIMIT - 1)}…`;
}

function lastAssistantText(ctx: ExtensionContext): string | undefined {
  const entries = ctx.sessionManager.getEntries();
  for (let index = entries.length - 1; index >= 0; index--) {
    const entry = entries[index] as {
      type?: string;
      message?: { role?: string; content?: unknown };
    };
    if (entry.type !== "message" || entry.message?.role !== "assistant") {
      continue;
    }

    const content = entry.message.content;
    if (!Array.isArray(content)) continue;

    const text = content
      .filter(
        (block): block is { type: "text"; text: string } =>
          typeof block === "object" &&
          block !== null &&
          (block as { type?: unknown }).type === "text" &&
          typeof (block as { text?: unknown }).text === "string",
      )
      .map((block) => block.text)
      .join(" ");

    return text.trim() ? truncate(text) : undefined;
  }
  return undefined;
}

export default function notificationsExtension(pi: ExtensionAPI): void {
  pi.registerCommand("notify", {
    description: "Toggle Pi desktop notifications (on, off, or status)",
    handler: async (rawArgs, ctx) => {
      const action = rawArgs.trim().toLowerCase();
      if (action === "on") enabled = true;
      else if (action === "off") enabled = false;
      else if (action && action !== "status") {
        ctx.ui.notify("Usage: /notify [on|off|status]", "warning");
        return;
      }

      ctx.ui.notify(
        `Pi notifications ${enabled ? "enabled" : "disabled"}.`,
        "info",
      );
    },
  });

  pi.on("agent_settled", async (_event, ctx) => {
    if (!ctx.hasUI || !ctx.isIdle() || !notificationsAvailable()) return;

    const summary = lastAssistantText(ctx);
    const where = basename(ctx.cwd) || ctx.cwd;
    notify(
      "Pi is waiting",
      summary ? `${where}: ${summary}` : `Finished in ${where}`,
    );
  });

  pi.on("ui_prompt_start", async (event, ctx) => {
    if (!ctx.hasUI || !notificationsAvailable()) return;

    const title = event.title?.trim() || "Input required";
    notify("Pi needs your input", `${title} (${event.kind})`, "critical");
  });
}
