@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

const PropertyParser := preload("res://addons/godot_mcp/utils/property_parser.gd")
const NodeUtils := preload("res://addons/godot_mcp/utils/node_utils.gd")


func get_commands() -> Dictionary:
	return {
		"add_mesh_instance": _add_mesh_instance,
		"setup_lighting": _setup_lighting,
		"set_material_3d": _set_material_3d,
		"setup_environment": _setup_environment,
		"setup_camera_3d": _setup_camera_3d,
		"add_gridmap": _add_gridmap,
	}


func get_command_schemas() -> Dictionary:
	return {
		"add_mesh_instance": {
			"category": "3d",
			"summary": "Add a MeshInstance3D under parent_path, built from a primitive mesh_type or loaded from mesh_file (.glb/.gltf/.obj/.mesh). Exactly one of mesh_type or mesh_file is required.",
			"params": {
				"parent_path": {"type": "string", "required": false, "default": ".", "desc": "Scene-relative path to the parent node"},
				"name": {"type": "string", "required": false, "default": "MeshInstance3D"},
				"mesh_type": {"type": "string", "required": false, "default": "", "desc": "One of: BoxMesh, SphereMesh, CylinderMesh, CapsuleMesh, PlaneMesh, PrismMesh, TorusMesh, QuadMesh; ignored if mesh_file is given"},
				"mesh_file": {"type": "string", "required": false, "default": "", "desc": "res:// path to a mesh/scene file; for a PackedScene, the first MeshInstance3D's mesh is used"},
				"mesh_properties": {"type": "object", "required": false, "default": {}, "desc": "Property name/value pairs applied to the created primitive mesh resource"},
				"position": {"type": "any", "required": false, "default": [0, 0, 0], "desc": "Vector3-like value: [x,y,z], {x,y,z}, or a 'Vector3(...)' string"},
				"rotation": {"type": "any", "required": false, "default": [0, 0, 0], "desc": "Rotation in degrees, Vector3-like"},
				"scale": {"type": "any", "required": false, "default": [1, 1, 1], "desc": "Vector3-like"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"setup_lighting": {
			"category": "3d",
			"summary": "Add a DirectionalLight3D, OmniLight3D, or SpotLight3D under parent_path, either from light_type or from a preset (sun/indoor/dramatic) that sets light_type and sensible defaults. Always creates a new node. Exactly one of light_type or preset is required.",
			"params": {
				"parent_path": {"type": "string", "required": false, "default": ".", "desc": "Scene-relative path to the parent node"},
				"light_type": {"type": "string", "required": false, "default": "", "desc": "One of: DirectionalLight3D, OmniLight3D, SpotLight3D; set automatically by preset"},
				"preset": {"type": "string", "required": false, "default": "", "desc": "One of: sun, indoor, dramatic; overrides light_type-derived defaults for energy, shadows, color, range, spot_angle, rotation"},
				"name": {"type": "string", "required": false, "default": "", "desc": "Defaults to the preset name or light_type"},
				"color": {"type": "any", "required": false, "default": [1, 1, 1, 1], "desc": "Color-like value: [r,g,b,a], {r,g,b,a}, or a 'Color(...)' string"},
				"energy": {"type": "float", "required": false, "default": 1.0, "desc": "light_energy; preset defaults differ (indoor 0.8, dramatic 2.0)"},
				"shadows": {"type": "bool", "required": false, "default": false, "desc": "shadow_enabled; preset defaults to true for sun and dramatic"},
				"range": {"type": "float", "required": false, "default": 5.0, "desc": "Omni/Spot range; preset defaults differ (indoor 8.0, dramatic 10.0)"},
				"attenuation": {"type": "float", "required": false, "default": 1.0, "desc": "Omni/Spot attenuation"},
				"spot_angle": {"type": "float", "required": false, "default": 45.0, "desc": "SpotLight3D only; preset dramatic defaults to 25.0"},
				"spot_angle_attenuation": {"type": "float", "required": false, "default": 1.0, "desc": "SpotLight3D only"},
				"position": {"type": "any", "required": false, "default": [0, 0, 0], "desc": "Vector3-like"},
				"rotation": {"type": "any", "required": false, "desc": "Rotation in degrees, Vector3-like; preset sun defaults to [-45,-30,0]"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"set_material_3d": {
			"category": "3d",
			"summary": "Create a StandardMaterial3D from the given properties and apply it as a surface override material on a MeshInstance3D.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Scene-relative path to a MeshInstance3D"},
				"surface_index": {"type": "int", "required": false, "default": 0},
				"albedo_color": {"type": "any", "required": false, "default": [1, 1, 1, 1], "desc": "Color-like value"},
				"albedo_texture": {"type": "string", "required": false, "desc": "res:// path to a texture"},
				"metallic": {"type": "float", "required": false, "default": 0.0},
				"roughness": {"type": "float", "required": false, "default": 1.0},
				"metallic_texture": {"type": "string", "required": false, "desc": "res:// path to a texture"},
				"roughness_texture": {"type": "string", "required": false, "desc": "res:// path to a texture"},
				"normal_texture": {"type": "string", "required": false, "desc": "res:// path to a texture; setting this enables normal mapping"},
				"emission": {"type": "any", "required": false, "desc": "Color-like value; setting this (or emission_color) enables emission"},
				"emission_color": {"type": "any", "required": false, "desc": "Fallback for emission"},
				"emission_energy": {"type": "float", "required": false, "default": 1.0},
				"emission_texture": {"type": "string", "required": false, "desc": "res:// path to a texture; setting this enables emission"},
				"transparency": {"type": "string", "required": false, "desc": "One of: DISABLED, ALPHA, ALPHA_SCISSOR, ALPHA_HASH, ALPHA_DEPTH_PRE_PASS (or their numeric codes)"},
				"cull_mode": {"type": "string", "required": false, "desc": "One of: BACK, FRONT, DISABLED (or their numeric codes)"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"setup_environment": {
			"category": "3d",
			"summary": "Create (or reconfigure, if node_path names an existing WorldEnvironment) a WorldEnvironment node's Environment resource: background, procedural sky, ambient light, tonemap, fog, glow, SSAO, SSR, SDFGI.",
			"params": {
				"parent_path": {"type": "string", "required": false, "default": ".", "desc": "Scene-relative path to the parent node, used when creating"},
				"name": {"type": "string", "required": false, "default": "WorldEnvironment", "desc": "Used when creating"},
				"node_path": {"type": "string", "required": false, "default": "", "desc": "Scene-relative path to an existing WorldEnvironment to reconfigure instead of creating one"},
				"background_mode": {"type": "string", "required": false, "default": "sky", "desc": "One of: sky, color, canvas, clear_color"},
				"background_color": {"type": "any", "required": false, "default": [0.3, 0.3, 0.3], "desc": "Color-like value, used when background_mode is 'color'"},
				"sky": {"type": "object", "required": false, "desc": "Procedural sky params: sky_top_color, sky_horizon_color, ground_bottom_color, ground_horizon_color, sun_angle_max, sky_curve; setting this forces background_mode to sky"},
				"ambient_light_color": {"type": "any", "required": false, "default": [1, 1, 1, 1], "desc": "Color-like value"},
				"ambient_light_energy": {"type": "float", "required": false, "default": 1.0},
				"ambient_light_source": {"type": "string", "required": false, "desc": "One of: BACKGROUND, DISABLED, COLOR, SKY (or their numeric codes)"},
				"tonemap_mode": {"type": "string", "required": false, "desc": "One of: LINEAR, REINHARDT, FILMIC, ACES, AGX (or their numeric codes)"},
				"tonemap_exposure": {"type": "float", "required": false, "default": 1.0},
				"tonemap_white": {"type": "float", "required": false, "default": 1.0},
				"fog_enabled": {"type": "bool", "required": false, "default": false},
				"fog_light_color": {"type": "any", "required": false, "default": [0.518, 0.553, 0.608], "desc": "Color-like value; only applied when fog is enabled"},
				"fog_density": {"type": "float", "required": false, "default": 0.01, "desc": "Only applied when fog is enabled"},
				"fog_light_energy": {"type": "float", "required": false, "default": 1.0, "desc": "Only applied when fog is enabled"},
				"glow_enabled": {"type": "bool", "required": false, "default": false},
				"glow_intensity": {"type": "float", "required": false, "default": 0.8, "desc": "Only applied when glow is enabled"},
				"glow_strength": {"type": "float", "required": false, "default": 1.0, "desc": "Only applied when glow is enabled"},
				"glow_bloom": {"type": "float", "required": false, "default": 0.0, "desc": "Only applied when glow is enabled"},
				"ssao_enabled": {"type": "bool", "required": false, "default": false},
				"ssao_radius": {"type": "float", "required": false, "default": 1.0, "desc": "Only applied when SSAO is enabled"},
				"ssao_intensity": {"type": "float", "required": false, "default": 2.0, "desc": "Only applied when SSAO is enabled"},
				"ssr_enabled": {"type": "bool", "required": false, "default": false},
				"ssr_max_steps": {"type": "int", "required": false, "default": 64, "desc": "Only applied when SSR is enabled"},
				"ssr_fade_in": {"type": "float", "required": false, "default": 0.15, "desc": "Only applied when SSR is enabled"},
				"ssr_fade_out": {"type": "float", "required": false, "default": 2.0, "desc": "Only applied when SSR is enabled"},
				"sdfgi_enabled": {"type": "bool", "required": false, "default": false},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"setup_camera_3d": {
			"category": "3d",
			"summary": "Create (or reconfigure, if node_path names an existing Camera3D) a Camera3D: projection, FOV/size, near/far, cull mask, current flag, transform, look_at target, environment override.",
			"params": {
				"parent_path": {"type": "string", "required": false, "default": ".", "desc": "Scene-relative path to the parent node, used when creating"},
				"node_path": {"type": "string", "required": false, "default": "", "desc": "Scene-relative path to an existing Camera3D to reconfigure instead of creating one"},
				"name": {"type": "string", "required": false, "default": "Camera3D", "desc": "Used when creating"},
				"projection": {"type": "string", "required": false, "default": "", "desc": "One of: perspective, orthogonal (or orthographic), frustum"},
				"fov": {"type": "float", "required": false, "default": 75.0},
				"size": {"type": "float", "required": false, "default": 1.0, "desc": "Orthogonal/frustum size"},
				"near": {"type": "float", "required": false, "default": 0.05},
				"far": {"type": "float", "required": false, "default": 4000.0},
				"cull_mask": {"type": "int", "required": false, "default": 1048575},
				"current": {"type": "bool", "required": false, "default": false, "desc": "Make this the active camera"},
				"position": {"type": "any", "required": false, "default": [0, 1, 3], "desc": "Vector3-like; kept as-is when reconfiguring an existing camera and not given"},
				"rotation": {"type": "any", "required": false, "desc": "Rotation in degrees, Vector3-like"},
				"look_at": {"type": "any", "required": false, "desc": "Vector3-like target point; applies Camera3D.look_at() after position is set"},
				"environment_path": {"type": "string", "required": false, "desc": "res:// path to an Environment resource to assign as an override"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"add_gridmap": {
			"category": "3d",
			"summary": "Create (or reconfigure, if node_path names an existing GridMap) a GridMap: mesh library, cell size, position, and a batch of cell placements.",
			"params": {
				"parent_path": {"type": "string", "required": false, "default": ".", "desc": "Scene-relative path to the parent node, used when creating"},
				"name": {"type": "string", "required": false, "default": "GridMap", "desc": "Used when creating"},
				"node_path": {"type": "string", "required": false, "default": "", "desc": "Scene-relative path to an existing GridMap to reconfigure instead of creating one"},
				"mesh_library_path": {"type": "string", "required": false, "desc": "res:// path to a .meshlib/.tres MeshLibrary resource"},
				"cell_size": {"type": "any", "required": false, "default": [2, 2, 2], "desc": "Vector3-like"},
				"position": {"type": "any", "required": false, "default": [0, 0, 0], "desc": "Vector3-like; kept as-is when reconfiguring an existing GridMap and not given"},
				"cells": {"type": "array", "required": false, "default": [], "desc": "List of {x, y, z, item, orientation} cell placements"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
	}


## ─── Helpers ───────────────────────────────────────────────────────────────

## Kept as a thin alias so existing call sites are unchanged; the shared
## helper is the one that does not raise on null, arrays or dictionaries.
func _optional_float(params: Dictionary, key: String, default: float) -> float:
	return optional_float(params, key, default)


func _parse_color_param(params: Dictionary, key: String, default: Color) -> Color:
	if not params.has(key):
		return default
	var val: Variant = params[key]
	if val is String:
		return PropertyParser.parse_value(val, TYPE_COLOR)
	if val is Dictionary:
		return Color(
			float(val.get("r", default.r)),
			float(val.get("g", default.g)),
			float(val.get("b", default.b)),
			float(val.get("a", default.a))
		)
	return default


func _parse_vector3_param(params: Dictionary, key: String, default: Vector3) -> Vector3:
	if not params.has(key):
		return default
	var val: Variant = params[key]
	if val is String:
		return PropertyParser.parse_value(val, TYPE_VECTOR3)
	if val is Dictionary:
		return Vector3(
			float(val.get("x", default.x)),
			float(val.get("y", default.y)),
			float(val.get("z", default.z))
		)
	if val is Array and val.size() >= 3:
		return Vector3(float(val[0]), float(val[1]), float(val[2]))
	return default


func _add_child_with_undo(node: Node, parent: Node, root: Node, action_name: String) -> void:
	var undo_redo := get_undo_redo()
	undo_redo.create_action(action_name)
	undo_redo.add_do_method(parent, "add_child", node)
	undo_redo.add_do_method(node, "set_owner", root)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(parent, "remove_child", node)
	undo_redo.commit_action()


## ─── 1. add_mesh_instance ──────────────────────────────────────────────────

func _add_mesh_instance(params: Dictionary) -> Dictionary:
	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent := find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node '%s'" % parent_path)

	var node_name: String = optional_string(params, "name", "MeshInstance3D")
	var mesh_type: String = optional_string(params, "mesh_type", "")
	var mesh_file: String = optional_string(params, "mesh_file", "")

	if mesh_type.is_empty() and mesh_file.is_empty():
		return error_invalid_params("Either 'mesh_type' or 'mesh_file' is required")

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name

	if not mesh_file.is_empty():
		# Load .glb / .gltf / .obj
		if not ResourceLoader.exists(mesh_file):
			mesh_instance.queue_free()
			return error_not_found("Mesh file '%s'" % mesh_file, "Provide a valid res:// path to .glb, .gltf, or .obj")
		var loaded: Resource = load(mesh_file)
		if loaded is Mesh:
			mesh_instance.mesh = loaded as Mesh
		elif loaded is PackedScene:
			# For .glb/.gltf we instantiate and steal the first MeshInstance3D's mesh
			var scene_instance: Node = (loaded as PackedScene).instantiate()
			var found_mesh: Mesh = null
			var search_nodes: Array[Node] = [scene_instance]
			while not search_nodes.is_empty():
				var n: Node = search_nodes.pop_front()
				if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
					found_mesh = (n as MeshInstance3D).mesh
					break
				for child in n.get_children():
					search_nodes.append(child)
			scene_instance.queue_free()
			if found_mesh == null:
				mesh_instance.queue_free()
				return error_invalid_params("No mesh found in '%s'" % mesh_file)
			mesh_instance.mesh = found_mesh
		else:
			mesh_instance.queue_free()
			return error_invalid_params("'%s' is not a Mesh or PackedScene" % mesh_file)
	else:
		# Primitive mesh
		var mesh_classes := {
			"BoxMesh": BoxMesh,
			"SphereMesh": SphereMesh,
			"CylinderMesh": CylinderMesh,
			"CapsuleMesh": CapsuleMesh,
			"PlaneMesh": PlaneMesh,
			"PrismMesh": PrismMesh,
			"TorusMesh": TorusMesh,
			"QuadMesh": QuadMesh,
		}
		if not mesh_classes.has(mesh_type):
			mesh_instance.queue_free()
			return error_invalid_params("Unknown mesh_type '%s'. Available: %s" % [mesh_type, mesh_classes.keys()])
		var mesh_res: Mesh = mesh_classes[mesh_type].new()
		# Apply mesh properties if provided
		var mesh_properties: Dictionary = params.get("mesh_properties", {})
		for prop_name: String in mesh_properties:
			if prop_name in mesh_res:
				var current: Variant = mesh_res.get(prop_name)
				mesh_res.set(prop_name, PropertyParser.parse_value(mesh_properties[prop_name], typeof(current)))
		mesh_instance.mesh = mesh_res

	# Transform
	var position := _parse_vector3_param(params, "position", Vector3.ZERO)
	var rotation_deg := _parse_vector3_param(params, "rotation", Vector3.ZERO)
	var scale_vec := _parse_vector3_param(params, "scale", Vector3.ONE)

	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation_deg
	mesh_instance.scale = scale_vec

	_add_child_with_undo(mesh_instance, parent, root, "MCP: Add MeshInstance3D")

	return success({
		"node_path": str(root.get_path_to(mesh_instance)),
		"name": str(mesh_instance.name),
		"mesh_type": mesh_type if mesh_file.is_empty() else mesh_file,
	})


## ─── 2. setup_lighting ────────────────────────────────────────────────────

func _setup_lighting(params: Dictionary) -> Dictionary:
	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent := find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node '%s'" % parent_path)

	var light_type: String = optional_string(params, "light_type", "")
	var preset: String = optional_string(params, "preset", "")
	var node_name: String = optional_string(params, "name", "")

	# Preset configurations
	if not preset.is_empty():
		match preset:
			"sun":
				light_type = "DirectionalLight3D"
				if node_name.is_empty():
					node_name = "SunLight"
			"indoor":
				light_type = "OmniLight3D"
				if node_name.is_empty():
					node_name = "IndoorLight"
			"dramatic":
				light_type = "SpotLight3D"
				if node_name.is_empty():
					node_name = "DramaticLight"
			_:
				return error_invalid_params("Unknown preset '%s'. Available: sun, indoor, dramatic" % preset)

	if light_type.is_empty():
		return error_invalid_params("Either 'light_type' or 'preset' is required")

	var light: Light3D
	match light_type:
		"DirectionalLight3D":
			light = DirectionalLight3D.new()
		"OmniLight3D":
			light = OmniLight3D.new()
		"SpotLight3D":
			light = SpotLight3D.new()
		_:
			return error_invalid_params("Unknown light_type '%s'. Available: DirectionalLight3D, OmniLight3D, SpotLight3D" % light_type)

	if node_name.is_empty():
		node_name = light_type
	light.name = node_name

	# Common properties
	light.light_color = _parse_color_param(params, "color", Color.WHITE)
	light.light_energy = _optional_float(params, "energy", 1.0)
	light.shadow_enabled = optional_bool(params, "shadows", false)

	# Type-specific properties
	if light is OmniLight3D:
		var omni: OmniLight3D = light as OmniLight3D
		omni.omni_range = _optional_float(params, "range", 5.0)
		omni.omni_attenuation = _optional_float(params, "attenuation", 1.0)
	elif light is SpotLight3D:
		var spot: SpotLight3D = light as SpotLight3D
		spot.spot_range = _optional_float(params, "range", 5.0)
		spot.spot_attenuation = _optional_float(params, "attenuation", 1.0)
		spot.spot_angle = _optional_float(params, "spot_angle", 45.0)
		spot.spot_angle_attenuation = _optional_float(params, "spot_angle_attenuation", 1.0)

	# Apply preset defaults after type creation
	if not preset.is_empty():
		match preset:
			"sun":
				light.light_energy = _optional_float(params, "energy", 1.0)
				light.shadow_enabled = optional_bool(params, "shadows", true)
				light.rotation_degrees = _parse_vector3_param(params, "rotation", Vector3(-45, -30, 0))
			"indoor":
				light.light_energy = _optional_float(params, "energy", 0.8)
				light.light_color = _parse_color_param(params, "color", Color(1.0, 0.95, 0.85))
				if light is OmniLight3D:
					(light as OmniLight3D).omni_range = _optional_float(params, "range", 8.0)
			"dramatic":
				light.light_energy = _optional_float(params, "energy", 2.0)
				light.shadow_enabled = optional_bool(params, "shadows", true)
				if light is SpotLight3D:
					(light as SpotLight3D).spot_angle = _optional_float(params, "spot_angle", 25.0)
					(light as SpotLight3D).spot_range = _optional_float(params, "range", 10.0)

	# Position / rotation
	light.position = _parse_vector3_param(params, "position", Vector3.ZERO)
	if params.has("rotation"):
		light.rotation_degrees = _parse_vector3_param(params, "rotation", light.rotation_degrees)

	_add_child_with_undo(light, parent, root, "MCP: Add %s" % light_type)

	return success({
		"node_path": str(root.get_path_to(light)),
		"name": str(light.name),
		"light_type": light_type,
		"preset": preset,
	})


## ─── 3. set_material_3d ───────────────────────────────────────────────────

func _set_material_3d(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)

	if not node is MeshInstance3D:
		return error_invalid_params("Node '%s' is not a MeshInstance3D (is %s)" % [node_path, node.get_class()])

	var mesh_inst: MeshInstance3D = node as MeshInstance3D
	var surface_index: int = optional_int(params, "surface_index", 0)

	var mat := StandardMaterial3D.new()

	# Albedo
	mat.albedo_color = _parse_color_param(params, "albedo_color", Color.WHITE)
	if params.has("albedo_texture"):
		var tex_path: String = params["albedo_texture"]
		if ResourceLoader.exists(tex_path):
			mat.albedo_texture = load(tex_path) as Texture2D

	# PBR
	mat.metallic = _optional_float(params, "metallic", 0.0)
	mat.roughness = _optional_float(params, "roughness", 1.0)
	if params.has("metallic_texture"):
		var tex_path: String = params["metallic_texture"]
		if ResourceLoader.exists(tex_path):
			mat.metallic_texture = load(tex_path) as Texture2D
	if params.has("roughness_texture"):
		var tex_path: String = params["roughness_texture"]
		if ResourceLoader.exists(tex_path):
			mat.roughness_texture = load(tex_path) as Texture2D
	if params.has("normal_texture"):
		mat.normal_enabled = true
		var tex_path: String = params["normal_texture"]
		if ResourceLoader.exists(tex_path):
			mat.normal_texture = load(tex_path) as Texture2D

	# Emission
	if params.has("emission") or params.has("emission_color"):
		mat.emission_enabled = true
		mat.emission = _parse_color_param(params, "emission", _parse_color_param(params, "emission_color", Color.BLACK))
		mat.emission_energy_multiplier = _optional_float(params, "emission_energy", 1.0)
	if params.has("emission_texture"):
		mat.emission_enabled = true
		var tex_path: String = params["emission_texture"]
		if ResourceLoader.exists(tex_path):
			mat.emission_texture = load(tex_path) as Texture2D

	# Transparency
	if params.has("transparency"):
		var transparency_val: String = str(params["transparency"])
		match transparency_val.to_upper():
			"DISABLED", "0":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			"ALPHA", "1":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			"ALPHA_SCISSOR", "2":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			"ALPHA_HASH", "3":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
			"ALPHA_DEPTH_PRE_PASS", "4":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS

	# Cull mode
	if params.has("cull_mode"):
		var cull_val: String = str(params["cull_mode"])
		match cull_val.to_upper():
			"BACK", "0":
				mat.cull_mode = BaseMaterial3D.CULL_BACK
			"FRONT", "1":
				mat.cull_mode = BaseMaterial3D.CULL_FRONT
			"DISABLED", "2":
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Apply
	var old_mat: Material = mesh_inst.get_surface_override_material(surface_index)
	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Set material on %s" % mesh_inst.name)
	undo_redo.add_do_method(mesh_inst, "set_surface_override_material", surface_index, mat)
	undo_redo.add_undo_method(mesh_inst, "set_surface_override_material", surface_index, old_mat)
	undo_redo.commit_action()

	return success({
		"node_path": str(root.get_path_to(mesh_inst)),
		"surface_index": surface_index,
		"albedo_color": str(mat.albedo_color),
		"metallic": mat.metallic,
		"roughness": mat.roughness,
	})


## ─── 4. setup_environment ─────────────────────────────────────────────────

func _setup_environment(params: Dictionary) -> Dictionary:
	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent := find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node '%s'" % parent_path)

	var node_name: String = optional_string(params, "name", "WorldEnvironment")

	# Check if a WorldEnvironment already exists at the target
	var node_path: String = optional_string(params, "node_path", "")
	var world_env: WorldEnvironment = null
	var is_existing := false

	if not node_path.is_empty():
		var existing := find_node_by_path(node_path)
		if existing != null and existing is WorldEnvironment:
			world_env = existing as WorldEnvironment
			is_existing = true

	if world_env == null:
		world_env = WorldEnvironment.new()
		world_env.name = node_name

	var env: Environment = world_env.environment
	if env == null:
		env = Environment.new()

	# Background / Sky
	var bg_mode: String = optional_string(params, "background_mode", "sky")
	match bg_mode.to_lower():
		"sky":
			env.background_mode = Environment.BG_SKY
		"color":
			env.background_mode = Environment.BG_COLOR
			env.background_color = _parse_color_param(params, "background_color", Color(0.3, 0.3, 0.3))
		"canvas":
			env.background_mode = Environment.BG_CANVAS
		"clear_color":
			env.background_mode = Environment.BG_CLEAR_COLOR

	# Procedural sky
	if params.has("sky") and params["sky"] is Dictionary:
		var sky_params: Dictionary = params["sky"]
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = _parse_color_param(sky_params, "sky_top_color", Color(0.385, 0.454, 0.55))
		sky_mat.sky_horizon_color = _parse_color_param(sky_params, "sky_horizon_color", Color(0.646, 0.654, 0.67))
		sky_mat.ground_bottom_color = _parse_color_param(sky_params, "ground_bottom_color", Color(0.2, 0.169, 0.133))
		sky_mat.ground_horizon_color = _parse_color_param(sky_params, "ground_horizon_color", Color(0.646, 0.654, 0.67))
		sky_mat.sun_angle_max = _optional_float(sky_params, "sun_angle_max", 30.0) if sky_params.has("sun_angle_max") else 30.0
		sky_mat.sky_curve = _optional_float(sky_params, "sky_curve", 0.15) if sky_params.has("sky_curve") else 0.15

		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.sky = sky
		env.background_mode = Environment.BG_SKY

	# Ambient light
	if params.has("ambient_light_color"):
		env.ambient_light_color = _parse_color_param(params, "ambient_light_color", Color.WHITE)
	env.ambient_light_energy = _optional_float(params, "ambient_light_energy", 1.0) if params.has("ambient_light_energy") else env.ambient_light_energy
	if params.has("ambient_light_source"):
		var src: String = str(params["ambient_light_source"])
		match src.to_upper():
			"BACKGROUND", "0":
				env.ambient_light_source = Environment.AMBIENT_SOURCE_BG
			"DISABLED", "1":
				env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
			"COLOR", "2":
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			"SKY", "3":
				env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

	# Tonemap
	if params.has("tonemap_mode"):
		var tm: String = str(params["tonemap_mode"])
		match tm.to_upper():
			"LINEAR", "0":
				env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			"REINHARDT", "1":
				env.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
			"FILMIC", "2":
				env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			"ACES", "3":
				env.tonemap_mode = Environment.TONE_MAPPER_ACES
			"AGX", "4":
				env.tonemap_mode = 4  # Environment.TONE_MAPPER_AGX (Godot 4.4+)
	if params.has("tonemap_exposure"):
		env.tonemap_exposure = _optional_float(params, "tonemap_exposure", 1.0)
	if params.has("tonemap_white"):
		env.tonemap_white = _optional_float(params, "tonemap_white", 1.0)

	# Fog
	if params.has("fog_enabled"):
		env.fog_enabled = optional_bool(params, "fog_enabled", false)
	if env.fog_enabled or params.has("fog_light_color"):
		env.fog_light_color = _parse_color_param(params, "fog_light_color", Color(0.518, 0.553, 0.608))
		env.fog_density = _optional_float(params, "fog_density", 0.01) if params.has("fog_density") else env.fog_density
		env.fog_light_energy = _optional_float(params, "fog_light_energy", 1.0) if params.has("fog_light_energy") else env.fog_light_energy

	# Glow
	if params.has("glow_enabled"):
		env.glow_enabled = optional_bool(params, "glow_enabled", false)
	if env.glow_enabled:
		env.glow_intensity = _optional_float(params, "glow_intensity", 0.8) if params.has("glow_intensity") else env.glow_intensity
		env.glow_strength = _optional_float(params, "glow_strength", 1.0) if params.has("glow_strength") else env.glow_strength
		env.glow_bloom = _optional_float(params, "glow_bloom", 0.0) if params.has("glow_bloom") else env.glow_bloom

	# SSAO
	if params.has("ssao_enabled"):
		env.ssao_enabled = optional_bool(params, "ssao_enabled", false)
	if env.ssao_enabled:
		env.ssao_radius = _optional_float(params, "ssao_radius", 1.0) if params.has("ssao_radius") else env.ssao_radius
		env.ssao_intensity = _optional_float(params, "ssao_intensity", 2.0) if params.has("ssao_intensity") else env.ssao_intensity

	# SSR
	if params.has("ssr_enabled"):
		env.ssr_enabled = optional_bool(params, "ssr_enabled", false)
	if env.ssr_enabled:
		env.ssr_max_steps = optional_int(params, "ssr_max_steps", 64) if params.has("ssr_max_steps") else env.ssr_max_steps
		env.ssr_fade_in = _optional_float(params, "ssr_fade_in", 0.15) if params.has("ssr_fade_in") else env.ssr_fade_in
		env.ssr_fade_out = _optional_float(params, "ssr_fade_out", 2.0) if params.has("ssr_fade_out") else env.ssr_fade_out

	# SDFGI
	if params.has("sdfgi_enabled"):
		env.sdfgi_enabled = optional_bool(params, "sdfgi_enabled", false)

	world_env.environment = env

	if not is_existing:
		_add_child_with_undo(world_env, parent, root, "MCP: Add WorldEnvironment")

	var features: Array = []
	if env.fog_enabled: features.append("fog")
	if env.glow_enabled: features.append("glow")
	if env.ssao_enabled: features.append("ssao")
	if env.ssr_enabled: features.append("ssr")
	if env.sdfgi_enabled: features.append("sdfgi")

	return success({
		"node_path": str(root.get_path_to(world_env)),
		"name": str(world_env.name),
		"background_mode": bg_mode,
		"features": features,
		"is_existing": is_existing,
	})


## ─── 5. setup_camera_3d ──────────────────────────────────────────────────

func _setup_camera_3d(params: Dictionary) -> Dictionary:
	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent := find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node '%s'" % parent_path)

	# Check if we're configuring an existing camera
	var node_path: String = optional_string(params, "node_path", "")
	var camera: Camera3D = null
	var is_existing := false

	if not node_path.is_empty():
		var existing := find_node_by_path(node_path)
		if existing != null and existing is Camera3D:
			camera = existing as Camera3D
			is_existing = true
		elif existing != null:
			return error_invalid_params("Node '%s' is not a Camera3D (is %s)" % [node_path, existing.get_class()])

	if camera == null:
		camera = Camera3D.new()
		camera.name = optional_string(params, "name", "Camera3D")

	# Projection
	var projection_str: String = optional_string(params, "projection", "")
	if not projection_str.is_empty():
		match projection_str.to_lower():
			"perspective", "0":
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			"orthogonal", "orthographic", "1":
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			"frustum", "2":
				camera.projection = Camera3D.PROJECTION_FRUSTUM

	# Properties
	if params.has("fov"):
		camera.fov = _optional_float(params, "fov", 75.0)
	if params.has("size"):
		camera.size = _optional_float(params, "size", 1.0)
	if params.has("near"):
		camera.near = _optional_float(params, "near", 0.05)
	if params.has("far"):
		camera.far = _optional_float(params, "far", 4000.0)
	if params.has("cull_mask"):
		camera.cull_mask = optional_int(params, "cull_mask", 1048575)

	# Make current
	camera.current = optional_bool(params, "current", false)

	# Transform
	camera.position = _parse_vector3_param(params, "position", camera.position if is_existing else Vector3(0, 1, 3))
	if params.has("rotation"):
		camera.rotation_degrees = _parse_vector3_param(params, "rotation", camera.rotation_degrees)
	if params.has("look_at"):
		var target := _parse_vector3_param(params, "look_at", Vector3.ZERO)
		# We need to set position first, then use look_at
		camera.look_at(target)

	# Environment override
	if params.has("environment_path"):
		var env_path: String = params["environment_path"]
		if ResourceLoader.exists(env_path):
			var env_res: Resource = load(env_path)
			if env_res is Environment:
				camera.environment = env_res as Environment

	if not is_existing:
		_add_child_with_undo(camera, parent, root, "MCP: Add Camera3D")

	return success({
		"node_path": str(root.get_path_to(camera)),
		"name": str(camera.name),
		"projection": "perspective" if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else "orthogonal",
		"fov": camera.fov,
		"position": str(camera.position),
		"is_existing": is_existing,
	})


## ─── 6. add_gridmap ──────────────────────────────────────────────────────

func _add_gridmap(params: Dictionary) -> Dictionary:
	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent := find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node '%s'" % parent_path)

	var node_name: String = optional_string(params, "name", "GridMap")

	# Check for existing GridMap to configure
	var node_path: String = optional_string(params, "node_path", "")
	var gridmap: GridMap = null
	var is_existing := false

	if not node_path.is_empty():
		var existing := find_node_by_path(node_path)
		if existing != null and existing is GridMap:
			gridmap = existing as GridMap
			is_existing = true
		elif existing != null:
			return error_invalid_params("Node '%s' is not a GridMap (is %s)" % [node_path, existing.get_class()])

	if gridmap == null:
		gridmap = GridMap.new()
		gridmap.name = node_name

	# Mesh library
	if params.has("mesh_library_path"):
		var lib_path: String = params["mesh_library_path"]
		if not ResourceLoader.exists(lib_path):
			if not is_existing:
				gridmap.queue_free()
			return error_not_found("MeshLibrary '%s'" % lib_path, "Provide a valid res:// path to a .meshlib or .tres file")
		var lib: Resource = load(lib_path)
		if lib is MeshLibrary:
			gridmap.mesh_library = lib as MeshLibrary
		else:
			if not is_existing:
				gridmap.queue_free()
			return error_invalid_params("'%s' is not a MeshLibrary" % lib_path)

	# Cell size
	if params.has("cell_size"):
		gridmap.cell_size = _parse_vector3_param(params, "cell_size", Vector3(2, 2, 2))

	# Position
	gridmap.position = _parse_vector3_param(params, "position", gridmap.position if is_existing else Vector3.ZERO)

	if not is_existing:
		_add_child_with_undo(gridmap, parent, root, "MCP: Add GridMap")

	# Set cells
	var cells: Array = params.get("cells", [])
	var cells_set: int = 0
	for cell in cells:
		if cell is Dictionary:
			var x: int = int(cell.get("x", 0))
			var y: int = int(cell.get("y", 0))
			var z: int = int(cell.get("z", 0))
			var item: int = int(cell.get("item", 0))
			var orientation: int = int(cell.get("orientation", 0))
			gridmap.set_cell_item(Vector3i(x, y, z), item, orientation)
			cells_set += 1

	return success({
		"node_path": str(root.get_path_to(gridmap)),
		"name": str(gridmap.name),
		"cells_set": cells_set,
		"is_existing": is_existing,
		"has_mesh_library": gridmap.mesh_library != null,
	})
