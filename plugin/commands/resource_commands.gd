@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

const PropertyParser := preload("res://addons/godot_mcp/utils/property_parser.gd")


func get_commands() -> Dictionary:
	return {
		"read_resource": _read_resource,
		"edit_resource": _edit_resource,
		"create_resource": _create_resource,
		"get_resource_preview": _get_resource_preview,
	}


func get_command_schemas() -> Dictionary:
	return {
		"read_resource": {
			"category": "resource",
			"summary": "Load a .tres/.res resource and return its editor-visible properties. Refuses script/shader files, which load as Resource too but are edited via script commands.",
			"params": {
				"path": {"type": "string", "required": true, "desc": "res:// path to the resource file"},
				"force": {"type": "bool", "required": false, "default": false, "desc": "Bypass the offline text-resource read guard"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"edit_resource": {
			"category": "resource",
			"summary": "Update properties on an existing resource and save it back to disk. Unknown property names are silently skipped.",
			"params": {
				"path": {"type": "string", "required": true, "desc": "res:// path to the resource file"},
				"properties": {"type": "object", "required": true, "desc": "Property name/value pairs to set"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"create_resource": {
			"category": "resource",
			"summary": "Instantiate a Resource type and save it as a new .tres/.res file. Refuses to overwrite an existing file unless overwrite is set.",
			"params": {
				"path": {"type": "string", "required": true, "desc": "res:// path; must end in .tres or .res"},
				"type": {"type": "string", "required": true, "desc": "ClassDB Resource type to instantiate"},
				"overwrite": {"type": "bool", "required": false, "default": false, "desc": "Overwrite an existing file at path"},
				"properties": {"type": "object", "required": false, "default": {}, "desc": "Initial property name/value pairs to set on the new resource"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"get_resource_preview": {
			"category": "resource",
			"summary": "Render a resource (image file, Texture2D, or Image) to a base64 PNG thumbnail, downscaled to fit max_size.",
			"params": {
				"path": {"type": "string", "required": true, "desc": "res:// path to an image file or an image-producing resource"},
				"max_size": {"type": "int", "required": false, "default": 256, "desc": "Maximum width/height of the returned thumbnail"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
	}


func _read_resource(params: Dictionary) -> Dictionary:
	var result := require_string(params, "path")
	if result[1] != null:
		return result[1]
	var path: String = result[0]

	if not FileAccess.file_exists(path):
		return error_not_found("Resource '%s'" % path)

	var guard := guard_offline_scene_save(path)
	if not guard.is_empty():
		return guard

	# A script or shader also loads as a Resource, so without this the resource
	# tool could rewrite a file the user has open in the script editor —
	# the exact case guard_text_resource_write exists to prevent.
	var text_guard := guard_text_resource_write(path, optional_bool(params, "force", false))
	if not text_guard.is_empty():
		return text_guard

	var resource: Resource = ResourceLoader.load(path)
	if resource == null:
		return error_internal("Failed to load resource: %s" % path)

	var props: Dictionary = {}
	for prop_info in resource.get_property_list():
		var prop_name: String = prop_info["name"]
		var usage: int = prop_info["usage"]
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if prop_name.begins_with("_") or prop_name == "script" or prop_name == "resource_local_to_scene" or prop_name == "resource_name" or prop_name == "resource_path":
			continue
		props[prop_name] = PropertyParser.serialize_value(resource.get(prop_name))

	return success({
		"path": path,
		"type": resource.get_class(),
		"resource_name": resource.resource_name,
		"properties": props,
	})


func _edit_resource(params: Dictionary) -> Dictionary:
	var result := require_string(params, "path")
	if result[1] != null:
		return result[1]
	var path: String = result[0]

	if not params.has("properties") or not params["properties"] is Dictionary:
		return error_invalid_params("'properties' dictionary is required")
	var new_props: Dictionary = params["properties"]

	if not FileAccess.file_exists(path):
		return error_not_found("Resource '%s'" % path)

	var guard := guard_offline_scene_save(path)
	if not guard.is_empty():
		return guard

	var resource: Resource = ResourceLoader.load(path)
	if resource == null:
		return error_internal("Failed to load resource: %s" % path)

	var changed: Dictionary = {}
	for prop_name: String in new_props:
		if not prop_name in resource:
			continue
		var old_value: Variant = resource.get(prop_name)
		var target_type := typeof(old_value)
		var new_value: Variant = PropertyParser.parse_value(new_props[prop_name], target_type)
		resource.set(prop_name, new_value)
		changed[prop_name] = {
			"old": PropertyParser.serialize_value(old_value),
			"new": PropertyParser.serialize_value(resource.get(prop_name)),
		}

	if changed.is_empty():
		return success({"path": path, "changed": {}, "message": "No properties were changed"})

	var err := ResourceSaver.save(resource, path)
	if err != OK:
		return error_internal("Failed to save resource: %s" % error_string(err))

	return success({
		"path": path,
		"type": resource.get_class(),
		"changed": changed,
	})


func _create_resource(params: Dictionary) -> Dictionary:
	var result := require_string(params, "path")
	if result[1] != null:
		return result[1]
	var path: String = result[0]

	var result2 := require_string(params, "type")
	if result2[1] != null:
		return result2[1]
	var resource_type: String = result2[0]

	if not ClassDB.class_exists(resource_type):
		return error_invalid_params("Unknown resource type: %s" % resource_type)
	if not ClassDB.is_parent_class(resource_type, "Resource"):
		return error_invalid_params("'%s' is not a Resource type" % resource_type)

	var overwrite: bool = optional_bool(params, "overwrite", false)
	if FileAccess.file_exists(path) and not overwrite:
		return error(-32000, "Resource already exists: %s" % path, {"suggestion": "Set overwrite=true to replace"})

	var ext_guard := guard_expected_extension(path, ["tres", "res"], "a resource file")
	if not ext_guard.is_empty():
		return ext_guard

	var guard := guard_offline_scene_save(path)
	if not guard.is_empty():
		return guard

	var resource: Resource = ClassDB.instantiate(resource_type)
	if resource == null:
		return error_internal("Failed to instantiate: %s" % resource_type)

	# Apply properties
	var properties: Dictionary = params.get("properties", {})
	for prop_name: String in properties:
		if prop_name in resource:
			var current: Variant = resource.get(prop_name)
			resource.set(prop_name, PropertyParser.parse_value(properties[prop_name], typeof(current)))

	var dir_guard := ensure_parent_dir(path)
	if not dir_guard.is_empty():
		return dir_guard

	var err := ResourceSaver.save(resource, path)
	if err != OK:
		return error_internal("Failed to save resource '%s': %s" % [path, error_string(err)])

	# Rescan filesystem
	EditorInterface.get_resource_filesystem().scan()

	return success({
		"path": path,
		"type": resource_type,
		"properties_set": properties.keys(),
	})


func _get_resource_preview(params: Dictionary) -> Dictionary:
	var result := require_string(params, "path")
	if result[1] != null:
		return result[1]
	var path: String = result[0]

	if not FileAccess.file_exists(path):
		return error_not_found("Resource '%s'" % path)

	var max_size: int = optional_int(params, "max_size", 256)
	var image: Image = null

	# Try loading as image file directly
	var ext := path.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg", "bmp", "webp", "svg"]:
		image = Image.new()
		var err := image.load(path)
		if err != OK:
			return error_internal("Failed to load image: %s" % error_string(err))
	else:
		# Try loading as resource and extracting image
		var resource: Resource = ResourceLoader.load(path)
		if resource == null:
			return error_internal("Failed to load resource: %s" % path)

		if resource is Texture2D:
			image = (resource as Texture2D).get_image()
		elif resource is Image:
			image = resource as Image
		else:
			return error_invalid_params("Resource type '%s' does not have an image preview" % resource.get_class())

	if image == null:
		return error_internal("Could not extract image from resource")

	# Resize if needed
	if image.get_width() > max_size or image.get_height() > max_size:
		var scale_x := float(max_size) / float(image.get_width())
		var scale_y := float(max_size) / float(image.get_height())
		var scale := minf(scale_x, scale_y)
		var new_w := int(image.get_width() * scale)
		var new_h := int(image.get_height() * scale)
		image.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)

	var png_buffer := image.save_png_to_buffer()
	var base64 := Marshalls.raw_to_base64(png_buffer)

	return success({
		"image_base64": base64,
		"width": image.get_width(),
		"height": image.get_height(),
		"format": "png",
		"path": path,
	})
