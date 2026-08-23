#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
  ListResourcesRequestSchema,
  ListResourceTemplatesRequestSchema,
  ReadResourceRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import http from "node:http";
import crypto from "node:crypto";
import { Duplex } from "node:stream";
import { readFileSync, cpSync } from "node:fs";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { searchAssets, getAssetThumbnail, importAsset, type AssetProvider } from "./assets/index.js";

const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const BASE_PORT = parseInt(process.env.GODOT_MCP_PORT ?? "6505", 10);
const ALL_PORTS = Array.from({ length: 10 }, (_, i) => BASE_PORT + i);
const REQUEST_TIMEOUT = 30_000;
// Long enough for the longest thing the addon will do (run_stress_test caps
// duration at 60s) plus slack, without being unbounded.
const JOB_TIMEOUT = 300_000;

interface JobRecord {
  status: "running" | "done" | "error";
  method: string;
  started: number;
  result?: unknown;
  error?: string;
}

// Opt-in connection token (see SECURITY.md / godot_mcp/require_connection_token).
// The Godot side writes the token to user://mcp_auth_token, a path this
// process has no way to resolve on its own (it doesn't know the project's
// user data dir), so the token must be handed to us explicitly: either the
// literal value via GODOT_MCP_TOKEN, or a path to the file (e.g. the one
// printed in the editor Output panel) via GODOT_MCP_TOKEN_PATH.
export function getAuthToken(): string | null {
  const inline = process.env.GODOT_MCP_TOKEN;
  if (inline) return inline;
  const tokenPath = process.env.GODOT_MCP_TOKEN_PATH;
  if (tokenPath) {
    try {
      return readFileSync(tokenPath, "utf8").trim();
    } catch (err) {
      console.error(`godot-mcp: could not read GODOT_MCP_TOKEN_PATH (${tokenPath}): ${(err as Error).message}`);
    }
  }
  return null;
}

export function wsAccept(key: string): string {
  return crypto.createHash("sha1").update(key + WS_MAGIC).digest("base64");
}

export function wsSend(socket: Duplex, text: string): void {
  const buf = Buffer.from(text, "utf8");
  // Godot's WebSocketPeer rejects server frames that use the 16-bit extended
  // length marker (0x7E) even for small payloads, so encode per-length:
  //     < 126  -> short form     0x81 <len>
  //     < 64K  -> 16-bit marker  0x81 0x7E <u16be>
  //     else   -> 64-bit marker  0x81 0x7F <u64be>
  let h: Buffer;
  if (buf.length < 126) {
    h = Buffer.from([0x81, buf.length]);
  } else if (buf.length < 65536) {
    h = Buffer.alloc(4);
    h[0] = 0x81; h[1] = 126; h.writeUInt16BE(buf.length, 2);
  } else {
    h = Buffer.alloc(10);
    h[0] = 0x81; h[1] = 127; h.writeBigUInt64BE(BigInt(buf.length), 2);
  }
  socket.write(Buffer.concat([h, buf]));
}

interface Pending {
  resolve: (v: unknown) => void;
  reject: (e: unknown) => void;
  timer: NodeJS.Timeout;
}

interface MethodSummary {
  category: string;
  summary: string;
  annotations: Record<string, boolean>;
  has_schema: boolean;
}

// Plain Levenshtein edit distance, used to turn a typo'd method name into a
// suggestion instead of a bare "not found" that costs a round trip to learn.
export function levenshtein(a: string, b: string): number {
  const dp: number[][] = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
  for (let i = 0; i <= a.length; i++) dp[i][0] = i;
  for (let j = 0; j <= b.length; j++) dp[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1]);
    }
  }
  return dp[a.length][b.length];
}

export function suggestMethod(name: string, known: string[]): string | null {
  if (known.includes(name)) return null;
  let best: string | null = null;
  let bestDist = Infinity;
  for (const candidate of known) {
    const d = levenshtein(name, candidate);
    if (d < bestDist) { bestDist = d; best = candidate; }
  }
  // A distance close to the name's own length is "different method", not "typo".
  return best !== null && bestDist <= Math.max(3, Math.floor(name.length / 2)) ? best : null;
}

const MAX_OUTPUT_CHARS = 100_000;

export function truncateOutput(text: string, maxChars = MAX_OUTPUT_CHARS): string {
  if (text.length <= maxChars) return text;
  return text.slice(0, maxChars) +
    `\n\n... [truncated ${text.length - maxChars} of ${text.length} characters — narrow the call ` +
    `(many methods accept max_depth/max_results/filter params) or page through the underlying data ` +
    `differently]`;
}

export function decodeFrame(buf: Buffer): { opcode: number; payload: Buffer; total: number } | null {
  if (buf.length < 2) return null;
  const opcode = buf[0] & 0x0f;
  const masked = (buf[1] & 0x80) !== 0;
  let len = buf[1] & 0x7f;
  let off = 2;
  if (len === 126) { if (buf.length < 4) return null; len = buf.readUInt16BE(2); off = 4; }
  if (len === 127) { if (buf.length < 10) return null; len = Number(buf.readBigUInt64BE(2)); off = 10; }
  const mLen = masked ? 4 : 0;
  if (buf.length < off + mLen + len) return null;
  const mask = masked ? buf.subarray(off, off + 4) : null; off += mLen;
  let payload = Buffer.from(buf.subarray(off, off + len));
  if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
  return { opcode, payload, total: off + len };
}

// Method names src/index.ts calls directly by name (outside godot_call's
// live-validated path) — kept in sync with scripts/contract-check.mjs's
// TS_HARDCODED_METHODS. Duplicated rather than imported: contract-check.mjs
// is a plain Node script run against the repo tree (including via npm test
// and CI), while this file is compiled by tsc with rootDir "src" and would
// need to reach outside it to import from scripts/.
const DOCTOR_REQUIRED_METHODS = [
  "describe_methods",
  "describe_method",
  "get_scene_tree",
  "get_project_info",
  "get_project_settings",
  "get_output_log",
  "classdb_describe",
  "get_editor_screenshot",
  "execute_editor_script",
  "reload_project",
];

interface DoctorCheck {
  ok: boolean;
  label: string;
  detail: string;
  suggestion?: string;
}

