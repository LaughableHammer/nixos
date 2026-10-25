/**
 * Pi sandbox extension.
 *
 * Runs in the trusted Pi process (which keeps `~/.pi/agent/auth.json`, provider
 * credentials and session files) and routes every built-in tool into a Docker
 * container that holds only the mounted working directory, an ephemeral scratch
 * directory and a read-only view of `/nix/store`.
 *
 * All sandbox policy lives in Nix (`modules/home/ai/pi/sandbox/default.nix`);
 * this file only speaks the newline-delimited JSON protocol to `sandboxd` and
 * adapts the results to Pi's tool operations interfaces.
 *
 * The launcher loads it with `-e <this file> -nbt`, so a failure to load leaves
 * Pi with no built-in tools instead of unsandboxed ones (fail closed).
 */
import { spawn, type ChildProcess } from "node:child_process";
import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  DEFAULT_MAX_BYTES,
  createBashToolDefinition,
  createEditToolDefinition,
  createFindToolDefinition,
  createGrepToolDefinition,
  createLsToolDefinition,
  createReadToolDefinition,
  createWriteToolDefinition,
  formatSize,
  truncateHead,
  truncateLine,
  type BashOperations,
  type EditOperations,
  type FindOperations,
  type GrepOperations,
  type LsOperations,
  type ReadOperations,
  type WriteOperations,
} from "@earendil-works/pi-coding-agent";

const SANDBOX_TOOLS = ["read", "write", "edit", "ls", "find", "grep", "bash"];
const GREP_DEFAULT_LIMIT = 100;
const START_TIMEOUT_MS = 60_000;
const STOP_TIMEOUT_MS = 5000;
/** A streaming exec must be acknowledged quickly; only the command itself runs long. */
const ACK_TIMEOUT_MS = 30_000;
const SANDBOX_HOME = "/tmp/home";

type SandboxMode = "rw" | "ro" | "none";

interface SandboxConfig {
  command: string;
  mode: SandboxMode;
  network: boolean;
  /** Working directory mounted into the sandbox, or null when nothing is mounted. */
  cwd: string | null;
  /** Working directory inside the container. */
  workdir: string;
  scratch: string;
  apk: boolean;
  strict: boolean;
}

interface StatInfo {
  isDirectory: boolean;
  isFile: boolean;
  isSymbolicLink: boolean;
  size: number;
  mode: number;
  mtimeMs: number;
}

interface ExecResult {
  exitCode: number | null;
  signal: string | null;
  timedOut: boolean;
}

interface SandboxFailure extends Error {
  code?: string;
}

/** Marks failures that mean the sandbox itself is unusable. */
const SANDBOX_UNAVAILABLE = "SANDBOX_UNAVAILABLE";

function unavailable(message: string): SandboxFailure {
  const error: SandboxFailure = new Error(message);
  error.code = SANDBOX_UNAVAILABLE;
  return error;
}

/** Convert a daemon error reply into the error the caller sees. */
function toFailure(message: Record<string, unknown>): SandboxFailure {
  const error = message.error as { code?: string; message?: string } | undefined;
  const failure: SandboxFailure = new Error(error?.message ?? "sandbox request failed");
  if (error?.code) failure.code = error.code;
  return failure;
}

function readConfig(env: NodeJS.ProcessEnv): SandboxConfig | null {
  const command = env.PI_SANDBOX_CMD;
  if (!command) return null;
  const mode = env.PI_SANDBOX_MODE;
  return {
    command,
    mode: mode === "rw" || mode === "ro" ? mode : "none",
    network: env.PI_SANDBOX_NET !== "0",
    cwd: env.PI_SANDBOX_CWD ? env.PI_SANDBOX_CWD : null,
    workdir: env.PI_SANDBOX_WORKDIR || "/tmp",
    scratch: env.PI_SANDBOX_SCRATCH || "/tmp",
    apk: env.PI_SANDBOX_APK === "1",
    strict: env.PI_SANDBOX_STRICT === "1",
  };
}

/** Resolve a tool path the way Pi's built-ins do: `~`, absolute, else relative to cwd. */
function resolvePath(input: string, cwd: string): string {
  const trimmed = input.startsWith("@") ? input.slice(1) : input;
  if (trimmed === "~") return SANDBOX_HOME;
  if (trimmed.startsWith("~/")) return path.join(SANDBOX_HOME, trimmed.slice(2));
  return path.resolve(cwd, trimmed);
}

function isMissing(error: unknown): boolean {
  const code = (error as SandboxFailure | undefined)?.code;
  return code === "ENOENT" || code === "ENOTDIR";
}

function isUnavailable(error: unknown): boolean {
  return (error as SandboxFailure | undefined)?.code === SANDBOX_UNAVAILABLE;
}

