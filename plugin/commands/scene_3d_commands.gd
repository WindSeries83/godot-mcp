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
		"get_spatial_bounds": _get_spatial_bounds,
		"turntable_screenshot": _turntable_screenshot,
		"snap_to_ground": _snap_to_ground,
		"align_nodes": _align_nodes,
		"distribute_nodes": _distribute_nodes,
		"look_at_node": _look_at_node,
		"add_csg_shape": _add_csg_shape,
		"add_multimesh_scatter": _add_multimesh_scatter,
		"add_path3d": _add_path3d,
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
		"get_spatial_bounds": {
			"category": "3d",
			"summary": "World-space AABB of a Node3D, merged with its VisualInstance3D descendants' bounds. The primitive an agent needs before placing/sizing/framing anything in 3D — without it, positions and scales are guesses.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Scene-relative path to a Node3D"},
				"include_children": {"type": "bool", "required": false, "default": true, "desc": "Merge descendant VisualInstance3D bounds in, not just the node's own"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"turntable_screenshot": {
			"category": "3d",
			"summary": "Orbits the 3D editor camera around a node's world-space bounds, capturing one view per angle, and composites them into a single contact-sheet PNG. Restores the original camera position/FOV afterward. Does not work under --headless (same limitation as get_editor_screenshot). Refuses to overwrite an existing file at save_path unless overwrite is set.",
			"params": {
				"node_path": {"type": "string", "required": false, "default": ".", "desc": "Scene-relative path to the Node3D to frame"},
				"views": {"type": "int", "required": false, "default": 4, "desc": "Number of evenly-spaced angles around the node, clamped 1-12"},
				"elevation_degrees": {"type": "float", "required": false, "default": 25.0, "desc": "Camera elevation above the horizontal plane"},
				"padding": {"type": "float", "required": false, "default": 1.4, "desc": "Framing margin multiplier around the bounds, clamped 1.0-5.0"},
				"thumb_size": {"type": "int", "required": false, "default": 384, "desc": "Width/height in pixels of each view before tiling, clamped 64-1024"},
				"save_path": {"type": "string", "required": false, "default": "", "desc": "If given, save the composed sheet here (res://, user://, or absolute) instead of returning base64"},
				"overwrite": {"type": "bool", "required": false, "default": false, "desc": "Overwrite an existing file at save_path"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"snap_to_ground": {
			"category": "3d",
			"summary": "Moves a node's Y position so the bottom of its world-space bounds rests on a ground plane — either another node's bounds top, or a literal Y value. AABB-based, not a physics raycast, so it works reliably in the editor regardless of collision setup.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Scene-relative path to the Node3D to move"},
				"ground_path": {"type": "string", "required": false, "desc": "Scene-relative path to a node defining the ground surface (its bounds' top Y is used); if omitted, ground_y is used instead"},
				"ground_y": {"type": "float", "required": false, "default": 0.0, "desc": "World-space ground Y; used only when ground_path is omitted"},
				"offset": {"type": "float", "required": false, "default": 0.0, "desc": "Extra Y offset applied after snapping, e.g. to embed slightly or hover"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"align_nodes": {
			"category": "3d",
			"summary": "Sets every given node's global_position on one axis to a common value: min/max/center of their current positions, or an explicit number. Aligns by node origin (global_position), not visual bounds.",
			"params": {
				"node_paths": {"type": "array", "required": true, "desc": "Scene-relative paths to 2+ Node3D nodes"},
				"axis": {"type": "string", "required": true, "desc": "One of: x, y, z"},
				"align_to": {"type": "any", "required": false, "default": "center", "desc": "One of: min, max, center — or a literal number"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"distribute_nodes": {
			"category": "3d",
			"summary": "Evenly spaces 3+ nodes along one axis between the current min and max positions among them; the two extreme nodes stay fixed, the rest are repositioned. Distributes by node origin (global_position).",
			"params": {
				"node_paths": {"type": "array", "required": true, "desc": "Scene-relative paths to 3+ Node3D nodes"},
				"axis": {"type": "string", "required": true, "desc": "One of: x, y, z"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"look_at_node": {
			"category": "3d",
			"summary": "Rotates a node to face a target node or point. Exactly one of target_path or target is required.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Scene-relative path to the Node3D to rotate"},
				"target_path": {"type": "string", "required": false, "desc": "Scene-relative path to a node to face"},
				"target": {"type": "any", "required": false, "desc": "Vector3-like world point to face; used only when target_path is omitted"},
				"up": {"type": "any", "required": false, "default": [0, 1, 0], "desc": "Vector3-like up reference"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"add_csg_shape": {
			"category": "3d",
			"summary": "Add a CSG primitive (box/sphere/cylinder/polygon) or a CSGCombiner3D grouping node, for greyboxing a level with boolean union/intersection/subtraction. CSGShape3D can generate its own collision (use_collision).",
			"params": {
				"shape": {"type": "string", "required": true, "desc": "One of: box, sphere, cylinder, polygon, combiner"},
				"parent_path": {"type": "string", "required": false, "default": ".", "desc": "Scene-relative path to the parent node — typically a CSGCombiner3D to compose with siblings"},
				"name": {"type": "string", "required": false, "default": "", "desc": "Defaults to the capitalized shape name"},
				"operation": {"type": "string", "required": false, "default": "union", "desc": "One of: union, intersection, subtraction — applies to combiner too, since CSGCombiner3D is itself a CSGShape3D (relevant when nesting combiners)"},
				"use_collision": {"type": "bool", "required": false, "default": true, "desc": "Applies to combiner too, for the same reason"},
				"size": {"type": "any", "required": false, "default": [1, 1, 1], "desc": "box only: Vector3-like"},
				"radius": {"type": "float", "required": false, "default": 0.5, "desc": "sphere/cylinder only"},
				"radial_segments": {"type": "int", "required": false, "default": 12, "desc": "sphere only"},
				"rings": {"type": "int", "required": false, "default": 6, "desc": "sphere only"},
				"height": {"type": "float", "required": false, "default": 1.0, "desc": "cylinder only"},
				"sides": {"type": "int", "required": false, "default": 12, "desc": "cylinder only"},
				"cone": {"type": "bool", "required": false, "default": false, "desc": "cylinder only: taper to a point"},
				"polygon_points": {"type": "array", "required": false, "desc": "polygon only, required for it: 3+ [x,y] pairs or {x,y} dicts, the 2D cross-section to extrude"},
				"depth": {"type": "float", "required": false, "default": 1.0, "desc": "polygon only: extrusion depth"},
				"position": {"type": "any", "required": false, "default": [0, 0, 0], "desc": "Vector3-like"},
				"rotation": {"type": "any", "required": false, "default": [0, 0, 0], "desc": "Rotation in degrees, Vector3-like"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"add_multimesh_scatter": {
			"category": "3d",
			"summary": "Scatters random instances of a mesh across the flat top of another node's world-space bounds, as a single MultiMeshInstance3D. Places on a flat plane at the bounds' max Y — does not follow uneven terrain (no raycast involved).",
			"params": {
				"mesh_path": {"type": "string", "required": true, "desc": "res:// path to a Mesh resource (.res/.tres/.mesh) — a .tscn/.glb scene path is rejected, load its mesh resource directly"},
				"area_path": {"type": "string", "required": true, "desc": "Scene-relative path to a node defining the scatter area (its world bounds are used)"},
				"parent_path": {"type": "string", "required": false, "default": ".", "desc": "Scene-relative path to the parent for the new MultiMeshInstance3D"},
				"name": {"type": "string", "required": false, "default": "MultiMeshInstance3D"},
				"count": {"type": "int", "required": false, "default": 20, "desc": "Instance count, clamped 1-5000"},
				"y_offset": {"type": "float", "required": false, "default": 0.0, "desc": "Added to the computed ground Y for every instance"},
				"scale_min": {"type": "float", "required": false, "default": 1.0},
				"scale_max": {"type": "float", "required": false, "default": 1.0},
				"random_rotation_y": {"type": "bool", "required": false, "default": true, "desc": "Randomize each instance's yaw"},
				"seed": {"type": "int", "required": false, "default": 0, "desc": "Non-zero for reproducible scatter; 0 uses a random seed each call"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"add_path3d": {
			"category": "3d",
			"summary": "Create a Path3D from a list of points, optionally with a PathFollow3D child.",
			"params": {
				"points": {"type": "array", "required": true, "desc": "2+ Vector3-like points, e.g. [[0,0,0],[5,0,0],[5,0,5]]"},
				"parent_path": {"type": "string", "required": false, "default": ".", "desc": "Scene-relative path to the parent node"},
				"name": {"type": "string", "required": false, "default": "Path3D"},
				"add_path_follow": {"type": "bool", "required": false, "default": false, "desc": "Also add a PathFollow3D child"},
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

	add_child_with_undo(parent, mesh_instance, root, "MCP: Add MeshInstance3D")

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

	add_child_with_undo(parent, light, root, "MCP: Add %s" % light_type)

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

	# Duplicate rather than mutate world_env.environment in place: an
	# in-place mutation would leave the "old" value indistinguishable from
	# the "new" one by the time set_property_with_undo captures it below,
	# since both would already point at the same, already-mutated resource.
	var old_env: Environment = world_env.environment
	var env: Environment = old_env.duplicate() as Environment if old_env != null else Environment.new()

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

	if is_existing:
		set_property_with_undo(world_env, "environment", env, "MCP: Update Environment")
	else:
		world_env.environment = env
		add_child_with_undo(parent, world_env, root, "MCP: Add WorldEnvironment")

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

	# Snapshot before mutating an existing camera, so every touched property
	# can be wrapped in one undo action below — mutating it directly (as this
	# function does, to keep the match/if logic simple) would otherwise leave
	# no record for EditorUndoRedoManager to revert.
	var camera_undo_props: Array[String] = ["projection", "fov", "size", "near", "far", "cull_mask", "current", "position", "rotation_degrees", "environment"]
	var old_camera_values: Dictionary = {}
	if is_existing:
		for prop: String in camera_undo_props:
			old_camera_values[prop] = camera.get(prop)

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

	if is_existing:
		var undo_redo := get_undo_redo()
		undo_redo.create_action("MCP: Update Camera3D")
		for prop: String in camera_undo_props:
			undo_redo.add_do_property(camera, prop, camera.get(prop))
			undo_redo.add_undo_property(camera, prop, old_camera_values[prop])
		undo_redo.commit_action()
	else:
		add_child_with_undo(parent, camera, root, "MCP: Add Camera3D")

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

	# Snapshot before mutating an existing gridmap, so the scalar properties
	# touched below can be wrapped in the same undo action as the cell edits.
	var gridmap_undo_props: Array[String] = ["mesh_library", "cell_size", "position"]
	var old_gridmap_values: Dictionary = {}
	if is_existing:
		for prop: String in gridmap_undo_props:
			old_gridmap_values[prop] = gridmap.get(prop)

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

	# Set cells — capture the previous item/orientation at each touched
	# coordinate first so the change can be undone cell-by-cell, mirroring
	# tilemap_commands.gd's _capture_cell / _add_do_set_cells pattern.
	var cells: Array = params.get("cells", [])
	var cells_set: int = 0
	var old_cell_states: Array = []
	var new_cell_states: Array = []
	for cell in cells:
		if cell is Dictionary:
			var x: int = int(cell.get("x", 0))
			var y: int = int(cell.get("y", 0))
			var z: int = int(cell.get("z", 0))
			var item: int = int(cell.get("item", 0))
			var orientation: int = int(cell.get("orientation", 0))
			var coords := Vector3i(x, y, z)
			old_cell_states.append({
				"coords": coords,
				"item": gridmap.get_cell_item(coords),
				"orientation": gridmap.get_cell_item_orientation(coords),
			})
			new_cell_states.append({"coords": coords, "item": item, "orientation": orientation})
			cells_set += 1

	if is_existing:
		var undo_redo := get_undo_redo()
		undo_redo.create_action("MCP: Update GridMap")
		for prop: String in gridmap_undo_props:
			undo_redo.add_do_property(gridmap, prop, gridmap.get(prop))
			undo_redo.add_undo_property(gridmap, prop, old_gridmap_values[prop])
		for state: Dictionary in new_cell_states:
			undo_redo.add_do_method(gridmap, "set_cell_item", state["coords"], state["item"], state["orientation"])
		for state: Dictionary in old_cell_states:
			undo_redo.add_undo_method(gridmap, "set_cell_item", state["coords"], state["item"], state["orientation"])
		undo_redo.commit_action()
	else:
		add_child_with_undo(parent, gridmap, root, "MCP: Add GridMap")
		for state: Dictionary in new_cell_states:
			gridmap.set_cell_item(state["coords"], state["item"], state["orientation"])

	return success({
		"node_path": str(root.get_path_to(gridmap)),
		"name": str(gridmap.name),
		"cells_set": cells_set,
		"is_existing": is_existing,
		"has_mesh_library": gridmap.mesh_library != null,
	})


## ─── 7. get_spatial_bounds ──────────────────────────────────────────────────

func _get_spatial_bounds(params: Dictionary) -> Dictionary:
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
	if not node is Node3D:
		return error_invalid_params("Node '%s' is a %s, not a Node3D" % [node_path, node.get_class()])

	var include_children: bool = optional_bool(params, "include_children", true)
	var aabb: Variant = _world_aabb_of(node, include_children)
	if aabb == null:
		return error(-32000, "No visual geometry found under '%s'" % node_path, {
			"suggestion": "The node (or its children, if include_children) must contain a VisualInstance3D such as MeshInstance3D",
		})

	var b: AABB = aabb
	var center := b.get_center()
	return success({
		"node_path": node_path,
		"position": {"x": b.position.x, "y": b.position.y, "z": b.position.z},
		"size": {"x": b.size.x, "y": b.size.y, "z": b.size.z},
		"center": {"x": center.x, "y": center.y, "z": center.z},
		"radius": b.size.length() / 2.0,
	})


## World-space AABB of `node` (if it's a VisualInstance3D) merged with its
## descendants' (if include_children). Returns null — not an empty AABB at
## the origin — when nothing visual was found, so callers can tell "no
## geometry" apart from "geometry that happens to be zero-sized".
func _world_aabb_of(node: Node, include_children: bool) -> Variant:
	var combined: AABB
	var has_any := false

	if node is VisualInstance3D:
		var local_aabb: AABB = (node as VisualInstance3D).get_aabb()
		combined = (node as Node3D).global_transform * local_aabb
		has_any = true

	if include_children:
		for child in node.get_children():
			if child is Node3D:
				var child_aabb: Variant = _world_aabb_of(child, true)
				if child_aabb != null:
					combined = combined.merge(child_aabb) if has_any else child_aabb
					has_any = true

	return combined if has_any else null


## ─── 8. turntable_screenshot ────────────────────────────────────────────────

func _turntable_screenshot(params: Dictionary) -> Dictionary:
	var node_path: String = optional_string(params, "node_path", ".")

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)
	if not node is Node3D:
		return error_invalid_params("Node '%s' is a %s, not a Node3D" % [node_path, node.get_class()])

	var views: int = clampi(optional_int(params, "views", 4), 1, 12)
	var elevation_degrees: float = optional_float(params, "elevation_degrees", 25.0)
	var padding: float = clampf(optional_float(params, "padding", 1.4), 1.0, 5.0)
	var thumb_size: int = clampi(optional_int(params, "thumb_size", 384), 64, 1024)

	var aabb: Variant = _world_aabb_of(node, true)
	if aabb == null:
		return error(-32000, "No visual geometry found under '%s'" % node_path, {
			"suggestion": "The node (or a child) must contain a VisualInstance3D such as MeshInstance3D",
		})
	var b: AABB = aabb
	var center := b.get_center()
	# A single point has zero radius, which would divide framing distance by
	# zero below; floor it to something small instead of failing the call.
	var radius: float = maxf(b.size.length() / 2.0, 0.05)

	var vp3d := EditorInterface.get_editor_viewport_3d()
	var cam := vp3d.get_camera_3d() if vp3d else null
	if not cam:
		return error(-32000, "No 3D editor camera found", {"suggestion": "Open a 3D scene in the editor"})

	var orig_transform := cam.global_transform
	var orig_fov := cam.fov
	var fov := 50.0
	var distance: float = radius * padding / sin(deg_to_rad(fov * 0.5))
	cam.fov = fov

	var thumbs: Array[Image] = []
	var angles_used: Array = []
	var elevation_rad := deg_to_rad(elevation_degrees)

	for i in views:
		var azimuth := (TAU / views) * i
		var dir := Vector3(
			cos(elevation_rad) * sin(azimuth),
			sin(elevation_rad),
			cos(elevation_rad) * cos(azimuth)
		)
		cam.global_position = center + dir * distance
		cam.look_at(center, Vector3.UP)

		# The camera move only takes effect in a subsequently rendered frame;
		# without this, every capture in the loop would return the same stale
		# image (the one that was on screen when the call started).
		await RenderingServer.frame_post_draw

		var base_control: Control = get_editor().get_base_control()
		var viewport: Viewport = base_control.get_viewport() if base_control else null
		var texture: ViewportTexture = viewport.get_texture() if viewport else null
		var image: Image = texture.get_image() if texture else null
		if image == null:
			cam.global_transform = orig_transform
			cam.fov = orig_fov
			return error_internal("Could not capture a frame for view %d of %d" % [i + 1, views])

		image.resize(thumb_size, thumb_size, Image.INTERPOLATE_LANCZOS)
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		thumbs.append(image)
		angles_used.append(snappedf(rad_to_deg(azimuth), 0.1))

	cam.global_transform = orig_transform
	cam.fov = orig_fov

	var cols: int = ceili(sqrt(thumbs.size()))
	var rows: int = ceili(float(thumbs.size()) / cols)
	var sheet := Image.create(cols * thumb_size, rows * thumb_size, false, Image.FORMAT_RGBA8)
	for i in thumbs.size():
		var col := i % cols
		var row := i / cols
		sheet.blit_rect(thumbs[i], Rect2i(0, 0, thumb_size, thumb_size), Vector2i(col * thumb_size, row * thumb_size))

	var response := {
		"width": sheet.get_width(),
		"height": sheet.get_height(),
		"columns": cols,
		"rows": rows,
		"views": views,
		"angles_degrees": angles_used,
		"format": "png",
	}

	var save_path: String = optional_string(params, "save_path", "")
	if not save_path.is_empty():
		var overwrite_guard := guard_overwrite(save_path, optional_bool(params, "overwrite"))
		if overwrite_guard.has("error"):
			return overwrite_guard
		var abs_path := resolve_save_path(save_path)
		var err := sheet.save_png(abs_path)
		if err != OK:
			return error_internal("Failed to save turntable sheet: %s" % error_string(err))
		response["saved_path"] = save_path
		return success(response)

	var png_buffer := sheet.save_png_to_buffer()
	response["image_base64"] = Marshalls.raw_to_base64(png_buffer)
	return success(response)


## ─── 9. snap_to_ground ──────────────────────────────────────────────────────

func _snap_to_ground(params: Dictionary) -> Dictionary:
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
	if not node is Node3D:
		return error_invalid_params("Node '%s' is a %s, not a Node3D" % [node_path, node.get_class()])
	var node3d := node as Node3D

	var node_aabb: Variant = _world_aabb_of(node3d, true)
	if node_aabb == null:
		return error(-32000, "No visual geometry found under '%s'" % node_path, {
			"suggestion": "The node (or a child) must contain a VisualInstance3D such as MeshInstance3D",
		})
	var b: AABB = node_aabb

	var ground_y: float
	if params.has("ground_path"):
		var ground_node := find_node_by_path(str(params["ground_path"]))
		if ground_node == null:
			return error_not_found("Node '%s'" % params["ground_path"])
		if not ground_node is Node3D:
			return error_invalid_params("ground_path '%s' is a %s, not a Node3D" % [params["ground_path"], ground_node.get_class()])
		var ground_aabb: Variant = _world_aabb_of(ground_node, true)
		if ground_aabb == null:
			return error(-32000, "No visual geometry found under ground_path '%s'" % params["ground_path"], {})
		ground_y = (ground_aabb as AABB).position.y + (ground_aabb as AABB).size.y
	else:
		ground_y = optional_float(params, "ground_y", 0.0)

	var offset: float = optional_float(params, "offset", 0.0)
	var delta := (ground_y + offset) - b.position.y

	var old_pos := node3d.global_position
	var new_pos := old_pos + Vector3(0, delta, 0)

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Snap To Ground")
	undo_redo.add_do_property(node3d, "global_position", new_pos)
	undo_redo.add_undo_property(node3d, "global_position", old_pos)
	undo_redo.commit_action()

	return success({
		"node_path": node_path,
		"position": {"x": new_pos.x, "y": new_pos.y, "z": new_pos.z},
		"ground_y": ground_y,
	})


## ─── 10. align_nodes / distribute_nodes ────────────────────────────────────

func _collect_node3d_list(node_paths: Array) -> Array:
	## Returns [Array[Node3D], error_dict]; error_dict is null on success.
	var nodes: Array[Node3D] = []
	for p: Variant in node_paths:
		var n := find_node_by_path(str(p))
		if n == null:
			return [null, error_not_found("Node '%s'" % p)]
		if not n is Node3D:
			return [null, error_invalid_params("Node '%s' is a %s, not a Node3D" % [p, n.get_class()])]
		nodes.append(n as Node3D)
	return [nodes, null]


func _axis_value(v: Vector3, axis: String) -> float:
	match axis:
		"x": return v.x
		"y": return v.y
		_: return v.z


func _with_axis_value(v: Vector3, axis: String, value: float) -> Vector3:
	match axis:
		"x": return Vector3(value, v.y, v.z)
		"y": return Vector3(v.x, value, v.z)
		_: return Vector3(v.x, v.y, value)


func _align_nodes(params: Dictionary) -> Dictionary:
	if not params.has("node_paths") or not params["node_paths"] is Array or (params["node_paths"] as Array).is_empty():
		return error_invalid_params("'node_paths' (non-empty array) is required")

	var axis_result := require_string(params, "axis")
	if axis_result[1] != null:
		return axis_result[1]
	var axis: String = axis_result[0]
	if not axis in ["x", "y", "z"]:
		return error_invalid_params("'axis' must be one of: x, y, z")

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var collected := _collect_node3d_list(params["node_paths"])
	if collected[1] != null:
		return collected[1]
	var nodes: Array[Node3D] = collected[0]

	var values: Array[float] = []
	for n: Node3D in nodes:
		values.append(_axis_value(n.global_position, axis))

	var align_to: Variant = params.get("align_to", "center")
	var target: float
	if align_to is String:
		match align_to:
			"min":
				target = values.min()
			"max":
				target = values.max()
			"center", "average":
				var sum := 0.0
				for v: float in values:
					sum += v
				target = sum / values.size()
			_:
				return error_invalid_params("'align_to' must be a number, or one of: min, max, center")
	else:
		target = float(align_to)

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Align Nodes")
	var moved: Array = []
	for n: Node3D in nodes:
		var new_pos := _with_axis_value(n.global_position, axis, target)
		undo_redo.add_do_property(n, "global_position", new_pos)
		undo_redo.add_undo_property(n, "global_position", n.global_position)
		moved.append(str(root.get_path_to(n)))
	undo_redo.commit_action()

	return success({"aligned": moved, "axis": axis, "target": target})


func _distribute_nodes(params: Dictionary) -> Dictionary:
	if not params.has("node_paths") or not params["node_paths"] is Array:
		return error_invalid_params("'node_paths' (array) is required")

	var axis_result := require_string(params, "axis")
	if axis_result[1] != null:
		return axis_result[1]
	var axis: String = axis_result[0]
	if not axis in ["x", "y", "z"]:
		return error_invalid_params("'axis' must be one of: x, y, z")

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var collected := _collect_node3d_list(params["node_paths"])
	if collected[1] != null:
		return collected[1]
	var nodes: Array[Node3D] = collected[0]
	if nodes.size() < 3:
		return error_invalid_params("'node_paths' needs at least 3 nodes to distribute (the two extremes stay fixed)")

	var indices: Array = range(nodes.size())
	indices.sort_custom(func(a: int, b: int) -> bool:
		return _axis_value(nodes[a].global_position, axis) < _axis_value(nodes[b].global_position, axis)
	)
	var sorted_nodes: Array[Node3D] = []
	for i: int in indices:
		sorted_nodes.append(nodes[i])

	var lo := _axis_value(sorted_nodes[0].global_position, axis)
	var hi := _axis_value(sorted_nodes[-1].global_position, axis)
	var step := (hi - lo) / float(sorted_nodes.size() - 1)

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Distribute Nodes")
	var moved: Array = []
	for i in sorted_nodes.size():
		var n: Node3D = sorted_nodes[i]
		var target := lo + step * i
		var new_pos := _with_axis_value(n.global_position, axis, target)
		undo_redo.add_do_property(n, "global_position", new_pos)
		undo_redo.add_undo_property(n, "global_position", n.global_position)
		moved.append(str(root.get_path_to(n)))
	undo_redo.commit_action()

	return success({"distributed": moved, "axis": axis, "step": step})


## ─── 11. look_at_node ───────────────────────────────────────────────────────

func _look_at_node(params: Dictionary) -> Dictionary:
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
	if not node is Node3D:
		return error_invalid_params("Node '%s' is a %s, not a Node3D" % [node_path, node.get_class()])
	var node3d := node as Node3D

	var target_pos: Vector3
	if params.has("target_path"):
		var target_node := find_node_by_path(str(params["target_path"]))
		if target_node == null:
			return error_not_found("Node '%s'" % params["target_path"])
		if not target_node is Node3D:
			return error_invalid_params("target_path '%s' is a %s, not a Node3D" % [params["target_path"], target_node.get_class()])
		target_pos = (target_node as Node3D).global_position
	elif params.has("target"):
		target_pos = _parse_vector3_param(params, "target", Vector3.ZERO)
	else:
		return error_invalid_params("Either 'target_path' or 'target' is required")

	if target_pos.is_equal_approx(node3d.global_position):
		return error_invalid_params("Target is at the same position as the node; cannot compute a look direction")

	var up := _parse_vector3_param(params, "up", Vector3.UP)

	var old_transform := node3d.global_transform
	node3d.look_at(target_pos, up)
	var new_transform := node3d.global_transform
	node3d.global_transform = old_transform

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Look At")
	undo_redo.add_do_property(node3d, "global_transform", new_transform)
	undo_redo.add_undo_property(node3d, "global_transform", old_transform)
	undo_redo.commit_action()

	var final_rot := node3d.rotation_degrees
	return success({
		"node_path": node_path,
		"rotation_degrees": {"x": final_rot.x, "y": final_rot.y, "z": final_rot.z},
	})


## ─── 12. add_csg_shape ──────────────────────────────────────────────────────

func _add_csg_shape(params: Dictionary) -> Dictionary:
	var result := require_string(params, "shape")
	if result[1] != null:
		return result[1]
	var shape_kind: String = result[0].to_lower()

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent := find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node '%s'" % parent_path)

	var shape: Node3D = null
	match shape_kind:
		"box":
			var box := CSGBox3D.new()
			box.size = _parse_vector3_param(params, "size", Vector3.ONE)
			shape = box
		"sphere":
			var sph := CSGSphere3D.new()
			sph.radius = _optional_float(params, "radius", 0.5)
			sph.radial_segments = optional_int(params, "radial_segments", 12)
			sph.rings = optional_int(params, "rings", 6)
			shape = sph
		"cylinder":
			var cyl := CSGCylinder3D.new()
			cyl.radius = _optional_float(params, "radius", 0.5)
			cyl.height = _optional_float(params, "height", 1.0)
			cyl.sides = optional_int(params, "sides", 12)
			cyl.cone = optional_bool(params, "cone", false)
			shape = cyl
		"polygon":
			if not params.has("polygon_points") or not params["polygon_points"] is Array:
				return error_invalid_params("'polygon_points' (array of [x,y] pairs) is required for shape=polygon")
			var pts_raw: Array = params["polygon_points"]
			var polygon := PackedVector2Array()
			for pt: Variant in pts_raw:
				if pt is Array and (pt as Array).size() >= 2:
					polygon.append(Vector2(float(pt[0]), float(pt[1])))
				elif pt is Dictionary:
					polygon.append(Vector2(float(pt.get("x", 0)), float(pt.get("y", 0))))
			if polygon.size() < 3:
				return error_invalid_params("'polygon_points' needs at least 3 points")
			var poly := CSGPolygon3D.new()
			poly.polygon = polygon
			poly.depth = _optional_float(params, "depth", 1.0)
			shape = poly
		"combiner":
			shape = CSGCombiner3D.new()
		_:
			return error_invalid_params("Unknown shape '%s'. Use: box, sphere, cylinder, polygon, combiner" % shape_kind)

	if shape is CSGShape3D:
		var op_str: String = optional_string(params, "operation", "union").to_lower()
		var op_map := {
			"union": CSGShape3D.OPERATION_UNION,
			"intersection": CSGShape3D.OPERATION_INTERSECTION,
			"subtraction": CSGShape3D.OPERATION_SUBTRACTION,
		}
		if not op_map.has(op_str):
			shape.free()
			return error_invalid_params("'operation' must be one of: union, intersection, subtraction")
		(shape as CSGShape3D).operation = op_map[op_str] as CSGShape3D.Operation
		(shape as CSGShape3D).use_collision = optional_bool(params, "use_collision", true)

	shape.name = optional_string(params, "name", shape_kind.capitalize())
	shape.position = _parse_vector3_param(params, "position", Vector3.ZERO)
	shape.rotation_degrees = _parse_vector3_param(params, "rotation", Vector3.ZERO)

	add_child_with_undo(parent, shape, root, "MCP: Add CSG %s" % shape_kind.capitalize())

	return success({
		"node_path": str(root.get_path_to(shape)),
		"name": str(shape.name),
		"shape": shape_kind,
	})


## ─── 13. add_multimesh_scatter ─────────────────────────────────────────────

func _add_multimesh_scatter(params: Dictionary) -> Dictionary:
	var result := require_string(params, "mesh_path")
	if result[1] != null:
		return result[1]
	var mesh_path: String = result[0]
	if not ResourceLoader.exists(mesh_path):
		return error_not_found("Mesh resource '%s'" % mesh_path)
	var loaded: Resource = ResourceLoader.load(mesh_path)
	if not loaded is Mesh:
		return error_invalid_params("'%s' is a %s, not a Mesh" % [mesh_path, loaded.get_class()])
	var mesh: Mesh = loaded

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var area_result := require_string(params, "area_path")
	if area_result[1] != null:
		return area_result[1]
	var area_path: String = area_result[0]
	var area_node := find_node_by_path(area_path)
	if area_node == null:
		return error_not_found("Node '%s'" % area_path)
	if not area_node is Node3D:
		return error_invalid_params("area_path '%s' is a %s, not a Node3D" % [area_path, area_node.get_class()])

	var area_aabb: Variant = _world_aabb_of(area_node, true)
	if area_aabb == null:
		return error(-32000, "No visual geometry found under '%s' to scatter over" % area_path, {
			"suggestion": "area_path must contain a VisualInstance3D defining the surface bounds",
		})
	var b: AABB = area_aabb

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent := find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node '%s'" % parent_path)

	var count: int = clampi(optional_int(params, "count", 20), 1, 5000)
	var y_offset: float = optional_float(params, "y_offset", 0.0)
	var scale_min: float = optional_float(params, "scale_min", 1.0)
	var scale_max: float = optional_float(params, "scale_max", 1.0)
	var random_rotation_y: bool = optional_bool(params, "random_rotation_y", true)
	var seed_value: int = optional_int(params, "seed", 0)

	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count

	var top_y := b.position.y + b.size.y + y_offset

	for i in count:
		var x := rng.randf_range(b.position.x, b.position.x + b.size.x)
		var z := rng.randf_range(b.position.z, b.position.z + b.size.z)
		var s := rng.randf_range(scale_min, scale_max)
		var rot_y := rng.randf_range(0.0, TAU) if random_rotation_y else 0.0
		var xform := Transform3D(Basis(Vector3.UP, rot_y).scaled(Vector3.ONE * s), Vector3(x, top_y, z))
		multimesh.set_instance_transform(i, xform)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = multimesh
	mmi.name = optional_string(params, "name", "MultiMeshInstance3D")

	add_child_with_undo(parent, mmi, root, "MCP: Add MultiMesh Scatter")

	return success({
		"node_path": str(root.get_path_to(mmi)),
		"name": str(mmi.name),
		"count": count,
		"area_top_y": top_y,
	})


## ─── 14. add_path3d ─────────────────────────────────────────────────────────

func _add_path3d(params: Dictionary) -> Dictionary:
	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent := find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node '%s'" % parent_path)

	if not params.has("points") or not params["points"] is Array:
		return error_invalid_params("'points' (array of Vector3-like values) is required")
	var points_raw: Array = params["points"]
	if points_raw.size() < 2:
		return error_invalid_params("'points' needs at least 2 points")

	var curve := Curve3D.new()
	for pt: Variant in points_raw:
		var v := Vector3.ZERO
		if pt is Array and (pt as Array).size() >= 3:
			v = Vector3(float(pt[0]), float(pt[1]), float(pt[2]))
		elif pt is Dictionary:
			v = Vector3(float(pt.get("x", 0)), float(pt.get("y", 0)), float(pt.get("z", 0)))
		curve.add_point(v)

	var path3d := Path3D.new()
	path3d.curve = curve
	path3d.name = optional_string(params, "name", "Path3D")

	add_child_with_undo(parent, path3d, root, "MCP: Add Path3D")

	var add_follower: bool = optional_bool(params, "add_path_follow", false)
	var follow_path_str := ""
	if add_follower:
		var follower := PathFollow3D.new()
		follower.name = "PathFollow3D"
		var undo_redo := get_undo_redo()
		undo_redo.create_action("MCP: Add PathFollow3D")
		undo_redo.add_do_method(path3d, "add_child", follower)
		undo_redo.add_do_method(follower, "set_owner", root)
		undo_redo.add_do_reference(follower)
		undo_redo.add_undo_method(path3d, "remove_child", follower)
		undo_redo.commit_action()
		follow_path_str = str(root.get_path_to(follower))

	return success({
		"node_path": str(root.get_path_to(path3d)),
		"name": str(path3d.name),
		"point_count": curve.point_count,
		"path_follow_node": follow_path_str,
	})