function resolveGodotBinary(): { found: boolean; path?: string; version?: string } {
  const candidates = [process.env.GODOT_BIN, "godot4", "godot"].filter(Boolean) as string[];
  for (const candidate of candidates) {
    try {
      const result = spawnSync(candidate, ["--version"], { encoding: "utf8" });
      if (result.status === 0) {
        return { found: true, path: candidate, version: result.stdout.trim() };
      }
    } catch {
      // candidate not on PATH / not executable — try the next one
    }
  }
  return { found: false };
}

async function runDoctor(): Promise<DoctorCheck[]> {
  const checks: DoctorCheck[] = [];

  // 1. Port bound
  const boundPort = godot.boundPort;
  if (boundPort) {
    checks.push({ ok: true, label: "Port bound", detail: `Listening on port ${boundPort}.` });
  } else {
    checks.push({
      ok: false,
      label: "Port bound",
      detail: `No port bound — ${ALL_PORTS[0]}-${ALL_PORTS[ALL_PORTS.length - 1]} were all busy.`,
      suggestion: "Close an unused agent session's godot-mcp process, or set GODOT_MCP_PORT to move this one.",
    });
  }

  // 2. Editor connected
  const peerCount = godot.connectedPeerCount;
  if (peerCount === 1) {
    checks.push({ ok: true, label: "Editor connected", detail: "One Godot editor is connected." });
  } else if (peerCount > 1) {
    checks.push({
      ok: true,
      label: "Editor connected",
      detail: `${peerCount} Godot editors are connected — calls go to whichever answered first.`,
      suggestion: "Close the editors you are not driving to avoid ambiguity.",
    });
  } else {
    checks.push({
      ok: false,
      label: "Editor connected",
      detail: "No Godot editor connected.",
      suggestion: "Start Godot with the godot_mcp addon enabled (Project Settings → Plugins → godot-hands).",
    });
  }

  // 3. Addon version vs server version (this checkout only — see below)
  try {
    const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
    const pkg = JSON.parse(readFileSync(path.join(repoRoot, "package.json"), "utf8")) as { version?: string };
    const pluginCfg = readFileSync(path.join(repoRoot, "plugin", "plugin.cfg"), "utf8");
    const pluginVersionMatch = /version="([^"]+)"/.exec(pluginCfg);
    const pluginVersion = pluginVersionMatch?.[1];
    if (pkg.version && pluginVersion) {
      if (pkg.version === pluginVersion) {
        checks.push({
          ok: true,
          label: "Server/addon version match",
          detail: `Both report ${pkg.version} in this checkout.`,
        });
      } else {
        checks.push({
          ok: false,
          label: "Server/addon version match",
          detail: `package.json is ${pkg.version} but plugin/plugin.cfg is ${pluginVersion} in this checkout.`,
          suggestion: "One of the two wasn't bumped in the last release commit — check git history for the mismatch.",
        });
      }
    } else {
      checks.push({ ok: false, label: "Server/addon version match", detail: "Could not read one of the two version fields." });
    }
    checks.push({
      ok: true,
      label: "Addon freshness (informational)",
      detail: "This only compares the files bundled with this server checkout, not the copy inside your Godot project's addons/godot_mcp/.",
      suggestion: "After pulling an update, re-copy plugin/ over your project's addons/godot_mcp/ if you haven't already.",
    });
  } catch (err) {
    checks.push({
      ok: false,
      label: "Server/addon version match",
      detail: `Could not read package.json / plugin.cfg: ${(err as Error).message}`,
    });
  }

  // 4. Auth token / require_connection_token agreement
  const auth = godot.authStatus;
  const hasToken = getAuthToken() != null;
  if (!auth.required) {
    checks.push({
      ok: true,
      label: "Auth",
      detail: hasToken
        ? "A token is configured, but the editor hasn't asked for one (godot_mcp/require_connection_token is off, or no editor has connected yet)."
        : "No connection token required (godot_mcp/require_connection_token is off, or no editor has connected yet).",
    });
  } else if (auth.outcome === "ok") {
    checks.push({ ok: true, label: "Auth", detail: "The editor required a token and accepted ours." });
  } else if (auth.outcome === "no_token") {
    checks.push({
      ok: false,
      label: "Auth",
      detail: "The editor requires a connection token but none is configured on this server.",
      suggestion: "Set GODOT_MCP_TOKEN (the literal token) or GODOT_MCP_TOKEN_PATH (path to the token file, printed in the editor Output panel). See SECURITY.md.",
    });
  } else if (auth.outcome === "rejected") {
    checks.push({
      ok: false,
      label: "Auth",
      detail: "The editor required a token and rejected the one this server sent.",
      suggestion: "The configured token is stale or wrong — check GODOT_MCP_TOKEN(_PATH) against the editor's current token.",
    });
  } else {
    checks.push({ ok: false, label: "Auth", detail: "The editor requires a token but no auth attempt has completed yet." });
  }

  // 5. Live contract: methods this server calls by name must exist on the addon side
  if (peerCount > 0) {
    try {
      const known = await godot.listAllMethods();
      const missing = DOCTOR_REQUIRED_METHODS.filter((m) => !(m in known));
      if (missing.length === 0) {
        checks.push({ ok: true, label: "Live method contract", detail: "All methods this server depends on by name are registered." });
      } else {
        checks.push({
          ok: false,
          label: "Live method contract",
          detail: `The connected editor's addon is missing: ${missing.join(", ")}.`,
          suggestion: "The addon copy in your project is out of date — re-copy plugin/ over addons/godot_mcp/ and reload the project.",
        });
      }
      const undocumented = Object.values(known).filter((m) => !m.has_schema).length;
      checks.push({
        ok: true,
        label: "Method schema coverage",
        detail: `${Object.keys(known).length} methods registered, ${undocumented} without a schema.`,
      });
    } catch (err) {
      checks.push({ ok: false, label: "Live method contract", detail: `Could not query the editor: ${(err as Error).message}` });
    }
  } else {
    checks.push({ ok: false, label: "Live method contract", detail: "Skipped — no editor connected." });
  }

  // 5b. Degraded addon: modules that failed to load, or methods gated behind
  // a newer Godot than the connected editor — both fail soft on the addon
  // side (command_router.gd), so this is the only place either surfaces.
  if (peerCount > 0) {
    try {
      const info = await godot.call("get_available_methods") as {
        unavailable_modules?: Record<string, string>;
        version_gated?: Record<string, { min_godot: string; current: string }>;
        godot_version?: string;
      };
      const unavailable = Object.entries(info.unavailable_modules ?? {});
      const gated = Object.entries(info.version_gated ?? {});
      if (unavailable.length === 0 && gated.length === 0) {
        checks.push({
          ok: true,
          label: "Addon module health",
          detail: `All command modules loaded on Godot ${info.godot_version ?? "unknown"}.`,
        });
      } else {
        const parts: string[] = [];
        if (unavailable.length > 0) {
          parts.push(`${unavailable.length} module(s) failed to load: ${unavailable.map(([m, reason]) => `${m} (${reason})`).join("; ")}`);
        }
        if (gated.length > 0) {
          parts.push(`${gated.length} method(s) version-gated on Godot ${info.godot_version}: ${gated.map(([m, g]) => `${m} (needs ${g.min_godot})`).join("; ")}`);
        }
        checks.push({
          ok: false,
          label: "Addon module health",
          detail: parts.join(" | "),
          suggestion: unavailable.length > 0
            ? "A module failed to parse — check the Godot editor's Output panel at startup for the exact error."
            : "Upgrade Godot to reach the gated methods, or ignore them if you don't need that feature.",
        });
      }
    } catch (err) {
      checks.push({ ok: false, label: "Addon module health", detail: `Could not query the editor: ${(err as Error).message}` });
    }
  }

  // 6. Godot binary resolvable, for npm run test:godot
  const bin = resolveGodotBinary();
  if (bin.found) {
    checks.push({ ok: true, label: "Godot binary (for test:godot)", detail: `Found ${bin.path}: ${bin.version}.` });
  } else {
    checks.push({
      ok: false,
      label: "Godot binary (for test:godot)",
      detail: "No Godot binary found on PATH as 'godot4' or 'godot', and GODOT_BIN is unset.",
      suggestion: "Set GODOT_BIN to a Godot 4 executable if you want to run npm run test:godot locally.",
    });
  }

  return checks;
}

