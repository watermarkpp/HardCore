extends RefCounted
## Original overhead child input only. This is NOT a motion/visual snapshot,
## asset readiness, BindingFact or replacement ActorRef.
const Identity := preload("res://scripts/gameplay/presentation/actor_visual_projection_contract.gd")
const CONTRACT := "hardcore.enemy.overhead_birth_context.v1"
static func capture_original(handle: Object, model: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id()==OS.get_main_thread_id() or handle==null or model==null or handle.kind()!=&"enemy" or handle.model()!=model or model.get_script()!=preload("res://scripts/gameplay/actors/enemy_actor_model.gd"): return {}
	var context := {"contract_id":CONTRACT,"actor_identity":handle.identity(),"monster_id":model.monster_id,"display_name":model.display_name,"monster_data":model.monster_data,"metadata":{}}
	for key: StringName in [&"spawn_context",&"spawn_classification",&"spawn_is_boss"]:
		if model.metadata.contains(key): context.metadata[key]=model.metadata.read(key)
	return Identity.capture(context) if validate(context) else {}
static func validate(context: Dictionary) -> bool:
	if context.size()!=6 or context.get("contract_id")!=CONTRACT or not context.get("actor_identity") is Dictionary or not Identity.valid_identity(context.actor_identity) or not context.get("monster_id") is int or context.monster_id<0 or not context.get("display_name") is String or not context.get("monster_data") is Dictionary or not context.get("metadata") is Dictionary: return false
	for key: Variant in context.metadata:
		if not key is String and not key is StringName: return false
		if String(key) not in ["spawn_context","spawn_classification","spawn_is_boss"]: return false
	# Native value capture rejects live Object/Resource values recursively.
	return not Identity.capture(context).is_empty()
