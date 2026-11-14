import {
  BorderedLoader,
  DynamicBorder,
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
import { formatCost, formatTokens, formatTps, type Row, MIN_QUANT_BITS } from "./endpoints";

const MAX_VISIBLE_ROWS = 14;

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

export { ProviderPicker };

/**
 * Run a request behind a cancellable spinner. Resolves undefined when cancelled
 * or failed; `silent` keeps automatic checks from raising error notifications.
 */
export async function load<T>(
  ctx: ExtensionContext,
  message: string,
  task: (signal: AbortSignal) => Promise<T>,
  options: { silent?: boolean } = {},
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
  if (!options.silent && failure && !(failure instanceof Error && failure.name === "AbortError")) {
    ctx.ui.notify(`OpenRouter: ${failure instanceof Error ? failure.message : String(failure)}`, "error");
  }
  return result;
}