interface PeerInfo { projectPath: string; projectName: string; godotVersion: string }

export class GodotBridge {
  private server: http.Server | null = null;
  private port = 0;
  private peers = new Set<Duplex>();
  private bufs = new Map<Duplex, Buffer>();
  private pending = new Map<number, Pending>();
  private authPending = new Set<number>();
  private nextId = 1;
  private peerInfo = new Map<Duplex, PeerInfo>();
  private activePeer: Duplex | null = null;

  // Auth outcome tracking for godot_doctor — previously an auth mismatch
  // (server has no token configured, or the editor rejected the one it got)
  // was only ever logged to stderr and never surfaced to a tool caller.
  private authRequired = false;
  private authOutcome: "ok" | "no_token" | "rejected" | null = null;

  get authStatus(): { required: boolean; outcome: "ok" | "no_token" | "rejected" | null } {
    return { required: this.authRequired, outcome: this.authOutcome };
  }

  get boundPort(): number {
    return this.port;
  }

  get connectedPeerCount(): number {
    return this.peers.size;
  }

  // The addon is the source of truth for its own method schemas (see
  // command_router.gd describe_methods/describe_method) — these caches just
  // avoid a round trip on every godot_call. They're invalidated whenever a
  // peer (re)connects, since that's the only time the schemas could have
  // changed (a different/updated addon build).
  private methodListCache: Record<string, MethodSummary> | null = null;
  private schemaCache = new Map<string, unknown>();

  private invalidateSchemaCache(): void {
    this.methodListCache = null;
    this.schemaCache.clear();
  }

  async listAllMethods(): Promise<Record<string, MethodSummary>> {
    if (!this.methodListCache) {
      this.methodListCache = await this.call("describe_methods", {}) as Record<string, MethodSummary>;
    }
    return this.methodListCache;
  }

  async describeMethod(name: string): Promise<unknown> {
    if (!this.schemaCache.has(name)) {
      const result = await this.call("describe_method", { methods: [name] }) as Record<string, unknown>;
      this.schemaCache.set(name, result[name]);
    }
    return this.schemaCache.get(name);
  }

  // One port per instance is the contract the Godot addon expects: it dials
  // every port in the range and keeps a socket per server it finds
  // (plugin/websocket_server.gd). Binding the whole range from a single
  // instance broke it both ways — the second instance died on an unhandled
  // EADDRINUSE, so any second agent session silently had no Godot tools at
  // all, and the first instance sat on nine ports it never used.
  async start(): Promise<void> {
    for (const port of ALL_PORTS) {
      if (await this.listenOn(port)) return;
    }
    console.error(
      `godot-mcp: ports ${ALL_PORTS[0]}-${ALL_PORTS[ALL_PORTS.length - 1]} are all taken, ` +
      `so this instance has no channel to the editor. Close an unused agent session, ` +
      `or move this one with GODOT_MCP_PORT.`
    );
  }

  private listenOn(port: number): Promise<boolean> {
    return new Promise((resolve) => {
      const srv = http.createServer();
      let bound = false;
      srv.on("upgrade", (req, socket) => {
        const key = req.headers["sec-websocket-key"];
        if (!key) { socket.destroy(); return; }
        socket.write(
          "HTTP/1.1 101 Switching Protocols\r\n" +
          "Upgrade: websocket\r\n" +
          "Connection: Upgrade\r\n" +
          "Sec-WebSocket-Accept: " + wsAccept(key) + "\r\n\r\n"
        );
        // Keyed by socket, not by port: two editors reaching the same port used
        // to overwrite each other in the map, leaking the first socket.
        this.peers.add(socket);
        this.bufs.set(socket, Buffer.alloc(0));
        this.invalidateSchemaCache();
        socket.on("data", (chunk) => this.onData(socket, chunk));
        const forget = () => {
          this.peers.delete(socket); this.bufs.delete(socket); this.peerInfo.delete(socket);
          if (this.activePeer === socket) this.activePeer = null;
        };
        socket.on("close", forget);
        socket.on("error", forget);
      });
      // Without this listener a busy port throws out of the event loop and
      // takes the whole MCP process down.
      srv.on("error", (err: NodeJS.ErrnoException) => {
        if (bound) { console.error(`godot-mcp: server error on port ${port}: ${err.message}`); return; }
        srv.close();
        resolve(false);
      });
      srv.listen(port, "127.0.0.1", () => {
        bound = true;
        this.server = srv;
        this.port = port;
        resolve(true);
      });
    });
  }

