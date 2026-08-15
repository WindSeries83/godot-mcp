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

const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const BASE_PORT = parseInt(process.env.GODOT_MCP_PORT ?? "6505", 10);
const ALL_PORTS = Array.from({ length: 10 }, (_, i) => BASE_PORT + i);
const REQUEST_TIMEOUT = 30_000;

function wsAccept(key: string): string {
  return crypto.createHash("sha1").update(key + WS_MAGIC).digest("base64");
}

function wsSend(socket: Duplex, text: string): void {
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

function decodeFrame(buf: Buffer): { opcode: number; payload: Buffer; total: number } | null {
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

class GodotBridge {
  private servers = new Set<http.Server>();
  private peers = new Map<number, Duplex>();
  private bufs = new Map<Duplex, Buffer>();
  private pending = new Map<number, Pending>();
  private nextId = 1;

  start(): void {
    for (const port of ALL_PORTS) {
      const srv = http.createServer();
      srv.on("upgrade", (req, socket) => {
        const key = req.headers["sec-websocket-key"];
        if (!key) { socket.destroy(); return; }
        socket.write(
          "HTTP/1.1 101 Switching Protocols\r\n" +
          "Upgrade: websocket\r\n" +
          "Connection: Upgrade\r\n" +
          "Sec-WebSocket-Accept: " + wsAccept(key) + "\r\n\r\n"
        );
        this.peers.set(port, socket);
        this.bufs.set(socket, Buffer.alloc(0));
        socket.on("data", (chunk) => this.onData(socket, chunk));
        socket.on("close", () => { this.peers.delete(port); this.bufs.delete(socket); });
        socket.on("error", () => { this.peers.delete(port); this.bufs.delete(socket); });
      });
      srv.listen(port, "127.0.0.1");
      this.servers.add(srv);
    }
  }

  stop(): void {
    for (const [, p] of this.pending) { clearTimeout(p.timer); p.reject(new Error("Server shutting down")); }
    this.pending.clear();
    for (const srv of this.servers) srv.close();
    for (const sock of this.peers.values()) sock.destroy();
    this.peers.clear();
    this.bufs.clear();
  }

  get connected(): boolean {
    return this.peers.size > 0;
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
      if (msg.id != null) wsSend(socket, JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: { pong: true } }));
      return;
    }

    if (msg.method === "pong" || msg.method === "auth") return;

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
    description: "Call any method on the Godot editor addon. See godot_list_methods for available methods and their parameters.",
    inputSchema: {
      type: "object",
      properties: {
        method: { type: "string", description: "Method name, e.g. get_project_info, get_scene_tree, add_node" },
        params: { type: "object", description: "Parameters for the method (varies per method)" },
      },
      required: ["method"],
    },
  },
  {
    name: "godot_list_methods",
    description: "List all available Godot addon method categories with example methods for each.",
    inputSchema: {
      type: "object",
      properties: {
        category: { type: "string", description: "Optional filter: project, scene, node, script, editor, input, runtime, animation, tilemap, theme, 3d, physics, particles, navigation, audio, shader, resource, export, profiling, batch, analysis, animation_tree, test, android, headless" },
      },
    },
  },
  {
    name: "godot_info",
    description: "Get project info from the Godot editor (shorthand for godot_call method=get_project_info).",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "godot_screenshot",
    description: "Capture the Godot editor viewport. Returns base64 PNG image data.",
    inputSchema: { type: "object", properties: {} },
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
  },
  {
    name: "godot_status",
    description: "Check connection status to the Godot editor.",
    inputSchema: { type: "object", properties: {} },
  },
];

