@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

const NodeUtils := preload("res://addons/godot_mcp/utils/node_utils.gd")
const PropertyParser := preload("res://addons/godot_mcp/utils/property_parser.gd")


func get_commands() -> Dictionary:
	return {
		"add_node": _add_node,
		"delete_node": _delete_node,
		"duplicate_node": _duplicate_node,
		"move_node": _move_node,
		"update_property": _update_property,
		"get_node_properties": _get_node_properties,
		"add_resource": _add_resource,
		"set_anchor_preset": _set_anchor_preset,
		"rename_node": _rename_node,
		"connect_signal": _connect_signal,
		"disconnect_signal": _disconnect_signal,
		"get_node_groups": _get_node_groups,
		"set_node_groups": _set_node_groups,
		"find_nodes_in_group": _find_nodes_in_group,
		"get_editor_selection": _get_editor_selection,
		"select_nodes": _select_nodes,
		"clear_editor_selection": _clear_editor_selection,
	}


func get_command_schemas() -> Dictionary:
	return {
		"add_node": {
			"category": "node",
			"summary": "Instantiate a node (by ClassDB type or a script's class_name) and add it as a child, optionally setting initial properties.",
			"params": {
				"type": {"type": "string", "required": true, "desc": "ClassDB node type, or a script's class_name"},
				"parent_path": {"type": "string", "required": false, "default": ".", "desc": "Node path of the parent to add the new node under"},
				"name": {"type": "string", "required": false, "default": "", "desc": "Defaults to the type/class name"},
				"properties": {"type": "object", "required": false, "default": {}, "desc": "Initial property name/value pairs to set on the new node"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"delete_node": {
			"category": "node",
			"summary": "Remove a node from the scene tree. Refuses to delete the scene root.",
			"params": {"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"}},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": true},
		},
		"duplicate_node": {
			"category": "node",
			"summary": "Duplicate a node (and its subtree) as a sibling. Refuses to duplicate the scene root, since the copy would attach outside the scene and be lost on save.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"},
				"name": {"type": "string", "required": false, "default": "", "desc": "Defaults to '<original name>_copy'"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"move_node": {
			"category": "node",
			"summary": "Reparent a node to a different location in the scene tree. Refuses to move the root, or a node into its own subtree.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"},
				"new_parent_path": {"type": "string", "required": true, "desc": "Node path of the new parent"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"update_property": {
			"category": "node",
			"summary": "Set a single property on a node. Resolves string values against @export node-reference hints and Resource-typed properties, and refuses ambiguous coercions rather than silently nulling the property.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"},
				"property": {"type": "string", "required": true, "desc": "Property name"},
				"value": {"type": "any", "required": true, "desc": "Parsed against the property's current type"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"get_node_properties": {
			"category": "node",
			"summary": "All editor-visible properties and values of a node, optionally filtered by category prefix.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"},
				"category": {"type": "string", "required": false, "default": "", "desc": "Only include properties whose name starts with this prefix"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"add_resource": {
			"category": "node",
			"summary": "Create a Resource instance and assign it to a property on a node.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"},
				"property": {"type": "string", "required": true, "desc": "Property to assign the resource to"},
				"resource_type": {"type": "string", "required": true, "desc": "ClassDB Resource type to instantiate"},
				"resource_properties": {"type": "object", "required": false, "default": {}, "desc": "Initial property name/value pairs to set on the new resource"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": false},
		},
		"set_anchor_preset": {
			"category": "node",
			"summary": "Apply a Control anchor/offset preset (e.g. full_rect, center). Refuses non-Control nodes.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"},
				"preset": {"type": "string", "required": true, "desc": "One of the Control.PRESET_* names, e.g. 'full_rect', 'center', 'top_left'"},
				"keep_offsets": {"type": "bool", "required": false, "default": false, "desc": "Keep current size (PRESET_MODE_KEEP_SIZE) instead of resetting to minsize"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"rename_node": {
			"category": "node",
			"summary": "Change a node's name.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"},
				"new_name": {"type": "string", "required": true},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"connect_signal": {
			"category": "node",
			"summary": "Connect a signal on one node to a method on another, persistently (serialized into the scene on save). No-op if already connected.",
			"params": {
				"source_path": {"type": "string", "required": true, "desc": "Node path of the signal source"},
				"signal_name": {"type": "string", "required": true},
				"target_path": {"type": "string", "required": true, "desc": "Node path of the method target"},
				"method_name": {"type": "string", "required": true},
				"deferred": {"type": "bool", "required": false, "default": false, "desc": "Add CONNECT_DEFERRED"},
				"one_shot": {"type": "bool", "required": false, "default": false, "desc": "Add CONNECT_ONE_SHOT"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"disconnect_signal": {
			"category": "node",
			"summary": "Disconnect a previously connected signal. No-op if not connected.",
			"params": {
				"source_path": {"type": "string", "required": true, "desc": "Node path of the signal source"},
				"signal_name": {"type": "string", "required": true},
				"target_path": {"type": "string", "required": true, "desc": "Node path of the method target"},
				"method_name": {"type": "string", "required": true},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"get_node_groups": {
			"category": "node",
			"summary": "List the (non-internal) groups a node belongs to.",
			"params": {"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"}},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"set_node_groups": {
			"category": "node",
			"summary": "Replace a node's (non-internal) group membership with the given list, adding and removing as needed.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Node path relative to the scene root"},
				"groups": {"type": "array", "required": true, "desc": "Full desired list of group names"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"find_nodes_in_group": {
			"category": "node",
			"summary": "Recursively find every node in the scene belonging to a given group.",
			"params": {"group": {"type": "string", "required": true}},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"get_editor_selection": {
			"category": "node",
			"summary": "Nodes currently selected in the editor.",
			"params": {
				"top_only": {"type": "bool", "required": false, "default": false, "desc": "Only include top-level selected nodes, excluding selected descendants of other selected nodes"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"select_nodes": {
			"category": "node",
			"summary": "Set the editor selection to one or more nodes, and optionally focus/inspect them.",
			"params": {
				"node_paths": {"type": "array", "required": false, "desc": "Node paths to select; takes precedence over node_path if both given"},
				"node_path": {"type": "string", "required": false, "desc": "Single node path to select; required if node_paths is not given"},
				"mode": {"type": "string", "required": false, "default": "replace", "desc": "One of: replace, add, remove"},
				"inspect": {"type": "bool", "required": false, "default": true, "desc": "Show the selected node in the Inspector (only when exactly one node is selected)"},
				"focus": {"type": "bool", "required": false, "default": "same as inspect", "desc": "Also open/focus the node for editing (only when exactly one node is selected)"},
				"inspector_only": {"type": "bool", "required": false, "default": false, "desc": "Passed through to EditorInterface.inspect_object"},
				"for_property": {"type": "string", "required": false, "default": "", "desc": "Passed through to EditorInterface.inspect_object"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"clear_editor_selection": {
			"category": "node",
			"summary": "Clear the editor's current node selection.",
			"params": {},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
	}


func _find_script_by_class_name(class_name_str: String) -> Script:
	# Search project files for a script with matching class_name
	var global_classes: Array = ProjectSettings.get_global_class_list()
	for entry: Dictionary in global_classes:
		if entry.get("class", "") == class_name_str:
			var path: String = entry.get("path", "")
			if not path.is_empty():
				return load(path) as Script
	return null


func _add_node(params: Dictionary) -> Dictionary:
	var result := require_string(params, "type")
	if result[1] != null:
		return result[1]
	var type: String = result[0]

	var parent_path: String = optional_string(params, "parent_path", ".")
	var node_name: String = optional_string(params, "name", "")
	var properties: Dictionary = params.get("properties", {})

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var parent := find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node '%s'" % parent_path, "Use get_scene_tree to see available nodes")

	var node: Node
	var custom_script: Script = null

	if ClassDB.class_exists(type):
		# class_exists() is also true for Resources and abstract classes.
		# Assigning either into the typed `node` local raises, which aborts the
		# handler so the caller gets no response at all.
		if not ClassDB.is_parent_class(type, "Node"):
			return error_invalid_params("'%s' is not a Node type" % type)
		if not ClassDB.can_instantiate(type):
			return error_invalid_params("'%s' is abstract and cannot be instantiated" % type)
		node = ClassDB.instantiate(type)
	else:
		# Try to find a script with matching class_name
		custom_script = _find_script_by_class_name(type)
		if custom_script == null:
			return error_invalid_params("Unknown node type: '%s'. Not found in ClassDB or as a script class_name. Use list_scripts to see available script classes." % type)
		var base_type: String = custom_script.get_instance_base_type()
		if not ClassDB.class_exists(base_type) or not ClassDB.is_parent_class(base_type, "Node"):
			return error_invalid_params("Script '%s' extends '%s' which is not a valid node type" % [type, base_type])
		if not ClassDB.can_instantiate(base_type):
			return error_invalid_params("Script '%s' extends abstract class '%s'" % [type, base_type])
		node = ClassDB.instantiate(base_type)
		node.set_script(custom_script)
	if node == null:
		return error_internal("Could not instantiate '%s'" % type)
	if not node_name.is_empty():
		node.name = node_name

	# Apply properties
	for prop_name: String in properties:
		var prop_exists := false
		for prop in node.get_property_list():
			if prop["name"] == prop_name:
				prop_exists = true
				break
		if prop_exists:
			var current: Variant = node.get(prop_name)
			var target_type := typeof(current)
			node.set(prop_name, PropertyParser.parse_value(properties[prop_name], target_type))

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Add %s" % type)
	undo_redo.add_do_method(parent, "add_child", node)
	undo_redo.add_do_method(node, "set_owner", root)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(parent, "remove_child", node)
	undo_redo.commit_action()

	return success({
		"node_path": str(root.get_path_to(node)),
		"type": type,
		"name": str(node.name),
	})


func _delete_node(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	if node == root:
		return error_invalid_params("Cannot delete the root node")

	var parent := node.get_parent()
	var node_name := str(node.name)

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Delete %s" % node_name)
	undo_redo.add_do_method(parent, "remove_child", node)
	undo_redo.add_undo_method(parent, "add_child", node)
	undo_redo.add_undo_method(node, "set_owner", root)
	undo_redo.add_undo_reference(node)
	undo_redo.commit_action()

	return success({"deleted": node_name})


func _duplicate_node(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var new_name: String = optional_string(params, "name", "")

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	if new_name.is_empty():
		new_name = str(node.name) + "_copy"

	# The edited scene root does have a parent — an editor-internal node — so a
	# copy attached there lands OUTSIDE the scene and is silently discarded on
	# save. Verified: duplicating "." produced "../Main_copy", absent from
	# get_scene_tree. Refuse instead of producing an orphan.
	if node == root:
		return error_invalid_params(
			"Cannot duplicate the scene root '%s'. A copy would be attached outside the scene and lost on save; duplicate a child instead." % node.name
		)
	var parent := node.get_parent()
	if parent == null:
		return error_invalid_params(
			"Node '%s' has no parent to attach the copy to." % node.name
		)

	var dup := node.duplicate()
	dup.name = new_name

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Duplicate %s" % node.name)
	undo_redo.add_do_method(parent, "add_child", dup)
	undo_redo.add_do_method(dup, "set_owner", root)
	undo_redo.add_do_reference(dup)
	undo_redo.add_undo_method(parent, "remove_child", dup)
	undo_redo.commit_action()

	NodeUtils.set_owner_recursive(dup, root)

	return success({
		"original": str(root.get_path_to(node)),
		"duplicate": str(root.get_path_to(dup)),
		"name": str(dup.name),
	})


func _move_node(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var result2 := require_string(params, "new_parent_path")
	if result2[1] != null:
		return result2[1]
	var new_parent_path: String = result2[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	if node == root:
		return error_invalid_params("Cannot move the root node")

	var new_parent := find_node_by_path(new_parent_path)
	if new_parent == null:
		return error_not_found("Target parent '%s'" % new_parent_path, "Use get_scene_tree to see available nodes")

	# Check we're not moving a node into its own subtree
	if new_parent == node or node.is_ancestor_of(new_parent):
		return error_invalid_params("Cannot move a node into its own subtree")

	var old_parent := node.get_parent()

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Move %s" % node.name)
	undo_redo.add_do_method(old_parent, "remove_child", node)
	undo_redo.add_do_method(new_parent, "add_child", node)
	undo_redo.add_do_method(node, "set_owner", root)
	undo_redo.add_undo_method(new_parent, "remove_child", node)
	undo_redo.add_undo_method(old_parent, "add_child", node)
	undo_redo.add_undo_method(node, "set_owner", root)
	undo_redo.commit_action()

	NodeUtils.set_owner_recursive(node, root)

	return success({
		"node": str(node.name),
		"old_parent": str(root.get_path_to(old_parent)),
		"new_parent": str(root.get_path_to(new_parent)),
		"new_path": str(root.get_path_to(node)),
	})


func _update_property(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var result2 := require_string(params, "property")
	if result2[1] != null:
		return result2[1]
	var property: String = result2[0]

	if not params.has("value"):
		return error_invalid_params("Missing required parameter: value")
	var value: Variant = params["value"]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	# Check property exists
	if not property in node:
		var available: Array = []
		for prop in node.get_property_list():
			if prop["usage"] & PROPERTY_USAGE_EDITOR:
				available.append(prop["name"])
		return error_not_found("Property '%s' on %s" % [property, node.get_class()],
			"Available: %s" % str(available.slice(0, 20)))

	var old_value: Variant = node.get(property)
	var target_type := typeof(old_value)
	var parsed_value: Variant = PropertyParser.parse_value(value, target_type)

	# Handle @export node references (e.g. @export var hud: HUD)
	# typeof() returns TYPE_NIL when unset or TYPE_OBJECT when set,
	# neither resolves a string path to a node — check the property hint instead
	if value is String:
		for prop in node.get_property_list():
			if prop["name"] == property and prop["hint"] == PROPERTY_HINT_NODE_TYPE:
				# Never resolve absolute NodePaths ("/root/...") — they escape
				# the edited scene into the live editor tree.
				if (value as String).begins_with("/"):
					return error_invalid_params(
						"Node reference '%s' for property '%s' must be relative to the edited scene, not an absolute Godot path" % [value, property])
				var target_node: Node = node.get_node_or_null(NodePath(value))
				if target_node == null:
					target_node = root.get_node_or_null(NodePath(value))
				# A target outside the edited scene (sibling of root or higher)
				# would silently modify the live editor tree — reject it.
				if target_node == null or (target_node != root and not root.is_ancestor_of(target_node)):
					return error_not_found("Node '%s'" % value, "Could not resolve node path for property '%s'" % property)
				parsed_value = target_node
				break

	# Fail loudly instead of committing a String into an Object-typed property —
	# the engine would coerce it to null and silently destroy the existing value.
	if value is String and typeof(old_value) == TYPE_OBJECT and parsed_value == null:
		return error_invalid_params(
			"Could not resolve '%s' to a Resource for property '%s'" % [str(value), property])
	if value is String and parsed_value is String and typeof(old_value) in [TYPE_NIL, TYPE_OBJECT] \
			and (str(value).begins_with("res://") or str(value).begins_with("uid://")):
		return error_not_found("Resource '%s'" % str(value),
			"The path could not be loaded for property '%s'" % property)

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Set %s.%s" % [node.name, property])
	undo_redo.add_do_property(node, property, parsed_value)
	undo_redo.add_undo_property(node, property, old_value)
	undo_redo.commit_action()

	return success({
		"node": str(root.get_path_to(node)),
		"property": property,
		"old_value": PropertyParser.serialize_value(old_value),
		"new_value": PropertyParser.serialize_value(node.get(property)),
	})


func _get_node_properties(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	var category: String = optional_string(params, "category", "")
	var props := NodeUtils.get_node_properties_dict(node)

	# Filter by category if specified
	if not category.is_empty():
		var filtered: Dictionary = {}
		for key: String in props:
			if key.begins_with(category):
				filtered[key] = props[key]
		props = filtered

	return success({
		"node_path": str(root.get_path_to(node)),
		"type": node.get_class(),
		"properties": props,
	})


func _get_editor_selection(params: Dictionary) -> Dictionary:
	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var selection := EditorInterface.get_selection()
	var include_top_only: bool = optional_bool(params, "top_only", false)
	var selected_nodes: Array = selection.get_top_selected_nodes() if include_top_only else selection.get_selected_nodes()

	return success({
		"nodes": _serialize_selection_nodes(root, selected_nodes),
		"count": selected_nodes.size(),
		"top_only": include_top_only,
	})


func _select_nodes(params: Dictionary) -> Dictionary:
	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node_paths_result := _get_selection_node_paths(params)
	if node_paths_result[1] != null:
		return node_paths_result[1]
	var node_paths: Array = node_paths_result[0]

	var mode: String = optional_string(params, "mode", "replace")
	if mode != "replace" and mode != "add" and mode != "remove":
		return error_invalid_params("mode must be one of: replace, add, remove")

	var inspect: bool = optional_bool(params, "inspect", true)
	var focus: bool = optional_bool(params, "focus", inspect)
	var inspector_only: bool = optional_bool(params, "inspector_only", false)
	var for_property: String = optional_string(params, "for_property", "")

	var resolved_nodes: Array[Node] = []
	for node_path_variant: Variant in node_paths:
		var node_path := str(node_path_variant)
		if node_path.is_empty():
			return error_invalid_params("node_paths cannot contain empty values")
		var node := find_node_by_path(node_path)
		if node == null:
			return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")
		resolved_nodes.append(node)

	var selection := EditorInterface.get_selection()
	if mode == "replace":
		selection.clear()

	for node: Node in resolved_nodes:
		if mode == "remove":
			selection.remove_node(node)
		else:
			selection.add_node(node)

	# edit_node() and inspect_object() both reset EditorSelection to a single
	# node, which would collapse a multi-node selection down to the last node.
	# Only focus/inspect when exactly one node was selected.
	if mode != "remove" and resolved_nodes.size() == 1:
		var edited_node: Node = resolved_nodes[0]
		if focus:
			EditorInterface.edit_node(edited_node)
		if inspect:
			EditorInterface.inspect_object(edited_node, for_property, inspector_only)

	var selected_nodes: Array = selection.get_selected_nodes()
	return success({
		"mode": mode,
		"selected": _serialize_selection_nodes(root, selected_nodes),
		"count": selected_nodes.size(),
	})


func _clear_editor_selection(_params: Dictionary) -> Dictionary:
	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var selection := EditorInterface.get_selection()
	var before_count := selection.get_selected_nodes().size()
	selection.clear()

	return success({
		"cleared": before_count,
		"selected": [],
		"count": 0,
	})


func _get_selection_node_paths(params: Dictionary) -> Array:
	if params.has("node_paths"):
		if not params["node_paths"] is Array:
			return [[], error_invalid_params("node_paths must be an array of node paths")]
		return [params["node_paths"], null]

	var result := require_string(params, "node_path")
	if result[1] != null:
		return [[], result[1]]
	return [[result[0]], null]


func _serialize_selection_nodes(root: Node, nodes: Array) -> Array:
	var serialized: Array = []
	for node: Node in nodes:
		if node == null:
			continue
		if node != root and not root.is_ancestor_of(node):
			continue
		serialized.append({
			"name": node.name,
			"path": str(root.get_path_to(node)) if node != root else ".",
			"type": node.get_class(),
		})
	return serialized


func _add_resource(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var result2 := require_string(params, "property")
	if result2[1] != null:
		return result2[1]
	var property: String = result2[0]

	var result3 := require_string(params, "resource_type")
	if result3[1] != null:
		return result3[1]
	var resource_type: String = result3[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	if not ClassDB.class_exists(resource_type):
		return error_invalid_params("Unknown resource type: %s" % resource_type)

	if not ClassDB.is_parent_class(resource_type, "Resource"):
		return error_invalid_params("'%s' is not a Resource type" % resource_type)

	var resource: Resource = ClassDB.instantiate(resource_type)
	if resource == null:
		return error_internal("Failed to create resource: %s" % resource_type)

	# Apply resource properties if provided
	var resource_props: Dictionary = params.get("resource_properties", {})
	for prop_name: String in resource_props:
		if prop_name in resource:
			var current: Variant = resource.get(prop_name)
			resource.set(prop_name, PropertyParser.parse_value(resource_props[prop_name], typeof(current)))

	var old_value: Variant = node.get(property) if property in node else null

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Add %s to %s" % [resource_type, node.name])
	undo_redo.add_do_property(node, property, resource)
	undo_redo.add_undo_property(node, property, old_value)
	undo_redo.commit_action()

	return success({
		"node_path": str(root.get_path_to(node)),
		"property": property,
		"resource_type": resource_type,
	})


func _set_anchor_preset(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var result2 := require_string(params, "preset")
	if result2[1] != null:
		return result2[1]
	var preset_name: String = result2[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	if not node is Control:
		return error_invalid_params("Node '%s' is not a Control (is %s)" % [node_path, node.get_class()])

	var control: Control = node
	var presets := {
		"top_left": Control.PRESET_TOP_LEFT,
		"top_right": Control.PRESET_TOP_RIGHT,
		"bottom_left": Control.PRESET_BOTTOM_LEFT,
		"bottom_right": Control.PRESET_BOTTOM_RIGHT,
		"center_left": Control.PRESET_CENTER_LEFT,
		"center_top": Control.PRESET_CENTER_TOP,
		"center_right": Control.PRESET_CENTER_RIGHT,
		"center_bottom": Control.PRESET_CENTER_BOTTOM,
		"center": Control.PRESET_CENTER,
		"left_wide": Control.PRESET_LEFT_WIDE,
		"top_wide": Control.PRESET_TOP_WIDE,
		"right_wide": Control.PRESET_RIGHT_WIDE,
		"bottom_wide": Control.PRESET_BOTTOM_WIDE,
		"vcenter_wide": Control.PRESET_VCENTER_WIDE,
		"hcenter_wide": Control.PRESET_HCENTER_WIDE,
		"full_rect": Control.PRESET_FULL_RECT,
	}

	if not presets.has(preset_name):
		return error_invalid_params("Unknown preset: '%s'. Available: %s" % [preset_name, presets.keys()])

	var keep_offsets: bool = optional_bool(params, "keep_offsets", false)

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Set anchor preset on %s" % node.name)

	# Store old values
	var old_anchors := [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom]
	var old_offsets := [control.offset_left, control.offset_top, control.offset_right, control.offset_bottom]

	var target: Control = control.duplicate() as Control
	target.set_anchors_and_offsets_preset(presets[preset_name],
		Control.PRESET_MODE_KEEP_SIZE if keep_offsets else Control.PRESET_MODE_MINSIZE)

	undo_redo.add_do_property(control, "anchor_left", target.anchor_left)
	undo_redo.add_do_property(control, "anchor_top", target.anchor_top)
	undo_redo.add_do_property(control, "anchor_right", target.anchor_right)
	undo_redo.add_do_property(control, "anchor_bottom", target.anchor_bottom)
	undo_redo.add_do_property(control, "offset_left", target.offset_left)
	undo_redo.add_do_property(control, "offset_top", target.offset_top)
	undo_redo.add_do_property(control, "offset_right", target.offset_right)
	undo_redo.add_do_property(control, "offset_bottom", target.offset_bottom)

	undo_redo.add_undo_property(control, "anchor_left", old_anchors[0])
	undo_redo.add_undo_property(control, "anchor_top", old_anchors[1])
	undo_redo.add_undo_property(control, "anchor_right", old_anchors[2])
	undo_redo.add_undo_property(control, "anchor_bottom", old_anchors[3])
	undo_redo.add_undo_property(control, "offset_left", old_offsets[0])
	undo_redo.add_undo_property(control, "offset_top", old_offsets[1])
	undo_redo.add_undo_property(control, "offset_right", old_offsets[2])
	undo_redo.add_undo_property(control, "offset_bottom", old_offsets[3])

	target.free()
	undo_redo.commit_action()

	return success({"node_path": str(root.get_path_to(control)), "preset": preset_name})


func _rename_node(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var result2 := require_string(params, "new_name")
	if result2[1] != null:
		return result2[1]
	var new_name: String = result2[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	var old_name: String = node.name
	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Rename %s to %s" % [old_name, new_name])
	undo_redo.add_do_property(node, "name", new_name)
	undo_redo.add_undo_property(node, "name", old_name)
	undo_redo.commit_action()

	return success({"old_name": old_name, "new_name": str(node.name), "node_path": str(root.get_path_to(node))})


func _connect_signal(params: Dictionary) -> Dictionary:
	var result := require_string(params, "source_path")
	if result[1] != null:
		return result[1]
	var source_path: String = result[0]

	var result2 := require_string(params, "signal_name")
	if result2[1] != null:
		return result2[1]
	var signal_name: String = result2[0]

	var result3 := require_string(params, "target_path")
	if result3[1] != null:
		return result3[1]
	var target_path: String = result3[0]

	var result4 := require_string(params, "method_name")
	if result4[1] != null:
		return result4[1]
	var method_name: String = result4[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var source := find_node_by_path(source_path)
	if source == null:
		return error_not_found("Source node '%s'" % source_path)

	var target := find_node_by_path(target_path)
	if target == null:
		return error_not_found("Target node '%s'" % target_path)

	if not source.has_signal(signal_name):
		return error_invalid_params("Signal '%s' not found on %s" % [signal_name, source.get_class()])

	if source.is_connected(signal_name, Callable(target, method_name)):
		return success({"already_connected": true, "signal": signal_name})

	# CONNECT_PERSIST is required for PackedScene.pack() to serialize the
	# connection into the .tscn — without it the connection is editor-memory only.
	var flags: int = Object.CONNECT_PERSIST
	if optional_bool(params, "deferred", false):
		flags |= Object.CONNECT_DEFERRED
	if optional_bool(params, "one_shot", false):
		flags |= Object.CONNECT_ONE_SHOT

	var callable := Callable(target, method_name)
	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Connect signal")
	undo_redo.add_do_method(source, "connect", signal_name, callable, flags)
	undo_redo.add_undo_method(source, "disconnect", signal_name, callable)
	undo_redo.commit_action()

	return success({
		"source": str(root.get_path_to(source)),
		"signal": signal_name,
		"target": str(root.get_path_to(target)),
		"method": method_name,
		"connected": true,
		"flags": flags,
		"persistent": true,
	})


func _disconnect_signal(params: Dictionary) -> Dictionary:
	var result := require_string(params, "source_path")
	if result[1] != null:
		return result[1]
	var source_path: String = result[0]

	var result2 := require_string(params, "signal_name")
	if result2[1] != null:
		return result2[1]
	var signal_name: String = result2[0]

	var result3 := require_string(params, "target_path")
	if result3[1] != null:
		return result3[1]
	var target_path: String = result3[0]

	var result4 := require_string(params, "method_name")
	if result4[1] != null:
		return result4[1]
	var method_name: String = result4[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var source := find_node_by_path(source_path)
	if source == null:
		return error_not_found("Source node '%s'" % source_path)

	var target := find_node_by_path(target_path)
	if target == null:
		return error_not_found("Target node '%s'" % target_path)

	if not source.is_connected(signal_name, Callable(target, method_name)):
		return success({"was_connected": false})

	var callable := Callable(target, method_name)
	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Disconnect signal")
	undo_redo.add_do_method(source, "disconnect", signal_name, callable)
	undo_redo.add_undo_method(source, "connect", signal_name, callable)
	undo_redo.commit_action()

	return success({
		"source": str(root.get_path_to(source)),
		"signal": signal_name,
		"target": str(root.get_path_to(target)),
		"method": method_name,
		"disconnected": true,
	})


func _get_node_groups(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	var groups: Array = []
	for group: StringName in node.get_groups():
		var g := str(group)
		# Filter out internal groups (start with _)
		if not g.begins_with("_"):
			groups.append(g)

	return success({
		"node_path": str(root.get_path_to(node)),
		"groups": groups,
		"count": groups.size(),
	})


func _set_node_groups(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	if not params.has("groups") or not params["groups"] is Array:
		return error_invalid_params("'groups' array is required")
	var desired_groups: Array = params["groups"]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path, "Use get_scene_tree to see available nodes")

	# Get current non-internal groups
	var current_groups: Array = []
	for group: StringName in node.get_groups():
		var g := str(group)
		if not g.begins_with("_"):
			current_groups.append(g)

	var added: Array = []
	var removed: Array = []

	for group: String in current_groups:
		if group not in desired_groups:
			removed.append(group)

	for group in desired_groups:
		var g: String = str(group)
		if g not in current_groups:
			added.append(g)

	if not added.is_empty() or not removed.is_empty():
		var undo_redo := get_undo_redo()
		undo_redo.create_action("MCP: Set node groups")
		for group: String in removed:
			undo_redo.add_do_method(node, "remove_from_group", group)
			undo_redo.add_undo_method(node, "add_to_group", group, true)
		for group: String in added:
			undo_redo.add_do_method(node, "add_to_group", group, true)
			undo_redo.add_undo_method(node, "remove_from_group", group)
		undo_redo.commit_action()

	return success({
		"node_path": str(root.get_path_to(node)),
		"groups": desired_groups,
		"added": added,
		"removed": removed,
	})


func _find_nodes_in_group(params: Dictionary) -> Dictionary:
	var result := require_string(params, "group")
	if result[1] != null:
		return result[1]
	var group_name: String = result[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var matches: Array = []
	_find_in_group_recursive(root, root, group_name, matches)

	return success({
		"group": group_name,
		"nodes": matches,
		"count": matches.size(),
	})


func _find_in_group_recursive(node: Node, root: Node, group_name: String, matches: Array) -> void:
	if node.is_in_group(group_name):
		matches.append({
			"name": node.name,
			"path": str(root.get_path_to(node)),
			"type": node.get_class(),
		})
	for child in node.get_children():
		_find_in_group_recursive(child, root, group_name, matches)