  stop(): void {
    for (const [, p] of this.pending) { clearTimeout(p.timer); p.reject(new Error("Server shutting down")); }
    this.pending.clear();
    this.server?.close();
    this.server = null;
    for (const sock of this.peers) sock.destroy();
    this.peers.clear();
    this.bufs.clear();
    this.invalidateSchemaCache();
  }

  get connected(): boolean {
    return this.peers.size > 0;
  }

  get status(): string {
    if (!this.server) {
      return `No port bound — ${ALL_PORTS[0]}-${ALL_PORTS[ALL_PORTS.length - 1]} were all busy. ` +
        `Every agent session needs a free port; close an unused one or set GODOT_MCP_PORT.`;
    }
    if (this.peers.size === 0) {
      return `Listening on port ${this.port}, no Godot editor connected — ` +
        `start Godot with the godot_mcp plugin enabled.`;
    }
    if (this.peers.size === 1) return `Connected to the Godot editor on port ${this.port}.`;
    const peers = this.listPeers();
    const lines = peers.map((p) =>
      `  ${p.active ? "*" : " "} ${p.projectName || "(unidentified)"} — ${p.projectPath || "no project path reported"}`
    );
    return `${this.peers.size} Godot editors are connected on port ${this.port}:\n${lines.join("\n")}\n` +
      (this.activePeer
        ? `Calls go to the pinned editor (*).`
        : `No editor pinned — calls go to whichever is first. Pin one with godot_status {"select":"<project name>"}.`);
  }

  /** The pinned peer if it's still connected, else any peer. */
  private selectPeer(): Duplex {
    if (this.activePeer && this.peers.has(this.activePeer)) return this.activePeer;
    this.activePeer = null;
    return this.peers.values().next().value as Duplex;
  }

  listPeers(): (PeerInfo & { active: boolean })[] {
    return [...this.peers].map((sock) => ({
      projectPath: "", projectName: "", godotVersion: "",
      ...(this.peerInfo.get(sock) ?? {}),
      active: sock === this.activePeer,
    }));
  }

  /** Pin the editor whose project name or path contains `needle`. */
  selectByProject(needle: string): boolean {
    const lower = needle.toLowerCase();
    for (const sock of this.peers) {
      const info = this.peerInfo.get(sock);
      if (!info) continue;
      if (info.projectName.toLowerCase().includes(lower) || info.projectPath.toLowerCase().includes(lower)) {
        this.activePeer = sock;
        return true;
      }
    }
    return false;
  }

