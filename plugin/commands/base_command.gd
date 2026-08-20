@tool
extends Node

var editor_plugin: EditorPlugin


## Override in subclasses: return {"method_name": Callable}
func get_commands() -> Dictionary:
	return {}


## Override in subclasses: return {"method_name": schema}, one entry per key
## returned by get_commands(). Schema shape:
##   {
##       "category": "project",  # matches the category used in this file's own get_command_schemas()
##       "summary": "One line, what it does.",
##       "params": {
##           "key": {"type": "string|int|float|bool|object|array", "required": true, "desc": "..."},
##           "other": {"type": "string", "required": false, "default": ".", "desc": "..."},
##       },
##       "annotations": {"readOnly": bool, "destructive": bool, "idempotent": bool},
##   }
## `params` may be {} for a no-argument method. This is consumed by
## command_router.gd's describe_methods()/describe_method() and lets
## godot_list_methods / godot_describe on the Node side reflect the real,
## current parameter set instead of a hand-maintained, drifting copy. Category
## lives here (not on the Node side) so there is exactly one place that knows
## a method's grouping — the module that implements it.
func get_command_schemas() -> Dictionary:
	return {}


## Helper: return a success result
func success(data: Dictionary = {}) -> Dictionary:
	return {"result": data}


## Helper: return an error
func error(code: int, message: String, data: Dictionary = {}) -> Dictionary:
	var err := {"code": code, "message": message}
	if not data.is_empty():
		err["data"] = data
	return {"error": err}


## Error codes
func error_not_found(what: String, suggestion: String = "") -> Dictionary:
	var data := {}
	if suggestion:
		data["suggestion"] = suggestion
	return error(-32001, "%s not found" % what, data)


func error_invalid_params(message: String) -> Dictionary:
	return error(-32602, message)


func error_no_scene() -> Dictionary:
	return error(-32000, "No scene is currently open", {"suggestion": "Use open_scene to open a scene first"})


func error_internal(message: String) -> Dictionary:
	return error(-32603, "Internal error: %s" % message)


func error_conflict(message: String, data: Dictionary = {}) -> Dictionary:
	return error(-32009, message, data)


## Get required string param
func require_string(params: Dictionary, key: String) -> Array:
	if not params.has(key) or not params[key] is String or (params[key] as String).is_empty():
		return [null, error_invalid_params("Missing required parameter: %s" % key)]
	return [params[key] as String, null]


## Get optional string param with default
func optional_string(params: Dictionary, key: String, default: String = "") -> String:
	if params.has(key) and params[key] is String:
		return params[key] as String
	return default


## Get optional bool param with default
func optional_bool(params: Dictionary, key: String, default: bool = false) -> bool:
	if params.has(key) and params[key] is bool:
		return params[key] as bool
	return default


## Get optional int param with default.
##
## Only converts from types that have a meaningful integer value. int() raises
## on null, arrays and dictionaries — and a raise inside a command handler
## aborts the coroutine, so the caller gets no response at all and waits out
## its full timeout for what is really one bad parameter.
func optional_int(params: Dictionary, key: String, default: int = 0) -> int:
	if not params.has(key):
		return default
	var value: Variant = params[key]
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return default


## Get optional float param with default. Same reasoning as optional_int:
## float() raises on null, arrays and dictionaries, and a raise inside a
## handler means the caller never gets a response.
func optional_float(params: Dictionary, key: String, default: float = 0.0) -> float:
	if not params.has(key):
		return default
	var value: Variant = params[key]
	if value is float:
		return value
	if value is int:
		return float(value)
	if value is bool:
		return 1.0 if value else 0.0
	if value is String and (value as String).is_valid_float():
		return (value as String).to_float()
	return default


## Validates that every entry of `params[key]` is a Dictionary.
##
## `for entry: Dictionary in some_array` raises on the first non-Dictionary
## element, which aborts the handler before it can answer. Returns {} when the
## array is usable, or an error dictionary naming the offending index.
func require_dictionary_array(params: Dictionary, key: String) -> Dictionary:
	if not params.has(key) or not params[key] is Array:
		return error_invalid_params("'%s' array is required" % key)
	var items: Array = params[key]
	for i in items.size():
		if not items[i] is Dictionary:
			return error_invalid_params(
				"'%s'[%d] must be an object, got %s" % [key, i, type_string(typeof(items[i]))]
			)
	return {}


