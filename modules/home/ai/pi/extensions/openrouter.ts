// https://github.com/stacksparrow4/nix/blob/main/modules/pkgs/pi/extensions/openrouter.ts
import {
  BorderedLoader,
  DynamicBorder,
  getAgentDir,
  type ExtensionAPI,
  type ExtensionContext,
  type Theme,
} from "@earendil-works/pi-coding-agent";
import {
  type Component,
  type Focusable,
  Input,
  type TUI,
  fuzzyFilter,
  getKeybindings,
  truncateToWidth,
  visibleWidth,
} from "@earendil-works/pi-tui";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// OpenRouter requests are pinned to a single ZDR endpoint. There is no
// automatic routing: a model with no pin raises an error telling the user to
// run /or-model, and the picked endpoint is written to a shared save file so
// pins survive restarts. Only the openai-completions transport honours the
// `provider` routing field, so only those models are pinned/blocked.

const PROVIDER = "openrouter";
const ROUTING_API = "openai-completions";

// The ZDR list is exactly the model pages' `!(training || retainsPrompts)` set;
// `zdr`/`data_collection` also make OpenRouter enforce it server-side.
//
// Throughput stats (`throughput_last_30m`) are only returned for authenticated
// requests, so the list is fetched with the resolved OpenRouter API key.
const ZDR_ENDPOINTS = "https://openrouter.ai/api/v1/endpoints/zdr";

const PINS_FILE = "openrouter-pins.json";
const MIN_QUANT_BITS = 8;
const MAX_VISIBLE_ROWS = 14;

// Derived from a 31-call agentic session: 32,350 fresh input and 25,030 output
// tokens, scaled to a 100k-token final context with perfect prompt caching.
const CONTEXT_TOKENS = 100_000;
const EMPIRICAL_INPUT_TOKENS = 32_350;
const EMPIRICAL_OUTPUT_TOKENS = 25_030;
const EMPIRICAL_CALLS = 31;
const GROWTH_PER_CALL = (EMPIRICAL_INPUT_TOKENS + EMPIRICAL_OUTPUT_TOKENS) / EMPIRICAL_CALLS;
const INPUT_SHARE = EMPIRICAL_INPUT_TOKENS / (EMPIRICAL_INPUT_TOKENS + EMPIRICAL_OUTPUT_TOKENS);

type Endpoint = Record<string, any>;

interface Row {
  tag: string;
  provider: string;
  quant: string;
  bits: number | null;
  context: number | null;
  tps: number | null;
  cost: number;
}

interface Pin {
  tag: string;
  provider: string;
  quant: string;
  pinnedAt: number;
}

type PinStore = Record<string, Pin>;

// --- Pin store ------------------------------------------------------------

function pinsPath(): string {
  return join(getAgentDir(), "sessions", PINS_FILE);
}

function loadPins(): PinStore {
  try {
    const parsed = JSON.parse(readFileSync(pinsPath(), "utf8"));
    if (parsed && typeof parsed === "object") return parsed as PinStore;
  } catch {}
  return {};
}

function savePins(store: PinStore): void {
  try {
    writeFileSync(pinsPath(), `${JSON.stringify(store, null, 2)}\n`);
  } catch {
    // Best-effort; a write failure only costs the pin on the next restart.
  }
}

let pins: PinStore = loadPins();

function isRoutingModel(
  model: ExtensionContext["model"],
): model is NonNullable<ExtensionContext["model"]> {
  return !!model && model.provider === PROVIDER && model.api === ROUTING_API;
}

// --- Endpoint data --------------------------------------------------------

// Cached per auth state: an anonymous fetch returns the same list but with every
// throughput field null, so it must never satisfy a later authenticated request.
const zdrCache = new Map<string, Promise<Endpoint[]>>();

