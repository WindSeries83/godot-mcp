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