## Get the game process's user data directory.
## OS.get_user_data_dir() is cached at editor startup and won't reflect
## project name changes made to project.godot while the editor is running.
## The game process reads the name from disk, so we must do the same.
func get_game_user_dir() -> String:
	var cached_dir := OS.get_user_data_dir()
	var cfg := ConfigFile.new()
	var err := cfg.load(ProjectSettings.globalize_path("res://project.godot"))
	if err != OK:
		return cached_dir
	# When use_custom_user_dir=true, editor and game share the same dir
	# (OS.get_user_data_dir() already resolves to the custom path).
	if cfg.get_value("application", "config/use_custom_user_dir", false):
		return cached_dir
	var disk_name = cfg.get_value("application", "config/name", "")
	if typeof(disk_name) != TYPE_STRING or (disk_name as String).is_empty():
		return cached_dir
	# Sanitize exactly like Godot does when computing the default user dir
	# (core/config/project_settings.cpp ProjectSettings::_init).
	var sanitized := (disk_name as String).xml_unescape().validate_filename().replace(".", "_")
	if sanitized.is_empty():
		return cached_dir
	var base_dir := cached_dir.get_base_dir()
	var game_dir := base_dir.path_join(sanitized)
	# Ensure the directory exists (game may not have created it yet)
	if not DirAccess.dir_exists_absolute(game_dir):
		DirAccess.make_dir_recursive_absolute(game_dir)
	return game_dir


## Get EditorInterface
func get_editor() -> EditorInterface:
	return editor_plugin.get_editor_interface()


## Get the edited scene root
func get_edited_root() -> Node:
	return EditorInterface.get_edited_scene_root()


## Get UndoRedo
func get_undo_redo() -> EditorUndoRedoManager:
	return editor_plugin.get_undo_redo()


