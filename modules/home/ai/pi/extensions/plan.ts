import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const READ_ONLY_TOOLS = ["read", "grep", "find", "ls"];
const CONTEXT_TYPE = "approval-plan-context";
const STATE_TYPE = "approval-plan-state";

interface PlanState {
  planning: boolean;
  toolsBeforePlanning?: string[];
}

const PLAN_INSTRUCTIONS = `[PLAN MODE ACTIVE]
You must propose a solution before any implementation takes place.

Rules:
- Work in read-only mode. Do not modify files, run mutating commands, or implement the solution.
- Inspect the repository with the available read-only tools when useful.
- Do not stop to ask clarifying questions. Make reasonable assumptions, list them, and still produce a plan.
- Give a concrete proposed solution with a numbered implementation plan.
- Include likely files/components, validation or tests, and important risks or trade-offs.
- Do not ask whether to implement the plan and do not begin implementation.
- Do not ask a closing approval question. The extension will present implementation and revision choices after your response.`;

export default function planExtension(pi: ExtensionAPI): void {
  let planning = false;
  let toolsBeforePlanning: string[] | undefined;

  function persist(): void {
    pi.appendEntry(STATE_TYPE, {
      planning,
      toolsBeforePlanning,
    } satisfies PlanState);
  }

  function updateStatus(ctx: ExtensionContext): void {
    ctx.ui.setStatus(
      "approval-plan",
      planning ? ctx.ui.theme.fg("warning", "plan: read-only") : undefined,
    );
  }

  function enterPlanMode(ctx: ExtensionContext): void {
    if (!planning) {
      toolsBeforePlanning = pi.getActiveTools();
    }
    planning = true;
    // Deliberately exclude bash and unknown extension tools: their side effects
    // cannot be reliably classified. Pi's built-in inspection tools are enough
    // to research the repository before proposing a plan.
    pi.setActiveTools(READ_ONLY_TOOLS);
    updateStatus(ctx);
    persist();
  }

  function leavePlanMode(ctx: ExtensionContext): void {
    planning = false;
    if (toolsBeforePlanning) {
      pi.setActiveTools(toolsBeforePlanning);
    }
    toolsBeforePlanning = undefined;
    updateStatus(ctx);
    persist();
  }

  function requestImplementation(ctx: ExtensionContext): void {
    leavePlanMode(ctx);
    pi.sendUserMessage(
      "The proposed plan is approved. Implement it now, validating each change as described.",
      { deliverAs: "followUp" },
    );
  }

  pi.registerCommand("plan", {
    description:
      "Propose a read-only solution, then ask whether to implement or revise it",
    handler: async (rawArgs, ctx) => {
      const args = rawArgs.trim();
      const [action = "", ...rest] = args.split(/\s+/);
      const normalizedAction = action.toLowerCase();

      if (!args) {
        if (planning) {
          leavePlanMode(ctx);
          ctx.ui.notify("Plan mode disabled; previous tools restored.", "info");
        } else {
          enterPlanMode(ctx);
          ctx.ui.notify(
            "Plan mode enabled. Enter the problem to receive a read-only proposal.",
            "info",
          );
        }
        return;
      }

      if (normalizedAction === "off" || normalizedAction === "cancel") {
        leavePlanMode(ctx);
        ctx.ui.notify("Plan mode cancelled; previous tools restored.", "info");
        return;
      }

      if (normalizedAction === "implement" || normalizedAction === "execute") {
        if (!planning) {
          ctx.ui.notify("There is no active plan to implement.", "warning");
          return;
        }
        requestImplementation(ctx);
        return;
      }

      if (normalizedAction === "revise" || normalizedAction === "refine") {
        if (!planning) enterPlanMode(ctx);
        const feedback = rest.join(" ").trim();
        if (!feedback) {
          ctx.ui.notify("Usage: /plan revise <requested changes>", "info");
          return;
        }
        pi.sendUserMessage(
          `Revise the proposed plan using this feedback:\n\n${feedback}`,
        );
        return;
      }

      enterPlanMode(ctx);
      pi.sendUserMessage(
        `Create an implementation plan for this request:\n\n${args}`,
      );
    },
  });

  // Add the planning contract to every model turn while plan mode is active.
  pi.on("before_agent_start", async () => {
    if (!planning) return;
    return {
      message: {
        customType: CONTEXT_TYPE,
        content: PLAN_INSTRUCTIONS,
        display: false,
      },
    };
  });

  // Defense in depth: block mutating built-ins even if another extension changes
  // the active tool set while a plan is being prepared.
  pi.on("tool_call", async (event) => {
    if (!planning) return;
    if (!READ_ONLY_TOOLS.includes(event.toolName)) {
      return {
        block: true,
        reason: `Plan mode is read-only; '${event.toolName}' is unavailable until the plan is approved.`,
      };
    }
  });

  // Planning instructions should not influence implementation after approval.
  pi.on("context", async (event) => {
    if (planning) return;
    return {
      messages: event.messages.filter(
        (message) =>
          (message as AgentMessage & { customType?: string }).customType !==
          CONTEXT_TYPE,
      ),
    };
  });

  // The model only proposes the solution. Pi itself owns the approval prompt,
  // so model wording cannot accidentally skip this gate.
  pi.on("agent_end", async (_event, ctx) => {
    if (!planning || !ctx.hasUI) return;

    const choice = await ctx.ui.select(
      "Plan ready — what should happen next?",
      [
        "Implement this plan",
        "Revise the plan",
        "Keep planning mode active",
        "Cancel plan mode",
      ],
    );

    if (choice === "Implement this plan") {
      requestImplementation(ctx);
    } else if (choice === "Revise the plan") {
      const feedback = await ctx.ui.editor("How should the plan change?", "");
      if (feedback?.trim()) {
        pi.sendUserMessage(
          `Revise the proposed plan using this feedback:\n\n${feedback.trim()}`,
          { deliverAs: "followUp" },
        );
      }
    } else if (choice === "Cancel plan mode") {
      leavePlanMode(ctx);
      ctx.ui.notify("Plan mode cancelled; no changes were made.", "info");
    }
  });

  pi.on("session_start", async (_event, ctx) => {
    const latestState = ctx.sessionManager
      .getEntries()
      .filter(
        (entry: { type: string; customType?: string }) =>
          entry.type === "custom" && entry.customType === STATE_TYPE,
      )
      .pop() as { data?: PlanState } | undefined;

    if (latestState?.data?.planning) {
      planning = true;
      toolsBeforePlanning =
        latestState.data.toolsBeforePlanning ?? pi.getActiveTools();
      pi.setActiveTools(READ_ONLY_TOOLS);
    }
    updateStatus(ctx);
  });
}
