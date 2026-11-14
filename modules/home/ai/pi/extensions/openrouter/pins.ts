import { getAgentDir } from "@earendil-works/pi-coding-agent";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// Pins are written next to the sessions so they survive restarts and are shared
// by every Pi process; each model keeps the single ZDR endpoint it routes to.

const PINS_FILE = "openrouter-pins.json";

export interface Pin {
  tag: string;
  provider: string;
  quant: string;
  pinnedAt: number;
}

export type PinStore = Record<string, Pin>;

let pins: PinStore = loadPins();

function pinsPath(): string {
  return join(getAgentDir(), "sessions", PINS_FILE);
}

export function loadPins(): PinStore {
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

/** Re-read the store, e.g. on session start in case another process wrote it. */
export function reloadPins(): void {
  pins = loadPins();
}

export function pinFor(modelId: string): Pin | undefined {
  return pins[modelId];
}

export function setPin(modelId: string, pin: Pin): void {
  pins[modelId] = pin;
  savePins(pins);
}

export function removePin(modelId: string): void {
  if (!(modelId in pins)) return;
  delete pins[modelId];
  savePins(pins);
}
