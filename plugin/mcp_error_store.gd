@tool
extends RefCounted

## Ring buffer of runtime errors captured off the ScriptEditorDebugger's
## "debug_data" signal (see mcp_debugger_plugin.gd). Entries carry a monotonic
## sequence number that survives clear(), so a caller can poll "anything new
## since seq N?" without a race against entries dropping out of the buffer.

const MAX_ENTRIES := 500

var _entries: Array[Dictionary] = []
var _next_seq: int = 1


## `entry` should NOT include "seq" — it is assigned here.
func push(entry: Dictionary) -> void:
	var stamped := entry.duplicate()
	stamped["seq"] = _next_seq
	_next_seq += 1
	_entries.append(stamped)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()


## Entries with seq > since_seq, oldest first, capped at max_count, optionally
## excluding warnings.
func get_since(since_seq: int = 0, max_count: int = 50, include_warnings: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if entry.get("seq", 0) <= since_seq:
			continue
		if not include_warnings and entry.get("is_warning", false):
			continue
		out.append(entry)
		if out.size() >= max_count:
			break
	return out


## Empties the buffer but keeps _next_seq monotonic across the clear, so a
## caller holding an old seq still gets a correct "nothing new" instead of
## seeing seq numbers restart from 1 and misreading old errors as new.
func clear() -> void:
	_entries.clear()


func current_seq() -> int:
	return _next_seq - 1


func is_empty() -> bool:
	return _entries.is_empty()
