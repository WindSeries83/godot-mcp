@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

## Test automation framework tools.
## Editor-side orchestration + runtime assertions via file-based IPC.


func get_commands() -> Dictionary:
	return {
		"run_test_scenario": _run_test_scenario,
		"assert_node_state": _assert_node_state,
		"assert_screen_text": _assert_screen_text,
		"run_stress_test": _run_stress_test,
		"get_test_report": _get_test_report,
		"set_determinism": _set_determinism,
		"snapshot_state": _snapshot_state,
		"restore_state": _restore_state,
		"step_frames": _step_frames,
		"wait_for_condition": _wait_for_condition,
	}


func get_command_schemas() -> Dictionary:
	return {
		"run_test_scenario": {
			"category": "test",
			"summary": "Optionally plays a scene, then runs a sequence of steps (input, wait, assert, screenshot) against the running game and returns pass/fail results per step.",
			"params": {
				"steps": {"type": "array", "required": true, "desc": "Step objects: {type:'input'|'wait'|'assert'|'screenshot', ...}"},
				"scene_path": {"type": "string", "required": false, "default": "", "desc": "'main', 'current', or a res:// scene path; if empty, a scene must already be playing"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"assert_node_state": {
			"category": "test",
			"summary": "Asserts a running game node's property against an expected value using the given operator, and records the result for get_test_report.",
			"params": {
				"node_path": {"type": "string", "required": true},
				"property": {"type": "string", "required": true},
				"expected": {"type": "any", "required": true},
				"operator": {"type": "string", "required": false, "default": "eq", "desc": "One of: eq, neq, gt, lt, gte, lte, contains, type_is"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"assert_screen_text": {
			"category": "test",
			"summary": "Asserts that specific text is visible among the running game's UI elements, and records the result for get_test_report.",
			"params": {
				"text": {"type": "string", "required": true},
				"partial": {"type": "bool", "required": false, "default": true, "desc": "Match as a substring instead of an exact match"},
				"case_sensitive": {"type": "bool", "required": false, "default": true},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"run_stress_test": {
			"category": "test",
			"summary": "Sends rapid random input actions to the running game for a duration and reports whether it crashed and how many new log errors appeared.",
			"params": {
				"duration": {"type": "float", "required": false, "default": 5.0, "desc": "Seconds to run; must be between 0 and 60"},
				"actions": {"type": "array", "required": false, "default": [], "desc": "Extra action names to mix in with the default ui_* actions"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"get_test_report": {
			"category": "test",
			"summary": "Summarizes accumulated assertion results (from run_test_scenario, assert_node_state, assert_screen_text) into pass/fail counts and details.",
			"params": {
				"clear": {"type": "bool", "required": false, "default": true, "desc": "Clear the accumulated results after reporting"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"set_determinism": {
			"category": "test",
			"summary": "Pins the running game's sources of run-to-run variance (global RNG seed, physics tick rate, max FPS, time scale) so a playtest can be replayed and compared. Returns the applied values plus explicit caveats about what it cannot make deterministic. Call before run_test_scenario for reproducible runs.",
			"params": {
				"seed": {"type": "int", "required": false, "desc": "Seed for the global RNG behind randi/randf/randi_range. Does not reach RandomNumberGenerator instances the game created itself"},
				"physics_ticks_per_second": {"type": "int", "required": false, "desc": "Fixed physics tick rate, 1-1000. This is what actually makes _physics_process logic reproducible"},
				"max_fps": {"type": "int", "required": false, "desc": "Frame cap, 0-1000 (0 = uncapped). Pin to the physics rate to keep _process delta near-constant"},
				"time_scale": {"type": "float", "required": false, "desc": "Engine.time_scale, > 0 and <= 100. Useful to fast-forward a scenario"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"snapshot_state": {
			"category": "test",
			"summary": "Records the current property values of the given running-game nodes under a name, so a scenario can be re-run from the same starting state without restarting the game. Pairs with restore_state.",
			"params": {
				"name": {"type": "string", "required": true, "desc": "Name to store this snapshot under; reusing a name overwrites it"},
				"node_paths": {"type": "array", "required": true, "desc": "Scene-relative paths of the nodes to capture"},
				"properties": {"type": "array", "required": false, "default": [], "desc": "Property names to capture; if omitted, every storage property of each node"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"restore_state": {
			"category": "test",
			"summary": "Writes a snapshot taken by snapshot_state back onto the running game's nodes. Reports nodes that vanished and properties that could not be reapplied instead of failing the whole restore.",
			"params": {
				"name": {"type": "string", "required": true, "desc": "Name of a snapshot previously taken with snapshot_state"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": true},
		},
		"step_frames": {
			"category": "test",
			"summary": "Advances the running game exactly N process or physics frames, like a debugger's frame-step, then re-pauses (unless resume_after is set). Unpauses first if the game wasn't already paused, so exactly N frames of simulation happen either way. Completes set_determinism's determinism story: seeded RNG + fixed tick + exact frame control.",
			"params": {
				"count": {"type": "int", "required": false, "default": 1, "desc": "Frames to advance, clamped 1-600"},
				"physics": {"type": "bool", "required": false, "default": true, "desc": "Count physics frames (_physics_process); false counts process frames (_process) instead"},
				"resume_after": {"type": "bool", "required": false, "default": false, "desc": "Leave the game running after stepping instead of re-pausing"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"wait_for_condition": {
			"category": "test",
			"summary": "Polls a boolean GDScript expression against the running game every poll_interval seconds until it evaluates true or timeout elapses. 'step until X happens' instead of 'step N frames and hope X happened by then' — pairs with step_frames for reproducible scenarios.",
			"params": {
				"expression": {"type": "string", "required": true, "desc": "A single GDScript boolean expression, evaluated as a Node method body (e.g. 'get_node(\"/root/Main/Player\").health <= 0')"},
				"timeout": {"type": "float", "required": false, "default": 5.0, "desc": "Max seconds to wait, clamped 0.05-60"},
				"poll_interval": {"type": "float", "required": false, "default": 0.1, "desc": "Seconds between evaluations, clamped 0.01 to timeout"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
	}


# ── Internal test result accumulator ──────────────────────────────────────────

var _test_results: Array[Dictionary] = []


# ── Commands ──────────────────────────────────────────────────────────────────

func _run_test_scenario(params: Dictionary) -> Dictionary:
	## Execute a test scenario: optionally play a scene, run a sequence of steps
	## (input simulation, waits, assertions, screenshots), return pass/fail results.
	##
	## Steps array: [{type: "input"|"wait"|"assert"|"screenshot", ...params}]
	##   - input: {type:"input", action:str, pressed:bool} or {type:"input", keycode:str}
	##   - wait: {type:"wait", seconds:float} or {type:"wait", node_path:str, timeout:float}
	##   - assert: {type:"assert", node_path:str, property:str, expected:val, operator:str}
	##   - screenshot: {type:"screenshot"} — captures a frame for visual inspection

	if not params.has("steps") or not params["steps"] is Array:
		return error_invalid_params("Missing required parameter: steps (Array)")

	var steps: Array = params["steps"]
	if steps.is_empty():
		return error_invalid_params("Steps array is empty")

	var scene_path: String = optional_string(params, "scene_path")
	var ei := get_editor()

	# Play scene if requested
	if not scene_path.is_empty():
		if ei.is_playing_scene():
			ei.stop_playing_scene()
			await get_tree().create_timer(0.5).timeout

		if scene_path == "main":
			ei.play_main_scene()
		elif scene_path == "current":
			ei.play_current_scene()
		else:
			if not FileAccess.file_exists(scene_path):
				return error_not_found("Scene file '%s'" % scene_path)
			ei.play_custom_scene(scene_path)

		# Wait for game to start
		await get_tree().create_timer(1.0).timeout

	# Verify game is running
	if not ei.is_playing_scene():
		return error(-32000, "No scene is currently playing", {
			"suggestion": "Provide scene_path or use play_scene first"
		})

	var results: Array[Dictionary] = []
	var pass_count: int = 0
	var fail_count: int = 0
	var error_count: int = 0

	for i in steps.size():
		var step: Dictionary = steps[i]
		if not step.has("type"):
			results.append({"step": i, "error": "Missing 'type' field"})
			error_count += 1
			continue

		var step_type: String = str(step["type"])
		var step_result: Dictionary = {"step": i, "type": step_type}

		match step_type:
			"input":
				var input_result := await _execute_input_step(step)
				step_result.merge(input_result)

			"wait":
				var wait_result := await _execute_wait_step(step)
				step_result.merge(wait_result)

			"assert":
				var assert_result := await _execute_assert_step(step)
				step_result.merge(assert_result)
				if assert_result.get("passed", false):
					pass_count += 1
				else:
					fail_count += 1
				# Only assertion steps carry a verdict — store just these for
				# get_test_report (input/wait/screenshot steps have no "passed").
				_test_results.append(step_result)

			"screenshot":
				var screenshot_result := await send_game_command("capture_frames", {
					"count": 1,
					"frame_interval": 1,
					"half_resolution": optional_bool(step, "half_resolution", true),
				}, 5.0)
				if screenshot_result.has("result"):
					step_result["captured"] = true
				else:
					step_result["captured"] = false
					step_result["error"] = "Screenshot capture failed"
					error_count += 1

			_:
				step_result["error"] = "Unknown step type: %s" % step_type
				error_count += 1

		results.append(step_result)

		# Check if game crashed between steps
		if not ei.is_playing_scene():
			results.append({"step": i + 1, "error": "Game stopped unexpectedly"})
			error_count += 1
			break

	var summary := {
		"total_steps": steps.size(),
		"completed_steps": results.size(),
		"assertions_passed": pass_count,
		"assertions_failed": fail_count,
		"errors": error_count,
		"all_passed": fail_count == 0 and error_count == 0,
		"results": results,
	}

	return success(summary)


func _assert_node_state(params: Dictionary) -> Dictionary:
	## Assert a node's property equals expected value in the running game.
	## Supports operators: eq, neq, gt, lt, gte, lte, contains, type_is.
	## Returns pass/fail with actual value.

	var path_result := require_string(params, "node_path")
	if path_result[1] != null:
		return path_result[1]

	var prop_result := require_string(params, "property")
	if prop_result[1] != null:
		return prop_result[1]

	if not params.has("expected"):
		return error_invalid_params("Missing required parameter: expected")

	var operator: String = optional_string(params, "operator", "eq")
	var valid_operators := ["eq", "neq", "gt", "lt", "gte", "lte", "contains", "type_is"]
	if operator not in valid_operators:
		return error_invalid_params("Invalid operator '%s'. Valid: %s" % [operator, str(valid_operators)])

	var result := await send_game_command("assert_node_state", {
		"node_path": path_result[0],
		"property": prop_result[0],
		"expected": params["expected"],
		"operator": operator,
	}, 5.0)

	if result.has("error"):
		return result

	# The game reply is wrapped twice ({"result": {"result": {...}}}) — unwrap
	# defensively before storing/returning so "passed" sits at the top level.
	var payload := unwrap_game_result(result)
	if payload.has("passed"):
		_test_results.append(payload)
	return success(payload)


func _assert_screen_text(params: Dictionary) -> Dictionary:
	## Assert that specific text is visible on screen.
	## Uses find_ui_elements internally to check all visible UI text.

	var text_result := require_string(params, "text")
	if text_result[1] != null:
		return text_result[1]

	var expected_text: String = text_result[0]
	var partial: bool = optional_bool(params, "partial", true)
	var case_sensitive: bool = optional_bool(params, "case_sensitive", true)

	# Use find_ui_elements to get all visible UI text
	var ui_result := await send_game_command("find_ui_elements", {})
	if ui_result.has("error"):
		return ui_result

	var elements: Array = []
	if ui_result.has("result") and ui_result["result"].has("elements"):
		elements = ui_result["result"]["elements"]

	var found := false
	var matched_element: Dictionary = {}
	var all_texts: Array[String] = []

	for element: Dictionary in elements:
		var element_text: String = str(element.get("text", ""))
		if element_text.is_empty():
			continue
		all_texts.append(element_text)

		var search_text := expected_text
		var compare_text := element_text
		if not case_sensitive:
			search_text = search_text.to_lower()
			compare_text = compare_text.to_lower()

		if partial:
			if compare_text.contains(search_text):
				found = true
				matched_element = element
				break
		else:
			if compare_text == search_text:
				found = true
				matched_element = element
				break

	var assertion := {
		"passed": found,
		"expected_text": expected_text,
		"partial": partial,
		"case_sensitive": case_sensitive,
	}

	if found:
		assertion["matched_element"] = {
			"text": matched_element.get("text", ""),
			"type": matched_element.get("type", ""),
			"path": matched_element.get("path", ""),
		}
	else:
		assertion["visible_texts"] = all_texts

	# Store for test report
	_test_results.append(assertion)

	return success(assertion)


func _run_stress_test(params: Dictionary) -> Dictionary:
	## Run rapid random inputs for N seconds and check for crashes.
	## Returns frame count, timing, and any errors from game output.

	var duration: float = optional_float(params, "duration", 5.0)
	if duration <= 0 or duration > 60:
		return error_invalid_params("Duration must be between 0 and 60 seconds")

	var ei := get_editor()
	if not ei.is_playing_scene():
		return error(-32000, "No scene is currently playing", {
			"suggestion": "Use play_scene first"
		})

	# Record initial error count from log
	var initial_errors := _count_log_errors()

	# Generate random input events
	var actions := ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"]
	# Add common game actions if specified
	var custom_actions: Array = params.get("actions", [])
	for action in custom_actions:
		actions.append(str(action))

	var events_sent: int = 0
	var start_time := Time.get_ticks_msec()
	var duration_ms := int(duration * 1000.0)

	while Time.get_ticks_msec() - start_time < duration_ms:
		if not ei.is_playing_scene():
			var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
			return success({
				"completed": false,
				"crashed": true,
				"elapsed_seconds": elapsed,
				"events_sent": events_sent,
				"error": "Game stopped during stress test",
			})

		# Send a batch of random inputs
		var batch: Array = []
		for j in 3:
			var action_name: String = actions[randi() % actions.size()]
			batch.append({
				"type": "action",
				"action": action_name,
				"pressed": true,
				"strength": 1.0,
			})
			batch.append({
				"type": "action",
				"action": action_name,
				"pressed": false,
				"strength": 0.0,
			})

		# Write input commands directly (same as input_commands)
		var json := JSON.stringify({
			"sequence_events": batch,
			"frame_delay": 1,
		})
		var file := FileAccess.open("user://mcp_input_commands", FileAccess.WRITE)
		if file:
			file.store_string(json)
			file.close()
			events_sent += batch.size()

		await get_tree().create_timer(0.1).timeout

	var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
	var final_errors := _count_log_errors()
	var new_errors := final_errors - initial_errors

	# Check if game is still running
	var still_running := ei.is_playing_scene()

	return success({
		"completed": true,
		"crashed": not still_running,
		"duration_seconds": elapsed,
		"events_sent": events_sent,
		"new_errors": new_errors,
		"game_still_running": still_running,
	})


func _get_test_report(params: Dictionary) -> Dictionary:
	## Collect and format results from accumulated assertions into a test report.
	## Returns pass count, fail count, and detailed results.

	var clear: bool = optional_bool(params, "clear", true)

	var pass_count: int = 0
	var fail_count: int = 0
	var details: Array[Dictionary] = []

	for result: Dictionary in _test_results:
		# Unwrap defensively and skip entries that carry no verdict
		# (input/wait/screenshot steps are not assertions).
		var entry := unwrap_game_result(result)
		if not entry.has("passed"):
			continue
		if entry.get("passed", false):
			pass_count += 1
		else:
			fail_count += 1
		details.append(entry)

	var total := pass_count + fail_count
	var report := {
		"total": total,
		"passed": pass_count,
		"failed": fail_count,
		"pass_rate": ("%.1f%%" % (100.0 * pass_count / total)) if total > 0 else "N/A",
		"all_passed": fail_count == 0 and total > 0,
		"no_results": total == 0,
		"details": details,
	}

	if clear:
		_test_results.clear()

	return success(report)


# ── Step Executors (for run_test_scenario) ────────────────────────────────────

func _execute_input_step(step: Dictionary) -> Dictionary:
	## Execute an input step: simulate action or key press.
	var events: Array = []

	if step.has("action"):
		var pressed: bool = step.get("pressed", true) as bool
		events.append({
			"type": "action",
			"action": str(step["action"]),
			"pressed": pressed,
			"strength": float(step.get("strength", 1.0)),
		})
		# Auto-release if pressed
		if pressed and step.get("auto_release", true):
			events.append({
				"type": "action",
				"action": str(step["action"]),
				"pressed": false,
				"strength": 0.0,
			})
	elif step.has("keycode"):
		var pressed: bool = step.get("pressed", true) as bool
		events.append({
			"type": "key",
			"keycode": str(step["keycode"]),
			"pressed": pressed,
			"shift": step.get("shift", false),
			"ctrl": step.get("ctrl", false),
			"alt": step.get("alt", false),
		})
		# Auto-release if pressed, mirroring the action branch — otherwise the
		# key stays held for the rest of the session and corrupts later steps
		if pressed and step.get("auto_release", true):
			events.append({
				"type": "key",
				"keycode": str(step["keycode"]),
				"pressed": false,
				"shift": step.get("shift", false),
				"ctrl": step.get("ctrl", false),
				"alt": step.get("alt", false),
			})
	else:
		return {"error": "Input step requires 'action' or 'keycode'"}

	var json := JSON.stringify({
		"sequence_events": events,
		"frame_delay": int(step.get("frame_delay", 1)),
	})
	var file := FileAccess.open("user://mcp_input_commands", FileAccess.WRITE)
	if file == null:
		return {"error": "Failed to write input commands"}
	file.store_string(json)
	file.close()

	return {"sent": true, "event_count": events.size()}


func _execute_wait_step(step: Dictionary) -> Dictionary:
	## Execute a wait step: wait for seconds or wait for a node to appear.
	if step.has("node_path"):
		var timeout: float = float(step.get("timeout", 5.0))
		var result := await send_game_command("wait_for_node", {
			"node_path": str(step["node_path"]),
			"timeout": timeout,
			"poll_frames": int(step.get("poll_frames", 5)),
		}, timeout + 2.0)
		if result.has("error"):
			return {"error": "Wait for node failed: %s" % str(result["error"])}
		return {"waited_for": str(step["node_path"]), "found": true}
	else:
		var seconds: float = float(step.get("seconds", 1.0))
		await get_tree().create_timer(seconds).timeout
		return {"waited_seconds": seconds}


func _execute_assert_step(step: Dictionary) -> Dictionary:
	## Execute an assertion step within a scenario.
	if step.has("text"):
		# Screen text assertion
		var ui_result := await send_game_command("find_ui_elements", {})
		if ui_result.has("error"):
			return {"passed": false, "error": "Could not get UI elements"}

		var elements: Array = []
		if ui_result.has("result") and ui_result["result"].has("elements"):
			elements = ui_result["result"]["elements"]

		var expected_text: String = str(step["text"])
		var partial: bool = step.get("partial", true) as bool
		# "assert_type" (not "type") so the caller's step_result.merge() cannot
		# collide with the step's own "type": "assert" key
		for element: Dictionary in elements:
			var element_text: String = str(element.get("text", ""))
			if partial and element_text.contains(expected_text):
				return {"passed": true, "assert_type": "screen_text", "expected": expected_text, "found_in": element_text}
			elif not partial and element_text == expected_text:
				return {"passed": true, "assert_type": "screen_text", "expected": expected_text, "found_in": element_text}

		return {"passed": false, "assert_type": "screen_text", "expected": expected_text, "error": "Text not found on screen"}

	elif step.has("node_path") and step.has("property"):
		# Node state assertion
		var result := await send_game_command("assert_node_state", {
			"node_path": str(step["node_path"]),
			"property": str(step["property"]),
			"expected": step.get("expected", null),
			"operator": str(step.get("operator", "eq")),
		}, 5.0)
		if result.has("error"):
			return {"passed": false, "error": str(result["error"])}
		# Game replies are double-wrapped — unwrap until "passed" surfaces
		var payload := unwrap_game_result(result)
		if payload.has("passed"):
			return payload
		return {"passed": false, "error": "Unknown assertion error"}

	else:
		return {"passed": false, "error": "Assert step requires 'text' or 'node_path'+'property'"}


# ── Utility ───────────────────────────────────────────────────────────────────

func _count_log_errors() -> int:
	var count: int = 0
	var log_path := "user://logs/godot.log"
	if FileAccess.file_exists(log_path):
		var file := FileAccess.open(log_path, FileAccess.READ)
		if file:
			var content := file.get_as_text()
			file.close()
			var lines := content.split("\n")
			for line: String in lines:
				if line.contains("ERROR") or line.contains("SCRIPT ERROR"):
					count += 1
	return count


# ── Determinism / state snapshots ─────────────────────────────────────────────

func _set_determinism(params: Dictionary) -> Dictionary:
	## Forwards only the keys the caller actually supplied, so an omitted knob
	## keeps whatever the game currently has rather than being reset to a
	## default the caller never asked for.
	var forwarded := {}
	for key: String in ["seed", "physics_ticks_per_second", "max_fps", "time_scale"]:
		if params.has(key):
			forwarded[key] = params[key]

	if forwarded.is_empty():
		return error_invalid_params(
			"Supply at least one of: seed, physics_ticks_per_second, max_fps, time_scale"
		)

	var result := await send_game_command("set_determinism", forwarded)
	if result.has("error"):
		return result
	return success(unwrap_game_result(result))


func _snapshot_state(params: Dictionary) -> Dictionary:
	var name_result := require_string(params, "name")
	if name_result[1] != null:
		return name_result[1]
	var snapshot_name: String = name_result[0]

	var raw_paths: Variant = params.get("node_paths")
	if raw_paths == null:
		return error_invalid_params("Missing required parameter: node_paths (array of node paths)")
	if not raw_paths is Array or (raw_paths as Array).is_empty():
		return error_invalid_params("'node_paths' must be a non-empty array of node paths")

	var forwarded := {
		"name": snapshot_name,
		"node_paths": raw_paths,
	}
	var raw_props: Variant = params.get("properties", [])
	if raw_props is Array:
		forwarded["properties"] = raw_props

	var result := await send_game_command("snapshot_state", forwarded)
	if result.has("error"):
		return result
	return success(unwrap_game_result(result))


func _restore_state(params: Dictionary) -> Dictionary:
	var name_result := require_string(params, "name")
	if name_result[1] != null:
		return name_result[1]

	var result := await send_game_command("restore_state", {"name": name_result[0]})
	if result.has("error"):
		return result
	return success(unwrap_game_result(result))


func _step_frames(params: Dictionary) -> Dictionary:
	var forwarded := {}
	for key: String in ["count", "physics", "resume_after"]:
		if params.has(key):
			forwarded[key] = params[key]

	var raw_count: Variant = params.get("count", 1)
	var count: int = int(raw_count) if (raw_count is int or raw_count is float) else 1
	# Stepping waits real wall-clock time for `count` frames to render, so the
	# IPC timeout must scale with count rather than using send_game_command's
	# 5s default, which a large step count could outrun.
	var timeout_sec: float = maxf(5.0, float(clampi(count, 1, 600)) * 0.25)

	var result := await send_game_command("step_frames", forwarded, timeout_sec)
	if result.has("error"):
		return result
	return success(unwrap_game_result(result))


func _wait_for_condition(params: Dictionary) -> Dictionary:
	var expr_result := require_string(params, "expression")
	if expr_result[1] != null:
		return expr_result[1]

	var forwarded := {"expression": expr_result[0]}
	var raw_timeout: Variant = params.get("timeout", 5.0)
	var timeout_sec: float = float(raw_timeout) if (raw_timeout is int or raw_timeout is float) else 5.0
	timeout_sec = clampf(timeout_sec, 0.05, 60.0)
	forwarded["timeout"] = timeout_sec
	if params.has("poll_interval"):
		forwarded["poll_interval"] = params["poll_interval"]

	# The game side waits up to timeout_sec before answering; give the IPC
	# call itself a margin on top so it isn't the one that times out first.
	var result := await send_game_command("wait_for_condition", forwarded, timeout_sec + 2.0)
	if result.has("error"):
		return result
	return success(unwrap_game_result(result))
