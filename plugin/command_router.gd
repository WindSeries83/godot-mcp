@tool
extends Node

var editor_plugin: EditorPlugin

var _command_handlers: Dictionary = {}  # method_name -> Callable
var _command_schemas: Dictionary = {}  # method_name -> schema Dictionary (see base_command.gd)
var _disabled_tools: Dictionary = {}  # method_name -> true

const TOOL_CONFIG_PATH := "user://mcp_tool_config.cfg"


func _ready() -> void:
	_load_tool_config()
	_register_commands()


## Built-in command modules, by file basename. Deliberately NOT preload():
## preload() resolves at compile time, so a parse error in any single module
## (or in base_command.gd, which they all extend) prevented command_router.gd
## itself from compiling and took the whole plugin down with it — see the
## Godot 4.3 `var x := typed_array.pop_front()` breakage. Runtime load() lets
## one bad module degrade to N-1 working modules instead of zero, and reports
## which one failed through get_unavailable_modules().
const _BUILTIN_MODULES: Array[String] = [
	"project_commands",
	"scene_commands",
	"node_commands",
	"script_commands",
	"editor_commands",
	"input_commands",
	"runtime_commands",
	"animation_commands",
	"tilemap_commands",
	"theme_commands",
	"profiling_commands",
	"batch_commands",
	"shader_commands",
	"export_commands",
	"resource_commands",
	"input_map_commands",
	"scene_3d_commands",
	"physics_commands",
	"analysis_commands",
	"animation_tree_commands",
	"audio_commands",
	"navigation_commands",
	"particle_commands",
	"test_commands",
	"android_commands",
	"headless_commands",
]

## module basename -> reason it could not be registered.
var _unavailable_modules: Dictionary = {}


func _register_commands() -> void:
	for module_name: String in _BUILTIN_MODULES:
		_register_builtin_module(module_name)

	_register_user_commands()
	_register_meta_commands()

	if _unavailable_modules.is_empty():
		print("[MCP] Registered %d commands (%d with schemas)" % [
			_command_handlers.size(), _command_schemas.size()
		])
	else:
		# Loud, because a silently smaller tool surface is worse than a crash:
		# an agent would just see methods "not existing" with no explanation.
		push_warning("[MCP] %d command module(s) unavailable: %s" % [
			_unavailable_modules.size(), ", ".join(_unavailable_modules.keys())
		])
		print("[MCP] Registered %d commands (%d with schemas), %d module(s) UNAVAILABLE: %s" % [
			_command_handlers.size(), _command_schemas.size(),
			_unavailable_modules.size(), ", ".join(_unavailable_modules.keys())
		])


## Loads and registers one built-in module, recording the reason in
## _unavailable_modules instead of raising if it can't be used. Note that a
## GDScript parse error makes load() return null without throwing, which is
## exactly the case that used to be fatal here.
func _register_builtin_module(module_name: String) -> void:
	var script_path := "res://addons/godot_mcp/commands/%s.gd" % module_name

	var script: Variant = load(script_path)
	if script == null or not (script is Script):
		_unavailable_modules[module_name] = "script failed to load (parse error, or file missing)"
		return

	var instance: Object = (script as Script).new()
	if not (instance is Node):
		_unavailable_modules[module_name] = "script is not a Node subclass"
		return
	if not instance.has_method("get_commands"):
		_unavailable_modules[module_name] = "script does not expose get_commands()"
		return

	var cmd: Node = instance
	cmd.editor_plugin = editor_plugin
	add_child(cmd)

	var methods: Dictionary = cmd.get_commands()
	for method_name: String in methods:
		_command_handlers[method_name] = methods[method_name]
	# A module that hasn't been given schemas yet just contributes nothing
	# here rather than breaking startup — describe_method() reports those
	# methods as undocumented instead of command_router failing to register.
	if cmd.has_method("get_command_schemas"):
		var schemas: Dictionary = cmd.get_command_schemas()
		for method_name: String in schemas:
			_command_schemas[method_name] = schemas[method_name]


## Built-in modules that could not be registered this session, as
## {module_name: reason}. Surfaced through the discovery layer so an agent
## seeing a method "missing" can tell a degraded addon apart from a method
## that never existed.
func get_unavailable_modules() -> Dictionary:
	return _unavailable_modules.duplicate()


