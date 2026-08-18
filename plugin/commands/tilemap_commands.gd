@tool
extends "res://addons/godot_mcp/commands/base_command.gd"


func get_commands() -> Dictionary:
	return {
		"tilemap_set_cell": _tilemap_set_cell,
		"tilemap_fill_rect": _tilemap_fill_rect,
		"tilemap_get_cell": _tilemap_get_cell,
		"tilemap_clear": _tilemap_clear,
		"tilemap_get_info": _tilemap_get_info,
		"tilemap_get_used_cells": _tilemap_get_used_cells,
	}


func get_command_schemas() -> Dictionary:
	return {
		"tilemap_set_cell": {
			"category": "tilemap",
			"summary": "Set a single cell's tile on a TileMapLayer, or a legacy TileMap's layer.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Path to a TileMapLayer or legacy TileMap node"},
				"layer": {"type": "int", "required": false, "default": 0, "desc": "Legacy TileMap layer index; must be omitted or 0 for TileMapLayer"},
				"x": {"type": "int", "required": false, "default": 0, "desc": "Cell column"},
				"y": {"type": "int", "required": false, "default": 0, "desc": "Cell row"},
				"source_id": {"type": "int", "required": false, "default": 0, "desc": "TileSet atlas source id"},
				"atlas_x": {"type": "int", "required": false, "default": 0, "desc": "Atlas tile column"},
				"atlas_y": {"type": "int", "required": false, "default": 0, "desc": "Atlas tile row"},
				"alternative": {"type": "int", "required": false, "default": 0, "desc": "Alternative tile id"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"tilemap_fill_rect": {
			"category": "tilemap",
			"summary": "Set the same tile across every cell in a rectangular region (inclusive corners, order-independent).",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Path to a TileMapLayer or legacy TileMap node"},
				"layer": {"type": "int", "required": false, "default": 0, "desc": "Legacy TileMap layer index; must be omitted or 0 for TileMapLayer"},
				"x1": {"type": "int", "required": false, "default": 0, "desc": "First corner column"},
				"y1": {"type": "int", "required": false, "default": 0, "desc": "First corner row"},
				"x2": {"type": "int", "required": false, "default": 0, "desc": "Opposite corner column"},
				"y2": {"type": "int", "required": false, "default": 0, "desc": "Opposite corner row"},
				"source_id": {"type": "int", "required": false, "default": 0, "desc": "TileSet atlas source id"},
				"atlas_x": {"type": "int", "required": false, "default": 0, "desc": "Atlas tile column"},
				"atlas_y": {"type": "int", "required": false, "default": 0, "desc": "Atlas tile row"},
				"alternative": {"type": "int", "required": false, "default": 0, "desc": "Alternative tile id"},
			},
			"annotations": {"readOnly": false, "destructive": false, "idempotent": true},
		},
		"tilemap_get_cell": {
			"category": "tilemap",
			"summary": "Read a single cell's source id, atlas coords, and alternative tile. source_id is -1 when the cell is empty.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Path to a TileMapLayer or legacy TileMap node"},
				"layer": {"type": "int", "required": false, "default": 0, "desc": "Legacy TileMap layer index; must be omitted or 0 for TileMapLayer"},
				"x": {"type": "int", "required": false, "default": 0, "desc": "Cell column"},
				"y": {"type": "int", "required": false, "default": 0, "desc": "Cell row"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"tilemap_clear": {
			"category": "tilemap",
			"summary": "Clear cells. On a TileMapLayer this clears its one layer; on a legacy TileMap, a given layer or, if omitted, every layer.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Path to a TileMapLayer or legacy TileMap node"},
				"layer": {"type": "int", "required": false, "desc": "Legacy TileMap layer index; omit to clear all layers. Must be omitted or 0 for TileMapLayer"},
			},
			"annotations": {"readOnly": false, "destructive": true, "idempotent": true},
		},
		"tilemap_get_info": {
			"category": "tilemap",
			"summary": "Layer list, used-cell counts, TileSet source list, and tile size for a TileMapLayer or legacy TileMap.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Path to a TileMapLayer or legacy TileMap node"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
		"tilemap_get_used_cells": {
			"category": "tilemap",
			"summary": "List the non-empty cells on a layer, each with its coordinates and source id.",
			"params": {
				"node_path": {"type": "string", "required": true, "desc": "Path to a TileMapLayer or legacy TileMap node"},
				"layer": {"type": "int", "required": false, "default": 0, "desc": "Legacy TileMap layer index; must be omitted or 0 for TileMapLayer"},
				"max_count": {"type": "int", "required": false, "default": 500, "desc": "Maximum cells to return; negative values are clamped to 0"},
			},
			"annotations": {"readOnly": true, "destructive": false, "idempotent": true},
		},
	}


