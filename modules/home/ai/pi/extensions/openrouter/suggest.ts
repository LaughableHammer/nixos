import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { buildRows, MIN_QUANT_BITS, PROVIDER, zdrEndpoints, type Row } from "./endpoints";
import { pinFor } from "./pins";

// Set PI_OR_SUGGEST=0 to skip the per-session "faster, cheaper endpoint" check.
export const SUGGEST_DISABLE_ENV = "PI_OR_SUGGEST";

const CHAT_COMPLETIONS = "https://openrouter.ai/api/v1/chat/completions";

const MAX_PROBES = 3;
const PROBE_TIMEOUT_MS = 10_000;
const PROBE_MAX_TOKENS = 16;

export interface Candidate {
  provider: string;
  tag: string;
  quant: string;
  tps: number;
  cost: number;
  score: number;
}

export interface Suggestion {
  /** The endpoint the current model is pinned to. */
  current: Row;
  candidate: Candidate;
}

/** Tokens per second per dollar; the ranking used to prefer one candidate. */
function scoreOf(row: Row): number {
  return (row.tps ?? 0) / Math.max(row.cost, 1e-9);
}

/**
 * Other ZDR, tool-capable, >= 8-bit endpoints of the same model that are both
 * faster and cheaper than the pinned one. Any improvement counts, so a 1%
 * gain is enough; the best tokens-per-second-per-dollar candidate wins.
 */
function rankedCandidates(current: Row, rows: Row[], model: NonNullable<ExtensionContext["model"]>): Row[] {
  const baselineTps = current.tps;
  if (baselineTps === null) return [];

  // pi sends the model's context window and maxTokens. OpenRouter's own router
  // filters out endpoints below either limit, but `provider.only` overrides
  // that, so a pin there would 400 on the real request while a tiny probe works.
  const fitsContext = (row: Row) =>
    row.context === null ||
    typeof model.contextWindow !== "number" ||
    row.context >= model.contextWindow;
  const fitsOutput = (row: Row) =>
    row.maxCompletion === null ||
    typeof model.maxTokens !== "number" ||
    row.maxCompletion >= model.maxTokens;

  return rows
    .filter((row) => row.tag !== current.tag)
    .filter((row) => row.bits !== null && row.bits >= MIN_QUANT_BITS)
    .filter((row) => row.status === null || row.status === 0)
    .filter(fitsContext)
    .filter(fitsOutput)
    .filter((row) => row.tps !== null && row.tps > baselineTps)
    .filter((row) => row.cost < current.cost)
    .sort((left, right) => scoreOf(right) - scoreOf(left));
}

function normalize(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, "");
}

/**
 * Minimal live completion against one endpoint. `provider.only` plus
 * `allow_fallbacks: false` keeps the request on the tag being tested; the
 * response's `provider` field is checked when OpenRouter reports it.
 */
async function probe(apiKey: string, row: Row, signal: AbortSignal): Promise<boolean> {
  const controller = new AbortController();
  const abort = () => controller.abort();
  const timer = setTimeout(abort, PROBE_TIMEOUT_MS);
  if (signal.aborted) abort();
  else signal.addEventListener("abort", abort, { once: true });

  try {
    const response = await fetch(CHAT_COMPLETIONS, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "X-OpenRouter-Metadata": "enabled",
      },
      body: JSON.stringify({
        model: row.modelId,
        // Mirror pi's request shape: it always sends a system message and tool
        // declarations, and providers can reject either even while advertising
        // tool support.
        messages: [
          { role: "system", content: "You are a connectivity probe. Reply with a single word." },
          { role: "user", content: "ping" },
        ],
        tools: [
          {
            type: "function",
            function: {
              name: "probe_noop",
              description: "Do nothing.",
              parameters: { type: "object", properties: {} },
            },
          },
        ],
        max_tokens: PROBE_MAX_TOKENS,
        stream: false,
        provider: { only: [row.tag], allow_fallbacks: false },
      }),
      signal: controller.signal,
    });
    if (!response.ok) return false;

    const body = (await response.json()) as { choices?: unknown; provider?: unknown };
    if (!Array.isArray(body.choices) || body.choices.length === 0) return false;
    if (typeof body.provider !== "string" || body.provider.length === 0) return true;

    const served = normalize(body.provider);
    const tag = normalize(row.tag.split("/")[0] ?? row.tag);
    const name = normalize(row.provider);
    return [tag, name].some(
      (expected) => expected.length > 0 && (served.includes(expected) || expected.includes(served)),
    );
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
    signal.removeEventListener("abort", abort);
  }
}

function toCandidate(row: Row, tps: number): Candidate {
  return {
    provider: row.provider,
    tag: row.tag,
    quant: row.quant,
    tps,
    cost: row.cost,
    score: scoreOf(row),
  };
}

/**
 * Look for a faster and cheaper endpoint of the current model, verified with a
 * live request. Returns undefined when there is nothing worth prompting about.
 */
export async function maybeSuggest(
  ctx: ExtensionContext,
  signal: AbortSignal,
): Promise<Suggestion | undefined> {
  const model = ctx.model;
  if (!model || model.provider !== PROVIDER) return undefined;

  const pin = pinFor(model.id);
  if (!pin) return undefined;

  const apiKey = await ctx.modelRegistry.getApiKeyForProvider(PROVIDER);
  if (!apiKey) return undefined;

  const endpoints = await zdrEndpoints(apiKey);
  const rows = buildRows(model.id, endpoints);
  const current = rows.find((row) => row.tag === pin.tag);
  if (!current || current.tps === null) return undefined;

  for (const row of rankedCandidates(current, rows, model).slice(0, MAX_PROBES)) {
    if (signal.aborted) return undefined;
    if (!(await probe(apiKey, row, signal))) continue;
    return { current, candidate: toCandidate(row, row.tps as number) };
  }
  return undefined;
}
