extends SceneTree

## Headless test runner for the parts of the Godot addon that don't need a
## running editor: PropertyParser's Variant coercion, BaseCommand's
## scene-path safety guard and overwrite guard, and command_router.gd's
## confirm gate. Run with:
##   godot --headless --path test/godot --script res://run_tests.gd
## (or `npm run test:godot`, which also stages the addons/godot_mcp/ copy
## command_router.gd needs — see run-godot-tests.mjs).
##
## The addon lives at plugin/ in the repo root, not inside this fixture
## project (see project.godot), so PropertyParser and BaseCommand — which
## have no preload() dependencies of their own — are loaded by an absolute
## path resolved at runtime, with nothing here duplicating plugin/ code for
## them to drift out of sync with. command_router.gd is the one exception:
## it preload()s its 26 command modules by res:// path, which Godot resolves
## at parse time against *this* project's root regardless of how
## command_router.gd itself was loaded — so it only parses successfully when
## run-godot-tests.mjs has staged an ephemeral plugin/ copy at
## addons/godot_mcp/ first. Running this file directly (not through
## `npm run test:godot`) without that copy in place will fail the
## command_router.gd load and skip its dependent tests via _require_loaded().
##
## Exits with a non-zero code on any failure, so this composes with a CI
## step or `npm run test:godot` without extra parsing.

var _pass := 0
var _fail := 0


