@tool
extends EditorDebuggerPlugin

## Captures runtime errors (push_error / SCRIPT ERROR / unhandled GDScript
## exceptions) from the running game, structured with file/line/backtrace,
## replacing a UI-scrape of the debugger's "Errors" tab Tree.
##
## The public EditorDebuggerPlugin API (_capture/_has_capture) only sees
## messages the GAME sends with a custom "prefix:" — see
## https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html.
## Built-in engine "error" messages are not custom-prefixed and are invisible
## to that path; verified against the Godot 4.5 class docs.
##
## Instead this hooks ScriptEditorDebugger's "debug_data(msg, data)" signal
## (core/debugger/debugger_marshalls.cpp + editor/debugger/script_editor_debugger.cpp),
## which is emitted for EVERY incoming debugger message, before Godot's
## built-in routing to _msg_error() etc. This is undocumented internal API,
## not covered by any compatibility guarantee — if a future Godot version
## removes or renames it, error capture silently stops working rather than
## erroring (see _setup_session), degrading no worse than the UI-scrape it
## replaces would on the same kind of break.

const _BaseCommand := preload("res://addons/godot_mcp/commands/base_command.gd")

var error_store: RefCounted  # MCPErrorStore, untyped to avoid a preload cycle
var _connected_debuggers: Array[Node] = []


func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	if session == null:
		return

	# EditorDebuggerSession has no direct reference to its ScriptEditorDebugger.
	# add_session_tab() parents the given Control under the debugger's
	# TabContainer, so two get_parent() hops reach it from there.
	var probe := Control.new()
	probe.visible = false
	session.add_session_tab(probe)
	var tab_container: Node = probe.get_parent()
	var sed: Node = tab_container.get_parent() if tab_container != null else null
	if tab_container != null:
		tab_container.remove_child(probe)
	probe.queue_free()

	if sed == null or sed.get_class() != "ScriptEditorDebugger":
		# Fallback: BFS from the editor base control, same helper already used
		# by base_command.gd for the debugger Continue button / errors tab.
		sed = _BaseCommand._find_script_editor_debugger()

	if sed == null:
		push_warning("[MCP] Could not reach ScriptEditorDebugger for session %d — runtime error capture unavailable for this session, falling back to editor UI scraping." % session_id)
		return

	if sed.is_connected("debug_data", _on_debug_data):
		return
	if not sed.has_signal("debug_data"):
		push_warning("[MCP] ScriptEditorDebugger has no 'debug_data' signal on this Godot version — runtime error capture unavailable, falling back to editor UI scraping.")
		return

	sed.connect("debug_data", _on_debug_data)
	_connected_debuggers.append(sed)


## data layout for msg == "error" (DebuggerMarshalls::OutputError,
## core/debugger/debugger_marshalls.cpp):
##   0:hr 1:min 2:sec 3:msec 4:source_file 5:source_func 6:source_line
##   7:error 8:error_descr 9:warning 10:stack_size
##   11+: (file, func, line) triplets, one per stack frame
func _on_debug_data(msg: String, data: Array) -> void:
	if msg != "error" or error_store == null:
		return
	if data.size() < 11:
		return

	var stack: Array = []
	var i := 11
	while i + 2 < data.size():
		stack.append({
			"file": str(data[i]),
			"function": str(data[i + 1]),
			"line": int(data[i + 2]),
		})
		i += 3

	error_store.push({
		"time": "%02d:%02d:%02d.%03d" % [int(data[0]), int(data[1]), int(data[2]), int(data[3])],
		"file": str(data[4]),
		"function": str(data[5]),
		"line": int(data[6]),
		"error": str(data[7]),
		"description": str(data[8]),
		"is_warning": bool(data[9]),
		"stack": stack,
	})


## Called from plugin.gd's _exit_tree before remove_debugger_plugin(), so a
## reloaded/disabled plugin doesn't leave a connection to a freed script.
func disconnect_all() -> void:
	for sed in _connected_debuggers:
		if is_instance_valid(sed) and sed.is_connected("debug_data", _on_debug_data):
			sed.disconnect("debug_data", _on_debug_data)
	_connected_debuggers.clear()
