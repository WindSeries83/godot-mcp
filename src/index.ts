#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import http from "node:http";
import crypto from "node:crypto";
import { Duplex } from "node:stream";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { searchAssets, getAssetThumbnail, importAsset, type AssetProvider } from "./assets/index.js";

const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const BASE_PORT = parseInt(process.env.GODOT_MCP_PORT ?? "6505", 10);
const ALL_PORTS = Array.from({ length: 10 }, (_, i) => BASE_PORT + i);
const REQUEST_TIMEOUT = 30_000;

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

export class GodotBridge {
  private server: http.Server | null = null;
  private port = 0;
  private peers = new Set<Duplex>();
  private bufs = new Map<Duplex, Buffer>();
  private pending = new Map<number, Pending>();
  private authPending = new Set<number>();
  private nextId = 1;

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
        socket.on("close", () => { this.peers.delete(socket); this.bufs.delete(socket); });
        socket.on("error", () => { this.peers.delete(socket); this.bufs.delete(socket); });
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
    // ponytail: the protocol carries no project identity, so a second editor on
    // this port gets reported rather than routed — a call could otherwise land
    // in the wrong project with nothing to show for it. Upgrade: have the addon
    // announce its project path on connect and select the peer by project.
    return `${this.peers.size} Godot editors are connected on port ${this.port} — calls go to ` +
      `whichever answered first. Close the editors you are not driving.`;
  }

  async call(method: string, params?: Record<string, unknown>): Promise<unknown> {
    if (!this.connected) throw new Error("Godot editor not connected — is the plugin enabled and Godot running?");
    const peer = this.peers.values().next().value as Duplex;
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Request "${method}" timed out after ${REQUEST_TIMEOUT / 1000}s`));
      }, REQUEST_TIMEOUT);
      this.pending.set(id, { resolve, reject, timer });
      wsSend(peer, JSON.stringify({ jsonrpc: "2.0", id, method, params: params ?? {} }));
    });
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
      const token = getAuthToken();
      if (!token) {
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
        console.error(`godot-mcp: auth rejected by editor: ${JSON.stringify(msg.error)}`);
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

const server = new Server(
  { name: "godot-mcp", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

const TOOL_DEFS = [
  {
    name: "godot_call",
    description: "Call any method on the Godot editor addon. See godot_list_methods to browse what's available and godot_describe for a method's full parameter schema.",
    inputSchema: {
      type: "object",
      properties: {
        method: { type: "string", description: "Method name, e.g. get_project_info, get_scene_tree, add_node" },
        params: { type: "object", description: "Parameters for the method (varies per method)" },
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
    description: "Check connection status to the Godot editor.",
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
        return { content: [{ type: "text", text: godot.status }] };
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
            const info = await godot.call("get_project_info") as { project_path?: string };
            if (!info?.project_path) {
              throw new Error("Could not determine the Godot project path (get_project_info returned none) — is the editor connected?");
            }
            const resolution = args?.resolution as string | undefined;
            const format = args?.format as string | undefined;
            const result = await importAsset(provider, id, info.project_path, { resolution, format });
            // Best-effort: the import already succeeded and wrote real files
            // on disk regardless of whether the rescan itself goes through.
            await godot.call("reload_project").catch(() => {});
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

// Only run the server when this file is the process entrypoint, not when a
// test suite imports it for its pure helpers (wsAccept/wsSend/decodeFrame/
// GodotBridge) — otherwise every test run would bind real ports and attach a
// real stdio transport.
const isEntrypoint = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isEntrypoint) {
  main().catch((err) => { console.error("Fatal:", err); process.exit(1); });
}