/** Sandbox configuration exported by the launcher, forwarded to the runner. */
function sandboxEnv(): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (typeof value !== "string") continue;
    if (!key.startsWith("PI_SANDBOX_")) continue;
    result[key] = value;
  }
  return result;
}

/** Only Pi session metadata crosses into the sandbox; host environment stays out. */
function sanitizeSessionEnv(env: NodeJS.ProcessEnv | undefined): Record<string, string> {
  const result: Record<string, string> = {};
  if (!env) return result;
  for (const [key, value] of Object.entries(env)) {
    if (typeof value !== "string") continue;
    if (!/^PI_[A-Z0-9_]+$/.test(key)) continue;
    if (key === "PI_SESSION_FILE") continue;
    result[key] = value;
  }
  return result;
}

const SIGNAL_NUMBERS: Record<string, number> = {
  SIGHUP: 1,
  SIGINT: 2,
  SIGQUIT: 3,
  SIGILL: 4,
  SIGABRT: 6,
  SIGFPE: 8,
  SIGKILL: 9,
  SIGSEGV: 11,
  SIGPIPE: 13,
  SIGALRM: 14,
  SIGTERM: 15,
};

interface PendingRequest {
  resolve: (value: Record<string, unknown>) => void;
  reject: (error: Error) => void;
  onEvent?: (message: Record<string, unknown>) => void;
  timer?: NodeJS.Timeout;
  /** Streaming requests keep their entry after the ack so events keep routing. */
  streaming?: boolean;
}

/**
 * Client for the `sandboxd` supervisor running inside the container.
 *
 * The container is started once per Pi session and kept alive, so per-call cost
 * is a pipe round trip rather than a container start.
 */
class SandboxClient {
  private child: ChildProcess | null = null;
  private starting: Promise<void> | null = null;
  private buffer = "";
  private nextId = 1;
  private readonly pending = new Map<number, PendingRequest>();
  private readonly runIds = new Map<number, number>();
  private dead: Error | null = null;
  private stderrTail = "";

  constructor(private readonly config: SandboxConfig) {}

  async ensureStarted(): Promise<void> {
    if (this.dead) throw this.dead;
    if (this.child) return;
    if (!this.starting) {
      this.starting = this.start().finally(() => {
        this.starting = null;
      });
    }
    return this.starting;
  }

  private async start(): Promise<void> {
    const child = spawn(this.config.command, ["sandboxd"], {
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        PATH: process.env.PATH ?? "/run/current-system/sw/bin",
        HOME: process.env.HOME ?? "/tmp",
        TERM: process.env.TERM ?? "xterm-256color",
        LANG: process.env.LANG ?? "C.UTF-8",
        DOCKER_HOST: process.env.DOCKER_HOST ?? "",
        // The runner needs the prepared sandbox environment; nothing else from
        // the host process is forwarded to it.
        ...sandboxEnv(),
      },
    });
    this.child = child;
    child.stdout?.setEncoding("utf8");
    child.stdout?.on("data", (chunk: string) => this.consume(chunk));
    child.stderr?.setEncoding("utf8");
    child.stderr?.on("data", (chunk: string) => {
      this.stderrTail = `${this.stderrTail}${chunk}`.slice(-4000);
    });
    child.on("exit", (code, signal) => {
      const detail = this.stderrTail.trim() ? `\n${this.stderrTail.trim()}` : "";
      this.die(
        unavailable(
          `sandbox container exited (code=${code ?? "null"}, signal=${signal ?? "null"})${detail}`,
        ),
      );
    });
    child.on("error", (error) => this.die(unavailable(`failed to start sandbox: ${error.message}`)));