function zdrEndpoints(apiKey: string | undefined): Promise<Endpoint[]> {
  const cacheKey = apiKey ? "authenticated" : "anonymous";
  const cached = zdrCache.get(cacheKey);
  if (cached) return cached;

  const request = fetch(ZDR_ENDPOINTS, apiKey ? { headers: { Authorization: `Bearer ${apiKey}` } } : undefined)
    .then((response) => {
      if (!response.ok) throw new Error(`OpenRouter ZDR endpoint list returned ${response.status}`);
      return response.json();
    })
    .then((body) => {
      const data = (body as { data?: unknown }).data;
      if (!Array.isArray(data)) throw new Error("unexpected ZDR endpoint list shape");
      return data as Endpoint[];
    })
    .catch((error) => {
      zdrCache.delete(cacheKey);
      throw error;
    });

  zdrCache.set(cacheKey, request);
  return request;
}

function quantBits(quant: unknown): number | null {
  if (typeof quant !== "string" || quant.length === 0) return null;
  const match = /^(?:fp|bf|int)(\d+)/.exec(quant.toLowerCase());
  return match ? Number(match[1]) : null;
}

/** OpenRouter reports throughput as a `{p50,p75,p90,p99}` object; p50 is the median. */
function throughputP50(value: unknown): number | null {
  const p50 = value && typeof value === "object" ? (value as Record<string, unknown>).p50 : value;
  return typeof p50 === "number" && Number.isFinite(p50) ? p50 : null;
}

function estimatedCost(inputPerM: number, outputPerM: number, cacheReadPerM: number): number {
  const turns = CONTEXT_TOKENS / GROWTH_PER_CALL;
  const cacheTokens = (CONTEXT_TOKENS * (turns - 1)) / 2;
  const inputTokens = INPUT_SHARE * CONTEXT_TOKENS;
  const outputTokens = (1 - INPUT_SHARE) * CONTEXT_TOKENS;
  // Providers that report no cache-read price get no caching discount.
  const cachePrice = cacheReadPerM || inputPerM;
  return (cachePrice * cacheTokens + inputPerM * inputTokens + outputPerM * outputTokens) / 1e6;
}

/**
 * ZDR, tool-capable endpoints for `model`, cheapest first. Quantization is kept
 * on each row so the picker can default to >= 8-bit and toggle the rest with tab.
 */
function buildRows(model: string, endpoints: Endpoint[]): Row[] {
  const rows: Row[] = [];
  for (const endpoint of endpoints) {
    if (endpoint.model_id !== model) continue;

    const params = Array.isArray(endpoint.supported_parameters) ? endpoint.supported_parameters : [];
    if (!params.includes("tools")) continue;

    const tag = typeof endpoint.tag === "string" ? endpoint.tag : "";
    if (!tag) continue;

    const quant = typeof endpoint.quantization === "string" ? endpoint.quantization : "unknown";
    const pricing = (endpoint.pricing ?? {}) as Record<string, unknown>;
    const input = Number(pricing.prompt ?? 0) * 1e6;
    const output = Number(pricing.completion ?? 0) * 1e6;
    const cacheRead = Number(pricing.input_cache_read ?? 0) * 1e6;

    rows.push({
      tag,
      provider: typeof endpoint.provider_name === "string" ? endpoint.provider_name : tag,
      quant: quant.toLowerCase(),
      bits: quantBits(quant),
      context: typeof endpoint.context_length === "number" ? endpoint.context_length : null,
      tps: throughputP50(endpoint.throughput_last_30m),
      cost: estimatedCost(input, output, cacheRead),
    });
  }
  rows.sort((left, right) => left.cost - right.cost);
  return rows;
}

// --- Formatting -----------------------------------------------------------

function formatTokens(tokens: number | null): string {
  if (!tokens) return "?";
  if (tokens >= 1_000_000) return `${Number((tokens / 1_000_000).toFixed(1))}M`;
  if (tokens >= 1_000) return `${Math.round(tokens / 1_000)}K`;
  return String(tokens);
}

function formatCost(cost: number): string {
  if (cost === 0) return "$0";
  if (cost < 0.01) return `$${cost.toFixed(4)}`;
  return `$${cost.toFixed(cost < 1 ? 3 : 2)}`;
}

function formatTps(tps: number | null): string {
  return tps === null ? "?" : String(Math.round(tps));
}

// --- Picker ---------------------------------------------------------------