## Project-side extension point: any *.gd file dropped into
## res://addons/godot_mcp_user_commands/ that extends base_command.gd and
## exposes get_commands() (optionally get_command_schemas()) is picked up
## automatically, same as a built-in module — no fork of this repo needed.
## Lives outside plugin/ so it isn't wiped out by an addon update.
func _register_user_commands() -> void:
	const USER_COMMANDS_DIR := "res://addons/godot_mcp_user_commands"
	if not DirAccess.dir_exists_absolute(USER_COMMANDS_DIR):
		return
	var dir := DirAccess.open(USER_COMMANDS_DIR)
	if dir == null:
		return

	var registered := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".gd"):
			if _register_user_command_file(USER_COMMANDS_DIR + "/" + file_name):
				registered += 1
		file_name = dir.get_next()
	dir.list_dir_end()

	if registered > 0:
		print("[MCP] Registered %d user command module(s) from %s" % [registered, USER_COMMANDS_DIR])


## Loads and registers a single *.gd file from the user command modules
## directory. Returns false (and just warns) instead of crashing addon
## startup when the file isn't a valid command module, since this directory
## is user-edited and may contain a script mid-edit or with a typo.
func _register_user_command_file(script_path: String) -> bool:
	var script: Variant = load(script_path)
	if script == null or not (script is Script):
		push_warning("[MCP] Could not load user command module '%s'" % script_path)
		return false

	var cmd: Object = (script as Script).new()
	if not (cmd is Node) or not cmd.has_method("get_commands"):
		push_warning("[MCP] '%s' does not look like a command module (must extend base_command.gd and expose get_commands()); skipped" % script_path)
		return false

	if "editor_plugin" in cmd:
		cmd.editor_plugin = editor_plugin
	add_child(cmd)

	var methods: Dictionary = cmd.get_commands()
	var added_names: Array = []
	for method_name: String in methods:
		if _command_handlers.has(method_name):
			push_warning("[MCP] User command module '%s' redefines existing method '%s'; ignoring to protect built-ins" % [script_path, method_name])
			continue
		_command_handlers[method_name] = methods[method_name]
		added_names.append(method_name)

	if cmd.has_method("get_command_schemas"):
		var schemas: Dictionary = cmd.get_command_schemas()
		for method_name: String in schemas:
			if method_name in added_names:
				_command_schemas[method_name] = schemas[method_name]

	return true


## Router-level commands (get_available_methods, describe_methods,
## describe_method) aren't owned by any command module, but are reachable
## through the same godot_call{method,params} path as everything else so the
## Node side never needs a second RPC shape just to ask "what can I call?".
func _register_meta_commands() -> void:
	_command_handlers["get_available_methods"] = func(_params: Dictionary) -> Dictionary:
		return {"result": {
			"methods": get_available_methods(),
			"unavailable_modules": _unavailable_modules,
		}}

	_command_handlers["describe_methods"] = func(params: Dictionary) -> Dictionary:
		var names: Variant = params.get("methods", [])
		if not names is Array:
			return {"error": {"code": -32602, "message": "'methods' must be an array of method names, or omitted"}}
		var category: Variant = params.get("category", "")
		if not category is String:
			return {"error": {"code": -32602, "message": "'category' must be a string, or omitted"}}
		return {"result": describe_methods(names, category)}

	_command_handlers["describe_method"] = func(params: Dictionary) -> Dictionary:
		var names: Variant = params.get("methods")
		if names == null:
			return {"error": {"code": -32602, "message": "Missing required parameter: methods (array of method names)"}}
		if not names is Array:
			return {"error": {"code": -32602, "message": "'methods' must be an array of method names"}}
		return {"result": describe_method(names)}

	_command_schemas["get_available_methods"] = {
		"category": "meta",
		"summary": "List every registered method name, unfiltered and without schema detail. Also returns unavailable_modules: built-in command modules that failed to load this session (empty on a healthy addon), so a missing method can be told apart from a degraded install.",
		"params": {},
		"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
	}
	_command_schemas["describe_methods"] = {
		"category": "meta",
		"summary": "Compact listing (category, one-line summary, annotations) for the given methods, or all of them if omitted.",
		"params": {
			"methods": {"type": "array", "required": false, "desc": "Method names to describe; omit for every registered method"},
			"category": {"type": "string", "required": false, "desc": "Restrict to methods in this category"},
		},
		"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
	}
	_command_schemas["describe_method"] = {
		"category": "meta",
		"summary": "Full schema (category, summary, params, annotations) for the given methods.",
		"params": {
			"methods": {"type": "array", "required": true, "desc": "Method names to fetch full schemas for"},
		},
		"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
	}


