# Security — Connection Token

The Godot plugin accepts commands from any MCP server that connects to the
WebSocket ports (6505–6514). An optional connection token lets you require
servers to authenticate before sending commands.

## How it works

1. Enable the requirement by setting the project setting
   `godot_mcp/require_connection_token` to `true` (Project Settings → General,
   or `project.godot`), or by setting the environment variable
   `GODOT_MCP_REQUIRE_TOKEN` to a non-empty, non-zero value.
2. On startup, the plugin generates a random token, stores it in
   `user://mcp_auth_token` on the machine running the editor, and sends an
   `auth_required` notification to every connecting peer.
3. A server must reply with `{"method":"auth","params":{"token":"<token>"}}`
   within 5 seconds. Until then, every other request is rejected with a
   "requires a connection token" error.
4. Your MCP server / AI client must therefore read the token file before
   connecting. The absolute path is printed in the editor Output panel when
   the requirement is on.

This repo's `src/index.ts` runs as a separate process with no way to resolve
`user://mcp_auth_token` to a real path on its own, so it needs the token
handed to it explicitly. Set one of:

- `GODOT_MCP_TOKEN` — the literal token value, or
- `GODOT_MCP_TOKEN_PATH` — the absolute path to the token file (the one
  printed in the Output panel)

before starting `node dist/index.js`. Without either, the server logs a
warning and leaves the connection unauthenticated (Godot will keep closing
and retrying it every few seconds until a token is supplied).

## What it protects against

- Other **users** on a shared machine (or other processes running under a
  different account) connecting to the open WebSocket ports.
- Accidental cross-project mix-ups where a server meant for another project
  connects to the wrong editor.

## What it does NOT protect against

- Any process running **as the same OS user** as the editor: it can read
  `user://mcp_auth_token` exactly like a legitimate server does.
- Malicious content inside the edited project itself (scripts, scenes), which
  runs with the editor's full privileges regardless of the token.
- Network-level interception: traffic on 127.0.0.1 is not encrypted.

This is a shared-secret gate, not a full security boundary. Do not rely on it
against same-user processes, and never connect the plugin to a non-loopback
interface.

# Security — Confirmation gate on irreversible writes

Separately from the connection token above, every method whose schema marks
`annotations.confirm: true` is rejected by `command_router.gd`'s `execute()`
with error code `-32009` unless the call's `params` includes `confirm: true`.
This covers methods that write or delete a file on disk, modify
`project.godot`, or run arbitrary code in the editor/game process — roughly
20 of the addon's ~190 methods, e.g. `create_scene`, `delete_scene`,
`edit_script`, `create_resource`, `execute_editor_script`,
`set_project_setting`, `run_headless_scene`.

## What it protects against

- An AI assistant silently overwriting or deleting a file, or running
  arbitrary code, as a side effect of a call it didn't fully explain to the
  operator before making it.
- The specific class of write that **cannot** be undone with Ctrl-Z: unlike
  edits to the currently open scene (which go through
  `EditorUndoRedoManager` and are always undoable), a file write/delete or a
  `project.godot` change persists immediately and survives an editor restart.

## What it deliberately does NOT cover

- **Mutations to the edited scene** (`add_node`, `delete_node`,
  `update_property`, CSG/scatter tools, etc.) are never gated, even though
  several of them are marked `destructive: true`. `EditorUndoRedoManager`
  already makes every one of them a single Ctrl-Z away from reverting, which
  is a stronger and lower-friction guarantee than a confirmation flag would
  add.
- **Transient runtime input** (`simulate_key`, `simulate_mouse_click`,
  `replay_recording`, …) is not gated either — these drive a running game
  process via file IPC and confirming every keystroke would make them
  unusable, without protecting anything that outlives the play session.
- This is a **cooperative** gate: it relies on the calling MCP client (and
  the assistant it drives) respecting the `-32009` refusal and the
  `confirm: true` contract. A client that always retries with
  `confirm: true` regardless of the refusal gets no protection from this
  gate — same trust model as the connection token above.
