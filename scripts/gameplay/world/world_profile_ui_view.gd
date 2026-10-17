extends RefCounted
## Main read view of values computed by the actual S ProfileModel. No hydrate,
## stat formula, quest algorithm, item count or persistence lives on Main.
signal profile_changed
signal inventory_changed
signal equipment_changed
signal skills_changed
signal quests_changed
var _owner := OS.get_thread_caller_id()
var _snapshot: Dictionary = {}
var _serial := 0
func owner_thread_id() -> int: return _owner
func actual_source_snapshot() -> Dictionary: return _snapshot
func _get(field: StringName) -> Variant:
	assert(OS.get_thread_caller_id()==_owner)
	assert(_snapshot.fields.has(field),"actual_Source_Profile_UI_field_missing:"+str(field))
	return _snapshot.fields[field]
func accept_original_journal_snapshot(snapshot: Dictionary) -> bool:
	if _owner!=OS.get_main_thread_id() or OS.get_thread_caller_id()!=_owner or snapshot.get("contract_id")!="world.profile.actual_Source_read_view.v1" or not snapshot.get("fields") is Dictionary or not snapshot.get("queries") is Dictionary: return false
	if not snapshot.get("sequence") is int or snapshot.sequence<=_serial and not _snapshot.is_empty(): return snapshot==_snapshot
	if not _snapshot.is_empty():
		if snapshot.session_id!=_snapshot.session_id or snapshot.handoff_identity!=_snapshot.handoff_identity: return false
		if snapshot.profile_model_id!=_snapshot.profile_model_id and not (_snapshot.origin=="actual_Main_loaded_before_adoption" and snapshot.origin=="actual_S_adopted_owner"): return false
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary=graph.capture(snapshot,true,false)
	if captured.get("success")!=true: return false
	_snapshot=captured.value;_serial=snapshot.sequence
	profile_changed.emit();inventory_changed.emit();equipment_changed.emit();skills_changed.emit();quests_changed.emit()
	return true
func experience_to_next_level() -> int: return _snapshot.queries.experience_to_next_level
func item_count_by_entity_id(id: String) -> int: return int(_snapshot.queries.item_counts.get(id,0))
func current_bich_quest_id() -> String: return _snapshot.queries.current_bich_quest_id
func quest_objective_lines(id: String) -> Array[String]:
	var result: Array[String]=[]
	if not _snapshot.queries.quest_lines.has(id): return result
	result.assign(_snapshot.queries.quest_lines[id]);return result
func skill_button_assignments_snapshot() -> Dictionary: return _snapshot.queries.skill_button_assignments_snapshot
func skill_name_for_slot(group: String, slot: int) -> String:
	var key: String="%s:%d" % [group,slot]
	assert(_snapshot.queries.slot_names.has(key),"actual_Source_skill_slot_read_missing")
	return str(_snapshot.queries.slot_names[key])

static func original_handoff_identity(handoff: Dictionary) -> String:
	var witness: Dictionary=handoff.get("source_witness",{})
	if not witness.get("model_object_id") is int or witness.model_object_id==0 or not handoff.get("active_profile_id") is String or not handoff.get("source_model_sha256") is String: return ""
	var disk: Dictionary=witness.get("profile_document",{})
	var shared: Dictionary=witness.get("shared_document",{})
	if not disk.get("bytes_sha256") is String or disk.bytes_sha256.length()!=64 or not shared.get("bytes_sha256") is String or shared.bytes_sha256.length()!=64: return ""
	return JSON.stringify([handoff.source_model_sha256,handoff.active_profile_id,witness.model_object_id,disk.bytes_sha256,shared.bytes_sha256]).sha256_text()
static func capture_original_main_loaded(profile: RefCounted, handoff: Dictionary, actual_budget_session_id: int, world: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	var identity:=original_handoff_identity(handoff)
	if identity.is_empty() or actual_budget_session_id<=0 or profile==null or profile.get_script()!=preload("res://scripts/gameplay/profile/profile_model.gd") or profile._owner_thread_id!=OS.get_main_thread_id() or not profile._configured: return {}
	if handoff.source_witness.model_object_id!=profile.get_instance_id() or handoff.active_profile_id!=profile.active_profile_id or handoff.source_witness.actual_load_receipt!=profile.last_load_result or profile._runtime_port.profile_is_owned_by_gameplay(): return {}
	# The original handoff transports the sole stored _profession_id. Both
	# public profession properties are derived getters, not stored fields in
	# that document. Compare the authority, then capture those actual getters.
	for name: String in ["_profession_id","gender","equipment","level","experience","gold","computed_stats","inventory","quest_states","quick_slots"]:
		if handoff.source_fields.get(name)!=profile.get(name): return {}
	return _capture_profile(profile,GameData.item_entity_id,{"session_id":actual_budget_session_id,"sequence":0,"world_context":world,"handoff_identity":identity,"origin":"actual_Main_loaded_before_adoption"})
static func capture_actual_owner(core: RefCounted, sequence: int) -> Dictionary:
	assert(OS.get_thread_caller_id()!=OS.get_main_thread_id() and core.owner_thread_id()==OS.get_thread_caller_id())
	var session: RefCounted=core.original_source_session()
	var identity: String=session.original_profile_handoff_identity()
	if identity.is_empty() or sequence<=0: return {}
	return _capture_profile(core.profile,core.owner_services.GameData.item_entity_id,{"session_id":session.original_budget_session_id(),"sequence":sequence,"world_context":core.current_world_identity(),"handoff_identity":identity,"origin":"actual_S_adopted_owner"})
static func _capture_profile(profile: RefCounted, item_id: Callable, header: Dictionary) -> Dictionary:
	var fields: Dictionary={}
	for name: String in ["profession","profession_id","gender","equipment","level","experience","gold","computed_stats","inventory","quest_states","quick_slots"]: fields[name]=profile.get(name)
	var counts: Dictionary={}
	for raw: Variant in profile.inventory:
		if not raw is Dictionary: continue
		var id: String=item_id.call(raw)
		if not id.is_empty(): counts[id]=profile.item_count_by_entity_id(id)
	var current: String=profile.current_bich_quest_id()
	var lines: Dictionary={}
	for id: String in profile.quest_states.keys(): lines[id]=profile.quest_objective_lines(id)
	if not current.is_empty(): lines[current]=profile.quest_objective_lines(current)
	var slots: Dictionary={}
	var assignments: Dictionary=profile.skill_button_assignments_snapshot()
	for group: String in [profile.SKILL_SLOT_GROUP_CENTER,profile.SKILL_SLOT_GROUP_ATTACK,profile.SKILL_SLOT_GROUP_ATTACK_RING]:
		var actual_slots: Array=profile.skill_slots_for_group(group)
		for i: int in range(actual_slots.size()): slots["%s:%d" % [group,i]]=profile.skill_name_for_slot(group,i)
	var queries: Dictionary={"experience_to_next_level":profile.experience_to_next_level(),"item_counts":counts,"current_bich_quest_id":current,"quest_lines":lines,"slot_names":slots,"skill_button_assignments_snapshot":assignments}
	var snapshot: Dictionary=header.duplicate(true)
	snapshot.merge({"contract_id":"world.profile.actual_Source_read_view.v1","profile_model_id":profile.get_instance_id(),"fields":fields,"queries":queries})
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var copied: Dictionary=graph.capture(snapshot,true,false)
	return copied.value if copied.get("success")==true else {}