func _init() -> void:
	var repo_root := _find_repo_root()
	var PropertyParser: Script = load(repo_root.path_join("plugin/utils/property_parser.gd"))
	var BaseCommand: Script = load(repo_root.path_join("plugin/commands/base_command.gd"))
	var CommandRouter: Script = load(repo_root.path_join("plugin/command_router.gd"))

	# A script with a parse error surfaces as SCRIPT ERROR output plus a null
	# return from load() — it does NOT raise, so a test function called on a
	# null Script fails on its first call with a "Nonexistent function" error
	# that aborts just that function, silently, before _check() ever runs.
	# Left unguarded, that reports a false green ("0 failed") instead of the
	# real parse error further up the log — this is exactly what happened the
	# first time this file ran in CI (see base_command.gd/editor_commands.gd
	# ":=" pop_front() history). Fail loudly instead.
	if _require_loaded("plugin/utils/property_parser.gd", PropertyParser):
		_test_property_parser(PropertyParser)
	if _require_loaded("plugin/commands/base_command.gd", BaseCommand):
		_test_is_safe_scene_path(BaseCommand)
		_test_guard_overwrite(BaseCommand)
		_test_guard_stale_write(BaseCommand)
	if _require_loaded("plugin/command_router.gd", CommandRouter):
		_test_requires_confirm(CommandRouter)

	print("\n[godot headless tests] %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _require_loaded(rel_path: String, script: Script) -> bool:
	if script != null:
		return true
	_fail += 1
	print("FAIL %s: load() returned null — check the SCRIPT ERROR output above for a parse error." % rel_path)
	return false


## test/godot/run_tests.gd -> test/godot -> test -> <repo root>
func _find_repo_root() -> String:
	var script_path: String = (get_script() as GDScript).resource_path
	var abs_dir := ProjectSettings.globalize_path(script_path).get_base_dir()
	return abs_dir.get_base_dir().get_base_dir()


func _check(label: String, actual: Variant, expected: Variant) -> void:
	var ok: bool
	if actual is float and expected is float:
		ok = is_equal_approx(actual, expected)
	elif (actual is Vector2 and expected is Vector2) or (actual is Vector3 and expected is Vector3) \
			or (actual is Color and expected is Color) or (actual is Rect2 and expected is Rect2):
		ok = actual.is_equal_approx(expected)
	else:
		ok = actual == expected
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL %s: expected %s, got %s" % [label, expected, actual])


func _test_property_parser(PropertyParser: Script) -> void:
	_check("bool from string 'true'", PropertyParser.parse_value("true", TYPE_BOOL), true)
	_check("bool from string 'yes'", PropertyParser.parse_value("yes", TYPE_BOOL), true)
	_check("int from string", PropertyParser.parse_value("42", TYPE_INT), 42)
	_check("int from float", PropertyParser.parse_value(3.9, TYPE_INT), 3)
	_check("float from string", PropertyParser.parse_value("3.5", TYPE_FLOAT), 3.5)

	_check(
		"Vector2 from dict",
		PropertyParser.parse_value({"x": 1, "y": 2}, TYPE_VECTOR2),
		Vector2(1, 2)
	)
	_check(
		"Vector2 from 'Vector2(x, y)' text",
		PropertyParser.parse_value("Vector2(3, 4)", TYPE_VECTOR2),
		Vector2(3, 4)
	)
	_check(
		"Vector3 from dict",
		PropertyParser.parse_value({"x": 1, "y": 2, "z": 3}, TYPE_VECTOR3),
		Vector3(1, 2, 3)
	)

	# Regression: a structured value stringified as JSON by the caller must
	# still parse, not silently fall back to a default (see the comment on
	# _STRUCTURED_TYPES in property_parser.gd).
	_check(
		"Color from stringified JSON dict",
		PropertyParser.parse_value('{"r":1,"g":0,"b":0,"a":1}', TYPE_COLOR),
		Color(1, 0, 0, 1)
	)
	_check(
		"Color from #hex",
		PropertyParser.parse_value("#ff0000", TYPE_COLOR),
		Color(1, 0, 0, 1)
	)
	_check(
		"Color from html round-trip (serialize_value output fed back in)",
		PropertyParser.parse_value(PropertyParser.serialize_value(Color(0, 1, 0, 1)), TYPE_COLOR),
		Color(0, 1, 0, 1)
	)

	var serialized_v3: Dictionary = PropertyParser.serialize_value(Vector3(1, 2, 3))
	_check("serialize_value(Vector3) shape", serialized_v3, {"x": 1.0, "y": 2.0, "z": 3.0})

	_check(
		"Vector2 round-trip through serialize+parse",
		PropertyParser.parse_value(PropertyParser.serialize_value(Vector2(5, 6)), TYPE_VECTOR2),
		Vector2(5, 6)
	)


func _test_is_safe_scene_path(BaseCommand: Script) -> void:
	_check("relative path is safe", BaseCommand.is_safe_scene_path("Player/Camera"), true)
	_check("absolute path is rejected", BaseCommand.is_safe_scene_path("/root/Something"), false)
	_check("leading .. is rejected", BaseCommand.is_safe_scene_path("../escape"), false)
	_check("embedded .. segment is rejected", BaseCommand.is_safe_scene_path("a/../b"), false)
	_check("empty string is rejected", BaseCommand.is_safe_scene_path(""), false)
	_check("empty segment is rejected", BaseCommand.is_safe_scene_path("a//b"), false)
	# "." alone is handled by find_node_by_path's own special-case before it
	# ever reaches this guard — the guard itself treats a bare "." segment as
	# unsafe, which is intentional (it also rejects "a/./b").
	_check("bare '.' is rejected by the guard itself", BaseCommand.is_safe_scene_path("."), false)


func _test_requires_confirm(CommandRouter: Script) -> void:
	var gated_schema := {"annotations": {"destructive": true, "confirm": true}}
	var ungated_schema := {"annotations": {"destructive": true, "confirm": false}}
	var no_annotations_schema := {}

	_check(
		"gated method without confirm:true in params requires confirmation",
		CommandRouter._requires_confirm(gated_schema, {}),
		true
	)
	_check(
		"gated method with confirm:true in params does not require confirmation",
		CommandRouter._requires_confirm(gated_schema, {"confirm": true}),
		false
	)
	_check(
		"gated method with confirm:false in params still requires confirmation",
		CommandRouter._requires_confirm(gated_schema, {"confirm": false}),
		true
	)
	_check(
		"non-gated method never requires confirmation",
		CommandRouter._requires_confirm(ungated_schema, {}),
		false
	)
	_check(
		"a method with no schema at all never requires confirmation",
		CommandRouter._requires_confirm(no_annotations_schema, {}),
		false
	)


func _test_guard_overwrite(BaseCommand: Script) -> void:
	var cmd: Object = BaseCommand.new()

	_check(
		"empty path never blocks",
		cmd.guard_overwrite("", false).has("error"),
		false
	)
	_check(
		"a path that doesn't exist on disk never blocks",
		cmd.guard_overwrite("user://mcp_contract_test_definitely_missing.png", false).has("error"),
		false
	)
	_check(
		"overwrite:true always bypasses the guard, existing file or not",
		cmd.guard_overwrite("user://mcp_contract_test_definitely_missing.png", true).has("error"),
		false
	)

	var existing_path := "user://mcp_contract_test_existing.tmp"
	var abs_path := ProjectSettings.globalize_path(existing_path)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	_check(
		"an existing file without overwrite:true is blocked",
		cmd.guard_overwrite(existing_path, false).has("error"),
		true
	)
	_check(
		"an existing file with overwrite:true is allowed",
		cmd.guard_overwrite(existing_path, true).has("error"),
		false
	)

	DirAccess.remove_absolute(abs_path)
	cmd.free()


func _test_guard_stale_write(BaseCommand: Script) -> void:
	var cmd: Object = BaseCommand.new()
	var path := "user://mcp_stale_test.gd"
	var abs_path := ProjectSettings.globalize_path(path)

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("extends Node\n")
	f.close()

	var real_sha := FileAccess.get_sha256(path)

	_check(
		"empty expected sha opts out of the check entirely",
		cmd.guard_stale_write(path, "").has("error"),
		false
	)
	_check(
		"matching sha allows the write",
		cmd.guard_stale_write(path, real_sha).has("error"),
		false
	)
	_check(
		"mismatched sha blocks the write",
		cmd.guard_stale_write(path, "not-the-real-hash").has("error"),
		true
	)

	# The refusal must carry the CURRENT hash, or the caller has no way to
	# recover without a second round trip.
	var blocked: Dictionary = cmd.guard_stale_write(path, "not-the-real-hash")
	_check(
		"refusal reports the current sha so the caller can retry",
		blocked.get("error", {}).get("data", {}).get("current_sha256", ""),
		real_sha
	)

	# A file edited after the hash was taken must now be refused.
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string("extends Node\nfunc _ready() -> void:\n\tpass\n")
	f2.close()
	_check(
		"a sha taken before an external edit is now stale",
		cmd.guard_stale_write(path, real_sha).has("error"),
		true
	)

	DirAccess.remove_absolute(abs_path)
	cmd.free()
