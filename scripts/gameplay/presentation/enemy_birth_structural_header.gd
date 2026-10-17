extends RefCounted

const CONTRACT := "hardcore.enemy.structural_header.v1"
const Identity := preload("res://scripts/gameplay/presentation/actor_visual_projection_contract.gd")
static func capture(value: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("HardCoreContentValueGraph"): return {}
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var result: Dictionary = graph.capture(value,true,false)
	return result.value if result.get("success") == true else {}
static func validate(header: Dictionary, kind: String) -> bool:
	if kind not in ["ACTOR_HEADER","VISUAL_HEADER"] or header.size() != (6 if kind == "ACTOR_HEADER" else 7) or header.get("contract_id") != CONTRACT or header.get("header_kind") != kind or not header.get("actor_identity") is Dictionary or not Identity.valid_identity(header.actor_identity): return false
	if not header.get("event_identity") is Dictionary or header.event_identity.size() != 3 or not header.get("sequence") is int or header.sequence <= 0: return false
	for key: String in ["bridge_generation","journal_generation","event_ordinal"]:
		if not header.event_identity.get(key) is int or header.event_identity[key] <= 0: return false
	if header.event_identity.event_ordinal != header.sequence or not header.get("source_site") is Dictionary or header.source_site.get("world_context") != header.actor_identity.world: return false
	for key: String in ["clock_epoch","domain","entry_id","entry_ordinal","bootstrap","observation_process_epoch","world_context","deadline_usec"]:
		if not header.source_site.has(key): return false
	if header.source_site.size() != 8: return false
	if kind == "VISUAL_HEADER" and (not header.get("visual_service_id") is int or header.visual_service_id <= 0): return false
	return not capture(header).is_empty()
