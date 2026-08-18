@tool
extends "res://addons/godot_mcp/commands/base_command.gd"


func get_commands() -> Dictionary:
	return {
		"create_shader": _create_shader,
		"read_shader": _read_shader,
		"edit_shader": _edit_shader,
		"assign_shader_material": _assign_shader_material,
		"set_shader_param": _set_shader_param,
		"get_shader_params": _get_shader_params,
	}


func get_command_schemas() -> Dictionary:
	return {
		"create_shader": {
			"category": "shader",
			"summary": "Write a new .gdshader/.gdshaderinc file, with boilerplate for the given shader_type if no content is given. Refuses to overwrite an existing file unless force is set.",
			"params": {
				"path": {"type": "string", "required": true, "desc": "res:// path, must end in .gdshader or .gdshaderinc"},
				"content": {"type": "string", "required": false, "default": "", "desc": "Full shader source; if empty, boilerplate for shader_type is used"},
				"shader_type": {"type": "string", "required": false, "default": "spatial", "desc": "One of: spatial, canvas_item, particles, sky; picks the boilerplate when content is empty"},
				"force": {"type": "bool", "required": false, "default": false, "desc": "Overwrite an existing file at path"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": false},
		},
		"read_shader": {
			"category": "shader",
			"summary": "Read the full source of a shader file.",
			"params": {
				"path": {"type": "string", "required": true, "desc": "res:// path to the shader file"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"edit_shader": {
			"category": "shader",
			"summary": "Replace a shader's entire content, or apply a list of search/replace substitutions. Refuses to overwrite unless force is set.",
			"params": {
				"path": {"type": "string", "required": true, "desc": "res:// path to an existing shader file"},
				"force": {"type": "bool", "required": false, "default": false, "desc": "Bypass the overwrite guard"},
				"content": {"type": "string", "required": false, "desc": "Full replacement source; if given, replacements is ignored"},
				"replacements": {"type": "array", "required": false, "desc": "List of {search, replace} string pairs applied to the current content"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": true},
		},
		"assign_shader_material": {
			"category": "shader",
			"summary": "Load a shader and assign it as a new ShaderMaterial on a node's material (CanvasItem) or material_override (MeshInstance3D) property.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Scene-relative path to the target node"},
				"shader_path": {"type": "string", "required": true, "desc": "res:// path to the .gdshader to load"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"set_shader_param": {
			"category": "shader",
			"summary": "Set a shader_parameter on a node's existing ShaderMaterial. String values that parse as an expression (e.g. 'Vector3(1,0,0)') are evaluated first.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Scene-relative path to the node holding the ShaderMaterial"},
				"param": {"type": "string", "required": true, "desc": "Shader parameter name"},
				"value": {"type": "any", "required": false, "desc": "Value to assign; strings are evaluated as expressions when possible"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"get_shader_params": {
			"category": "shader",
			"summary": "List all shader_parameter values currently set on a node's ShaderMaterial.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Scene-relative path to the node holding the ShaderMaterial"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
	}


func _create_shader(params: Dictionary) -> Dictionary:
	var result := require_string(params, "path")
	if result[1] != null:
		return result[1]
	var path: String = result[0]

	var content: String = optional_string(params, "content", "")
	var shader_type: String = optional_string(params, "shader_type", "spatial")
	var force: bool = optional_bool(params, "force", false)

	var guard := guard_text_resource_write(path, force)
	if not guard.is_empty():
		return guard

	if content.is_empty():
		match shader_type:
			"spatial":
				content = "shader_type spatial;\n\nvoid vertex() {\n\t// Called for every vertex\n}\n\nvoid fragment() {\n\t// Called for every pixel\n\tALBEDO = vec3(1.0);\n}\n"
			"canvas_item":
				content = "shader_type canvas_item;\n\nvoid vertex() {\n\t// Called for every vertex\n}\n\nvoid fragment() {\n\t// Called for every pixel\n\tCOLOR = vec4(1.0);\n}\n"
			"particles":
				content = "shader_type particles;\n\nvoid start() {\n\t// Called when particle spawns\n}\n\nvoid process() {\n\t// Called every frame per particle\n}\n"
			"sky":
				content = "shader_type sky;\n\nvoid sky() {\n\tCOLOR = vec3(0.3, 0.5, 0.8);\n}\n"

	var ext_guard := guard_expected_extension(path, ["gdshader", "gdshaderinc"], "a shader")
	if not ext_guard.is_empty():
		return ext_guard

	# Ensure directory exists
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return error_internal("Cannot create shader: %s" % error_string(FileAccess.get_open_error()))

	file.store_string(content)
	file.close()

	_refresh_loaded_shader(path, content)

	return success({"path": path, "shader_type": shader_type, "created": true})


func _read_shader(params: Dictionary) -> Dictionary:
	var result := require_string(params, "path")
	if result[1] != null:
		return result[1]
	var path: String = result[0]

	if not FileAccess.file_exists(path):
		return error_not_found("Shader '%s'" % path)

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return error_internal("Cannot read shader: %s" % error_string(FileAccess.get_open_error()))

	var content := file.get_as_text()
	file.close()

	return success({"path": path, "content": content, "size": content.length()})


func _refresh_loaded_shader(path: String, content: String) -> void:
	var normalized := normalize_project_path(path)
	if normalized.is_empty():
		return
	if ResourceLoader.has_cached(normalized):
		var shader := Shader.new()
		shader.code = content
		shader.take_over_path(normalized)
		shader.emit_changed()
	EditorInterface.get_resource_filesystem().update_file(normalized)


func _edit_shader(params: Dictionary) -> Dictionary:
	var result := require_string(params, "path")
	if result[1] != null:
		return result[1]
	var path: String = result[0]

	if not FileAccess.file_exists(path):
		return error_not_found("Shader '%s'" % path)

	var force: bool = optional_bool(params, "force", false)
	var guard := guard_text_resource_write(path, force)
	if not guard.is_empty():
		return guard

	var changes_made := 0
	var content := ""

	if params.has("content"):
		content = str(params["content"])
		changes_made = 1
	elif params.has("replacements") and params["replacements"] is Array:
		# Read current
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return error_internal("Cannot read shader")
		content = file.get_as_text()
		file.close()

		for replacement in params["replacements"]:
			if replacement is Dictionary:
				var search: String = replacement.get("search", "")
				var replace: String = replacement.get("replace", "")
				if not search.is_empty() and content.contains(search):
					content = content.replace(search, replace)
					changes_made += 1

	if changes_made > 0:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return error_internal("Cannot write shader: %s" % error_string(FileAccess.get_open_error()))
		file.store_string(content)
		file.close()
		_refresh_loaded_shader(path, content)

	return success({"path": path, "changes_made": changes_made})


func _assign_shader_material(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var result2 := require_string(params, "shader_path")
	if result2[1] != null:
		return result2[1]
	var shader_path: String = result2[0]

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node at '%s'" % node_path)

	if not ResourceLoader.exists(shader_path):
		return error_not_found("Shader '%s'" % shader_path)

	var shader: Shader = load(shader_path)
	if shader == null:
		return error_internal("Failed to load shader")

	var material := ShaderMaterial.new()
	material.shader = shader

	if node is CanvasItem:
		set_property_with_undo(node, "material", material, "MCP: Assign shader material")
	elif node is MeshInstance3D:
		set_property_with_undo(node, "material_override", material, "MCP: Assign shader material")
	else:
		# Try generic material property
		if "material" in node:
			set_property_with_undo(node, "material", material, "MCP: Assign shader material")
		else:
			return error_invalid_params("Node '%s' (%s) does not support materials" % [node_path, node.get_class()])

	return success({"node_path": node_path, "shader_path": shader_path, "assigned": true})


func _set_shader_param(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var result2 := require_string(params, "param")
	if result2[1] != null:
		return result2[1]
	var param_name: String = result2[0]

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node at '%s'" % node_path)

	var material: ShaderMaterial = null
	if node is CanvasItem and (node as CanvasItem).material is ShaderMaterial:
		material = (node as CanvasItem).material
	elif node is MeshInstance3D and (node as MeshInstance3D).material_override is ShaderMaterial:
		material = (node as MeshInstance3D).material_override

	if material == null:
		return error(-32000, "Node has no ShaderMaterial")

	var value = params.get("value")
	if value is String:
		var s: String = value
		var expr := Expression.new()
		if expr.parse(s) == OK:
			var parsed = expr.execute()
			if parsed != null:
				value = parsed

	material.set_shader_parameter(param_name, value)

	return success({"node_path": node_path, "param": param_name, "value": str(value)})


func _get_shader_params(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node at '%s'" % node_path)

	var material: ShaderMaterial = null
	if node is CanvasItem and (node as CanvasItem).material is ShaderMaterial:
		material = (node as CanvasItem).material
	elif node is MeshInstance3D and (node as MeshInstance3D).material_override is ShaderMaterial:
		material = (node as MeshInstance3D).material_override

	if material == null:
		return error(-32000, "Node has no ShaderMaterial")

	var shader_params: Dictionary = {}
	for prop in material.get_property_list():
		var pname: String = prop["name"]
		if pname.begins_with("shader_parameter/"):
			var key := pname.substr(17)
			shader_params[key] = str(material.get(pname))

	return success({"node_path": node_path, "params": shader_params})
