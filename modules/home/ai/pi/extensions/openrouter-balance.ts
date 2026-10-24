import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

// Shows the OpenRouter balance in Pi's footer while an OpenRouter model is
// active. A key with an explicit `limit` reports its own remaining allowance;
// unlimited keys fall back to the account's remaining credits
// (`total_credits - total_usage`).

const PROVIDER = "openrouter";
const KEY_API = "https://openrouter.ai/api/v1/key";
const CREDITS_API = "https://openrouter.ai/api/v1/credits";
const CACHE_MS = 60_000;
const STATUS_KEY = "openrouter-balance";

interface Balance {
  remaining: number;
  /** "key" for a per-key limit, "credits" for the account balance. */
  source: "key" | "credits";
}

let cached: { at: number; balance: Balance } | undefined;
let pending: Promise<Balance | undefined> | undefined;

function isOpenRouter(model: ExtensionContext["model"]): boolean {
  return model?.provider === PROVIDER;
}

async function getJson(url: string, apiKey: string): Promise<any> {
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });
  if (!response.ok) {
    throw new Error(`OpenRouter ${new URL(url).pathname} returned ${response.status}`);
  }
  return response.json();
}

async function fetchBalance(ctx: ExtensionContext): Promise<Balance | undefined> {
  const apiKey = await ctx.modelRegistry.getApiKeyForProvider(PROVIDER);
  if (!apiKey) return undefined;

  const key = await getJson(KEY_API, apiKey);
  const keyData = key?.data ?? {};
  const limit = typeof keyData.limit === "number" ? keyData.limit : null;
  const usage = typeof keyData.usage === "number" ? keyData.usage : 0;
  if (limit !== null) {
    return { remaining: limit - usage, source: "key" };
  }

  const credits = await getJson(CREDITS_API, apiKey);
  const creditData = credits?.data ?? {};
  const total = typeof creditData.total_credits === "number" ? creditData.total_credits : 0;
  const used = typeof creditData.total_usage === "number" ? creditData.total_usage : 0;
  return { remaining: total - used, source: "credits" };
}

/** Cached lookup; dedupes concurrent refreshes so footer updates stay cheap. */
async function balance(ctx: ExtensionContext, force = false): Promise<Balance | undefined> {
  if (!force && cached && Date.now() - cached.at < CACHE_MS) {
    return cached.balance;
  }
  if (pending) return pending;

  pending = fetchBalance(ctx)
    .then((value) => {
      if (value) cached = { at: Date.now(), balance: value };
      return value;
    })
    .catch(() => undefined)
    .finally(() => {
      pending = undefined;
    });
  return pending;
}

function formatMoney(amount: number): string {
  if (amount < 0) return `-$${Math.abs(amount).toFixed(2)}`;
  if (amount < 0.01) return `$${amount.toFixed(3)}`;
  return `$${amount.toFixed(2)}`;
}

/** Human-readable line used by /or-balance; footer uses the compact form. */
function describe(balance: Balance): string {
  const what = balance.source === "key" ? "key limit remaining" : "credits remaining";
  return `${formatMoney(balance.remaining)} ${what}`;
}

async function refresh(ctx: ExtensionContext, force = false): Promise<void> {
  if (!ctx.hasUI) return;
  if (!isOpenRouter(ctx.model)) {
    ctx.ui.setStatus(STATUS_KEY, undefined);
    return;
  }

  // Keep the last known value when a refresh fails.
  const value = (await balance(ctx, force)) ?? cached?.balance;
  if (!isOpenRouter(ctx.model)) {
    ctx.ui.setStatus(STATUS_KEY, undefined);
    return;
  }
  if (!value) {
    ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("muted", "or: ?"));
    return;
  }

  const color = value.remaining <= 0 ? "error" : value.remaining < 1 ? "warning" : "success";
  ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg(color, `or: ${formatMoney(value.remaining)}`));
}

export default function openrouterBalanceExtension(pi: ExtensionAPI): void {
  pi.on("session_start", (_event, ctx) => {
    void refresh(ctx);
  });

  pi.on("model_select", (_event, ctx) => {
    void refresh(ctx);
  });

  // Refresh after a run so spending is reflected without polling.
  pi.on("agent_settled", (_event, ctx) => {
    void refresh(ctx, true);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
  });

  pi.registerCommand("or-balance", {
    description: "Show the remaining OpenRouter key balance or account credits",
    handler: async (_args, ctx) => {
      if (!isOpenRouter(ctx.model)) {
        ctx.ui.notify("/or-balance: select an OpenRouter model first.", "error");
        return;
      }
      const value = await balance(ctx, true);
      if (!value) {
        ctx.ui.notify("Could not fetch the OpenRouter balance.", "error");
        return;
      }
      ctx.ui.notify(describe(value), "info");
      await refresh(ctx);
    },
  });
}
