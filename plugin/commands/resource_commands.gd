@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

const PropertyParser := preload("res://addons/godot_mcp/utils/property_parser.gd")


func get_commands() -> Dictionary:
	return {
		"read_resource": _read_resource,
		"edit_resource": _edit_resource,
		"create_resource": _create_resource,
		"get_resource_preview": _get_resource_preview,
		"resource_contact_sheet": _resource_contact_sheet,
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
		"resource_contact_sheet": {
			"category": "resource",
			"summary": "Renders the editor's own generated thumbnails (EditorResourcePreview — the same previewer that powers the FileSystem dock) for a list of resources into one grid PNG, so an agent can see candidate scenes/meshes/materials/audio/etc. instead of guessing from filenames. Unlike get_resource_preview, this works for any previewable resource type, not just images.",
			"params": {
				"paths": {"type": "array", "required": true, "desc": "res:// paths to preview, e.g. scenes, meshes, materials, audio streams; max 64 per call"},
				"thumb_size": {"type": "int", "required": false, "default": 128, "desc": "Width/height in pixels of each cell, clamped 32-512"},
				"timeout": {"type": "float", "required": false, "default": 10.0, "desc": "Seconds to wait for all previews to render before filling remaining cells blank"},
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


func _resource_contact_sheet(params: Dictionary) -> Dictionary:
	if not params.has("paths") or not params["paths"] is Array:
		return error_invalid_params("'paths' (array of res:// paths) is required")
	var paths: Array = params["paths"]
	if paths.is_empty():
		return error_invalid_params("'paths' must not be empty")
	if paths.size() > 64:
		return error_invalid_params("Too many paths (%d); max 64 per call" % paths.size())

	var thumb_size: int = clampi(optional_int(params, "thumb_size", 128), 32, 512)
	var timeout: float = optional_float(params, "timeout", 10.0)

	var previewer := EditorInterface.get_resource_previewer()
	# Each entry is shared, by reference, with the queued preview callback
	# below — it fills in "image"/"error" once the engine finishes rendering
	# that resource's thumbnail, which happens on a later frame.
	var entries: Array[Dictionary] = []
	for path: Variant in paths:
		var entry := {"path": str(path)}
		entries.append(entry)
		if not (path is String) or not FileAccess.file_exists(path):
			entry["error"] = "not found"
			continue
		previewer.queue_resource_preview(path, self, "_on_contact_sheet_preview", entry)

	var elapsed := 0.0
	while elapsed < timeout:
		var all_done := true
		for entry: Dictionary in entries:
			if not entry.has("image") and not entry.has("error"):
				all_done = false
				break
		if all_done:
			break
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	var cols: int = ceili(sqrt(entries.size()))
	var rows: int = ceili(float(entries.size()) / cols)
	var sheet := Image.create(cols * thumb_size, rows * thumb_size, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.15, 0.15, 1.0))

	var missing: Array = []
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var img: Variant = entry.get("image")
		if img == null:
			missing.append(entry["path"])
			continue
		var resized: Image = (img as Image)
		if resized.get_width() != thumb_size or resized.get_height() != thumb_size:
			resized.resize(thumb_size, thumb_size, Image.INTERPOLATE_LANCZOS)
		if resized.get_format() != Image.FORMAT_RGBA8:
			resized.convert(Image.FORMAT_RGBA8)
		var col := i % cols
		var row := i / cols
		sheet.blit_rect(resized, Rect2i(0, 0, thumb_size, thumb_size), Vector2i(col * thumb_size, row * thumb_size))

	var png_buffer := sheet.save_png_to_buffer()
	var base64 := Marshalls.raw_to_base64(png_buffer)

	var order: Array = []
	for entry: Dictionary in entries:
		order.append(entry["path"])

	return success({
		"image_base64": base64,
		"width": sheet.get_width(),
		"height": sheet.get_height(),
		"columns": cols,
		"rows": rows,
		"thumb_size": thumb_size,
		"order": order,
		"missing": missing,
	})


## EditorResourcePreview callback signature: (path, preview, thumbnail_preview, userdata).
## `userdata` is the same entry Dictionary queued above, so writing into it
## here is visible to the polling loop in _resource_contact_sheet.
func _on_contact_sheet_preview(_path: String, preview: Texture2D, _thumbnail_preview: Texture2D, userdata: Variant) -> void:
	var entry: Dictionary = userdata
	if preview:
		entry["image"] = preview.get_image()
	else:
		entry["error"] = "no preview available for this resource type"