  async call(method: string, params?: Record<string, unknown>, timeoutMs = REQUEST_TIMEOUT): Promise<unknown> {
    if (!this.connected) throw new Error("Godot editor not connected — is the plugin enabled and Godot running?");
    const peer = this.selectPeer();
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Request "${method}" timed out after ${timeoutMs / 1000}s`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      wsSend(peer, JSON.stringify({ jsonrpc: "2.0", id, method, params: params ?? {} }));
    });
  }

  // ponytail: in-memory only, lost on server restart. A job can't outlive the
  // session that started it anyway, so persisting it would buy nothing.
  private jobs = new Map<string, JobRecord>();
  private nextJobId = 1;

  startJob(method: string, params: Record<string, unknown>): string {
    const id = `job-${this.nextJobId++}`;
    this.jobs.set(id, { status: "running", method, started: Date.now() });
    // Deliberately not awaited: the point is to return the handle now.
    this.call(method, params, JOB_TIMEOUT).then(
      (result) => this.jobs.set(id, { ...this.jobs.get(id)!, status: "done", result }),
      (err: Error) => this.jobs.set(id, { ...this.jobs.get(id)!, status: "error", error: err.message }),
    );
    return id;
  }

  getJob(id: string): JobRecord | undefined {
    return this.jobs.get(id);
  }

  private onData(socket: Duplex, chunk: Buffer): void {
    let buf = Buffer.concat([this.bufs.get(socket)!, chunk]);
    while (true) {
      const frame = decodeFrame(buf);
      if (!frame) break;
      buf = buf.subarray(frame.total);

      if (frame.opcode === 0x8) return; // close
      if (frame.opcode === 0x9) { // ping
        const pong = Buffer.alloc(2);
        pong[0] = 0x8a; pong[1] = 0;
        socket.write(pong);
        continue;
      }
      if (frame.opcode !== 0x1) continue; // not text

      const text = frame.payload.toString("utf8");
      this.dispatch(socket, text);
    }
    this.bufs.set(socket, buf);
  }

  private dispatch(socket: Duplex, text: string): void {
    let msg: Record<string, unknown>;
    try { msg = JSON.parse(text); } catch { return; }

    if (msg.method === "hello") {
      // Sent unconditionally by the addon on connect. Its absence is normal
      // for an older addon build — those peers simply stay anonymous and the
      // bridge behaves exactly as it did before.
      const p = (msg.params ?? {}) as Record<string, unknown>;
      this.peerInfo.set(socket, {
        projectPath: String(p.project_path ?? ""),
        projectName: String(p.project_name ?? ""),
        godotVersion: String(p.godot_version ?? ""),
      });
      return;
    }

    if (msg.method === "ping") {
      // Godot's own heartbeat (plugin/websocket_server.gd PING_INTERVAL) sends
      // this as an id-less notification. It previously went unanswered, so
      // Godot never saw a reply packet and force-closed the socket as stale
      // every INACTIVITY_TIMEOUT even on a perfectly healthy connection.
      if (msg.id != null) wsSend(socket, JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: { pong: true } }));
      else wsSend(socket, JSON.stringify({ jsonrpc: "2.0", method: "pong", params: {} }));
      return;
    }

    if (msg.method === "auth_required") {
      // Sent when godot_mcp/require_connection_token is on. Previously
      // ignored entirely, so Godot closed the peer after its AUTH_TIMEOUT and
      // the bridge reconnect-looped forever with no working tools.
      this.authRequired = true;
      const token = getAuthToken();
      if (!token) {
        this.authOutcome = "no_token";
        console.error(
          "godot-mcp: the Godot editor requires a connection token but none is configured. " +
          "Set GODOT_MCP_TOKEN (the literal token) or GODOT_MCP_TOKEN_PATH (path to the token " +
          "file, printed in the editor Output panel). See SECURITY.md."
        );
        return;
      }
      const id = this.nextId++;
      this.authPending.add(id);
      wsSend(socket, JSON.stringify({ jsonrpc: "2.0", id, method: "auth", params: { token } }));
      return;
    }

    if (msg.method === "pong" || msg.method === "auth") return;

    if (typeof msg.id === "number" && this.authPending.has(msg.id)) {
      this.authPending.delete(msg.id);
      if (msg.error) {
        this.authOutcome = "rejected";
        console.error(`godot-mcp: auth rejected by editor: ${JSON.stringify(msg.error)}`);
      } else {
        this.authOutcome = "ok";
      }
      return;
    }

    if (typeof msg.id === "number" && this.pending.has(msg.id)) {
      const { resolve, reject, timer } = this.pending.get(msg.id)!;
      clearTimeout(timer);
      this.pending.delete(msg.id);
      if (msg.error) reject(new Error(typeof msg.error === "object" ? JSON.stringify(msg.error) : String(msg.error)));
      else resolve(msg.result);
    }
  }
}

const godot = new GodotBridge();

export const server = new Server(
  { name: "godot-hands", version: "1.0.0" },
  { capabilities: { tools: {}, resources: {}, prompts: {} } },
);

export const TOOL_DEFS = [
  {
    name: "godot_call",
    description:
      "Call any method on the Godot editor addon. See godot_list_methods to browse what's available and " +
      "godot_describe for a method's full parameter schema. Any 'node_path' parameter also accepts a session " +
      "handle (the \"@id:...\" string returned as \"handle\" by get_scene_tree, add_node, and similar methods) " +
      "instead of a path — a handle keeps addressing the same node across a rename or reparent, where a path " +
      "would break. Handles go stale when the scene is reloaded/reopened; get_scene_tree again for fresh ones.",
    inputSchema: {
      type: "object",
      properties: {
        method: { type: "string", description: "Method name, e.g. get_project_info, get_scene_tree, add_node" },
        params: { type: "object", description: "Parameters for the method (varies per method)" },
        async: { type: "boolean", description: "Return a job_id immediately instead of blocking. Use for long operations (run_stress_test, run_test_scenario, bake_navigation_mesh, headless commands) which otherwise exceed the 30s request timeout. Poll the result with godot_job." },
      },
      required: ["method"],
    },
    // A generic passthrough can invoke anything the addon exposes, including
    // destructive methods (delete_node, export_project, ...) — annotate
    // conservatively rather than claim a safety this tool can't guarantee.
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true },
  },
  {
    name: "godot_list_methods",
    description: "List available Godot addon methods, live from the connected editor. Call with no arguments for category counts, or with a category to list its methods and one-line summaries.",
    inputSchema: {
      type: "object",
      properties: {
        category: { type: "string", description: "Optional category filter, e.g. project, scene, node, script, editor, 3d, physics — call with no category first to see what's available" },
      },
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true },
  },
  {
    name: "godot_describe",
    description: "Get the full parameter schema (types, required/optional, defaults, annotations) for one or more godot_call methods.",
    inputSchema: {
      type: "object",
      properties: {
        methods: { type: "array", items: { type: "string" }, description: "Method names, e.g. [\"add_node\", \"update_property\"]" },
      },
      required: ["methods"],
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true },
  },
  {
    name: "godot_info",
    description: "Get project info from the Godot editor (shorthand for godot_call method=get_project_info).",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true },
  },
  {
    name: "godot_screenshot",
    description: "Capture the Godot editor viewport. Returns base64 PNG image data.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true },
  },
  {
    name: "godot_execute",
    description: "Execute GDScript code in the Godot editor (shorthand for godot_call method=execute_editor_script).",
    inputSchema: {
      type: "object",
      properties: {
        code: { type: "string", description: "GDScript code to execute in the editor" },
      },
      required: ["code"],
    },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true },
  },
  {
    name: "godot_status",
    description: "Check connection status to the Godot editor. With 'select', pins which editor subsequent calls go to when several are connected.",
    inputSchema: {
      type: "object",
      properties: {
        select: { type: "string", description: "Project name or path fragment of the editor to pin for subsequent calls" },
      },
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  {
    name: "godot_job",
    description: "Check an async job started by godot_call with async:true. Returns its status and, once finished, its result or error.",
    inputSchema: {
      type: "object",
      properties: { job_id: { type: "string", description: "The job_id returned by godot_call" } },
      required: ["job_id"],
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  {
    name: "godot_doctor",
    description: "Diagnose the MCP bridge end-to-end (port, editor connection, auth, addon/server contract, Godot binary for headless tests) with a checklist and fix suggestions for anything failing.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  {
    name: "godot_assets",
    description:
      "Search, preview, and import free CC0 3D assets (Poly Haven, ambientCG) straight into the Godot project. " +
      "'search' finds candidates by name/tag; 'preview' returns a thumbnail so you can pick by sight instead of " +
      "guessing from an id; 'import' downloads into res://assets/<provider>/<id>/ and rescans the project filesystem.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["search", "preview", "import"] },
        query: { type: "string", description: "search: text matched against name/tags/categories" },
        provider: { type: "string", enum: ["polyhaven", "ambientcg"], description: "Restrict to one provider; omit to use both (search) or when unambiguous" },
        type: { type: "string", description: "search: provider-specific category filter — 'hdris'/'textures'/'models' for Poly Haven, 'Material'/'HDRI'/'Decal'/etc. for ambientCG" },
        limit: { type: "number", description: "search: max results, default 20" },
        id: { type: "string", description: "preview/import: an asset id from a prior search result" },
        resolution: { type: "string", description: "import: resolution to fetch, e.g. '1k'/'2k' (Poly Haven) or '1K'/'2K' (ambientCG); a small default is used if omitted" },
        format: { type: "string", description: "import, Poly Haven only: file format to fetch, e.g. 'jpg'/'exr'/'gltf'; a sensible default is used if omitted" },
      },
      required: ["action"],
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true },
  },
];

// Grouped counts only — the full per-method listing is fetched live from the
// addon (describe_methods) so this never drifts from what's actually
// registered, unlike the old hand-maintained METHOD_CATALOG it replaces.
function summarizeCategories(all: Record<string, MethodSummary>): string {
  const counts = new Map<string, number>();
  for (const m of Object.values(all)) {
    const cat = m.category || "(uncategorized)";
    counts.set(cat, (counts.get(cat) ?? 0) + 1);
  }
  const lines = [...counts.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([cat, n]) => `${cat} (${n})`);
  return `${Object.keys(all).length} methods across ${counts.size} categories. ` +
    `Call godot_list_methods again with one of these categories to list its methods.\n\n${lines.join(", ")}`;
}

// --- MCP resources ---------------------------------------------------------
// Unlike tools, resources cost nothing in the tool-listing window — the model
// only pays for one it actually reads. These mirror the addon's own
// read-only methods so an agent can pull project/scene state as ambient
// context instead of spending a tool call on it.

interface ResourceDef {
  uri: string;
  name: string;
  description: string;
  mimeType: string;
  fetch: () => Promise<unknown>;
}

export const RESOURCE_DEFS: ResourceDef[] = [
  {
    uri: "godot://scene/current",
    name: "Current scene tree",
    description: "The node tree of the scene currently open in the editor (see get_scene_tree).",
    mimeType: "application/json",
    fetch: () => godot.call("get_scene_tree"),
  },
  {
    uri: "godot://project/info",
    name: "Project info",
    description: "Project name, Godot version, path, main scene, viewport/window size, renderer, autoloads.",
    mimeType: "application/json",
    fetch: () => godot.call("get_project_info"),
  },
  {
    uri: "godot://project/settings",
    name: "Project settings",
    description: "All ProjectSettings key/value pairs (see get_project_settings).",
    mimeType: "application/json",
    fetch: () => godot.call("get_project_settings"),
  },
  {
    uri: "godot://logs/recent",
    name: "Recent editor output",
    description: "The last lines of the editor's Output panel (see get_output_log).",
    mimeType: "text/plain",
    fetch: async () => {
      const result = await godot.call("get_output_log", { max_lines: 200 }) as Record<string, unknown>;
      return result?.log ?? result?.lines ?? result;
    },
  },
];

// ClassDB reflection never changes mid-session (the engine's own classes are
// fixed once Godot starts), so this is the one resource worth caching —
// everything else above reflects live, frequently-changing editor state.
const CLASS_RESOURCE_TTL_MS = 5 * 60_000;
const classResourceCache = new Map<string, { value: unknown; at: number }>();

async function readClassResource(className: string): Promise<unknown> {
  const cached = classResourceCache.get(className);
  if (cached && Date.now() - cached.at < CLASS_RESOURCE_TTL_MS) return cached.value;
  const value = await godot.call("classdb_describe", { class_name: className });
  classResourceCache.set(className, { value, at: Date.now() });
  return value;
}

server.setRequestHandler(ListResourcesRequestSchema, async () => ({
  resources: RESOURCE_DEFS.map(({ uri, name, description, mimeType }) => ({ uri, name, description, mimeType })),
}));

server.setRequestHandler(ListResourceTemplatesRequestSchema, async () => ({
  resourceTemplates: [
    {
      uriTemplate: "godot://class/{name}",
      name: "ClassDB class reflection",
      description: "Properties, methods, signals, enums, and inheritance for a Godot engine class, e.g. godot://class/RigidBody3D.",
      mimeType: "application/json",
    },
  ],
}));

server.setRequestHandler(ReadResourceRequestSchema, async (req) => {
  const { uri } = req.params;
  const classMatch = /^godot:\/\/class\/(.+)$/.exec(uri);
  if (classMatch) {
    const value = await readClassResource(decodeURIComponent(classMatch[1]));
    return { contents: [{ uri, mimeType: "application/json", text: JSON.stringify(value, null, 2) }] };
  }
  const def = RESOURCE_DEFS.find((r) => r.uri === uri);
  if (!def) throw new Error(`Unknown resource: ${uri}`);
  const value = await def.fetch();
  const text = def.mimeType === "text/plain" && typeof value === "string" ? value : JSON.stringify(value, null, 2);
  return { contents: [{ uri, mimeType: def.mimeType, text }] };
});

// --- MCP prompts -------------------------------------------------------
// Reusable task templates for the workflows this server was actually built
// to support — surfaced so a client can offer them as slash-command-like
// shortcuts instead of the user having to describe the whole workflow.

interface PromptDef {
  name: string;
  description: string;
  arguments: { name: string; description: string; required: boolean }[];
  render: (args: Record<string, string>) => string;
}

export const PROMPT_DEFS: PromptDef[] = [
  {
    name: "blockout-3d-level",
    description: "Block out a 3D level with CSG primitives, checking the result visually as you go.",
    arguments: [
      { name: "brief", description: "What to build, e.g. 'a small courtyard with two raised platforms'", required: true },
    ],
    render: (args) =>
      `Block out this 3D level: ${args.brief}\n\n` +
      `Work iteratively and check your work visually — don't place more than a couple of pieces blind:\n` +
      `1. Use get_spatial_bounds on the scene root to see what's already there.\n` +
      `2. Add grey-box geometry with add_csg_shape (box/cylinder/sphere/combiner with boolean operations).\n` +
      `3. Use align_nodes / distribute_nodes / snap_to_ground to place pieces without overlap or floating gaps.\n` +
      `4. After a few pieces, call turntable_screenshot on the new geometry to see it from multiple angles — ` +
      `look for interpenetration, floating objects, or wrong scale before continuing.\n` +
      `5. Repeat until the brief is met, then take a final turntable_screenshot of the whole scene.`,
  },
  {
    name: "diagnose-crash",
    description: "Investigate an editor error or crash using the output log and project state.",
    arguments: [
      { name: "symptom", description: "What went wrong, e.g. 'editor freezes when I open Level3.tscn'", required: true },
    ],
    render: (args) =>
      `Diagnose this problem: ${args.symptom}\n\n` +
      `1. Read godot://logs/recent (or godot_call get_output_log with a larger max_lines) for the actual error/stack.\n` +
      `2. If the error names a class or method you don't recognize, look it up with godot://class/{name} ` +
      `or godot_call classdb_describe rather than guessing.\n` +
      `3. Use search_in_files to find where the offending code or node path is referenced.\n` +
      `4. Cross-check against get_scene_tree / get_node_properties for the scene involved.\n` +
      `Report the root cause before proposing a fix.`,
  },
  {
    name: "audit-scene-perf",
    description: "Audit a scene for common performance issues (draw calls, LOD, unbounded lights, missing culling).",
    arguments: [
      { name: "scene_path", description: "Scene to audit; omit for the currently edited scene", required: false },
    ],
    render: (args) =>
      `Audit ${args.scene_path ? `the scene at ${args.scene_path}` : "the currently edited scene"} for performance issues.\n\n` +
      `1. Walk get_scene_tree and count nodes per type — flag large numbers of individual MeshInstance3D nodes ` +
      `that could be collapsed into a single MultiMeshInstance3D.\n` +
      `2. For 3D scenes, check get_spatial_bounds on major subtrees and look for objects without visibility_range ` +
      `set despite being far from the camera's typical path.\n` +
      `3. Flag lights and ReflectionProbes with unbounded or very large ranges.\n` +
      `4. Check classdb_describe on any custom/unusual node types found, to understand what they cost.\n` +
      `Summarize findings as a prioritized list, most expensive first — don't apply fixes without confirming.`,
  },
  {
    name: "asset-strategy",
    description: "Decide whether to source a free CC0 asset or generate primitives/procedural geometry for a given need.",
    arguments: [
      { name: "need", description: "What's needed, e.g. 'a rusty barrel prop' or 'a rock texture for the courtyard floor'", required: true },
    ],
    render: (args) =>
      `Decide how to get this: ${args.need}\n\n` +
      `Prefer a real CC0 asset over hand-built geometry whenever one exists and fits — it will look better ` +
      `and cost less effort than modeling from primitives:\n` +
      `1. Search first: godot_assets {action: "search", query: "..."} across Poly Haven (models/HDRIs/textures) ` +
      `and ambientCG (PBR materials).\n` +
      `2. Preview 2-3 candidates (godot_assets {action: "preview", ...}) before picking — don't import blind.\n` +
      `3. Only fall back to CSG primitives / procedural placement (add_csg_shape, add_multimesh_scatter) when ` +
      `nothing suitable turns up, or the need is genuinely abstract (blockout geometry, gameplay volumes).\n` +
      `4. On import, note the dest_dir and NOTICE.txt path in your response so the source is traceable.`,
  },
];

