import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

export const PROVIDER = "openrouter";
export const ROUTING_API = "openai-completions";

// The ZDR list is exactly the model pages' `!(training || retainsPrompts)` set;
// `zdr`/`data_collection` also make OpenRouter enforce it server-side.
//
// Throughput stats (`throughput_last_30m`) are only returned for authenticated
// requests, so the list is fetched with the resolved OpenRouter API key.
const ZDR_ENDPOINTS = "https://openrouter.ai/api/v1/endpoints/zdr";

export const MIN_QUANT_BITS = 8;

// Derived from a 31-call agentic session: 32,350 fresh input and 25,030 output
// tokens, scaled to a 100k-token final context with perfect prompt caching.
const CONTEXT_TOKENS = 100_000;
const EMPIRICAL_INPUT_TOKENS = 32_350;
const EMPIRICAL_OUTPUT_TOKENS = 25_030;
const EMPIRICAL_CALLS = 31;
const GROWTH_PER_CALL = (EMPIRICAL_INPUT_TOKENS + EMPIRICAL_OUTPUT_TOKENS) / EMPIRICAL_CALLS;
const INPUT_SHARE = EMPIRICAL_INPUT_TOKENS / (EMPIRICAL_INPUT_TOKENS + EMPIRICAL_OUTPUT_TOKENS);

export type Endpoint = Record<string, any>;

export interface Row {
  modelId: string;
  modelName: string;
  tag: string;
  provider: string;
  quant: string;
  bits: number | null;
  context: number | null;
  /** Advertised output limit; pi sends the model's maxTokens, so it must fit. */
  maxCompletion: number | null;
  tps: number | null;
  cost: number;
  /** OpenRouter endpoint status: 0 is operational, null when unreported. */
  status: number | null;
}

// --- Endpoint data --------------------------------------------------------

// Cached per auth state: an anonymous fetch returns the same list but with every
// throughput field null, so it must never satisfy a later authenticated request.
const zdrCache = new Map<string, Promise<Endpoint[]>>();

export function zdrEndpoints(apiKey: string | undefined): Promise<Endpoint[]> {
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

export function quantBits(quant: unknown): number | null {
  if (typeof quant !== "string" || quant.length === 0) return null;
  const match = /^(?:fp|bf|int)(\d+)/.exec(quant.toLowerCase());
  return match ? Number(match[1]) : null;
}

/** OpenRouter reports throughput as a `{p50,p75,p90,p99}` object; p50 is the median. */
export function throughputP50(value: unknown): number | null {
  const p50 = value && typeof value === "object" ? (value as Record<string, unknown>).p50 : value;
  return typeof p50 === "number" && Number.isFinite(p50) ? p50 : null;
}

export function estimatedCost(inputPerM: number, outputPerM: number, cacheReadPerM: number): number {
  const turns = CONTEXT_TOKENS / GROWTH_PER_CALL;
  const cacheTokens = (CONTEXT_TOKENS * (turns - 1)) / 2;
  const inputTokens = INPUT_SHARE * CONTEXT_TOKENS;
  const outputTokens = (1 - INPUT_SHARE) * CONTEXT_TOKENS;
  // Providers that report no cache-read price get no caching discount.
  const cachePrice = cacheReadPerM || inputPerM;
  return (cachePrice * cacheTokens + inputPerM * inputTokens + outputPerM * outputTokens) / 1e6;
}

/** One row for a ZDR, tool-capable endpoint; null when the endpoint is not usable. */
function rowFromEndpoint(endpoint: Endpoint): Row | null {
  const params = Array.isArray(endpoint.supported_parameters) ? endpoint.supported_parameters : [];
  if (!params.includes("tools")) return null;

  const tag = typeof endpoint.tag === "string" ? endpoint.tag : "";
  if (!tag) return null;

  const modelId = typeof endpoint.model_id === "string" ? endpoint.model_id : "";
  if (!modelId) return null;

  const quant = typeof endpoint.quantization === "string" ? endpoint.quantization : "unknown";
  const pricing = (endpoint.pricing ?? {}) as Record<string, unknown>;
  const input = Number(pricing.prompt ?? 0) * 1e6;
  const output = Number(pricing.completion ?? 0) * 1e6;
  const cacheRead = Number(pricing.input_cache_read ?? 0) * 1e6;

  return {
    modelId,
    modelName: typeof endpoint.model_name === "string" ? endpoint.model_name : modelId,
    tag,
    provider: typeof endpoint.provider_name === "string" ? endpoint.provider_name : tag,
    quant: quant.toLowerCase(),
    bits: quantBits(quant),
    context: typeof endpoint.context_length === "number" ? endpoint.context_length : null,
    maxCompletion:
      typeof endpoint.max_completion_tokens === "number" ? endpoint.max_completion_tokens : null,
    tps: throughputP50(endpoint.throughput_last_30m),
    cost: estimatedCost(input, output, cacheRead),
    status: typeof endpoint.status === "number" ? endpoint.status : null,
  };
}

/**
 * ZDR, tool-capable endpoints for `model`, cheapest first. Quantization is kept
 * on each row so the picker can default to >= 8-bit and toggle the rest with tab.
 */
export function buildRows(model: string, endpoints: Endpoint[]): Row[] {
  const rows: Row[] = [];
  for (const endpoint of endpoints) {
    if (endpoint.model_id !== model) continue;
    const row = rowFromEndpoint(endpoint);
    if (row) rows.push(row);
  }
  rows.sort((left, right) => left.cost - right.cost);
  return rows;
}

/** Every usable endpoint, across all models; used to look for a better model. */
export function buildAllRows(endpoints: Endpoint[]): Row[] {
  const rows: Row[] = [];
  for (const endpoint of endpoints) {
    const row = rowFromEndpoint(endpoint);
    if (row) rows.push(row);
  }
  return rows;
}

// --- Formatting -----------------------------------------------------------

export function formatTokens(tokens: number | null): string {
  if (!tokens) return "?";
  if (tokens >= 1_000_000) return `${Number((tokens / 1_000_000).toFixed(1))}M`;
  if (tokens >= 1_000) return `${Math.round(tokens / 1_000)}K`;
  return String(tokens);
}

export function formatCost(cost: number): string {
  if (cost === 0) return "$0";
  if (cost < 0.01) return `$${cost.toFixed(4)}`;
  return `$${cost.toFixed(cost < 1 ? 3 : 2)}`;
}

export function formatTps(tps: number | null): string {
  return tps === null ? "?" : String(Math.round(tps));
}

export function isRoutingModel(
  model: ExtensionContext["model"],
): model is NonNullable<ExtensionContext["model"]> {
  return !!model && model.provider === PROVIDER && model.api === ROUTING_API;
}
