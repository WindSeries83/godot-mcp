@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

## Editor-side commands for runtime game inspection.
## Communicates with MCPGameInspector autoload via file-based IPC.


func get_commands() -> Dictionary:
	return {
		"get_game_scene_tree": _get_game_scene_tree,
		"get_game_node_properties": _get_game_node_properties,
		"set_game_node_property": _set_game_node_property,
		"capture_frames": _capture_frames,
		"monitor_properties": _monitor_properties,
		"execute_game_script": _execute_game_script,
		"start_recording": _start_recording,
		"stop_recording": _stop_recording,
		"replay_recording": _replay_recording,
		"find_nodes_by_script": _find_nodes_by_script,
		"get_autoload": _get_autoload,
		"batch_get_properties": _batch_get_properties,
		"find_ui_elements": _find_ui_elements,
		"click_button_by_text": _click_button_by_text,
		"wait_for_node": _wait_for_node,
		"find_nearby_nodes": _find_nearby_nodes,
		"navigate_to": _navigate_to,
		"move_to": _move_to,
		"watch_signals": _watch_signals,
	}


func get_command_schemas() -> Dictionary:
	return {
		"get_game_scene_tree": {
			"category": "runtime",
			"summary": "Returns the running game's scene tree via file-based IPC to the MCPGameInspector autoload.",
			"params": {
				"max_depth": {"type": "int", "required": false, "default": -1, "desc": "Maximum recursion depth; -1 for unlimited"},
				"script_filter": {"type": "string", "required": false, "default": "", "desc": "Only include nodes whose script path matches this"},
				"type_filter": {"type": "string", "required": false, "default": "", "desc": "Only include nodes of this class"},
				"named_only": {"type": "bool", "required": false, "default": false, "desc": "Only include nodes with a non-default name"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"get_game_node_properties": {
			"category": "runtime",
			"summary": "Reads properties of a node in the running game via game IPC.",
			"params": {
				"node_path": {"type": "string", "required": true},
				"properties": {"type": "array", "required": false, "default": [], "desc": "Property names to read; all properties if omitted"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"set_game_node_property": {
			"category": "runtime",
			"summary": "Sets a property on a node in the running game via game IPC.",
			"params": {
				"node_path": {"type": "string", "required": true},
				"property": {"type": "string", "required": true},
				"value": {"type": "any", "required": true},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"capture_frames": {
			"category": "runtime",
			"summary": "Captures a sequence of frames from the running game via game IPC. Timeout scales with count * frame_interval.",
			"params": {
				"count": {"type": "int", "required": false, "default": 5, "desc": "Number of frames to capture"},
				"frame_interval": {"type": "int", "required": false, "default": 10, "desc": "Engine frames between captures"},
				"half_resolution": {"type": "bool", "required": false, "default": true},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"monitor_properties": {
			"category": "runtime",
			"summary": "Samples a node's properties over a number of frames in the running game via game IPC. Timeout scales with frame_count * frame_interval.",
			"params": {
				"node_path": {"type": "string", "required": true},
				"properties": {"type": "array", "required": true, "desc": "Property names to sample each frame"},
				"frame_count": {"type": "int", "required": false, "default": 60},
				"frame_interval": {"type": "int", "required": false, "default": 1, "desc": "Engine frames between samples"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"execute_game_script": {
			"category": "runtime",
			"summary": "Compiles and runs arbitrary GDScript inside the running game process via game IPC (10s timeout).",
			"params": {
				"code": {"type": "string", "required": true},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"start_recording": {
			"category": "runtime",
			"summary": "Starts recording input/state events in the running game via game IPC.",
			"params": {},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"stop_recording": {
			"category": "runtime",
			"summary": "Stops the current recording in the running game via game IPC (5s timeout).",
			"params": {},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"replay_recording": {
			"category": "runtime",
			"summary": "Replays a previously captured list of events in the running game via game IPC. Timeout is derived from the events' time_ms and speed, capped at 120s.",
			"params": {
				"events": {"type": "array", "required": true, "desc": "Array of event objects, each with a numeric 'time_ms'"},
				"speed": {"type": "float", "required": false, "default": 1.0, "desc": "Playback speed multiplier"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"find_nodes_by_script": {
			"category": "runtime",
			"summary": "Finds nodes in the running game whose attached script matches, via game IPC.",
			"params": {
				"script": {"type": "string", "required": true, "desc": "Script res:// path to match"},
				"properties": {"type": "array", "required": false, "default": [], "desc": "Property names to include for each match; all properties if omitted"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"get_autoload": {
			"category": "runtime",
			"summary": "Reads an autoload singleton's properties in the running game via game IPC.",
			"params": {
				"name": {"type": "string", "required": true, "desc": "Autoload name"},
				"properties": {"type": "array", "required": false, "default": [], "desc": "Property names to read; all properties if omitted"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"batch_get_properties": {
			"category": "runtime",
			"summary": "Reads properties for multiple nodes in one round trip to the running game via game IPC.",
			"params": {
				"nodes": {"type": "array", "required": true, "desc": "Array of {node_path, properties} request objects"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"find_ui_elements": {
			"category": "runtime",
			"summary": "Lists visible UI elements (with their text) in the running game via game IPC.",
			"params": {
				"type_filter": {"type": "string", "required": false, "default": "", "desc": "Only include elements of this Control class"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"click_button_by_text": {
			"category": "runtime",
			"summary": "Finds a UI button by its visible text in the running game and clicks it via game IPC. Can trigger arbitrary in-game actions.",
			"params": {
				"text": {"type": "string", "required": true},
				"partial": {"type": "bool", "required": false, "default": true, "desc": "Match as a substring instead of an exact match"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"wait_for_node": {
			"category": "runtime",
			"summary": "Polls the running game via game IPC until a node exists (or a timeout elapses).",
			"params": {
				"node_path": {"type": "string", "required": true},
				"timeout": {"type": "float", "required": false, "default": 5.0, "desc": "Seconds to wait before giving up"},
				"poll_frames": {"type": "int", "required": false, "default": 5, "desc": "Engine frames between polls"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"find_nearby_nodes": {
			"category": "runtime",
			"summary": "Finds nodes near a world position in the running game via game IPC.",
			"params": {
				"position": {"type": "any", "required": true, "desc": "{x, y, z} or {x, y} world position"},
				"radius": {"type": "float", "required": false, "default": 0.0},
				"type_filter": {"type": "string", "required": false, "default": "", "desc": "Only include nodes of this class"},
				"group_filter": {"type": "string", "required": false, "default": "", "desc": "Only include nodes in this group"},
				"max_results": {"type": "int", "required": false, "default": 0},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"navigate_to": {
			"category": "runtime",
			"summary": "Directs the game-side player toward a target via game IPC (pathfinding/steering handled game-side).",
			"params": {
				"target": {"type": "any", "required": true, "desc": "Node path string or {x, y, z} world position"},
				"player_path": {"type": "string", "required": false, "default": "", "desc": "Node path to the player; game-side default if omitted"},
				"camera_path": {"type": "string", "required": false, "default": "", "desc": "Node path to the camera; game-side default if omitted"},
				"move_speed": {"type": "float", "required": false, "default": 0.0, "desc": "Game-side default used if omitted"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"move_to": {
			"category": "runtime",
			"summary": "Moves the game-side player to a target and waits for arrival via game IPC. IPC timeout is the game-side timeout plus 5s overhead.",
			"params": {
				"target": {"type": "any", "required": true, "desc": "Node path string or {x, y, z} world position"},
				"player_path": {"type": "string", "required": false, "default": "", "desc": "Node path to the player; game-side default if omitted"},
				"camera_path": {"type": "string", "required": false, "default": "", "desc": "Node path to the camera; game-side default if omitted"},
				"arrival_radius": {"type": "float", "required": false, "default": 0.0, "desc": "Game-side default used if omitted"},
				"timeout": {"type": "float", "required": false, "default": 15.0, "desc": "Seconds to wait for arrival; also extends the IPC wait"},
				"run": {"type": "bool", "required": false, "default": false, "desc": "Game-side default used if omitted"},
				"look_at_target": {"type": "bool", "required": false, "default": false, "desc": "Game-side default used if omitted"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"watch_signals": {
			"category": "runtime",
			"summary": "Records signal emissions from the given nodes over a duration in the running game via game IPC.",
			"params": {
				"node_paths": {"type": "array", "required": true},
				"signal_filter": {"type": "array", "required": false, "default": [], "desc": "Only record these signal names; all signals if omitted"},
				"duration_ms": {"type": "int", "required": false, "default": 5000},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
	}


func _get_game_scene_tree(params: Dictionary) -> Dictionary:
	var max_depth: int = optional_int(params, "max_depth", -1)
	var cmd_params := {"max_depth": max_depth}

	var script_filter: String = optional_string(params, "script_filter")
	if not script_filter.is_empty():
		cmd_params["script_filter"] = script_filter

	var type_filter: String = optional_string(params, "type_filter")
	if not type_filter.is_empty():
		cmd_params["type_filter"] = type_filter

	var named_only: bool = optional_bool(params, "named_only", false)
	if named_only:
		cmd_params["named_only"] = true

	return await send_game_command("get_scene_tree", cmd_params)


func _get_game_node_properties(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]

	var cmd_params := {"node_path": result[0]}
	# Optional property filter
	if params.has("properties") and params["properties"] is Array:
		cmd_params["properties"] = params["properties"]

	return await send_game_command("get_node_properties", cmd_params)


func _set_game_node_property(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]

	var prop_result := require_string(params, "property")
	if prop_result[1] != null:
		return prop_result[1]

	if not params.has("value"):
		return error_invalid_params("Missing required parameter: value")

	return await send_game_command("set_node_property", {
		"node_path": result[0],
		"property": prop_result[0],
		"value": params["value"],
	})


func _execute_game_script(params: Dictionary) -> Dictionary:
	var result := require_string(params, "code")
	if result[1] != null:
		return result[1]

	return await send_game_command("execute_script", {
		"code": result[0],
	}, 10.0)


func _capture_frames(params: Dictionary) -> Dictionary:
	var count: int = optional_int(params, "count", 5)
	var frame_interval: int = optional_int(params, "frame_interval", 10)
	var half_resolution: bool = optional_bool(params, "half_resolution", true)

	# Dynamic timeout: allow enough time for frame capture
	# At 60fps, 30 frames * 10 interval = 300 frames = 5 seconds + overhead
	var estimated_seconds: float = (count * frame_interval) / 60.0 + 2.0
	var timeout := minf(estimated_seconds, 25.0)

	return await send_game_command("capture_frames", {
		"count": count,
		"frame_interval": frame_interval,
		"half_resolution": half_resolution,
	}, timeout)


func _monitor_properties(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]

	if not params.has("properties") or not params["properties"] is Array:
		return error_invalid_params("'properties' array is required")

	var frame_count: int = optional_int(params, "frame_count", 60)
	var frame_interval: int = optional_int(params, "frame_interval", 1)

	# Dynamic timeout
	var estimated_seconds: float = (frame_count * frame_interval) / 60.0 + 2.0
	var timeout := minf(estimated_seconds, 25.0)

	return await send_game_command("monitor_properties", {
		"node_path": result[0],
		"properties": params["properties"],
		"frame_count": frame_count,
		"frame_interval": frame_interval,
	}, timeout)


func _start_recording(params: Dictionary) -> Dictionary:
	return await send_game_command("start_recording", {})


func _stop_recording(params: Dictionary) -> Dictionary:
	return await send_game_command("stop_recording", {}, 5.0)


func _replay_recording(params: Dictionary) -> Dictionary:
	# `for e: Dictionary in ...` raises on the first non-Dictionary entry,
	# aborting the handler before it can answer.
	var events_guard := require_dictionary_array(params, "events")
	if not events_guard.is_empty():
		return events_guard
	var speed: float = optional_float(params, "speed", 1.0)

	# Calculate timeout based on event duration
	var max_time_ms: int = 0
	for event_data: Dictionary in params["events"]:
		# time_ms comes straight from JSON; int() raises on an array or object.
		var raw_t: Variant = event_data.get("time_ms", 0)
		var t: int = int(raw_t) if (raw_t is int or raw_t is float or raw_t is bool) else 0
		if t > max_time_ms:
			max_time_ms = t
	var timeout := (max_time_ms / 1000.0 / speed) + 5.0

	return await send_game_command("replay_recording", {
		"events": params["events"],
		"speed": speed,
	}, minf(timeout, 120.0))


func _find_nodes_by_script(params: Dictionary) -> Dictionary:
	var result := require_string(params, "script")
	if result[1] != null:
		return result[1]

	var cmd_params := {"script": result[0]}
	if params.has("properties") and params["properties"] is Array:
		cmd_params["properties"] = params["properties"]

	return await send_game_command("find_nodes_by_script", cmd_params)


func _get_autoload(params: Dictionary) -> Dictionary:
	var result := require_string(params, "name")
	if result[1] != null:
		return result[1]

	var cmd_params := {"name": result[0]}
	if params.has("properties") and params["properties"] is Array:
		cmd_params["properties"] = params["properties"]

	return await send_game_command("get_autoload", cmd_params)


func _batch_get_properties(params: Dictionary) -> Dictionary:
	if not params.has("nodes") or not params["nodes"] is Array:
		return error_invalid_params("'nodes' array is required")

	return await send_game_command("batch_get_properties", {
		"nodes": params["nodes"],
	})


func _find_ui_elements(params: Dictionary) -> Dictionary:
	var cmd_params := {}
	var type_filter: String = optional_string(params, "type_filter")
	if not type_filter.is_empty():
		cmd_params["type_filter"] = type_filter
	return await send_game_command("find_ui_elements", cmd_params)


func _click_button_by_text(params: Dictionary) -> Dictionary:
	var result := require_string(params, "text")
	if result[1] != null:
		return result[1]

	var cmd_params := {"text": result[0]}
	var partial: bool = optional_bool(params, "partial", true)
	cmd_params["partial"] = partial

	return await send_game_command("click_button_by_text", cmd_params)


func _wait_for_node(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]

	var timeout: float = optional_float(params, "timeout", 5.0)
	var poll_frames: int = optional_int(params, "poll_frames", 5)

	return await send_game_command("wait_for_node", {
		"node_path": result[0],
		"timeout": timeout,
		"poll_frames": poll_frames,
	}, timeout + 2.0)


func _find_nearby_nodes(params: Dictionary) -> Dictionary:
	if not params.has("position"):
		return error_invalid_params("Missing required parameter: position")

	var cmd_params: Dictionary = {"position": params["position"]}
	if params.has("radius"):
		cmd_params["radius"] = optional_float(params, "radius")
	var type_filter: String = optional_string(params, "type_filter")
	if not type_filter.is_empty():
		cmd_params["type_filter"] = type_filter
	var group_filter: String = optional_string(params, "group_filter")
	if not group_filter.is_empty():
		cmd_params["group_filter"] = group_filter
	if params.has("max_results"):
		cmd_params["max_results"] = optional_int(params, "max_results")

	return await send_game_command("find_nearby_nodes", cmd_params)


func _navigate_to(params: Dictionary) -> Dictionary:
	if not params.has("target"):
		return error_invalid_params("Missing required parameter: target")

	var cmd_params: Dictionary = {"target": params["target"]}
	var player_path: String = optional_string(params, "player_path")
	if not player_path.is_empty():
		cmd_params["player_path"] = player_path
	var camera_path: String = optional_string(params, "camera_path")
	if not camera_path.is_empty():
		cmd_params["camera_path"] = camera_path
	if params.has("move_speed"):
		cmd_params["move_speed"] = optional_float(params, "move_speed")

	return await send_game_command("navigate_to", cmd_params)


func _move_to(params: Dictionary) -> Dictionary:
	if not params.has("target"):
		return error_invalid_params("Missing required parameter: target")

	var cmd_params: Dictionary = {"target": params["target"]}
	var player_path: String = optional_string(params, "player_path")
	if not player_path.is_empty():
		cmd_params["player_path"] = player_path
	var camera_path: String = optional_string(params, "camera_path")
	if not camera_path.is_empty():
		cmd_params["camera_path"] = camera_path
	if params.has("arrival_radius"):
		cmd_params["arrival_radius"] = optional_float(params, "arrival_radius")
	if params.has("timeout"):
		cmd_params["timeout"] = optional_float(params, "timeout")
	if params.has("run"):
		cmd_params["run"] = optional_bool(params, "run")
	if params.has("look_at_target"):
		cmd_params["look_at_target"] = optional_bool(params, "look_at_target")

	# Dynamic timeout: game-side timeout + overhead for IPC polling
	var game_timeout: float = optional_float(params, "timeout", 15.0)
	var ipc_timeout: float = game_timeout + 5.0

	return await send_game_command("move_to", cmd_params, ipc_timeout)


func _watch_signals(params: Dictionary) -> Dictionary:
	if not params.has("node_paths") or not params["node_paths"] is Array:
		return error_invalid_params("Missing required parameter: node_paths (Array)")

	var cmd_params: Dictionary = {"node_paths": params["node_paths"]}
	if params.has("signal_filter") and params["signal_filter"] is Array:
		cmd_params["signal_filter"] = params["signal_filter"]
	var duration_ms: int = optional_int(params, "duration_ms", 5000)
	cmd_params["duration_ms"] = duration_ms

	# Dynamic timeout: duration + overhead
	var timeout_sec: float = (duration_ms / 1000.0) + 5.0

	return await send_game_command("watch_signals", cmd_params, timeout_sec)
