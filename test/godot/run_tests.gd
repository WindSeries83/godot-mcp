extends SceneTree

## Headless test runner for the parts of the Godot addon that don't need a
## running editor: PropertyParser's Variant coercion and BaseCommand's
## scene-path safety guard. Run with:
##   godot --headless --path test/godot --script res://run_tests.gd
##
## The addon lives at plugin/ in the repo root, not inside this fixture
## project (see project.godot), so the real .gd files are loaded by an
## absolute path resolved at runtime — there is nothing here duplicating
## plugin/ code for these tests to drift out of sync with.
##
## Exits with a non-zero code on any failure, so this composes with a CI
## step or `npm run test:godot` without extra parsing.

var _pass := 0
var _fail := 0


func _init() -> void:
	var repo_root := _find_repo_root()
	var PropertyParser: Script = load(repo_root.path_join("plugin/utils/property_parser.gd"))
	var BaseCommand: Script = load(repo_root.path_join("plugin/commands/base_command.gd"))

	_test_property_parser(PropertyParser)
	_test_is_safe_scene_path(BaseCommand)

	print("\n[godot headless tests] %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


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
