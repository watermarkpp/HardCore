extends RefCounted
## Finite exact projection of this one Source snapshot. No Callable or model
## crosses owners, and no linear map transform is guessed by the renderer.
const Snapshot:=preload("res://scripts/skills/skill_footprint_snapshot.gd")
static func project_captured_ground(point: Vector2, values: Dictionary) -> Vector2:
	for sample: Dictionary in values.samples:
		if sample.ground==point: return sample.screen
	values.failure={"error":"original_melee_projection_point_outside_captured_snapshot","point":point}
	return Vector2.INF
static func capture_source(context: Dictionary, snapshot: Dictionary, world: Dictionary, source_context: Dictionary) -> Dictionary:
	if source_context.get("world_context")!=world or world.get("runtime_map_id")!=snapshot.get("runtime_map_id"): return {}
	if Snapshot.validate_for_consumer(snapshot,context,Snapshot.VALIDATION_STRICT_V2).get("valid")!=true: return {}
	var converter: Callable=context.get("ground_position_gu_to_screen_position_px",Callable())
	if not converter.is_valid(): return {}
	var origin: Variant=context.get("projection_origin_ground_gu")
	if not origin is Vector2: return {}
	var origin_screen: Variant=converter.call(origin)
	if not origin_screen is Vector2 or not origin_screen.is_finite(): return {}
	var samples: Array=[{"ground":origin,"screen":origin_screen}]
	var polygons: Array=_polygons(snapshot)
	var projected: Array=Snapshot.projected_polygons_screen_offset_px(snapshot)
	if polygons.size()!=projected.size() or polygons.is_empty(): return {}
	for index: int in polygons.size():
		if polygons[index].size()!=projected[index].size(): return {}
		for vertex: int in polygons[index].size():
			var point: Vector2=polygons[index][vertex]
			var screen: Variant=converter.call(point)
			if not screen is Vector2 or not screen.is_finite() or screen-origin_screen!=projected[index][vertex]: return {}
			samples.append({"ground":point,"screen":screen})
	var plain: Dictionary=context.duplicate(true)
	plain.erase("ground_position_gu_to_screen_position_px")
	plain.original_melee_projection={"contract_id":"hardcore.melee.exact_source_projection.v1","snapshot_id":snapshot.get("snapshot_id"),"runtime_map_id":snapshot.get("runtime_map_id"),"world":world.duplicate(true),"source_context":source_context.duplicate(true),"samples":samples,"origin_screen":origin_screen}
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	return plain if graph.validate(plain,false).get("success")==true else {}
static func restore_main(plain: Dictionary, snapshot: Dictionary, world: Dictionary, source_context: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id(): return {}
	var proof: Variant=plain.get("original_melee_projection")
	if not proof is Dictionary or proof.get("contract_id")!="hardcore.melee.exact_source_projection.v1" or proof.get("snapshot_id")!=snapshot.get("snapshot_id") or proof.get("runtime_map_id")!=snapshot.get("runtime_map_id") or proof.get("world")!=world or proof.get("source_context")!=source_context or not proof.get("samples") is Array or proof.samples.is_empty() or not proof.get("origin_screen") is Vector2: return {}
	var samples: Array=proof.samples.duplicate(true)
	var seen: Dictionary={}
	for sample: Variant in samples:
		if not sample is Dictionary or not sample.get("ground") is Vector2 or not sample.ground.is_finite() or not sample.get("screen") is Vector2 or not sample.screen.is_finite(): return {}
		if seen.has(sample.ground) and seen[sample.ground]!=sample.screen: return {}
		seen[sample.ground]=sample.screen
	var origin: Variant=plain.get("projection_origin_ground_gu")
	if not origin is Vector2 or not seen.has(origin) or seen[origin]!=proof.origin_screen: return {}
	var polygons: Array=_polygons(snapshot)
	var projected: Array=Snapshot.projected_polygons_screen_offset_px(snapshot)
	if polygons.is_empty() or polygons.size()!=projected.size(): return {}
	for index: int in polygons.size():
		if polygons[index].size()!=projected[index].size(): return {}
		for vertex: int in polygons[index].size():
			var found:=false
			for sample: Dictionary in samples:
				if sample.ground==polygons[index][vertex]:
					if sample.screen-proof.origin_screen!=projected[index][vertex]: return {}
					found=true;break
			if not found: return {}
	var context: Dictionary=plain.duplicate(true)
	context.erase("original_melee_projection")
	# The existing Main Script is the callable target, not a temporary Object.
	# Its bound payload is plain finite geometry; no Source object/Callable is
	# retained. This also avoids zero-ref temporary script-instance teardown.
	var module: Script=load("res://scripts/gameplay/presentation/original_melee_presentation_context.gd")
	var values: Dictionary={"samples":samples,"failure":{}}
	context._actual_projection_owner=module
	context._actual_projection_values=values
	context.ground_position_gu_to_screen_position_px=Callable(module,"project_captured_ground").bind(values)
	return context if Snapshot.validate_for_consumer(snapshot,context,Snapshot.VALIDATION_STRICT_V2).get("valid")==true else {}

static func _polygons(snapshot: Dictionary) -> Array:
	return Snapshot.ground_polygons_gu(snapshot)

static func release_main(context: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id(): return false
	var module: Script=context.get("_actual_projection_owner")
	var converter: Callable=context.get("ground_position_gu_to_screen_position_px",Callable())
	if module==null or module.resource_path!="res://scripts/gameplay/presentation/original_melee_presentation_context.gd" or converter.get_object()!=module: return false
	context.erase("ground_position_gu_to_screen_position_px")
	converter=Callable()
	context.erase("_actual_projection_values")
	context.erase("_actual_projection_owner")
	return true