    // Fail fast when the image is missing, the daemon is down, or the container
    // cannot start, instead of failing later on the first tool call.
    await this.send({ op: "ping" }, { timeoutMs: START_TIMEOUT_MS });
  }

  private die(error: Error): void {
    if (this.dead) return;
    this.dead = error;
    this.child = null;
    for (const [id, entry] of this.pending) {
      if (entry.timer) clearTimeout(entry.timer);
      if (entry.streaming) {
        // Streaming callers wait for an exit event; synthesise one so they do
        // not hang when the container dies mid-command.
        entry.onEvent?.({ id, event: "exit", code: null, signal: null, error: error.message });
      }
      entry.reject(error);
    }
    this.pending.clear();
    this.runIds.clear();
  }

  private consume(chunk: string): void {
    this.buffer += chunk;
    let index = this.buffer.indexOf("\n");
    while (index !== -1) {
      const line = this.buffer.slice(0, index).trim();
      this.buffer = this.buffer.slice(index + 1);
      if (line) this.dispatch(line);
      index = this.buffer.indexOf("\n");
    }
  }

  private dispatch(line: string): void {
    let message: Record<string, unknown>;
    try {
      message = JSON.parse(line) as Record<string, unknown>;
    } catch {
      return;
    }
    const id = typeof message.id === "number" ? message.id : undefined;
    if (id === undefined) return;
    const entry = this.pending.get(id);
    if (!entry) return;
    if (message.event !== undefined) {
      entry.onEvent?.(message);
      // The exit event ends a streaming request.
      if (message.event === "exit") {
        this.pending.delete(id);
        this.runIds.delete(id);
        if (entry.timer) clearTimeout(entry.timer);
      }
      return;
    }
    // A failed request (for example an `exec` whose cwd is not a directory) may
    // never produce an `exit` event, so it has to reject instead of resolving
    // the ack; otherwise a streaming caller waits forever.
    if (entry.streaming) {
      if (entry.timer) clearTimeout(entry.timer);
      if (message.ok === false) {
        this.pending.delete(id);
        entry.reject(toFailure(message));
        return;
      }
      // Ack of a streaming request: resolve so the caller learns the run id, but
      // keep the entry registered for the events that follow.
      entry.resolve(message);
      return;
    }
    this.pending.delete(id);
    if (entry.timer) clearTimeout(entry.timer);
    if (message.ok === false) {
      entry.reject(toFailure(message));
      return;
    }
    entry.resolve(message);
  }

  private send(
    request: Record<string, unknown>,
    options: {
      timeoutMs?: number;
      onEvent?: (message: Record<string, unknown>) => void;
      signal?: AbortSignal;
      streaming?: boolean;
      /** Pre-allocated id, so the caller can register abort handling for it. */
      id?: number;
    } = {},
  ): Promise<Record<string, unknown>> {
    const child = this.child;
    if (!child || this.dead) {
      return Promise.reject(this.dead ?? unavailable("sandbox is not running"));
    }
    const id = options.id ?? this.nextId++;
    return new Promise<Record<string, unknown>>((resolve, reject) => {
      const entry: PendingRequest = {
        resolve,
        reject,
        onEvent: options.onEvent,
        streaming: options.streaming === true,
      };
      // For a streaming request this timer only covers the ack; the command's
      // own timeout is enforced inside the sandbox (`timeoutMs`).
      const ackTimeoutMs = options.streaming
        ? options.timeoutMs && options.timeoutMs > 0
          ? options.timeoutMs
          : ACK_TIMEOUT_MS
        : options.timeoutMs;
      if (ackTimeoutMs && ackTimeoutMs > 0) {
        entry.timer = setTimeout(() => {
          if (this.pending.delete(id)) {
            reject(unavailable(`sandbox request timed out: ${String(request.op)}`));
          }
        }, ackTimeoutMs);
      }
      this.pending.set(id, entry);
      options.signal?.addEventListener(
        "abort",
        () => {
          const runId = this.runIds.get(id);
          if (runId !== undefined) void this.kill(runId);
        },
        { once: true },
      );
      child.stdin?.write(`${JSON.stringify({ id, ...request })}\n`, (error) => {
        if (error) this.die(unavailable(`sandbox write failed: ${error.message}`));
      });
    });
  }

  private async request(
    request: Record<string, unknown>,
    options: { timeoutMs?: number } = {},
  ): Promise<Record<string, unknown>> {
    await this.ensureStarted();
    return this.send(request, options);
  }

  async stop(): Promise<void> {
    const child = this.child;
    if (!child) return;
    this.child = null;
    try {
      child.stdin?.write(`${JSON.stringify({ id: this.nextId++, op: "shutdown" })}\n`);
      child.stdin?.end();
    } catch {
      // Container may already be gone.
    }
    await new Promise<void>((resolve) => {
      const timer = setTimeout(() => {
        child.kill("SIGKILL");
        resolve();
      }, STOP_TIMEOUT_MS);
      child.once("exit", () => {
        clearTimeout(timer);
        resolve();
      });
    });
  }

  async read(filePath: string): Promise<Buffer> {
    const response = await this.request({ op: "read", path: filePath });
    return Buffer.from(String(response.data ?? ""), "base64");
  }

  async write(filePath: string, data: Buffer | string): Promise<void> {
    const buffer = typeof data === "string" ? Buffer.from(data, "utf8") : data;
    await this.request({ op: "write", path: filePath, data: buffer.toString("base64") });
  }

  async mkdir(dirPath: string): Promise<void> {
    await this.request({ op: "mkdir", path: dirPath, recursive: true });
  }

  async access(filePath: string, write = false): Promise<void> {
    await this.request({ op: "access", path: filePath, write });
  }

  async stat(target: string): Promise<StatInfo> {
    const response = await this.request({ op: "stat", path: target });
    return {
      isDirectory: response.isDirectory === true,
      isFile: response.isFile === true,
      isSymbolicLink: response.isSymbolicLink === true,
      size: Number(response.size ?? 0),
      mode: Number(response.mode ?? 0),
      mtimeMs: Number(response.mtimeMs ?? 0),
    };
  }

  async readdir(target: string): Promise<string[]> {
    const response = await this.request({ op: "readdir", path: target });
    return Array.isArray(response.entries) ? (response.entries as string[]) : [];
  }

  async exists(target: string): Promise<boolean> {
    try {
      await this.stat(target);
      return true;
    } catch (error) {
      if (isMissing(error)) return false;
      throw error;
    }
  }

  async kill(runId: number): Promise<void> {
    // `send` rejects when the container is already gone; killing is best effort.
    try {
      await this.send({ op: "kill", runId, signal: "SIGKILL" });
    } catch {
      // Ignore; the run is gone with the container.
    }
  }

  /**
   * Run a command inside the sandbox, streaming stdout and stderr separately.
   * Resolves with the exit status; the caller decides how to interpret it.
   */
  async execStreaming(
    command: string,
    cwd: string,
    options: {
      signal?: AbortSignal;
      timeoutMs?: number;
      env?: NodeJS.ProcessEnv;
      onStdout?: (data: Buffer) => void;
      onStderr?: (data: Buffer) => void;
      onRunId?: (runId: number) => void;
    } = {},
  ): Promise<ExecResult> {
    await this.ensureStarted();
    let resolveExit!: (value: Record<string, unknown>) => void;
    let rejectExit!: (error: Error) => void;
    const exited = new Promise<Record<string, unknown>>((resolve, reject) => {
      resolveExit = resolve;
      rejectExit = reject;
    });

    const pendingId = this.nextId++;
    const ack = this.send(
      {
        op: "exec",
        command,
        cwd,
        timeoutMs: options.timeoutMs,
        env: sanitizeSessionEnv(options.env),
      },
      {
        id: pendingId,
        signal: options.signal,
        streaming: true,
        onEvent: (message) => {
          if (message.event === "data") {
            const data = Buffer.from(String(message.data ?? ""), "base64");
            if (data.length === 0) return;
            if (message.stream === "stderr") options.onStderr?.(data);
            else options.onStdout?.(data);
          } else if (message.event === "exit") {
            resolveExit(message);
          }
        },
      },
    );

    // Abort must settle the call, not just stop the process: the agent loop waits
    // on this promise, and a lost `exit` event would freeze the session.
    const onAbort = () => {
      const runId = this.runIds.get(pendingId);
      if (runId !== undefined) void this.kill(runId);
      rejectExit(new Error("aborted"));
    };
    if (options.signal) {
      if (options.signal.aborted) onAbort();
      else options.signal.addEventListener("abort", onAbort, { once: true });
    }

    ack
      .then((response) => {
        const runId = typeof response.runId === "number" ? response.runId : undefined;
        if (runId === undefined) return;
        this.runIds.set(pendingId, runId);
        options.onRunId?.(runId);
        if (options.signal?.aborted) onAbort();
      })
      .catch((error: Error) => rejectExit(error));

    try {
      const exit = await exited;
      if (typeof exit.error === "string") throw new Error(exit.error);
      return {
        exitCode: typeof exit.code === "number" ? exit.code : null,
        signal: typeof exit.signal === "string" ? exit.signal : null,
        timedOut: exit.timedOut === true,
      };
    } finally {
      options.signal?.removeEventListener("abort", onAbort);
    }
  }

  /** `BashOperations` adapter: merged output, Pi's timeout/abort conventions. */
  async exec(
    command: string,
    cwd: string,
    options: {
      onData: (data: Buffer) => void;
      signal?: AbortSignal;
      timeout?: number;
      env?: NodeJS.ProcessEnv;
    },
  ): Promise<{ exitCode: number | null }> {
    const timeoutSeconds = options.timeout && options.timeout > 0 ? options.timeout : undefined;
    const result = await this.execStreaming(command, cwd, {
      signal: options.signal,
      timeoutMs: timeoutSeconds ? timeoutSeconds * 1000 : undefined,
      env: options.env,
      onStdout: options.onData,
      onStderr: options.onData,
    });
    if (options.signal?.aborted) throw new Error("aborted");
    if (result.timedOut) throw new Error(`timeout:${timeoutSeconds}`);
    if (result.exitCode === null && result.signal) {
      return { exitCode: 128 + (SIGNAL_NUMBERS[result.signal] ?? 15) };
    }
    return { exitCode: result.exitCode };
  }

  /** Run a command and capture both streams; used for sandboxed `rg`/`fd`. */
  async capture(
    command: string,
    options: {
      cwd?: string;
      signal?: AbortSignal;
      onRunId?: (runId: number) => void;
      onStdout?: (data: Buffer) => void;
    } = {},
  ): Promise<{ stdout: string; stderr: string; exitCode: number | null }> {
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    const result = await this.execStreaming(command, options.cwd ?? this.config.workdir, {
      signal: options.signal,
      onRunId: options.onRunId,
      onStdout: (data) => {
        options.onStdout?.(data);
        stdout.push(data);
      },
      onStderr: (data) => stderr.push(data),
    });
    return {
      stdout: Buffer.concat(stdout).toString("utf8"),
      stderr: Buffer.concat(stderr).toString("utf8"),
      exitCode: result.exitCode,
    };
  }
}

