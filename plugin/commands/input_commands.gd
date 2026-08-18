@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

const COMMANDS_PATH := "user://mcp_input_commands"


func get_commands() -> Dictionary:
	return {
		"simulate_key": _simulate_key,
		"simulate_mouse_click": _simulate_mouse_click,
		"simulate_mouse_move": _simulate_mouse_move,
		"simulate_action": _simulate_action,
		"simulate_sequence": _simulate_sequence,
	}


func get_command_schemas() -> Dictionary:
	return {
		"simulate_key": {
			"category": "input",
			"summary": "Injects a keyboard event into the running game via file-based IPC.",
			"params": {
				"keycode": {"type": "string", "required": true, "desc": "Key name, e.g. 'A', 'Space', 'Enter'"},
				"pressed": {"type": "bool", "required": false, "default": true},
				"shift": {"type": "bool", "required": false, "default": false},
				"ctrl": {"type": "bool", "required": false, "default": false},
				"alt": {"type": "bool", "required": false, "default": false},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"simulate_mouse_click": {
			"category": "input",
			"summary": "Injects a mouse button event into the running game. When pressed and auto_release are both true, sends a press+release pair in one frame so UI buttons actually fire.",
			"params": {
				"button": {"type": "int", "required": false, "default": 1, "desc": "MouseButton index, e.g. 1 = left"},
				"pressed": {"type": "bool", "required": false, "default": true},
				"double_click": {"type": "bool", "required": false, "default": false},
				"auto_release": {"type": "bool", "required": false, "default": true, "desc": "Also send a release event right after a press"},
				"x": {"type": "float", "required": false, "default": 0.0},
				"y": {"type": "float", "required": false, "default": 0.0},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"simulate_mouse_move": {
			"category": "input",
			"summary": "Injects a mouse motion event into the running game. Marked unhandled (bypassing normal GUI dispatch) automatically when button_mask is set for a drag, unless 'unhandled' is passed explicitly.",
			"params": {
				"x": {"type": "float", "required": false, "default": 0.0},
				"y": {"type": "float", "required": false, "default": 0.0},
				"relative_x": {"type": "float", "required": false, "default": 0.0},
				"relative_y": {"type": "float", "required": false, "default": 0.0},
				"button_mask": {"type": "int", "required": false, "default": 0},
				"unhandled": {"type": "bool", "required": false, "default": false, "desc": "Force unhandled-input dispatch instead of the button_mask-based default"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"simulate_action": {
			"category": "input",
			"summary": "Injects an input action event (as defined in the Input Map) into the running game.",
			"params": {
				"action": {"type": "string", "required": true, "desc": "Input Map action name"},
				"pressed": {"type": "bool", "required": false, "default": true},
				"strength": {"type": "float", "required": false, "default": 1.0},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"simulate_sequence": {
			"category": "input",
			"summary": "Injects a sequence of input events (key/mouse/action) into the running game, either all in one frame or spaced by frame_delay.",
			"params": {
				"events": {"type": "array", "required": true, "desc": "Array of event objects, each with a 'type' field"},
				"frame_delay": {"type": "int", "required": false, "default": 1, "desc": "Frames between events; <=0 sends every event in a single frame"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
	}


func _simulate_key(params: Dictionary) -> Dictionary:
	var result := require_string(params, "keycode")
	if result[1] != null:
		return result[1]
	var keycode: String = result[0]

	var pressed: bool = optional_bool(params, "pressed", true)
	var shift: bool = optional_bool(params, "shift", false)
	var ctrl: bool = optional_bool(params, "ctrl", false)
	var alt: bool = optional_bool(params, "alt", false)

	var event := {
		"type": "key",
		"keycode": keycode,
		"pressed": pressed,
		"shift": shift,
		"ctrl": ctrl,
		"alt": alt,
	}
	_write_commands([event])
	return success({"sent": true, "event": event})


func _simulate_mouse_click(params: Dictionary) -> Dictionary:
	var button: int = optional_int(params, "button", 1)  # MOUSE_BUTTON_LEFT
	var pressed: bool = optional_bool(params, "pressed", true)
	var double_click: bool = optional_bool(params, "double_click", false)
	var auto_release: bool = optional_bool(params, "auto_release", true)
	var x: float = optional_float(params, "x", 0.0)
	var y: float = optional_float(params, "y", 0.0)

	var press_event := {
		"type": "mouse_button",
		"button": button,
		"pressed": pressed,
		"double_click": double_click,
		"position": {"x": x, "y": y},
	}

	# Auto-release: send press + release in sequence so UI buttons actually fire
	if pressed and auto_release:
		var release_event := press_event.duplicate()
		release_event["pressed"] = false
		var sequence_data := {
			"sequence_events": [press_event, release_event],
			"frame_delay": 1,
		}
		var json := JSON.stringify(sequence_data)
		var file := FileAccess.open(COMMANDS_PATH, FileAccess.WRITE)
		if file == null:
			return error_internal("Failed to write commands: %s" % error_string(FileAccess.get_open_error()))
		file.store_string(json)
		file.close()
		return success({"sent": true, "event": press_event, "auto_release": true})

	_write_commands([press_event])
	return success({"sent": true, "event": press_event})


func _simulate_mouse_move(params: Dictionary) -> Dictionary:
	var x: float = optional_float(params, "x", 0.0)
	var y: float = optional_float(params, "y", 0.0)
	var rel_x: float = optional_float(params, "relative_x", 0.0)
	var rel_y: float = optional_float(params, "relative_y", 0.0)
	var button_mask: int = optional_int(params, "button_mask", 0)
	var unhandled_explicit: bool = params.has("unhandled")
	var unhandled: bool = optional_bool(params, "unhandled", false)

	var event := {
		"type": "mouse_motion",
		"position": {"x": x, "y": y},
		"relative": {"x": rel_x, "y": rel_y},
		"button_mask": button_mask,
	}
	# Auto-enable unhandled for drag motions (camera-pan use case) ONLY when
	# the caller did NOT explicitly pass an "unhandled" key. If they passed
	# one — true or false — honor it. This lets UI drag-and-drop tests opt
	# back into normal GUI dispatch by passing unhandled: false explicitly.
	if unhandled_explicit:
		event["unhandled"] = unhandled
	elif button_mask > 0:
		event["unhandled"] = true
	_write_commands([event])
	return success({"sent": true, "event": event})


func _simulate_action(params: Dictionary) -> Dictionary:
	var result := require_string(params, "action")
	if result[1] != null:
		return result[1]
	var action_name: String = result[0]

	var pressed: bool = optional_bool(params, "pressed", true)
	var strength: float = optional_float(params, "strength", 1.0)

	var event := {
		"type": "action",
		"action": action_name,
		"pressed": pressed,
		"strength": strength,
	}
	_write_commands([event])
	return success({"sent": true, "event": event})


func _simulate_sequence(params: Dictionary) -> Dictionary:
	if not params.has("events") or not params["events"] is Array:
		return error_invalid_params("Missing required parameter: events (Array)")

	var events: Array = params["events"]
	if events.is_empty():
		return error_invalid_params("Events array is empty")

	var frame_delay: int = optional_int(params, "frame_delay", 1)

	for entry: Variant in events:
		# Typed iteration would raise on a non-Dictionary entry, and `as String`
		# raises on a non-String type — both abort before any response is sent.
		if not entry is Dictionary:
			return error_invalid_params("Each sequence event must be an object, got %s" % type_string(typeof(entry)))
		var event_data: Dictionary = entry
		if not event_data.has("type") or not event_data["type"] is String or (event_data["type"] as String).is_empty():
			return error_invalid_params("Invalid event in sequence: %s" % str(event_data))

	if frame_delay <= 0:
		# All events in one frame - write as plain array
		_write_commands(events)
	else:
		# Sequence with frame delay - game side handles timing
		var sequence_data := {
			"sequence_events": events,
			"frame_delay": frame_delay,
		}
		var json := JSON.stringify(sequence_data)
		var file := FileAccess.open(COMMANDS_PATH, FileAccess.WRITE)
		if file == null:
			return error_internal("Failed to write commands: %s" % error_string(FileAccess.get_open_error()))
		file.store_string(json)
		file.close()

	return success({"sent": true, "event_count": events.size(), "frame_delay": frame_delay})


func _write_commands(events: Array) -> void:
	var json := JSON.stringify(events)
	var file := FileAccess.open(COMMANDS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[MCP Input] Failed to write commands: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(json)
	file.close()
