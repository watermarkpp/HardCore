extends RefCounted
const Working:=preload("res://scripts/gameplay/world/world_runtime_working_graph.gd")
static func container_modes(value: Variant,path: Array,sources: Array,modes: Array) -> void:
	if not (value is Dictionary or value is Array):return
	for previous: Variant in sources:
		if is_same(previous,value):return
	sources.append(value)
	if value is Dictionary:
		for key: Variant in value:
			var child: Array=path.duplicate();child.append(key);container_modes(value[key],child,sources,modes)
	else:
		for index: int in range(value.size()):
			var child: Array=path.duplicate();child.append(index);container_modes(value[index],child,sources,modes)
	modes.append({"path":path,"read_only":value.is_read_only()})
static func restore(roots: Dictionary,modes: Array) -> Dictionary:
	var actual: Dictionary=Working.restore_runtime_roots(roots)
	if actual.get("ok")!=true:return actual
	var restored: Array=[];container_modes(actual.value,[],[],restored)
	if restored.size()!=modes.size():return {"ok":false,"errors":["original_path_container_metadata_missing"]}
	for index: int in range(restored.size()):
		if not modes[index] is Dictionary or modes[index].get("path")!=restored[index].path or not modes[index].get("read_only") is bool:return {"ok":false,"errors":["original_path_alias_or_mode_mismatch"]}
	for row: Dictionary in modes:
		if row.read_only:
			var value: Variant=actual.value
			for key: Variant in row.path:value=value[key]
			value.make_read_only()
	return actual
