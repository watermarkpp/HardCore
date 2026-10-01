extends RefCounted

const ALLOWED := ["hc.can_see_stealth","hc.immune.periodic"]
var _sources: Dictionary = {}
var _counts: Dictionary = {}
func replace_source(handle: String, capabilities: Array) -> bool:
	if handle.is_empty() or capabilities.size() > ALLOWED.size(): return false
	var selected: Dictionary = {}
	for id: Variant in capabilities:
		if not id is String or id not in ALLOWED or selected.has(id): return false
		selected[id] = true
	var candidate := _sources.duplicate(true)
	if selected.is_empty(): candidate.erase(handle)
	else: candidate[handle] = selected
	if candidate.size() > 64: return false
	var counts: Dictionary = {}
	for values: Dictionary in candidate.values():
		for id: String in values: counts[id] = int(counts.get(id,0))+1
	_sources = candidate; _counts = counts
	return true
func has(id: String) -> bool: return int(_counts.get(id,0)) > 0
func clear() -> void:
	_sources.clear(); _counts.clear()
func snapshot() -> Dictionary:
	return preload("res://scripts/features/contracts/plain_graph.gd").capture({"sources":_sources,"counts":_counts}).value
