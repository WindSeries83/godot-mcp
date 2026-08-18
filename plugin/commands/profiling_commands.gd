@tool
extends "res://addons/godot_mcp/commands/base_command.gd"


func get_commands() -> Dictionary:
	return {
		"get_performance_monitors": _get_performance_monitors,
		"get_editor_performance": _get_editor_performance,
	}


func get_command_schemas() -> Dictionary:
	return {
		"get_performance_monitors": {
			"category": "profiling",
			"summary": "Reads the running game's Performance monitors via game IPC. Requires a scene to be playing; notes when an embedded game's FPS reading is throttled by editor focus.",
			"params": {
				"category": {"type": "string", "required": false, "default": "", "desc": "Only return monitor keys starting with this prefix, e.g. 'time/'"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"get_editor_performance": {
			"category": "profiling",
			"summary": "Reads the editor process's own Performance monitors (fps, frame time, draw calls, node counts, memory).",
			"params": {},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
	}


func _get_performance_monitors(params: Dictionary) -> Dictionary:
	# Performance is a per-process singleton: reading it here would report the
	# EDITOR's metrics, not the game's. Route through the game IPC channel.
	if get_editor().is_playing_scene():
		var game_result := await send_game_command("get_performance_monitors", {}, 5.0)
		if game_result.has("error"):
			return game_result
		var payload := unwrap_game_result(game_result)
		var game_monitors: Dictionary = payload.get("monitors", {})

		# An embedded game throttles to ~10 FPS while the editor window is
		# unfocused — which it always is when an agent drives it from a
		# terminal. Say so, or the reading looks like a huge regression.
		# A game running in its own window is NOT throttled by editor focus,
		# so the warning is gated on the embed mode rather than focus alone.
		var editor_focused := _is_editor_focused()
		var embed_mode := _game_embed_mode()
		# Only "Disabled" runs the game in its own OS window. "Floating" still
		# embeds it — it just moves the Game workspace into a separate editor
		# window, which is throttled the same way when unfocused. "Use
		# Per-Project Configuration" defers to the project's own toggle.
		var embedded := _game_is_embedded(embed_mode)
		var context := {
			"process": "game",
			"editor_focused": editor_focused,
			"game_embedded": embedded,
		}

		if not embedded:
			# Own OS window: editor focus has no bearing on its frame rate.
			context["fps_throttled"] = false
		elif not _subwindows_available():
			# Embedding is configured but the display driver cannot host a
			# subwindow, so Godot falls back to an external window. Which of
			# the two actually happened is not observable from here.
			context["fps_throttled"] = null
			context["note"] = "Embedding is configured, but this display driver reports no subwindow support, so Godot may have launched the game in its own window instead. Whether the ~10 FPS unfocused throttle applies cannot be determined here — treat time/fps and time/process as undetermined. Draw-call, primitive and memory counters are unaffected and remain trustworthy."
		elif _game_is_floating(embed_mode):
			# The Game workspace is a separate editor window, and editor_focused
			# describes the main one. Deriving the throttle state from it would
			# be wrong in both directions, so report it as undetermined rather
			# than assert something this process cannot observe.
			context["fps_throttled"] = null
			context["note"] = "The game is embedded in a floating Game workspace window, whose focus this process cannot read (editor_focused refers to the main editor window). Godot throttles an unfocused embedded game to ~10 FPS, so time/fps and time/process may or may not be representative here — treat them as undetermined. Draw-call, primitive and memory counters are unaffected and remain trustworthy."
		else:
			context["fps_throttled"] = not editor_focused
			if not editor_focused:
				context["note"] = "Editor window is unfocused, so Godot throttles the embedded game to ~10 FPS. time/fps and time/process are NOT representative of real performance. Draw-call, primitive and memory counters are unaffected and remain trustworthy."

		var category: String = optional_string(params, "category", "")
		if not category.is_empty():
			var filtered := {}
			for key: String in game_monitors:
				if key.begins_with(category):
					filtered[key] = game_monitors[key]
			context["monitors"] = filtered
			context["category"] = category
			return success(context)
		context["monitors"] = game_monitors
		return success(context)

	return error(-32000, "No scene is currently playing", {
		"suggestion": "Use play_scene first. For editor-process metrics, use get_editor_performance.",
	})


## EditorSettings "run/window_placement/game_embed_mode" values.
## Hint string: Disabled:-1, Use Per-Project Configuration:0, Embed Game:1,
## Make Game Workspace Floating:2 — only the first and last run the game in a
## window of its own, where editor focus does not throttle it.
const _EMBED_DISABLED := -1
const _EMBED_PER_PROJECT := 0
const _EMBED_FLOATING := 2
const _EMBED_SETTING := "run/window_placement/game_embed_mode"


func _game_embed_mode() -> int:
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(_EMBED_SETTING):
		return _EMBED_PER_PROJECT
	return int(settings.get_setting(_EMBED_SETTING))


## Floating means the Game workspace sits in its own editor window, whose
## focus this process cannot read. Per-project mode has its own toggle for it,
## so checking the global mode alone would miss that case.
func _game_is_floating(embed_mode: int) -> bool:
	if embed_mode == _EMBED_FLOATING:
		return true
	if embed_mode != _EMBED_PER_PROJECT:
		return false
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		return false
	return bool(settings.get_project_metadata("game_view", "make_floating_on_play", false))


## Embedding needs subwindow support; without it Godot launches the game in a
## separate OS window regardless of the setting.
func _subwindows_available() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS)


## "Use Per-Project Configuration" defers to the Game workspace's own toggle,
## which lives in project metadata rather than in ProjectSettings. A project
## that turned embedding off runs the game in its own window, where editor
## focus does not throttle it. Godot's own default for the toggle is true.
func _game_is_embedded(embed_mode: int) -> bool:
	if embed_mode == _EMBED_DISABLED:
		return false
	if embed_mode != _EMBED_PER_PROJECT:
		return true
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		return true
	return bool(settings.get_project_metadata("game_view", "embed_on_play", true))


func _is_editor_focused() -> bool:
	var base: Control = get_editor().get_base_control()
	if base == null:
		return false
	var window := base.get_window()
	if window == null:
		return false
	return window.has_focus()


func _get_editor_performance(params: Dictionary) -> Dictionary:
	# Quick summary for common use
	var summary := {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_time_msec": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0),
	}
	return success(summary)
