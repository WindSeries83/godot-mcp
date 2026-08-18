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


func _register_commands() -> void:
	var command_classes := [
		preload("res://addons/godot_mcp/commands/project_commands.gd"),
		preload("res://addons/godot_mcp/commands/scene_commands.gd"),
		preload("res://addons/godot_mcp/commands/node_commands.gd"),
		preload("res://addons/godot_mcp/commands/script_commands.gd"),
		preload("res://addons/godot_mcp/commands/editor_commands.gd"),
		preload("res://addons/godot_mcp/commands/input_commands.gd"),
		preload("res://addons/godot_mcp/commands/runtime_commands.gd"),
		preload("res://addons/godot_mcp/commands/animation_commands.gd"),
		preload("res://addons/godot_mcp/commands/tilemap_commands.gd"),
		preload("res://addons/godot_mcp/commands/theme_commands.gd"),
		preload("res://addons/godot_mcp/commands/profiling_commands.gd"),
		preload("res://addons/godot_mcp/commands/batch_commands.gd"),
		preload("res://addons/godot_mcp/commands/shader_commands.gd"),
		preload("res://addons/godot_mcp/commands/export_commands.gd"),
		preload("res://addons/godot_mcp/commands/resource_commands.gd"),
		preload("res://addons/godot_mcp/commands/input_map_commands.gd"),
		preload("res://addons/godot_mcp/commands/scene_3d_commands.gd"),
		preload("res://addons/godot_mcp/commands/physics_commands.gd"),
		preload("res://addons/godot_mcp/commands/analysis_commands.gd"),
		preload("res://addons/godot_mcp/commands/animation_tree_commands.gd"),
		preload("res://addons/godot_mcp/commands/audio_commands.gd"),
		preload("res://addons/godot_mcp/commands/navigation_commands.gd"),
		preload("res://addons/godot_mcp/commands/particle_commands.gd"),
		preload("res://addons/godot_mcp/commands/test_commands.gd"),
		preload("res://addons/godot_mcp/commands/android_commands.gd"),
		preload("res://addons/godot_mcp/commands/headless_commands.gd"),
	]

	for cmd_class in command_classes:
		var cmd: Node = cmd_class.new()
		cmd.editor_plugin = editor_plugin
		add_child(cmd)
		var methods: Dictionary = cmd.get_commands()
		for method_name: String in methods:
			_command_handlers[method_name] = methods[method_name]
		# A module that hasn't been given schemas yet (or a stale command_classes
		# entry) just contributes nothing here rather than breaking startup —
		# describe_method() reports those methods as undocumented instead of
		# command_router failing to register anything.
		if cmd.has_method("get_command_schemas"):
			var schemas: Dictionary = cmd.get_command_schemas()
			for method_name: String in schemas:
				_command_schemas[method_name] = schemas[method_name]

	_register_meta_commands()

	print("[MCP] Registered %d commands (%d with schemas)" % [_command_handlers.size(), _command_schemas.size()])


## Router-level commands (get_available_methods, describe_methods,
## describe_method) aren't owned by any command module, but are reachable
## through the same godot_call{method,params} path as everything else so the
## Node side never needs a second RPC shape just to ask "what can I call?".
func _register_meta_commands() -> void:
	_command_handlers["get_available_methods"] = func(_params: Dictionary) -> Dictionary:
		return {"result": {"methods": get_available_methods()}}

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
		"summary": "List every registered method name, unfiltered and without schema detail.",
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
			out[method_name] = _command_schemas[method_name]
		else:
			out[method_name] = {"summary": "", "params": {}, "annotations": {}, "undocumented": true}
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
