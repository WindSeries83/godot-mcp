import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { Duplex } from "node:stream";
import { GodotBridge } from "../src/index.js";

// Exercises GodotBridge.dispatch() directly — it's private in the public API
// but not at runtime, and driving it through a real socket/WS handshake
// would just be testing Node's http server. What matters here is the
// JSON-RPC behaviour fixed in Lot 0: replying to id-less pings (else Godot's
// own heartbeat never resets its inactivity timer and the bridge churns
// reconnects every 30s) and answering auth_required (else the token
// handshake documented in SECURITY.md just hangs).
function fakeSocket(): { socket: Duplex; frames: () => string[] } {
  const chunks: Buffer[] = [];
  const socket = new Duplex({
    write(chunk, _enc, cb) { chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)); cb(); },
    read() {},
  });
  // Decode each written frame's text payload (unmasked, server->client) for
  // assertions, without re-implementing the WS reader: server frames here
  // are always short-form (<126 bytes) text frames in these tests.
  return {
    socket,
    frames: () => chunks.map((buf) => {
      const len = buf[1] & 0x7f;
      return buf.subarray(2, 2 + len).toString("utf8");
    }),
  };
}

describe("GodotBridge.dispatch", () => {
  let bridge: GodotBridge;

  beforeEach(() => {
    bridge = new GodotBridge();
    vi.restoreAllMocks();
  });

  it("replies to an id-less ping with a pong notification", () => {
    const { socket, frames } = fakeSocket();
    (bridge as any).dispatch(socket, JSON.stringify({ jsonrpc: "2.0", method: "ping", params: {} }));
    const msgs = frames().map((f) => JSON.parse(f));
    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toMatchObject({ jsonrpc: "2.0", method: "pong" });
    expect(msgs[0].id).toBeUndefined();
  });

  it("replies to a ping carrying an id with a correlated result", () => {
    const { socket, frames } = fakeSocket();
    (bridge as any).dispatch(socket, JSON.stringify({ jsonrpc: "2.0", id: 7, method: "ping", params: {} }));
    const [msg] = frames().map((f) => JSON.parse(f));
    expect(msg).toEqual({ jsonrpc: "2.0", id: 7, result: { pong: true } });
  });

  it("answers auth_required by sending the configured token", () => {
    vi.stubEnv("GODOT_MCP_TOKEN", "secret-token");
    const { socket, frames } = fakeSocket();
    (bridge as any).dispatch(socket, JSON.stringify({ jsonrpc: "2.0", method: "auth_required", params: {} }));
    const [msg] = frames().map((f) => JSON.parse(f));
    expect(msg.method).toBe("auth");
    expect(msg.params).toEqual({ token: "secret-token" });
    expect(typeof msg.id).toBe("number");
    expect((bridge as any).authPending.has(msg.id)).toBe(true);
    vi.unstubAllEnvs();
  });

  it("logs and sends nothing when auth_required arrives with no token configured", () => {
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { socket, frames } = fakeSocket();
    (bridge as any).dispatch(socket, JSON.stringify({ jsonrpc: "2.0", method: "auth_required", params: {} }));
    expect(frames()).toHaveLength(0);
    expect(errSpy).toHaveBeenCalled();
  });

  it("clears authPending on an auth error response and logs it", () => {
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    (bridge as any).authPending.add(3);
    (bridge as any).dispatch(
      fakeSocket().socket,
      JSON.stringify({ jsonrpc: "2.0", id: 3, error: { code: -32001, message: "Invalid token" } })
    );
    expect((bridge as any).authPending.has(3)).toBe(false);
    expect(errSpy).toHaveBeenCalled();
  });

  it("resolves a pending godot_call on a matching result", async () => {
    const { socket } = fakeSocket();
    (bridge as any).peers.add(socket);
    const callPromise = bridge.call("get_project_info");
    // The id assigned by call() is deterministic (starts at 1 for a fresh bridge).
    (bridge as any).dispatch(socket, JSON.stringify({ jsonrpc: "2.0", id: 1, result: { ok: true } }));
    await expect(callPromise).resolves.toEqual({ ok: true });
  });

  it("rejects a pending godot_call on a matching error", async () => {
    const { socket } = fakeSocket();
    (bridge as any).peers.add(socket);
    const callPromise = bridge.call("bad_method");
    (bridge as any).dispatch(socket, JSON.stringify({ jsonrpc: "2.0", id: 1, error: { code: -32601, message: "not found" } }));
    await expect(callPromise).rejects.toThrow(/not found/);
  });

  it("rejects call() immediately when no editor is connected", async () => {
    await expect(bridge.call("get_project_info")).rejects.toThrow(/not connected/);
  });
});

describe("GodotBridge schema caching", () => {
  let bridge: GodotBridge;

  beforeEach(() => {
    bridge = new GodotBridge();
  });

  it("caches listAllMethods() across calls (only one RPC round trip)", async () => {
    const { socket } = fakeSocket();
    (bridge as any).peers.add(socket);

    const first = bridge.listAllMethods();
    (bridge as any).dispatch(socket, JSON.stringify({
      jsonrpc: "2.0", id: 1, result: { add_node: { category: "node", summary: "adds a node", annotations: {}, has_schema: true } },
    }));
    await first;

    // A second call must not send another request — id 2 was never answered,
    // so if listAllMethods() tried to re-fetch this would hang and time out.
    const second = await bridge.listAllMethods();
    expect(second).toHaveProperty("add_node");
    expect((bridge as any).nextId).toBe(2); // still just the one RPC from the first call
  });

  it("invalidates the cache when a new peer connects", async () => {
    const { socket: socketA } = fakeSocket();
    (bridge as any).peers.add(socketA);

    const first = bridge.listAllMethods();
    (bridge as any).dispatch(socketA, JSON.stringify({ jsonrpc: "2.0", id: 1, result: { a: {} } }));
    await first;
    expect((bridge as any).methodListCache).not.toBeNull();

    (bridge as any).invalidateSchemaCache();
    expect((bridge as any).methodListCache).toBeNull();
  });

  it("caches describeMethod() per method name", async () => {
    const { socket } = fakeSocket();
    (bridge as any).peers.add(socket);

    const first = bridge.describeMethod("add_node");
    (bridge as any).dispatch(socket, JSON.stringify({
      jsonrpc: "2.0", id: 1, result: { add_node: { summary: "adds a node", params: {} } },
    }));
    const result = await first;
    expect(result).toEqual({ summary: "adds a node", params: {} });

    // Cached: no second RPC needed.
    const cached = await bridge.describeMethod("add_node");
    expect(cached).toEqual({ summary: "adds a node", params: {} });
    expect((bridge as any).nextId).toBe(2);
  });
});