func _find_tilemap_node(node_path: String) -> Node:
	var node := find_node_by_path(node_path)
	if node is TileMapLayer or _is_legacy_tilemap(node):
		return node
	return null


func _is_legacy_tilemap(node: Node) -> bool:
	return node != null and node.get_class() == "TileMap"


func _not_found_result(node_path: String) -> Dictionary:
	return error_not_found(
		"TileMapLayer or TileMap at '%s'" % node_path,
		"Use TileMapLayer for current Godot projects, or pass a deprecated TileMap node with optional layer."
	)


func _get_single_layer(tilemap: Node, params: Dictionary) -> Array:
	if tilemap is TileMapLayer:
		if params.has("layer") and optional_int(params, "layer") != 0:
			return [0, error_invalid_params("layer only applies to deprecated TileMap nodes; TileMapLayer has one implicit layer")]
		return [0, null]

	var layer: int = optional_int(params, "layer", 0)
	var layer_error := _validate_tilemap_layer(tilemap, layer)
	if not layer_error.is_empty():
		return [layer, layer_error]
	return [layer, null]


func _get_clear_layers(tilemap: Node, params: Dictionary) -> Array:
	if tilemap is TileMapLayer:
		var layer_result := _get_single_layer(tilemap, params)
		if layer_result[1] != null:
			return [[], layer_result[1]]
		return [[0], null]

	if params.has("layer"):
		var layer_result := _get_single_layer(tilemap, params)
		if layer_result[1] != null:
			return [[], layer_result[1]]
		return [[int(layer_result[0])], null]

	var layers: Array = []
	for layer in range(_get_tilemap_layer_count(tilemap)):
		layers.append(layer)
	return [layers, null]


func _validate_tilemap_layer(tilemap: Node, layer: int) -> Dictionary:
	if tilemap is TileMapLayer:
		return {}

	var layer_count := _get_tilemap_layer_count(tilemap)
	if layer_count <= 0:
		return error_invalid_params("TileMap has no layers")
	if layer < -layer_count or layer >= layer_count:
		return error_invalid_params("layer %d is out of range for TileMap with %d layers" % [layer, layer_count])
	return {}


func _get_tilemap_layer_count(tilemap: Node) -> int:
	if tilemap is TileMapLayer:
		return 1
	return int(tilemap.call("get_layers_count"))


func _get_used_cells(tilemap: Node, layer: int) -> Array:
	if tilemap is TileMapLayer:
		return tilemap.call("get_used_cells")
	return tilemap.call("get_used_cells", layer)


func _get_cell_source_id(tilemap: Node, layer: int, coords: Vector2i) -> int:
	if tilemap is TileMapLayer:
		return int(tilemap.call("get_cell_source_id", coords))
	return int(tilemap.call("get_cell_source_id", layer, coords))


func _get_cell_atlas_coords(tilemap: Node, layer: int, coords: Vector2i) -> Vector2i:
	if tilemap is TileMapLayer:
		return tilemap.call("get_cell_atlas_coords", coords)
	return tilemap.call("get_cell_atlas_coords", layer, coords)


func _get_cell_alternative_tile(tilemap: Node, layer: int, coords: Vector2i) -> int:
	if tilemap is TileMapLayer:
		return int(tilemap.call("get_cell_alternative_tile", coords))
	return int(tilemap.call("get_cell_alternative_tile", layer, coords))