server.setRequestHandler(ListPromptsRequestSchema, async () => ({
  prompts: PROMPT_DEFS.map(({ name, description, arguments: args }) => ({ name, description, arguments: args })),
}));

server.setRequestHandler(GetPromptRequestSchema, async (req) => {
  const def = PROMPT_DEFS.find((p) => p.name === req.params.name);
  if (!def) throw new Error(`Unknown prompt: ${req.params.name}`);
  const args = (req.params.arguments ?? {}) as Record<string, string>;
  const missing = def.arguments.filter((a) => a.required && !args[a.name]);
  if (missing.length) throw new Error(`Missing required argument(s): ${missing.map((a) => a.name).join(", ")}`);
  return {
    description: def.description,
    messages: [{ role: "user", content: { type: "text", text: def.render(args) } }],
  };
});

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOL_DEFS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;
  try {
    switch (name) {
      case "godot_call": {
        const method = args?.method as string;
        if (!method) throw new Error("method is required");
        const params = (args?.params ?? {}) as Record<string, unknown>;

        // Best-effort validation against the addon's own live schemas — never
        // blocks the call if the schema fetch itself fails (disconnected, or
        // an older addon build that predates describe_methods/describe_method:
        // this just degrades to the old unvalidated passthrough rather than
        // resurrecting a hand-maintained catalog that would drift again).
        const known = await godot.listAllMethods().catch(() => null);
        if (known && !(method in known)) {
          const suggestion = suggestMethod(method, Object.keys(known));
          throw new Error(
            `Unknown method "${method}".${suggestion ? ` Did you mean "${suggestion}"?` : ""} ` +
            `Use godot_list_methods to browse available methods.`
          );
        }
        if (known) {
          const schema = await godot.describeMethod(method).catch(() => null) as
            { params?: Record<string, { required?: boolean }> } | null;
          const requiredParams = schema?.params
            ? Object.entries(schema.params).filter(([, spec]) => spec.required).map(([key]) => key)
            : [];
          const missing = requiredParams.filter((key) => !(key in params));
          if (missing.length) {
            throw new Error(
              `Missing required parameter(s) for "${method}": ${missing.join(", ")}. ` +
              `Use godot_describe {"methods":["${method}"]} to see the full schema.`
            );
          }
        }

        if (args?.async) {
          const jobId = godot.startJob(method, params);
          return { content: [{ type: "text", text: JSON.stringify({ job_id: jobId, status: "running", method }, null, 2) }] };
        }
        const result = await godot.call(method, params);
        return { content: [{ type: "text", text: truncateOutput(JSON.stringify(result, null, 2)) }] };
      }
      case "godot_list_methods": {
        const filter = args?.category as string | undefined;
        const all = await godot.listAllMethods();
        if (!filter) {
          return { content: [{ type: "text", text: summarizeCategories(all) }] };
        }
        const entries = Object.entries(all)
          .filter(([, m]) => m.category === filter)
          .sort(([a], [b]) => a.localeCompare(b));
        if (!entries.length) {
          return { content: [{ type: "text", text: `No methods in category "${filter}".\n\n${summarizeCategories(all)}` }] };
        }
        const lines = entries.map(([name, m]) => `${name} — ${m.summary || "(no summary yet)"}`);
        return { content: [{ type: "text", text: `${entries.length} methods in "${filter}":\n\n${lines.join("\n")}` }] };
      }
      case "godot_describe": {
        const methods = args?.methods as string[] | undefined;
        if (!Array.isArray(methods) || methods.length === 0) throw new Error("methods (a non-empty array of method names) is required");
        const result = await godot.call("describe_method", { methods }) as Record<string, unknown>;
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      }
      case "godot_info": {
        const result = await godot.call("get_project_info");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      }
      case "godot_screenshot": {
        const result = await godot.call("get_editor_screenshot") as Record<string, unknown>;
        const base64 = result?.image_base64 as string;
        if (base64) {
          return { content: [
            { type: "text", text: `Screenshot: ${result.width}x${result.height} PNG` },
            { type: "image", data: base64, mimeType: "image/png" },
          ]};
        }
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      }
      case "godot_execute": {
        const code = args?.code as string;
        if (!code) throw new Error("code is required");
        const result = await godot.call("execute_editor_script", { code });
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      }
      case "godot_status": {
        const select = args?.select as string | undefined;
        if (select) {
          if (!godot.selectByProject(select)) {
            const names = godot.listPeers().map((p) => p.projectName || p.projectPath || "(unidentified)");
            throw new Error(
              `No connected editor matches "${select}". Connected: ${names.join(", ") || "none"}. ` +
              `Editors running an addon build older than this server report no project identity and cannot be pinned.`
            );
          }
        }
        return { content: [{ type: "text", text: godot.status }] };
      }
      case "godot_job": {
        const jobId = args?.job_id as string;
        if (!jobId) throw new Error("job_id is required");
        const job = godot.getJob(jobId);
        if (!job) throw new Error(`Unknown job "${jobId}". Jobs live in memory and are lost if the server restarts.`);
        return { content: [{ type: "text", text: truncateOutput(JSON.stringify({
          job_id: jobId,
          status: job.status,
          method: job.method,
          elapsed_ms: Date.now() - job.started,
          ...(job.result !== undefined ? { result: job.result } : {}),
          ...(job.error !== undefined ? { error: job.error } : {}),
        }, null, 2)) }] };
      }
      case "godot_doctor": {
        const checks = await runDoctor();
        const lines = checks.map((c) => {
          const mark = c.ok ? "✅" : "❌";
          let line = `${mark} ${c.label}: ${c.detail}`;
          if (c.suggestion) line += `\n   → ${c.suggestion}`;
          return line;
        });
        const failCount = checks.filter((c) => !c.ok).length;
        const summary = failCount === 0 ? "All checks passed." : `${failCount} check(s) need attention.`;
        return { content: [{ type: "text", text: `${summary}\n\n${lines.join("\n")}` }] };
      }
      case "godot_assets": {
        const action = args?.action as string;
        switch (action) {
          case "search": {
            const query = (args?.query as string) ?? "";
            const provider = args?.provider as AssetProvider | undefined;
            const type = args?.type as string | undefined;
            const limit = args?.limit as number | undefined;
            const results = await searchAssets(query, { provider, type, limit });
            return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] };
          }
          case "preview": {
            const provider = args?.provider as AssetProvider;
            const id = args?.id as string;
            if (!provider || !id) throw new Error("godot_assets preview requires 'provider' and 'id'");
            const buf = await getAssetThumbnail(provider, id);
            return { content: [
              { type: "text", text: `${provider}/${id} thumbnail` },
              { type: "image", data: buf.toString("base64"), mimeType: "image/png" },
            ]};
          }
          case "import": {
            const provider = args?.provider as AssetProvider;
            const id = args?.id as string;
            if (!provider || !id) throw new Error("godot_assets import requires 'provider' and 'id'");
            // Downloads can take a while on a slow connection; report progress
            // if the client asked for it (request _meta.progressToken), and
            // silently skip otherwise — this is optional per the MCP spec.
            const progressToken = (req.params as { _meta?: { progressToken?: string | number } })._meta?.progressToken;
            const reportProgress = (progress: number, total: number, message: string) =>
              progressToken != null
                ? server.notification({ method: "notifications/progress", params: { progressToken, progress, total, message } }).catch(() => {})
                : Promise.resolve();
            await reportProgress(0, 3, `Locating ${provider}/${id}`);
            const info = await godot.call("get_project_info") as { project_path?: string };
            if (!info?.project_path) {
              throw new Error("Could not determine the Godot project path (get_project_info returned none) — is the editor connected?");
            }
            const resolution = args?.resolution as string | undefined;
            const format = args?.format as string | undefined;
            await reportProgress(1, 3, `Downloading ${provider}/${id}`);
            const result = await importAsset(provider, id, info.project_path, { resolution, format });
            await reportProgress(2, 3, "Rescanning project filesystem");
            // Best-effort: the import already succeeded and wrote real files
            // on disk regardless of whether the rescan itself goes through.
            await godot.call("reload_project").catch(() => {});
            await reportProgress(3, 3, "Done");
            return { content: [{ type: "text", text: JSON.stringify({
              provider,
              id,
              files_written: result.files.length,
              total_bytes: result.files.reduce((sum, f) => sum + f.bytes, 0),
              dest_dir: result.destDir,
              notice: result.noticePath,
            }, null, 2) }] };
          }
          default:
            throw new Error(`Unknown action '${action}' for godot_assets — use search, preview, or import`);
        }
      }
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : typeof err === "object" && err !== null ? JSON.stringify(err) : String(err);
    return { content: [{ type: "text", text: `Error: ${message}` }], isError: true };
  }
});

async function main() {
  await godot.start();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

export function installAddon(projectDir: string): string {
  const pluginSrc = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "plugin");
  const dest = path.resolve(projectDir, "addons", "godot_mcp");
  cpSync(pluginSrc, dest, { recursive: true });
  return dest;
}

// Only run the server when this file is the process entrypoint, not when a
// test suite imports it for its pure helpers (wsAccept/wsSend/decodeFrame/
// GodotBridge) — otherwise every test run would bind real ports and attach a
// real stdio transport.
const isEntrypoint = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isEntrypoint) {
  if (process.argv[2] === "install") {
    const target = process.argv[3];
    if (!target) {
      console.error("Usage: godot-hands install <path/to/godot/project>");
      process.exit(1);
    }
    try {
      const dest = installAddon(target);
      console.log(`Godot addon installed at ${dest}`);
      console.log("Enable it in the editor: Project → Project Settings → Plugins → godot-hands.");
    } catch (err) {
      console.error(`godot-mcp: install failed: ${(err as Error).message}`);
      process.exit(1);
    }
  } else {
    main().catch((err) => { console.error("Fatal:", err); process.exit(1); });
  }
}