class ProviderPicker implements Component, Focusable {
  private readonly input = new Input();
  private readonly border: DynamicBorder;
  private readonly all: Row[];
  private readonly currentTag: string | undefined;
  private visible: Row[] = [];
  private selected = 0;
  private showAll = false;
  private isFocused = false;

  get focused(): boolean {
    return this.isFocused;
  }

  set focused(value: boolean) {
    this.isFocused = value;
    this.input.focused = value;
  }

  constructor(
    private readonly model: string,
    rows: Row[],
    currentTag: string | undefined,
    private readonly tui: TUI,
    private readonly theme: Theme,
    private readonly done: (tag: string | undefined) => void,
  ) {
    this.border = new DynamicBorder((text) => theme.fg("border", text));
    this.all = rows;
    this.currentTag = currentTag;
    this.refreshVisible();
  }

  /** Rows after the >= 8-bit filter (unless tab showed everything) and the search query. */
  private refreshVisible(): void {
    const base = this.showAll
      ? this.all
      : this.all.filter((row) => row.bits !== null && row.bits >= MIN_QUANT_BITS);
    const query = this.input.getValue().trim();
    this.visible = query ? fuzzyFilter(base, query, (row) => `${row.provider} ${row.quant} ${row.tag}`) : base;

    const pinned = this.visible.findIndex((row) => row.tag === this.currentTag);
    if (pinned >= 0) this.selected = pinned;
    else this.selected = Math.min(Math.max(this.selected, 0), Math.max(0, this.visible.length - 1));
  }

  handleInput(data: string): void {
    const keybindings = getKeybindings();
    if (keybindings.matches(data, "tui.input.tab")) {
      this.showAll = !this.showAll;
      this.refreshVisible();
    } else if (keybindings.matches(data, "tui.select.up")) {
      if (this.visible.length) this.selected = (this.selected - 1 + this.visible.length) % this.visible.length;
    } else if (keybindings.matches(data, "tui.select.down")) {
      if (this.visible.length) this.selected = (this.selected + 1) % this.visible.length;
    } else if (keybindings.matches(data, "tui.select.confirm")) {
      this.done(this.visible[this.selected]?.tag);
    } else if (keybindings.matches(data, "tui.select.cancel")) {
      this.done(undefined);
    } else {
      const before = this.input.getValue();
      this.input.handleInput(data);
      if (this.input.getValue() !== before) this.refreshVisible();
    }
    this.tui.requestRender();
  }

  render(width: number): string[] {
    const theme = this.theme;
    const header = ["provider", "quant", "context", "tps p50", "est. cost"];
    const lines = [...this.border.render(width)];
    lines.push(theme.fg("accent", theme.bold(`OpenRouter endpoints — ${this.model}`)));
    lines.push(
      theme.fg(
        "muted",
        this.showAll
          ? "all ZDR · tool-capable · cheapest first"
          : "ZDR · ≥ 8-bit · tool-capable · cheapest first",
      ),
    );
    lines.push("");
    lines.push(...this.input.render(width));
    lines.push("");

    if (this.visible.length === 0) {
      const hint =
        !this.showAll && this.all.length > 0
          ? "  no ≥ 8-bit endpoints — press tab to show all quants"
          : "  no matching endpoints";
      lines.push(theme.fg("muted", hint));
    } else {
      const start = Math.max(
        0,
        Math.min(this.selected - Math.floor(MAX_VISIBLE_ROWS / 2), this.visible.length - MAX_VISIBLE_ROWS),
      );
      const end = Math.min(start + MAX_VISIBLE_ROWS, this.visible.length);
      const cells = this.visible.map((row) => [
        row.provider,
        row.quant,
        formatTokens(row.context),
        formatTps(row.tps),
        formatCost(row.cost),
      ]);
      const widths = header.map((title, index) =>
        Math.max(visibleWidth(title), ...cells.map((row) => visibleWidth(row[index] ?? ""))),
      );
      const format = (row: string[]) =>
        row.map((cell, index) => (index === row.length - 1 ? cell : cell.padEnd(widths[index]))).join("  ");

      lines.push(`  ${theme.fg("muted", format(header))}`);
      for (let index = start; index < end; index++) {
        const isSelected = index === this.selected;
        const isPinned = this.visible[index].tag === this.currentTag;
        const text = format(cells[index]);
        const cursor = isSelected ? theme.fg("accent", "→ ") : "  ";
        const marker = isPinned ? theme.fg("success", "✓ ") : "  ";
        lines.push(`${cursor}${marker}${isSelected ? theme.fg("accent", text) : text}`);
      }
      if (start > 0 || end < this.visible.length) {
        lines.push(theme.fg("dim", `  (${this.selected + 1}/${this.visible.length})`));
      }
    }

    lines.push("");
    lines.push(theme.fg("dim", "tab all quants · type to filter · ↑↓ move · enter pin · esc cancel"));
    lines.push(...this.border.render(width));
    return lines.map((line) => truncateToWidth(line, width));
  }