func _tilemap_set_cell(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var tilemap := _find_tilemap_node(node_path)
	if tilemap == null:
		return _not_found_result(node_path)

	var layer_result := _get_single_layer(tilemap, params)
	if layer_result[1] != null:
		return layer_result[1]
	var layer: int = layer_result[0]

	var x: int = optional_int(params, "x", 0)
	var y: int = optional_int(params, "y", 0)
	var source_id: int = optional_int(params, "source_id", 0)
	var atlas_x: int = optional_int(params, "atlas_x", 0)
	var atlas_y: int = optional_int(params, "atlas_y", 0)
	var alternative: int = optional_int(params, "alternative", 0)

	var coords := Vector2i(x, y)
	var old_cells := [_capture_cell(tilemap, layer, coords)]
	var new_cells := [_make_cell(layer, coords, source_id, Vector2i(atlas_x, atlas_y), alternative)]

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Set TileMap cell")
	_add_do_set_cells(undo_redo, tilemap, new_cells)
	_add_undo_set_cells(undo_redo, tilemap, old_cells)
	undo_redo.commit_action()

	return success({"x": x, "y": y, "layer": layer, "node_class": tilemap.get_class(), "source_id": source_id, "atlas_coords": [atlas_x, atlas_y]})


func _tilemap_fill_rect(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var tilemap := _find_tilemap_node(node_path)
	if tilemap == null:
		return _not_found_result(node_path)

	var layer_result := _get_single_layer(tilemap, params)
	if layer_result[1] != null:
		return layer_result[1]
	var layer: int = layer_result[0]

	var x1: int = optional_int(params, "x1", 0)
	var y1: int = optional_int(params, "y1", 0)
	var x2: int = optional_int(params, "x2", 0)
	var y2: int = optional_int(params, "y2", 0)
	var source_id: int = optional_int(params, "source_id", 0)
	var atlas_x: int = optional_int(params, "atlas_x", 0)
	var atlas_y: int = optional_int(params, "atlas_y", 0)
	var alternative: int = optional_int(params, "alternative", 0)

	var count := 0
	var old_cells: Array = []
	var new_cells: Array = []
	for cx in range(mini(x1, x2), maxi(x1, x2) + 1):
		for cy in range(mini(y1, y2), maxi(y1, y2) + 1):
			var coords := Vector2i(cx, cy)
			old_cells.append(_capture_cell(tilemap, layer, coords))
			new_cells.append(_make_cell(layer, coords, source_id, Vector2i(atlas_x, atlas_y), alternative))
			count += 1

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Fill TileMap rect")
	_add_do_set_cells(undo_redo, tilemap, new_cells)
	_add_undo_set_cells(undo_redo, tilemap, old_cells)
	undo_redo.commit_action()

	return success({"filled": count, "rect": [x1, y1, x2, y2], "layer": layer, "node_class": tilemap.get_class()})


func _tilemap_get_cell(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var tilemap := _find_tilemap_node(node_path)
	if tilemap == null:
		return _not_found_result(node_path)

	var layer_result := _get_single_layer(tilemap, params)
	if layer_result[1] != null:
		return layer_result[1]
	var layer: int = layer_result[0]

	var x: int = optional_int(params, "x", 0)
	var y: int = optional_int(params, "y", 0)
	var coords := Vector2i(x, y)

	var source_id := _get_cell_source_id(tilemap, layer, coords)
	var atlas_coords := _get_cell_atlas_coords(tilemap, layer, coords)
	var alternative := _get_cell_alternative_tile(tilemap, layer, coords)

	return success({
		"x": x, "y": y,
		"layer": layer,
		"node_class": tilemap.get_class(),
		"source_id": source_id,
		"atlas_coords": [atlas_coords.x, atlas_coords.y],
		"alternative": alternative,
		"empty": source_id == -1,
	})


func _tilemap_clear(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var tilemap := _find_tilemap_node(node_path)
	if tilemap == null:
		return _not_found_result(node_path)

	var clear_layers_result := _get_clear_layers(tilemap, params)
	if clear_layers_result[1] != null:
		return clear_layers_result[1]
	var layers: Array = clear_layers_result[0]

	var old_cells := _capture_cells(tilemap, layers)

	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Clear TileMap")
	_add_do_clear(undo_redo, tilemap, layers)
	_add_undo_set_cells(undo_redo, tilemap, old_cells)
	undo_redo.commit_action()
	return success({"cleared": true, "layers": layers, "node_class": tilemap.get_class()})


func _make_cell(layer: int, coords: Vector2i, source_id: int, atlas_coords: Vector2i, alternative: int) -> Dictionary:
	return {
		"layer": layer,
		"coords": coords,
		"source_id": source_id,
		"atlas_coords": atlas_coords,
		"alternative": alternative,
	}


func _capture_cell(tilemap: Node, layer: int, coords: Vector2i) -> Dictionary:
	return _make_cell(
		layer,
		coords,
		_get_cell_source_id(tilemap, layer, coords),
		_get_cell_atlas_coords(tilemap, layer, coords),
		_get_cell_alternative_tile(tilemap, layer, coords)
	)


func _capture_cells(tilemap: Node, layers: Array) -> Array:
	var cells: Array = []
	for layer: int in layers:
		for coords: Vector2i in _get_used_cells(tilemap, layer):
			cells.append(_capture_cell(tilemap, layer, coords))
	return cells


func _add_do_set_cells(undo_redo: EditorUndoRedoManager, tilemap: Node, cells: Array) -> void:
	for cell: Dictionary in cells:
		if tilemap is TileMapLayer:
			undo_redo.add_do_method(tilemap, "set_cell", cell["coords"], cell["source_id"], cell["atlas_coords"], cell["alternative"])
		else:
			undo_redo.add_do_method(tilemap, "set_cell", cell["layer"], cell["coords"], cell["source_id"], cell["atlas_coords"], cell["alternative"])


func _add_undo_set_cells(undo_redo: EditorUndoRedoManager, tilemap: Node, cells: Array) -> void:
	for cell: Dictionary in cells:
		if tilemap is TileMapLayer:
			undo_redo.add_undo_method(tilemap, "set_cell", cell["coords"], cell["source_id"], cell["atlas_coords"], cell["alternative"])
		else:
			undo_redo.add_undo_method(tilemap, "set_cell", cell["layer"], cell["coords"], cell["source_id"], cell["atlas_coords"], cell["alternative"])


func _add_do_clear(undo_redo: EditorUndoRedoManager, tilemap: Node, layers: Array) -> void:
	if tilemap is TileMapLayer or layers.size() == _get_tilemap_layer_count(tilemap):
		undo_redo.add_do_method(tilemap, "clear")
		return

	for layer: int in layers:
		undo_redo.add_do_method(tilemap, "clear_layer", layer)


func _tilemap_get_info(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var tilemap := _find_tilemap_node(node_path)
	if tilemap == null:
		return _not_found_result(node_path)

	var tile_set: TileSet = tilemap.get("tile_set")
	var sources: Array = []
	if tile_set:
		for i in tile_set.get_source_count():
			var source_id := tile_set.get_source_id(i)
			var source := tile_set.get_source(source_id)
			var info := {"id": source_id, "type": source.get_class()}
			if source is TileSetAtlasSource:
				var atlas: TileSetAtlasSource = source
				info["texture"] = atlas.texture.resource_path if atlas.texture else ""
				info["tile_count"] = atlas.get_tiles_count()
			sources.append(info)

	var layers := _get_layer_info(tilemap)
	var used_cells := 0
	for layer_info: Dictionary in layers:
		used_cells += int(layer_info["used_cells"])

	return success({
		"node_path": node_path,
		"node_class": tilemap.get_class(),
		"layer_count": layers.size(),
		"layers": layers,
		"used_cells": used_cells,
		"tile_set_sources": sources,
		"tile_size": [tile_set.tile_size.x, tile_set.tile_size.y] if tile_set else [0, 0],
	})


func _get_layer_info(tilemap: Node) -> Array:
	var layers: Array = []
	if tilemap is TileMapLayer:
		layers.append({
			"index": 0,
			"name": tilemap.name,
			"enabled": true,
			"used_cells": _get_used_cells(tilemap, 0).size(),
		})
		return layers

	for layer in range(_get_tilemap_layer_count(tilemap)):
		layers.append({
			"index": layer,
			"name": String(tilemap.call("get_layer_name", layer)),
			"enabled": bool(tilemap.call("is_layer_enabled", layer)),
			"used_cells": _get_used_cells(tilemap, layer).size(),
		})
	return layers


func _tilemap_get_used_cells(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var tilemap := _find_tilemap_node(node_path)
	if tilemap == null:
		return _not_found_result(node_path)

	var layer_result := _get_single_layer(tilemap, params)
	if layer_result[1] != null:
		return layer_result[1]
	var layer: int = layer_result[0]

	var max_count: int = maxi(0, optional_int(params, "max_count", 500))
	var cells: Array = []
	var used := _get_used_cells(tilemap, layer)

	for i in mini(used.size(), max_count):
		var pos: Vector2i = used[i]
		cells.append({"x": pos.x, "y": pos.y, "layer": layer, "source_id": _get_cell_source_id(tilemap, layer, pos)})

	return success({"cells": cells, "total": used.size(), "returned": cells.size(), "layer": layer, "node_class": tilemap.get_class()})