const METHOD_CATALOG: Record<string, string[]> = {
  project: ["get_project_info", "get_filesystem_tree", "search_files", "search_in_files", "get_project_settings", "set_project_setting", "uid_to_project_path", "project_path_to_uid", "add_autoload", "remove_autoload"],
  scene: ["get_scene_tree", "get_scene_file_content", "create_scene", "open_scene", "delete_scene", "add_scene_instance", "play_scene", "stop_scene", "save_scene", "get_scene_exports"],
  node: ["add_node", "delete_node", "duplicate_node", "move_node", "update_property", "get_node_properties", "add_resource", "rename_node", "connect_signal", "disconnect_signal", "get_node_groups", "set_node_groups", "get_editor_selection", "select_nodes", "clear_editor_selection", "find_nodes_in_group", "set_anchor_preset"],
  script: ["list_scripts", "read_script", "create_script", "edit_script", "attach_script", "get_open_scripts", "validate_script"],
  editor: ["get_editor_errors", "get_output_log", "get_editor_screenshot", "get_game_screenshot", "execute_editor_script", "clear_output", "reload_plugin", "reload_project", "get_signals", "get_editor_camera", "set_editor_camera", "compare_screenshots", "set_auto_dismiss"],
  input: ["simulate_key", "simulate_mouse_click", "simulate_mouse_move", "simulate_action", "simulate_sequence", "get_input_actions", "set_input_action"],
  runtime: ["get_game_scene_tree", "get_game_node_properties", "set_game_node_property", "capture_frames", "monitor_properties", "execute_game_script", "find_nodes_by_script", "find_ui_elements", "click_button_by_text", "wait_for_node", "navigate_to", "move_to", "batch_get_properties", "find_nearby_nodes", "watch_signals", "start_recording", "stop_recording", "replay_recording", "get_autoload"],
  animation: ["list_animations", "create_animation", "add_animation_track", "set_animation_keyframe", "get_animation_info", "remove_animation"],
  tilemap: ["tilemap_set_cell", "tilemap_fill_rect", "tilemap_get_cell", "tilemap_clear", "tilemap_get_info", "tilemap_get_used_cells"],
  theme: ["create_theme", "set_theme_color", "set_theme_constant", "set_theme_font_size", "set_theme_stylebox", "get_theme_info", "setup_control"],
  "3d": ["add_mesh_instance", "setup_camera_3d", "setup_lighting", "setup_environment", "add_gridmap", "set_material_3d"],
  physics: ["setup_collision", "set_physics_layers", "get_physics_layers", "add_raycast", "setup_physics_body", "get_collision_info"],
  particles: ["create_particles", "set_particle_material", "set_particle_color_gradient", "apply_particle_preset", "get_particle_info"],
  navigation: ["setup_navigation_region", "setup_navigation_agent", "bake_navigation_mesh", "set_navigation_layers", "get_navigation_info"],
  audio: ["add_audio_player", "add_audio_bus", "add_audio_bus_effect", "set_audio_bus", "get_audio_bus_layout", "get_audio_info"],
  shader: ["create_shader", "read_shader", "edit_shader", "assign_shader_material", "set_shader_param", "get_shader_params"],
  resource: ["read_resource", "edit_resource", "create_resource", "get_resource_preview"],
  export: ["list_export_presets", "export_project", "get_export_info"],
  profiling: ["get_performance_monitors", "get_editor_performance"],
  batch: ["find_nodes_by_type", "find_signal_connections", "batch_set_property", "find_node_references", "get_scene_dependencies", "cross_scene_set_property", "batch_add_nodes"],
  analysis: ["find_unused_resources", "analyze_signal_flow", "analyze_scene_complexity", "find_script_references", "detect_circular_dependencies", "get_project_statistics"],
  animation_tree: ["create_animation_tree", "get_animation_tree_structure", "set_tree_parameter", "add_state_machine_state", "remove_state_machine_state", "add_state_machine_transition", "remove_state_machine_transition", "set_blend_tree_node"],
  test: ["run_test_scenario", "assert_node_state", "assert_screen_text", "run_stress_test", "get_test_report"],
  android: ["list_android_devices", "get_android_preset_info", "deploy_to_android"],
  headless: ["run_headless_scene", "run_headless_script", "get_godot_executable"],
};

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOL_DEFS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;
  try {
    switch (name) {
      case "godot_call": {
        const method = args?.method as string;
        if (!method) throw new Error("method is required");
        const params = (args?.params ?? {}) as Record<string, unknown>;
        const result = await godot.call(method, params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      }
      case "godot_list_methods": {
        const filter = args?.category as string | undefined;
        const entries = Object.entries(METHOD_CATALOG)
          .filter(([k]) => !filter || k === filter)
          .map(([cat, methods]) => `[${cat}] ${methods.slice(0, 6).join(", ")}${methods.length > 6 ? ` +${methods.length - 6} more` : ""}`);
        const text = filter ? entries.join("\n") : `${entries.length} categories. Use godot_call with one of these methods.\n\n${entries.join("\n")}`;
        return { content: [{ type: "text", text }] };
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
        return { content: [{ type: "text", text: godot.connected ? "Connected to Godot editor" : "Not connected — start Godot with the MCP plugin enabled" }] };
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
  godot.start();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => { console.error("Fatal:", err); process.exit(1); });
