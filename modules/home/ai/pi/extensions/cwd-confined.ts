import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const NOTICE = `[CWD CONFINEMENT ACTIVE]
This session is confined to its physical current working directory by Bubblewrap. Host project files outside that directory are unavailable, including paths reached through escaping symlinks. Only narrow read-only runtime resources (the Pi/tool Nix closure, CA certificates, /dev, and /proc) plus memory-backed /tmp are present. Network access remains enabled. This extension adds UI and lexical checks as defense in depth; Bubblewrap is the security boundary.`;

const FILE_TOOLS = new Set([
  "edit",
  "find",
  "grep",
  "ls",
  "read",
  "write",
]);
const PATH_KEYS = ["path", "file", "filename", "src", "dst", "dir"];

function isPathOutsideCwd(cwd: string, target: string): boolean {
  if (target === "~" || target.startsWith("~/")) return true;

  const absolute = target.startsWith("/");
  const parts = target.split(/\/+/);
  const stack = absolute ? [] : cwd.split("/").filter(Boolean);
  const boundaryDepth = cwd.split("/").filter(Boolean).length;

  for (const part of parts) {
    if (!part || part === ".") continue;
    if (part === "..") {
      if (stack.length === 0) return true;
      stack.pop();
    } else {
      stack.push(part);
    }

    if (!absolute && stack.length < boundaryDepth) return true;
  }

  const resolved = `/${stack.join("/")}`;
  return resolved !== cwd && !resolved.startsWith(`${cwd}/`);
}

export default function cwdConfinedExtension(pi: ExtensionAPI): void {
  if (process.env.PI_CWD_CONFINED !== "1") return;

  const cwd = process.cwd().replace(/\/+$/, "") || "/";

  function updateStatus(ctx: ExtensionContext): void {
    ctx.ui.setStatus(
      "cwd-confined",
      ctx.ui.theme.fg("warning", "cwd-confined"),
    );
  }

  pi.on("session_start", async (_event, ctx) => {
    updateStatus(ctx);
  });

  pi.on("session_info_changed", async (_event, ctx) => {
    updateStatus(ctx);
  });

  pi.on("before_agent_start", async () => ({
    message: {
      customType: "cwd-confined-notice",
      content: NOTICE,
      display: false,
    },
  }));

  pi.on("tool_call", async (event) => {
    // Reject extension tools that imply adding another workspace. Bubblewrap
    // would still make an external workspace unavailable.
    if (/^(add[-_])?(dir(ectory)?|workspace)$/.test(event.toolName)) {
      return {
        block: true,
        reason: "Workspace expansion is disabled in cwd-confinement mode.",
      };
    }

    if (!FILE_TOOLS.has(event.toolName)) return;

    const input = event.input as Record<string, unknown>;
    for (const key of PATH_KEYS) {
      const value = input[key];
      if (typeof value === "string" && isPathOutsideCwd(cwd, value)) {
        return {
          block: true,
          reason: `Path '${value}' leaves the confined working directory.`,
        };
      }
    }
  });
}