/** Minimal single-quote shell escaping for values interpolated into commands. */
function quote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

export default function sandboxExtension(pi: ExtensionAPI): void {
  const config = readConfig(process.env);
  const hostCwd = process.cwd();
  const sandboxCwd = config?.workdir ?? hostCwd;

  if (!config) {
    // Loaded outside the launcher: refuse to run tools rather than silently
    // falling back to unsandboxed host execution.
    pi.on("session_start", async (_event, ctx) => {
      ctx.ui.notify(
        "Pi sandbox extension loaded without sandbox configuration; built-in tools are disabled. Use `pi -insecure` for unsandboxed runs.",
        "error",
      );
    });
    return;
  }

  const client = new SandboxClient(config);
  let sandboxReady = false;

  async function ensureSandbox(): Promise<SandboxClient> {
    if (sandboxReady) return client;
    await client.ensureStarted();
    sandboxReady = true;
    return client;
  }

  /** In `none` mode relative paths resolve inside the sandbox workdir. */
  function rewritePath(input: string | undefined, fallback: string): string | undefined {
    if (config?.cwd) return input;
    if (input === undefined) return resolvePath(fallback, config?.workdir ?? "/tmp");
    if (path.isAbsolute(input) || input.startsWith("~") || input.startsWith("@/")) return input;
    return resolvePath(input, config?.workdir ?? "/tmp");
  }

  /** Map Pi's cwd onto a path that exists inside the container. */
  function toSandboxCwd(cwd: string): string {
    if (config?.cwd && (cwd === config.cwd || cwd.startsWith(`${config.cwd}/`))) return cwd;
    return config?.workdir ?? "/tmp";
  }

  function fail(error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text" as const,
          text: `Sandbox error: ${message}\n\nThe sandboxed tools are unavailable. Fix the container setup, or restart Pi with \`-insecure\` to run unsandboxed on the host.`,
        },
      ],
      details: undefined,
    };
  }

  /**
   * Tool failures that come from the sandbox being down become a readable tool
   * result; ordinary failures (missing files, read-only mounts) are rethrown so
   * Pi reports them the way it reports its built-in tools.
   */
  function toolError(error: unknown): never | ReturnType<typeof fail> {
    if (!isUnavailable(error)) throw error;
    return fail(error);
  }

  const readOperations: ReadOperations = {
    readFile: async (filePath) => {
      await ensureSandbox();
      return client.read(filePath);
    },
    access: async (filePath) => {
      await ensureSandbox();
      await client.access(filePath);
    },
    detectImageMimeType: async (filePath) => {
      const extension = path.extname(filePath).toLowerCase();
      if (extension === ".png") return "image/png";
      if (extension === ".jpg" || extension === ".jpeg") return "image/jpeg";
      if (extension === ".gif") return "image/gif";
      if (extension === ".webp") return "image/webp";
      return null;
    },
  };

  const writeOperations: WriteOperations = {
    writeFile: async (filePath, content) => {
      await ensureSandbox();
      await client.write(filePath, content);
    },
    mkdir: async (dir) => {
      await ensureSandbox();
      await client.mkdir(dir);
    },
  };

  const editOperations: EditOperations = {
    readFile: readOperations.readFile,
    access: async (filePath) => {
      await ensureSandbox();
      await client.access(filePath, true);
    },
    writeFile: writeOperations.writeFile,
  };

  const lsOperations: LsOperations = {
    exists: async (filePath) => {
      await ensureSandbox();
      return client.exists(filePath);
    },
    stat: async (filePath) => {
      await ensureSandbox();
      const info = await client.stat(filePath);
      return { isDirectory: () => info.isDirectory };
    },
    readdir: async (dir) => {
      await ensureSandbox();
      return client.readdir(dir);
    },
  };

  const grepOperations: GrepOperations = {
    isDirectory: async (filePath) => {
      await ensureSandbox();
      return (await client.stat(filePath)).isDirectory;
    },
    readFile: async (filePath) => {
      await ensureSandbox();
      return (await client.read(filePath)).toString("utf8");
    },
  };

  /**
   * `find` uses custom `glob` operations when they are provided, so the search
   * runs inside the sandbox instead of Pi shelling out to a host `fd`.
   */
  const findOperations: FindOperations = {
    exists: async (filePath) => {
      await ensureSandbox();
      return client.exists(filePath);
    },
    glob: async (pattern, searchPath, options) => {
      await ensureSandbox();
      let insideGitRepo = false;
      for (let current = searchPath; ; ) {
        if (await client.exists(path.join(current, ".git"))) {
          insideGitRepo = true;
          break;
        }
        const parent = path.dirname(current);
        if (parent === current) break;
        current = parent;
      }
      const args = ["--glob", "--color=never", "--hidden"];
      if (!insideGitRepo) args.push("--no-require-git");
      args.push("--max-results", String(options.limit));
      let effectivePattern = pattern;
      if (pattern.includes("/")) {
        args.push("--full-path");
        if (!pattern.startsWith("/") && !pattern.startsWith("**/") && pattern !== "**") {
          effectivePattern = `**/${pattern}`;
        }
      }
      args.push("--", effectivePattern, searchPath);
      const result = await client.capture(`fd ${args.map(quote).join(" ")}`, { cwd: searchPath });
      return result.stdout
        .split("\n")
        .map((line) => line.replace(/\r$/, "").trim())
        .filter((line) => line.length > 0);
    },
  };

  const bashOperations: BashOperations = {
    exec: async (command, cwd, options) => {
      await ensureSandbox();
      return client.exec(command, toSandboxCwd(cwd), options);
    },
  };

  /**
   * `grep` is reimplemented instead of delegated: Pi's built-in grep always
   * spawns a host `rg`, which would search the host filesystem from the trusted
   * process. This mirrors `dist/core/tools/grep.js` (same arguments, same output
   * shape and truncation notices) but runs `rg` inside the sandbox. If Pi's
   * formatting changes upstream, this needs to follow.
   */
  async function runSandboxedGrep(
    params: {
      pattern: string;
      path?: string;
      glob?: string;
      ignoreCase?: boolean;
      literal?: boolean;
      context?: number;
      limit?: number;
    },
    signal: AbortSignal | undefined,
    ctx: ExtensionContext | undefined,
  ) {
    await ensureSandbox();
    const searchPath = resolvePath(params.path ?? ".", ctx?.cwd ?? sandboxCwd);
    let isDirectory: boolean;
    try {
      isDirectory = (await client.stat(searchPath)).isDirectory;
    } catch (error) {
      // Only a missing path is "not found"; sandbox failures must surface as-is,
      // otherwise they look like ordinary tool errors and hide a broken sandbox.
      if (isMissing(error)) throw new Error(`Path not found: ${searchPath}`);
      throw error;
    }

    // `rg` takes a file or a directory, but its cwd must be a directory. Using the
    // file as cwd makes `spawn` fail, which used to leave the call waiting for an
    // exit event that never came.
    const runCwd = isDirectory ? searchPath : path.dirname(searchPath);

    const contextLines = params.context && params.context > 0 ? params.context : 0;
    const effectiveLimit = Math.max(1, params.limit ?? GREP_DEFAULT_LIMIT);
    const formatPath = (filePath: string): string => {
      if (isDirectory) {
        const relative = path.relative(searchPath, filePath);
        if (relative && !relative.startsWith("..")) return relative.replace(/\\/g, "/");
      }
      return path.basename(filePath);
    };

    const args = ["--json", "--line-number", "--color=never", "--hidden"];
    if (params.ignoreCase) args.push("--ignore-case");
    if (params.literal) args.push("--fixed-strings");
    if (params.glob) args.push("--glob", params.glob);
    args.push("--", params.pattern, searchPath);

    const matches: Array<{ filePath: string; lineNumber: number; lineText?: string }> = [];
    let matchCount = 0;
    let matchLimitReached = false;
    let linesTruncated = false;
    let streamBuffer = "";
    let currentRunId: number | undefined;
    let killedByLimit = false;

    const stopOnLimit = (): void => {
      if (currentRunId !== undefined) void client.kill(currentRunId);
    };

    const consumeLine = (line: string): void => {
      if (!line.trim() || matchCount >= effectiveLimit) return;
      let event: {
        type?: string;
        data?: { path?: { text?: string }; line_number?: number; lines?: { text?: string } };
      };
      try {
        event = JSON.parse(line) as typeof event;
      } catch {
        return;
      }
      if (event.type !== "match") return;
      matchCount += 1;
      const filePath = event.data?.path?.text;
      const lineNumber = event.data?.line_number;
      if (filePath && typeof lineNumber === "number") {
        matches.push({ filePath, lineNumber, lineText: event.data?.lines?.text });
      }
      if (matchCount >= effectiveLimit) {
        matchLimitReached = true;
        killedByLimit = true;
        stopOnLimit();
      }
    };

    const result = await client.execStreaming(
      `rg ${args.map(quote).join(" ")}`,
      runCwd,
      {
        signal,
        onRunId: (runId) => {
          currentRunId = runId;
          // The limit can be reached before the ack arrives (rg streams output
          // immediately), so re-check here instead of letting rg scan on.
          if (matchLimitReached) stopOnLimit();
        },
        onStdout: (data) => {
          streamBuffer += data.toString("utf8");
          let index = streamBuffer.indexOf("\n");
          while (index !== -1) {
            const line = streamBuffer.slice(0, index);
            streamBuffer = streamBuffer.slice(index + 1);
            index = streamBuffer.indexOf("\n");
            consumeLine(line);
          }
        },
      },
    );

    if (signal?.aborted) throw new Error("aborted");
    if (!killedByLimit && result.exitCode !== null && result.exitCode !== 0 && result.exitCode !== 1) {
      throw new Error(`ripgrep exited with code ${result.exitCode}`);
    }
    if (matchCount === 0) {
      return { content: [{ type: "text" as const, text: "No matches found" }], details: undefined };
    }

    const outputLines: string[] = [];
    const fileCache = new Map<string, string[]>();
    const fileLines = async (filePath: string): Promise<string[]> => {
      const cached = fileCache.get(filePath);
      if (cached) return cached;
      let lines: string[] = [];
      try {
        const content = await client.read(filePath);
        lines = content.toString("utf8").replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
      } catch {
        lines = [];
      }
      fileCache.set(filePath, lines);
      return lines;
    };

    for (const match of matches) {
      const relativePath = formatPath(match.filePath);
      if (contextLines === 0 && match.lineText !== undefined) {
        const sanitized = match.lineText
          .replace(/\r\n/g, "\n")
          .replace(/\r/g, "")
          .replace(/\n$/, "");
        const { text, wasTruncated } = truncateLine(sanitized);
        if (wasTruncated) linesTruncated = true;
        outputLines.push(`${relativePath}:${match.lineNumber}: ${text}`);
        continue;
      }
      const lines = await fileLines(match.filePath);
      if (lines.length === 0) {
        outputLines.push(`${relativePath}:${match.lineNumber}: (unable to read file)`);
        continue;
      }
      const start = contextLines > 0 ? Math.max(1, match.lineNumber - contextLines) : match.lineNumber;
      const end =
        contextLines > 0 ? Math.min(lines.length, match.lineNumber + contextLines) : match.lineNumber;
      for (let current = start; current <= end; current++) {
        const sanitized = (lines[current - 1] ?? "").replace(/\r/g, "");
        const { text, wasTruncated } = truncateLine(sanitized);
        if (wasTruncated) linesTruncated = true;
        const separator = current === match.lineNumber ? ":" : "-";
        outputLines.push(`${relativePath}${separator}${current}${separator} ${text}`);
      }
    }

    const truncation = truncateHead(outputLines.join("\n"), { maxLines: Number.MAX_SAFE_INTEGER });
    let output = truncation.content;
    const details: Record<string, unknown> = {};
    const notices: string[] = [];
    if (matchLimitReached) {
      notices.push(
        `${effectiveLimit} matches limit reached. Use limit=${effectiveLimit * 2} for more, or refine pattern`,
      );
      details.matchLimitReached = effectiveLimit;
    }
    if (truncation.truncated) {
      notices.push(`${formatSize(DEFAULT_MAX_BYTES)} limit reached`);
      details.truncation = truncation;
    }
    if (linesTruncated) {
      notices.push("Some lines truncated to 500 chars. Use read tool to see full lines");
      details.linesTruncated = true;
    }
    if (notices.length > 0) output += `\n\n[${notices.join(". ")}]`;

    return {
      content: [{ type: "text" as const, text: output }],
      details: Object.keys(details).length > 0 ? details : undefined,
    };
  }

  // ---------------------------------------------------------------------------
  // Tool registration
  // ---------------------------------------------------------------------------

  const readTool = createReadToolDefinition(sandboxCwd, { operations: readOperations });
  pi.registerTool({
    ...readTool,
    execute: async (id, params, signal, onUpdate, ctx) => {
      try {
        return await readTool.execute(
          id,
          { ...params, path: rewritePath(params.path, ".") ?? params.path },
          signal,
          onUpdate,
          ctx,
        );
      } catch (error) {
        return toolError(error);
      }
    },
  });

  const writeTool = createWriteToolDefinition(sandboxCwd, { operations: writeOperations });
  pi.registerTool({
    ...writeTool,
    execute: async (id, params, signal, onUpdate, ctx) => {
      try {
        return await writeTool.execute(
          id,
          { ...params, path: rewritePath(params.path, ".") ?? params.path },
          signal,
          onUpdate,
          ctx,
        );
      } catch (error) {
        return toolError(error);
      }
    },
  });

  const editTool = createEditToolDefinition(sandboxCwd, { operations: editOperations });
  pi.registerTool({
    ...editTool,
    execute: async (id, params, signal, onUpdate, ctx) => {
      try {
        return await editTool.execute(
          id,
          { ...params, path: rewritePath(params.path, ".") ?? params.path },
          signal,
          onUpdate,
          ctx,
        );
      } catch (error) {
        return toolError(error);
      }
    },
  });

  const lsTool = createLsToolDefinition(sandboxCwd, { operations: lsOperations });
  pi.registerTool({
    ...lsTool,
    execute: async (id, params, signal, onUpdate, ctx) => {
      try {
        return await lsTool.execute(
          id,
          { ...params, path: rewritePath(params.path, ".") ?? params.path },
          signal,
          onUpdate,
          ctx,
        );
      } catch (error) {
        return toolError(error);
      }
    },
  });

  const findTool = createFindToolDefinition(sandboxCwd, { operations: findOperations });
  pi.registerTool({
    ...findTool,
    execute: async (id, params, signal, onUpdate, ctx) => {
      try {
        return await findTool.execute(
          id,
          { ...params, path: rewritePath(params.path, ".") ?? params.path },
          signal,
          onUpdate,
          ctx,
        );
      } catch (error) {
        return toolError(error);
      }
    },
  });

  const bashTool = createBashToolDefinition(sandboxCwd, { operations: bashOperations });
  pi.registerTool({
    ...bashTool,
    execute: async (id, params, signal, onUpdate, ctx) => {
      try {
        return await bashTool.execute(id, params, signal, onUpdate, ctx);
      } catch (error) {
        return toolError(error);
      }
    },
  });

  const grepTool = createGrepToolDefinition(sandboxCwd, { operations: grepOperations });
  pi.registerTool({
    ...grepTool,
    execute: async (_id, params, signal, _onUpdate, ctx) => {
      try {
        return await runSandboxedGrep(
          { ...params, path: rewritePath(params.path, ".") ?? params.path },
          signal,
          ctx,
        );
      } catch (error) {
        return toolError(error);
      }
    },
  });

  // ---------------------------------------------------------------------------
  // User commands, lifecycle and prompt guidelines
  // ---------------------------------------------------------------------------

  pi.on("user_bash", async () => ({ operations: bashOperations }));

  if (config.strict) {
    pi.on("tool_call", async (event) => {
      if (SANDBOX_TOOLS.includes(event.toolName)) return;
      return {
        block: true,
        reason: `Sandboxed session: only ${SANDBOX_TOOLS.join(", ")} are available.`,
      };
    });
  }

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setStatus("sandbox", ctx.ui.theme.fg("accent", statusLabel(config)));
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    ctx.ui.setStatus("sandbox", undefined);
    sandboxReady = false;
    await client.stop().catch(() => {});
  });

  /**
   * Short, factual notes so the model does not spend turns on things the sandbox
   * cannot do. They describe restrictions; the container is the boundary.
   */
  pi.on("before_agent_start", async (event) => {
    const activeTools = new Set(pi.getActiveTools());
    const hasBash = activeTools.has("bash");
    const guidelines: string[] = [];

    if (hasBash && config.network) {
      guidelines.push(
        "Avoid recalling information about source available software and instead answer definitively by cloning the source to /tmp and referring to it",
      );
      guidelines.push("`uv` is available for Python packages");
      guidelines.push(
        config.apk
          ? "You are in an Alpine linux container with a read-only /nix volume mounted in. Use apk to install packages."
          : "You are in an Alpine linux container with a read-only /nix volume mounted in.",
      );
    }
    if (hasBash) {
      guidelines.push(
        "Nix builds are unavailable in the sandbox: ask the user to run `nix build` on the host.",
      );
    }
    if (!config.network) {
      guidelines.push("You are in a sandbox with no network access.");
    }
    if (config.cwd) {
      guidelines.push(
        "The user has mounted data into the sandbox at the current working directory. The user's question will be in reference to the data in the current working directory.",
      );
    }
    if (config.mode === "ro") {
      guidelines.push("The current working directory is read-only; write scratch files to /tmp.");
    }
    if (config.mode === "none") {
      guidelines.push("The current working directory is not mounted; work in /tmp.");
    }
    if (config.mode === "copy") {
      guidelines.push(
        "The original working directory is not mounted; a private copy of it is at /tmp/work.",
      );
    }

    event.systemPromptOptions.promptGuidelines.push(...guidelines);
  });
}

function statusLabel(config: SandboxConfig): string {
  const parts = [config.mode, config.network ? "net on" : "net off"];
  if (config.strict) parts.push("strict");
  return `🔒 sandbox: ${parts.join(" · ")}`;
}