func execute(method: String, params: Dictionary) -> Dictionary:
	if not _command_handlers.has(method):
		return {
			"error": {
				"code": -32601,
				"message": "Method not found: %s" % method,
				"data": {"available_methods": _command_handlers.keys()}
			}
		}

	if _disabled_tools.has(method):
		return {
			"error": {
				"code": -32603,
				"message": "Tool '%s' is disabled in MCP Server settings" % method
			}
		}

	if _requires_confirm(_command_schemas.get(method, {}), params):
		return {
			"error": {
				"code": -32009,
				"message": "'%s' writes to disk (or another persistent target outside EditorUndoRedoManager) and requires explicit confirmation." % method,
				"data": {
					"suggestion": "Retry the same call with confirm: true in params once you've verified this is intended.",
				}
			}
		}

	var handler: Callable = _command_handlers[method]
	# Not typed as Dictionary on assignment: a handler that returns something
	# else would raise here, aborting the coroutine so no response is ever
	# sent and the caller waits out its whole timeout instead of being told
	# what went wrong.
	var result: Variant = await handler.call(params)
	if not result is Dictionary:
		return {
			"error": {
				"code": -32603,
				"message": "Handler for '%s' returned %s instead of a result dictionary" % [
					method, type_string(typeof(result))
				],
			}
		}
	return result


## True when `schema` marks its method annotations.confirm:true and `params`
## doesn't carry confirm:true itself. Pure and static so it's testable from
## GDScript headless test runners without an EditorPlugin/editor_plugin.
static func _requires_confirm(schema: Dictionary, params: Dictionary) -> bool:
	var annotations: Dictionary = schema.get("annotations", {})
	if not annotations.get("confirm", false):
		return false
	return not (params.get("confirm", false) == true)


func get_available_methods() -> Array:
	return _command_handlers.keys()


## Compact listing: method name, category, one-line summary, annotations — no
## param detail. Pass `method_names` to restrict to specific methods, and/or
## `category` to filter by the category each module assigns its own methods
## in get_command_schemas() (see base_command.gd). Both empty means
## everything.
func describe_methods(method_names: Array = [], category: String = "") -> Dictionary:
	var wanted: Array = method_names if not method_names.is_empty() else _command_handlers.keys()
	var out: Dictionary = {}
	for method_name: String in wanted:
		if not _command_handlers.has(method_name):
			continue
		var schema: Dictionary = _command_schemas.get(method_name, {})
		var method_category: String = schema.get("category", "")
		if not category.is_empty() and method_category != category:
			continue
		out[method_name] = {
			"category": method_category,
			"summary": schema.get("summary", ""),
			"annotations": schema.get("annotations", {}),
			"has_schema": _command_schemas.has(method_name),
		}
	return out


## Full schema (summary, params, annotations) for one or more named methods.
func describe_method(method_names: Array) -> Dictionary:
	var out: Dictionary = {}
	for method_name: String in method_names:
		if not _command_handlers.has(method_name):
			out[method_name] = {"error": "Unknown method"}
		elif _command_schemas.has(method_name):
			out[method_name] = _with_confirm_param(_command_schemas[method_name])
		else:
			out[method_name] = {"summary": "", "params": {}, "annotations": {}, "undocumented": true}
	return out


## Adds a synthetic "confirm" param to a schema's params when its own
## annotations.confirm is true, so an agent calling godot_describe sees the
## gate without any module having to hand-write this param itself (which
## would drift the moment the module's annotations changed).
func _with_confirm_param(schema: Dictionary) -> Dictionary:
	var annotations: Dictionary = schema.get("annotations", {})
	if not annotations.get("confirm", false):
		return schema
	var out: Dictionary = schema.duplicate(true)
	var params: Dictionary = out.get("params", {}).duplicate(true)
	params["confirm"] = {
		"type": "bool",
		"required": false,
		"default": false,
		"desc": "This method writes to disk (or another persistent target outside EditorUndoRedoManager) and is irreversible via Ctrl-Z. Pass true to proceed.",
	}
	out["params"] = params
	return out


func is_tool_disabled(method: String) -> bool:
	return _disabled_tools.has(method)


func set_tool_disabled(method: String, disabled: bool) -> void:
	if disabled:
		_disabled_tools[method] = true
	else:
		_disabled_tools.erase(method)
	_save_tool_config()


func set_all_tools_disabled(disabled: bool) -> void:
	if disabled:
		for method: String in _command_handlers:
			_disabled_tools[method] = true
	else:
		_disabled_tools.clear()
	_save_tool_config()


func _load_tool_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(TOOL_CONFIG_PATH) != OK:
		return
	if not cfg.has_section("disabled_tools"):
		return
	for method: String in cfg.get_section_keys("disabled_tools"):
		if cfg.get_value("disabled_tools", method, false):
			_disabled_tools[method] = true


func _save_tool_config() -> void:
	var cfg := ConfigFile.new()
	for method: String in _disabled_tools:
		cfg.set_value("disabled_tools", method, true)
	cfg.save(TOOL_CONFIG_PATH)