func normalize_project_path(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return path.simplify_path()
	return ProjectSettings.localize_path(path).simplify_path()


## Turns a res:// or user:// path into an absolute filesystem path suitable
## for Image.save_png()/FileAccess; an already-absolute path is passed
## through unchanged. Shared by every command that can write a capture to an
## arbitrary caller-given path (screenshots, turntable sheets, ...).
func resolve_save_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


## Compares two project paths for the purpose of a protective guard.
##
## Windows and macOS have case-insensitive filesystems, so "res://Player.gd"
## and "res://player.gd" are the same file while comparing unequal. An exact
## match would let a differently-cased alias slip past the open-resource
## guards and overwrite the file the user has open. These guards are meant to
## refuse when in doubt, so the comparison is case-insensitive: at worst a
## write is refused that would have been safe, which the caller can override.
func paths_match(a: String, b: String) -> bool:
	return a.nocasecmp_to(b) == 0


## Refuses a write whose path does not carry one of the expected extensions.
##
## Without this, create_shader / create_theme / create_resource and friends
## will happily ResourceSaver.save over whatever the path points at — a
## mistyped destination silently destroys a script or an image, with no undo.
## `what` names the tool's own file kind for the message.
func guard_expected_extension(path: String, allowed: Array, what: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if ext in allowed:
		return {}
	var pretty: Array = []
	for e: String in allowed:
		pretty.append("." + e)
	return error_invalid_params(
		"'%s' does not look like %s (expected %s). Refusing to write, since this would overwrite whatever is at that path." % [
			path, what, ", ".join(pretty)
		]
	)


func is_scene_resource_path(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext == "tscn" or ext == "scn"


func get_open_scene_paths() -> Array[String]:
	var paths: Array[String] = []
	var open_scenes: PackedStringArray = EditorInterface.get_open_scenes()
	for scene_path: String in open_scenes:
		var normalized := normalize_project_path(scene_path)
		if not normalized.is_empty() and normalized not in paths:
			paths.append(normalized)

	var root := get_edited_root()
	if root != null and not root.scene_file_path.is_empty():
		var active_path := normalize_project_path(root.scene_file_path)
		if active_path not in paths:
			paths.append(active_path)
	return paths


func is_scene_path_open(path: String) -> bool:
	var normalized := normalize_project_path(path)
	if normalized.is_empty():
		return false
	for open_path: String in get_open_scene_paths():
		if paths_match(open_path, normalized):
			return true
	return false


func is_active_scene_path(path: String) -> bool:
	var root := get_edited_root()
	if root == null:
		return false
	return paths_match(normalize_project_path(root.scene_file_path), normalize_project_path(path))


func guard_offline_scene_save(path: String) -> Dictionary:
	if is_scene_resource_path(path) and is_scene_path_open(path):
		return error_conflict(
			"Refusing to save open scene '%s' outside the Godot editor state" % normalize_project_path(path),
			{
				"path": normalize_project_path(path),
				"open_scenes": get_open_scene_paths(),
				"suggestion": "Use live editor changes plus save_scene, or close the scene before offline edits.",
			}
		)
	return {}


## Helper: create the parent directory of a res:// path if missing.
## Returns {} on success, an error dictionary on failure.
func ensure_parent_dir(path: String) -> Dictionary:
	var dir := path.get_base_dir()
	if dir.is_empty() or DirAccess.dir_exists_absolute(dir):
		return {}
	var derr := DirAccess.make_dir_recursive_absolute(dir)
	if derr != OK:
		return error_internal("Cannot create directory '%s': %s" % [dir, error_string(derr)])
	return {}


## Helper: unwrap the (possibly multi-)wrapped {"result": ...} envelope returned
## by the game IPC channel. The game writes its own {"result": ...} envelope and
## the transport wraps it again, so consumers must unwrap defensively.
func unwrap_game_result(result: Dictionary) -> Dictionary:
	var payload: Variant = result
	while payload is Dictionary and payload.has("result") and payload["result"] is Dictionary:
		payload = payload["result"]
	return payload if payload is Dictionary else {}


## Shared IPC helper: send a command to the running game and await its response.
## Only one game command may be in flight: the request and response files are
## shared, so two at once would overwrite each other's request and consume each
## other's reply. Static, because each command file has its own instance.
static var _game_command_busy := false
static var _game_command_seq := 0


func send_game_command(command: String, params: Dictionary = {}, timeout_sec: float = 5.0) -> Dictionary:
	var ei := get_editor()
	if not ei.is_playing_scene():
		return error(-32000, "No scene is currently playing", {"suggestion": "Use play_scene first"})

	# Wait for any in-flight game command rather than trampling it.
	var waited := 0.0
	var queue_limit := timeout_sec + 5.0
	while _game_command_busy and waited < queue_limit:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	if _game_command_busy:
		return error(-32000, "Another game command is still running", {
			"suggestion": "Retry once it finishes; game commands are serialised because they share one request channel.",
		})

	_game_command_busy = true
	var result := await _send_game_command_locked(command, params, timeout_sec)
	_game_command_busy = false
	return result


func _send_game_command_locked(command: String, params: Dictionary, timeout_sec: float) -> Dictionary:
	var ei := get_editor()
	var user_dir := get_game_user_dir()
	var request_path := user_dir + "/mcp_game_request"
	var response_path := user_dir + "/mcp_game_response"

	# Clean stale response
	if FileAccess.file_exists(response_path):
		DirAccess.remove_absolute(response_path)

	# Write request, tagged so a late reply from a command that already timed
	# out is recognised and discarded instead of being read as this one's.
	_game_command_seq += 1
	var request_id := "%d-%d" % [Time.get_ticks_msec(), _game_command_seq]
	var request_data := JSON.stringify({"command": command, "params": params, "request_id": request_id})
	var req := FileAccess.open(request_path, FileAccess.WRITE)
	if req == null:
		return error_internal("Could not create game request file")
	req.store_string(request_data)
	req.close()

	# Poll for response
	var attempts := int(timeout_sec / 0.1)
	while attempts > 0:
		await get_tree().create_timer(0.1).timeout
		if FileAccess.file_exists(response_path):
			break
		if not ei.is_playing_scene():
			if FileAccess.file_exists(request_path):
				DirAccess.remove_absolute(request_path)
			return error(-32000, "Game stopped during command execution")
		attempts -= 1

	if not FileAccess.file_exists(response_path):
		# Try to auto-resume the debugger (runtime error may have paused the game)
		if ei.is_playing_scene():
			try_debugger_continue()
			for _retry in 20:
				await get_tree().create_timer(0.1).timeout
				if FileAccess.file_exists(response_path):
					break

	if not FileAccess.file_exists(response_path):
		if FileAccess.file_exists(request_path):
			DirAccess.remove_absolute(request_path)
		return build_timeout_error(timeout_sec)

	# Read response
	var file := FileAccess.open(response_path, FileAccess.READ)
	if file == null:
		return error_internal("Could not read game response file")
	var text := file.get_as_text()
	file.close()
	DirAccess.remove_absolute(response_path)

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		return error_internal("Invalid response JSON from game")

	var reply_id := str(parsed.get("request_id", ""))
	if not reply_id.is_empty() and reply_id != request_id:
		return error_internal(
			"Discarded a stale game response belonging to an earlier command. Retry this one."
		)

	if parsed.has("error"):
		return error(-32000, str(parsed["error"]))

	return success(parsed)


func is_shader_resource_path(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext == "gdshader" or ext == "gdshaderinc" or ext == "shader"


func is_text_resource_open_in_script_editor(path: String) -> bool:
	var target := normalize_project_path(path)
	if target.is_empty():
		return false
	if is_shader_resource_path(target) and ResourceLoader.has_cached(target):
		return true
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return false
	for open_resource in script_editor.get_open_scripts():
		if open_resource is Resource:
			var resource_path := normalize_project_path((open_resource as Resource).resource_path)
			if paths_match(resource_path, target):
				return true
	return false


func guard_text_resource_write(path: String, force: bool) -> Dictionary:
	if not force and is_text_resource_open_in_script_editor(path):
		return error_conflict(
			"Refusing to write open text resource '%s' outside the script editor state" % normalize_project_path(path),
			{
				"path": normalize_project_path(path),
				"suggestion": "Close the file in Godot's script editor or pass force=true to overwrite it deliberately.",
			}
		)
	return {}


## Refuses to overwrite a file that already exists at `path` unless `overwrite`
## is true. `path` may be res://, user://, or an absolute filesystem path (see
## resolve_save_path()) — shared by every command that writes a capture to a
## caller-supplied path (screenshots, turntable sheets) instead of a path the
## tool itself chose, where a typo'd path would otherwise silently clobber
## something unrelated.
func guard_overwrite(path: String, overwrite: bool) -> Dictionary:
	if overwrite or path.is_empty():
		return {}
	var abs_path := resolve_save_path(path)
	if not FileAccess.file_exists(abs_path):
		return {}
	return error_conflict(
		"Refusing to overwrite existing file '%s'" % path,
		{
			"path": path,
			"suggestion": "Pass overwrite=true to replace it deliberately, or choose a different save_path.",
		}
	)


func mark_current_scene_unsaved() -> void:
	if EditorInterface.has_method("mark_scene_as_unsaved"):
		EditorInterface.mark_scene_as_unsaved()


func add_child_with_undo(parent: Node, child: Node, root: Node, action_name: String) -> void:
	var undo_redo := get_undo_redo()
	undo_redo.create_action(action_name)
	undo_redo.add_do_method(parent, "add_child", child)
	undo_redo.add_do_method(child, "set_owner", root)
	undo_redo.add_do_reference(child)
	undo_redo.add_undo_method(parent, "remove_child", child)
	undo_redo.commit_action()


func set_property_with_undo(target: Object, property: String, new_value: Variant, action_name: String) -> void:
	var old_value: Variant = target.get(property)
	var undo_redo := get_undo_redo()
	undo_redo.create_action(action_name)
	undo_redo.add_do_property(target, property, new_value)
	if new_value is Resource:
		undo_redo.add_do_reference(new_value)
	undo_redo.add_undo_property(target, property, old_value)
	if old_value is Resource:
		undo_redo.add_undo_reference(old_value)
	undo_redo.commit_action()


## ── Game-command timeout diagnostics ──────────────────────────────────────────
## Shared by the file-IPC `_send_game_command` helpers (runtime/test commands).
## The goal is to never tell the agent "the game isn't running / autoload missing"
## when the game IS running and merely paused by a runtime error.

## Locate the editor's ScriptEditorDebugger node (BFS from base control).
static func _find_script_editor_debugger() -> Node:
	var base := EditorInterface.get_base_control()
	if base == null:
		return null
	var queue: Array[Node] = [base]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node.get_class() == "ScriptEditorDebugger":
			return node
		for child in node.get_children():
			queue.append(child)
	return null


## Look up an editor theme icon by name (locale-independent), or null.
static func _get_editor_icon(icon_name: String) -> Texture2D:
	var base := EditorInterface.get_base_control()
	if base != null and base.has_theme_icon(icon_name, "EditorIcons"):
		return base.get_theme_icon(icon_name, "EditorIcons")
	return null


## Find the debugger "Continue" button without relying on UI text.
## The editor is translated, so matching tooltip/label text breaks for
## non-English editors (issue #34: Italian → "Continua"). Match by the editor
## theme icon "DebugContinue" first, falling back to the English text only if
## the icon can't be resolved.
static func _find_debugger_continue_button() -> Button:
	var dbg := _find_script_editor_debugger()
	if dbg == null:
		return null
	var continue_icon := _get_editor_icon("DebugContinue")
	var fallback: Button = null
	var inner: Array[Node] = [dbg]
	while not inner.is_empty():
		var n: Node = inner.pop_front()
		if n is Button:
			var b := n as Button
			if continue_icon != null and b.icon == continue_icon:
				return b
			if b.tooltip_text == "Continue":
				fallback = b
		for c in n.get_children():
			inner.append(c)
	return fallback


## True when the running game is halted at a breakpoint or runtime error
## (the debugger's "Continue" button is present and enabled).
func is_debugger_paused() -> bool:
	var btn := _find_debugger_continue_button()
	return btn != null and not btn.disabled


## Read recent runtime errors, so a timeout caused by a script error can
## report the actual cause inline. Prefers the structured ring buffer fed by
## mcp_debugger_plugin.gd's "debug_data" hook; falls back to scraping the
## debugger's "Errors" tab Tree only if that buffer isn't available (e.g. the
## hook failed to attach on this Godot version — see mcp_debugger_plugin.gd).
func collect_debugger_errors(max_errors: int = 10) -> Array:
	var store: RefCounted = editor_plugin.error_store if "error_store" in editor_plugin else null
	if store != null and not store.is_empty():
		var out_store: Array = []
		for entry: Dictionary in store.get_since(0, max_errors, true):
			var tag: String = "WARNING" if entry.get("is_warning", false) else "ERROR"
			out_store.append("%s: %s:%d - %s" % [
				tag, entry.get("file", ""), entry.get("line", 0), entry.get("description", entry.get("error", "")),
			])
		return out_store

	var out: Array = []
	var dbg := _find_script_editor_debugger()
	if dbg == null:
		return out
	for child in dbg.get_children():
		if child is TabContainer:
			var tab_container := child as TabContainer
			for tab_idx in range(tab_container.get_tab_count()):
				var tab_control: Control = tab_container.get_tab_control(tab_idx)
				if tab_control is VBoxContainer and tab_control.name.begins_with("Errors"):
					for vchild in tab_control.get_children():
						if vchild is Tree:
							var tree := vchild as Tree
							var root_item: TreeItem = tree.get_root()
							if root_item:
								var item: TreeItem = root_item.get_first_child()
								while item and out.size() < max_errors:
									var col0: String = item.get_text(0).strip_edges()
									var col1: String = item.get_text(1).strip_edges()
									var msg: String = col0
									if not col1.is_empty():
										msg = (msg + " " + col1) if not msg.is_empty() else col1
									if not msg.is_empty():
										out.append(msg)
									item = item.get_next()
					break
			break
	return out


## Press the debugger "Continue" button to resume a paused game process.
func try_debugger_continue() -> void:
	var btn := _find_debugger_continue_button()
	if btn != null and not btn.disabled:
		btn.emit_signal("pressed")
		push_warning("[MCP] Auto-resumed debugger after runtime error")


## Build an accurate error for a file-IPC game-command timeout.
## Distinguishes "game not running" from "game running but unresponsive
## (likely paused by a runtime error / breakpoint)" so callers aren't misled
## into thinking the MCP connection is dead or the autoload is missing.
func build_timeout_error(timeout_sec: float) -> Dictionary:
	# Re-check play state at the moment we give up.
	if not get_editor().is_playing_scene():
		return error(
			-32000,
			"Game command timed out after %.1fs and the game process is no longer running." % timeout_sec,
			{
				"game_running": false,
				"suggestion": "The scene stopped. Call play_scene to start it again before sending runtime commands.",
			}
		)

	# The game IS running. Figure out *why* it didn't answer.
	var paused := is_debugger_paused()
	var runtime_errors := collect_debugger_errors(10)
	var data := {
		"game_running": true,
		"debugger_paused": paused,
	}
	if not runtime_errors.is_empty():
		data["runtime_errors"] = runtime_errors

	var msg: String
	if paused or not runtime_errors.is_empty():
		msg = ("Game command timed out after %.1fs, but the game IS running. " % timeout_sec) \
			+ "A runtime/script error paused the scene, so it could not respond to the command."
		data["suggestion"] = "This is NOT a connection or autoload problem. Fix the error in 'runtime_errors' " \
			+ "(or call get_editor_errors for the full list), then retry. The debugger was auto-resumed; " \
			+ "if errors persist, call stop_scene then play_scene to restart cleanly."
	else:
		msg = ("Game command timed out after %.1fs. The game is running but did not respond in time." % timeout_sec)
		data["suggestion"] = "The MCP server connection is fine and the game is running. The command may be slow " \
			+ "or the game may be busy/blocked. Retry with a longer timeout, and call get_editor_errors to check " \
			+ "for runtime errors. In rare cases (custom projects) verify the MCPGameInspector autoload is active."
	return error(-32000, msg, data)


## True when `node_path` is a plain relative path that is safe to resolve
## against the edited scene root. Godot resolves NodePaths starting with "/"
## as ABSOLUTE paths from the SceneTree root, and ".." segments walk upwards —
## both escape the edited scene and silently target the live editor tree.
## Anything but a clean relative path is rejected so callers get an explicit
## "not found" error instead of polluting the editor.
static func is_safe_scene_path(node_path: String) -> bool:
	if node_path.is_empty() or node_path.begins_with("/"):
		return false
	for segment: String in node_path.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


## Prefix marking a session handle rather than a NodePath. "@" cannot appear
## in a Godot node name, so this can never collide with a real relative path
## — no escaping/validation needed to tell the two apart.
const HANDLE_PREFIX := "@id:"

## The handle to hand back to a caller instead of (or alongside) a node_path,
## when it's expected to keep addressing the node after an operation that
## might rename or reparent it. See find_node_by_path() for resolution.
func node_handle(node: Node) -> String:
	return HANDLE_PREFIX + str(node.get_instance_id())


## Find node by path — or by session handle — in the edited scene.
##
## `node_path` is either:
##  - a path relative to the edited scene root: "." for the root itself,
##    "Player/Camera" for a descendant, or "<RootName>/Player/Camera" with
##    the root name prefix. Absolute paths ("/root/...") and paths escaping
##    upward ("../...") are rejected.
##  - a handle in the "@id:<instance_id>" form returned by get_scene_tree
##    and several node-mutating commands (see node_handle()). Unlike a path,
##    a handle survives the node being renamed or reparented within the same
##    editor session, because it doesn't encode a path at all — it's the
##    node's own object identity. It stops resolving once the node is freed
##    or the scene is reloaded, rather than silently pointing at whatever
##    unrelated node/object now happens to reuse that instance id (Godot
##    never reuses a live id; a freed one simply resolves to null via
##    is_instance_valid below).
func find_node_by_path(node_path: String) -> Node:
	if node_path.begins_with(HANDLE_PREFIX):
		return _resolve_node_handle(node_path)

	var root := get_edited_root()
	if root == null:
		return null
	if node_path == "." or node_path == root.name:
		return root
	# Reject absolute or escaping paths before touching has_node/get_node,
	# which would otherwise resolve them against the live editor tree.
	if not is_safe_scene_path(node_path):
		return null
	# Try relative from root
	if root.has_node(node_path):
		return root.get_node(node_path)
	# Try with root name prefix stripped
	if node_path.begins_with(root.name + "/"):
		var rel := node_path.substr(root.name.length() + 1)
		if root.has_node(rel):
			return root.get_node(rel)
	return null


func _resolve_node_handle(handle: String) -> Node:
	var id_str := handle.substr(HANDLE_PREFIX.length())
	if not id_str.is_valid_int():
		return null
	var obj := instance_from_id(id_str.to_int())
	if obj == null or not is_instance_valid(obj) or not obj is Node:
		return null
	var node := obj as Node
	var root := get_edited_root()
	if root == null:
		return null
	# A handle must resolve inside the edited scene, same as a NodePath must
	# — otherwise it would be a way to reach the live editor's own tree that
	# is_safe_scene_path()'s absolute/".." rejection does not cover, since a
	# handle carries no path segments for that check to inspect in the first
	# place.
	if node != root and not root.is_ancestor_of(node):
		return null
	return node


func is_node_handle(ref: String) -> bool:
	return ref.begins_with(HANDLE_PREFIX)


## A "not found" error phrased for whichever kind of reference `ref` is —
## generic wording for a bad path is actively misleading for a stale handle
## (the node existed, the reference just no longer resolves), so this is
## worth a distinct message at the handful of node-mutating call sites where
## an agent is most likely to be chaining a handle across several calls.
func error_node_not_found(ref: String) -> Dictionary:
	if is_node_handle(ref):
		return error(-32001, "Handle '%s' does not resolve to a node in the currently edited scene" % ref, {
			"suggestion": "The node may have been freed, or the scene was reloaded/reopened since the handle was captured. Call get_scene_tree again for a fresh handle.",
		})
	return error_not_found("Node '%s'" % ref, "Use get_scene_tree to see available nodes")
