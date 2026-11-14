// https://github.com/stacksparrow4/nix/blob/main/modules/pkgs/pi/extensions/openrouter.ts
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  buildRows,
  formatCost,
  formatTps,
  isRoutingModel,
  PROVIDER,
  ROUTING_API,
  zdrEndpoints,
} from "./endpoints";
import { load, ProviderPicker } from "./picker";
import { pinFor, reloadPins, setPin, type Pin } from "./pins";
import { maybeSuggest, SUGGEST_DISABLE_ENV } from "./suggest";

// OpenRouter requests are pinned to a single ZDR endpoint. There is no
// automatic routing: a model with no pin raises an error telling the user to
// run /or-model, and the picked endpoint is written to a shared save file so
// pins survive restarts. Only the openai-completions transport honours the
// `provider` routing field, so only those models are pinned/blocked.
//
// Once per session, the first user message that runs on a pinned OpenRouter
// model also gets a one-shot offer to switch that model to a different endpoint
// of the same model when it is both faster and cheaper (see ./suggest.ts).
// Declining keeps the current pin and suppresses the offer until the next Pi
// session.

/** One check per Pi session; reset on session start, never persisted. */
let checkedThisSession = false;

/** The pin a suggestion replaced, kept until the next provider response is seen. */
let pendingRevert: { modelId: string; previous: Pin; attempted: Pin } | undefined;

// --- Status / warnings ----------------------------------------------------

function refreshStatus(ctx: ExtensionContext): void {
  if (!ctx.hasUI) return;
  const model = ctx.model;
  if (!model || model.provider !== PROVIDER) {
    ctx.ui.setStatus("openrouter", undefined);
    return;
  }
  const pin = pinFor(model.id);
  if (pin) {
    ctx.ui.setStatus("openrouter", `or: ${pin.provider} ${pin.quant}`);
  } else {
    ctx.ui.setStatus("openrouter", isRoutingModel(model) ? "or: unpinned" : undefined);
  }
}

/** Routing-capable OpenRouter models cannot be used until a provider is pinned. */
function warnIfUnpinned(ctx: ExtensionContext): void {
  const model = ctx.model;
  if (!isRoutingModel(model) || pinFor(model.id)) return;
  if (ctx.hasUI) ctx.ui.notify(`No OpenRouter provider pinned for ${model.id}. Run /or-model to pin one.`, "error");
}

// --- Suggest a faster, cheaper endpoint ------------------------------------

/**
 * Runs before the agent loop, after the prompt is submitted, so the new pin
 * applies to the very first provider request of the session.
 */
async function offerSwitch(ctx: ExtensionContext, modelId: string): Promise<void> {
  const suggestion = await load(
    ctx,
    `Looking for a faster, cheaper endpoint for ${modelId}…`,
    (signal) => maybeSuggest(ctx, signal),
    { silent: true },
  );
  if (!suggestion) return;

  const { current, candidate } = suggestion;
  const title = `Switch ${modelId} to ${candidate.provider} (${formatTps(candidate.tps)} tps, ${formatCost(candidate.cost)} est.)?`;
  const body = [
    `pinned: ${current.provider} · ${current.quant}`,
    `  ${formatTps(current.tps)} tps · ${formatCost(current.cost)} estimated`,
    "",
    `faster & cheaper: ${candidate.provider} · ${candidate.quant}`,
    `  ${formatTps(candidate.tps)} tps · ${formatCost(candidate.cost)} estimated`,
    "",
    "Re-pin this model?",
  ].join("\n");

  if (!(await ctx.ui.confirm(title, body))) return;

  const previous = pinFor(modelId);
  const attempted: Pin = {
    tag: candidate.tag,
    provider: candidate.provider,
    quant: candidate.quant,
    pinnedAt: Date.now(),
  };
  setPin(modelId, attempted);
  if (previous) pendingRevert = { modelId, previous, attempted };

  ctx.ui.notify(`${modelId} → ${candidate.provider} (${candidate.quant})`, "info");
  refreshStatus(ctx);
}

