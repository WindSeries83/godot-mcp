@tool
extends RefCounted

## Recursively set owner for all children (needed when adding nodes via code)
static func set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		set_owner_recursive(child, owner)


## Get a simplified tree structure from a node.
## Paths are scene-relative (usable as node_path input for other tools) —
## node.get_path() would leak the editor's internal dock hierarchy.
static func get_node_tree(node: Node, root: Node = null, max_depth: int = -1, current_depth: int = 0) -> Dictionary:
	if root == null:
		root = node
	var result := {
		"name": node.name,
		"type": node.get_class(),
		"path": "." if node == root else str(root.get_path_to(node)),
		# Session-scoped handle (format must match base_command.gd's
		# find_node_by_path/node_handle): stays valid across a rename or
		# reparent, unlike "path" above, which breaks the moment either
		# happens. Invalid after the scene is closed/reloaded, or the node
		# freed — callers should re-fetch the tree rather than cache this
		# indefinitely.
		"handle": "@id:%d" % node.get_instance_id(),
	}

	# Add script info
	var script: Script = node.get_script()
	if script:
		result["script"] = script.resource_path

	# Add children
	if max_depth == -1 or current_depth < max_depth:
		var children: Array = []
		for child in node.get_children():
			children.append(get_node_tree(child, root, max_depth, current_depth + 1))
		if not children.is_empty():
			result["children"] = children

	return result


## Get all properties of a node as a serializable dictionary
static func get_node_properties_dict(node: Node) -> Dictionary:
	var PropertyParser := preload("res://addons/godot_mcp/utils/property_parser.gd")
	var result: Dictionary = {}
	var property_list := node.get_property_list()

	for prop_info in property_list:
		var prop_name: String = prop_info["name"]
		var usage: int = prop_info["usage"]

		# Only include user-facing properties (PROPERTY_USAGE_EDITOR)
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue

		# Skip internal/meta properties
		if prop_name.begins_with("_") or prop_name in ["script"]:
			continue

		var value: Variant = node.get(prop_name)
		result[prop_name] = PropertyParser.serialize_value(value)

	return result


## Duplicate a node and all its children, properly setting owners
## Returns null when `node` has no parent — the scene root cannot be duplicated
## in place, and dereferencing the null parent would raise.
static func duplicate_node_in_scene(node: Node, new_name: String, root: Node) -> Node:
	var parent := node.get_parent()
	if parent == null:
		return null
	var dup := node.duplicate()
	dup.name = new_name
	parent.add_child(dup)
	dup.owner = root
	set_owner_recursive(dup, root)
	return dup


## Find node by class type in subtree
static func find_nodes_by_type(root: Node, type_name: String) -> Array[Node]:
	var result: Array[Node] = []
	if root.get_class() == type_name or root.is_class(type_name):
		result.append(root)
	for child in root.get_children():
		result.append_array(find_nodes_by_type(child, type_name))
	return result