  invalidate(): void {
    this.input.invalidate();
    this.border.invalidate();
  }
}

/** Run a request behind a cancellable spinner. Resolves undefined when cancelled or failed. */
async function load<T>(
  ctx: ExtensionContext,
  message: string,
  task: (signal: AbortSignal) => Promise<T>,
): Promise<T | undefined> {
  let failure: unknown;
  const result = await ctx.ui.custom<T | undefined>((tui, theme, _keybindings, done) => {
    let settled = false;
    const finish = (value: T | undefined) => {
      if (settled) return;
      settled = true;
      done(value);
    };
    const loader = new BorderedLoader(tui, theme, message);
    loader.onAbort = () => finish(undefined);
    task(loader.signal).then(finish, (error: unknown) => {
      failure = error;
      finish(undefined);
    });
    return loader;
  });
  if (failure && !(failure instanceof Error && failure.name === "AbortError")) {
    ctx.ui.notify(`OpenRouter: ${failure instanceof Error ? failure.message : String(failure)}`, "error");
  }
  return result;
}

// --- Status / warnings ----------------------------------------------------

function refreshStatus(ctx: ExtensionContext): void {
  if (!ctx.hasUI) return;
  const model = ctx.model;
  if (!model || model.provider !== PROVIDER) {
    ctx.ui.setStatus("openrouter", undefined);
    return;
  }
  const pin = pins[model.id];
  if (pin) {
    ctx.ui.setStatus("openrouter", `or: ${pin.provider} ${pin.quant}`);
  } else {
    ctx.ui.setStatus("openrouter", isRoutingModel(model) ? "or: unpinned" : undefined);
  }
}

/** Routing-capable OpenRouter models cannot be used until a provider is pinned. */
function warnIfUnpinned(ctx: ExtensionContext): void {
  const model = ctx.model;
  if (!isRoutingModel(model) || pins[model.id]) return;
  if (ctx.hasUI) ctx.ui.notify(`No OpenRouter provider pinned for ${model.id}. Run /or-model to pin one.`, "error");
}

// --- Extension ------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    pins = loadPins();
    refreshStatus(ctx);
    warnIfUnpinned(ctx);
  });

  pi.on("model_select", (_event, ctx) => {
    refreshStatus(ctx);
    warnIfUnpinned(ctx);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    if (ctx.hasUI) ctx.ui.setStatus("openrouter", undefined);
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
          new ProviderPicker(model.id, rows, pins[model.id]?.tag, tui, theme, done),
      );
      if (!tag) return;

      const row = rows.find((candidate) => candidate.tag === tag);
      if (!row) return;

      pins[model.id] = { tag: row.tag, provider: row.provider, quant: row.quant, pinnedAt: Date.now() };
      savePins(pins);
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

    const pin = pins[model.id];
    if (!pin) {
      throw new Error(`No OpenRouter provider pinned for ${model.id}. Run /or-model to pin an endpoint.`);
    }

    const payload = event.payload as { provider?: Record<string, unknown> } | null;
    if (!payload || typeof payload !== "object") return;
    payload.provider = { only: [pin.tag], allow_fallbacks: false };
    return payload;
  });
}