// --- Extension ------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    checkedThisSession = false;
    reloadPins();
    refreshStatus(ctx);
    warnIfUnpinned(ctx);
  });

  pi.on("model_select", (_event, ctx) => {
    refreshStatus(ctx);
    warnIfUnpinned(ctx);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    checkedThisSession = false;
    pendingRevert = undefined;
    if (ctx.hasUI) ctx.ui.setStatus("openrouter", undefined);
  });

  // The probe can pass while the real payload still fails (for example a
  // provider that cannot serve the model's maxTokens or tool schema). Restore
  // the previous pin on the first failing response so the next message works.
  pi.on("after_provider_response", (event, ctx) => {
    const pending = pendingRevert;
    if (!pending) return;
    if (event.status < 400) {
      pendingRevert = undefined;
      return;
    }
    if (event.status === 429) return; // rate limited: keep the pin, Pi retries

    pendingRevert = undefined;
    // Ignore responses for a different model, and let a manual /or-model in the
    // meantime win over the revert.
    if (ctx.model?.id !== pending.modelId) return;
    if (pinFor(pending.modelId)?.tag !== pending.attempted.tag) return;

    setPin(pending.modelId, pending.previous);
    ctx.ui.notify(
      `OpenRouter: ${pending.attempted.provider} failed with ${event.status}; reverted the pin to ${pending.previous.provider} (${pending.previous.quant}).`,
      "error",
    );
    refreshStatus(ctx);
  });

  pi.on("before_agent_start", async (event, ctx) => {
    // Versions before the messageType union only fire for user prompts.
    if (event.messageType && event.messageType !== "user") return;
    if (checkedThisSession) return;
    if (process.env[SUGGEST_DISABLE_ENV] === "0") return;
    if (!ctx.hasUI || ctx.mode !== "tui") return;

    const model = ctx.model;
    if (!isRoutingModel(model) || !pinFor(model.id)) return;

    // Claim the check before awaiting so a queued run cannot prompt twice.
    checkedThisSession = true;
    await offerSwitch(ctx, model.id);
  });

  pi.registerCommand("or-model", {
    description: "Pin the OpenRouter endpoint used for the current model",
    handler: async (_args, ctx) => {
      const model = ctx.model;
      if (!model || model.provider !== PROVIDER) {
        ctx.ui.notify("/or-model: select an OpenRouter model first.", "error");
        return;
      }
      if (model.api !== ROUTING_API) {
        ctx.ui.notify(`${model.id} uses ${model.api}, which ignores OpenRouter provider routing.`, "error");
        return;
      }
      if (ctx.mode !== "tui") {
        ctx.ui.notify("/or-model needs the interactive terminal UI.", "error");
        return;
      }

      const endpoints = await load(ctx, `Fetching ZDR endpoints for ${model.id}…`, async () => {
        // The key unlocks per-endpoint throughput stats in the same response.
        const apiKey = await ctx.modelRegistry.getApiKeyForProvider(PROVIDER);
        return zdrEndpoints(apiKey);
      });
      if (!endpoints) return;

      const rows = buildRows(model.id, endpoints);
      if (rows.length === 0) {
        ctx.ui.notify(`No ZDR, tool-capable endpoints for ${model.id}.`, "warning");
        return;
      }

      const tag = await ctx.ui.custom<string | undefined>(
        (tui, theme, _keybindings, done) =>
          new ProviderPicker(model.id, rows, pinFor(model.id)?.tag, tui, theme, done),
      );
      if (!tag) return;

      const row = rows.find((candidate) => candidate.tag === tag);
      if (!row) return;

      setPin(model.id, { tag: row.tag, provider: row.provider, quant: row.quant, pinnedAt: Date.now() });
      ctx.ui.notify(`${model.id} → ${row.provider} (${row.quant})`, "info");
      refreshStatus(ctx);
    },
  });

  pi.on("before_provider_headers", (event, ctx) => {
    if (ctx.model?.provider !== PROVIDER) return;
    event.headers["x-openrouter-metadata"] = "enabled";
  });

  pi.on("before_provider_request", (event, ctx) => {
    const model = ctx.model;
    if (!isRoutingModel(model)) return;

    const pin = pinFor(model.id);
    if (!pin) {
      throw new Error(`No OpenRouter provider pinned for ${model.id}. Run /or-model to pin an endpoint.`);
    }

    const payload = event.payload as { provider?: Record<string, unknown> } | null;
    if (!payload || typeof payload !== "object") return;
    payload.provider = { only: [pin.tag], allow_fallbacks: false };
    return payload;
  });
}
