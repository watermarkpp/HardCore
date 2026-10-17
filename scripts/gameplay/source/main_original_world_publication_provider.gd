extends RefCounted
const Observe:=preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
var _assembler: RefCounted
func owner_thread_id() -> int:return OS.get_main_thread_id()
func configure_main(actual_assembler: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _assembler!=null or actual_assembler==null or actual_assembler.get_script() == null or actual_assembler.get_script().resource_path != "res://scripts/gameplay/source/main_boot_application.gd" or not actual_assembler.has_method("capture_actual_original_world_loading_assembly"):return false
	_assembler=actual_assembler;return true
func capture_original_prepared_world_boot(blueprint: Dictionary,prepared: Dictionary) -> Dictionary:
	var root: Variant=blueprint.get("root")
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not root is Node2D or not root.is_inside_tree() or root.get_script()!=preload("res://scripts/game_root.gd") or root.get("_original_source_main_attachment")==null:return Observe.missing("actual_guarded_prepared_Main_root")
	var observed: Dictionary={"root_scope_observation":Observe.node(root),"actual_current_map_id":root.get("current_map_id"),"actual_zone_generation":root.get("_zone_generation"),"engine_clock":Observe.engine(root.get_tree())}
	if _assembler==null:return Observe.missing("actual_full_World_Loading_assembly_producer",observed)
	var actual: Dictionary=_assembler.capture_actual_original_world_loading_assembly(blueprint,prepared)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"ACTUAL_WORLD_ASSEMBLER_RETURNED")
	if actual.get("success")!=true: return actual
	if not actual.get("world_boot") is Dictionary:return Observe.missing("actual_World_Loading_assembly_incomplete",observed)
	var boot: Dictionary=actual.world_boot
	if boot.get("world_identity")!=blueprint.get("world") or not boot.get("assembly") is Dictionary:return Observe.missing("actual_same_prepared_world_assembly",observed)
	var front: Dictionary = _assembler.get("_session_front")
	if not boot.assembly.get("owner_session_id") is int or boot.assembly.owner_session_id <= 0 or boot.assembly.owner_session_id != front.get("session_id"): return Observe.missing("actual_same_persistent_Session_World_owner",observed)
	for key: String in ["profile_publication","profile_state","content_snapshot","feature_resource_boot"]:
		if boot.assembly.has(key): return Observe.missing("persistent_Session_publication_must_not_be_republished_by_Core:"+key,observed)
	for key: String in ["source_scopes","initial_input","action_timing","world_random","streaming_catalog","visual_catalog","service_birth_scopes","source_domain_publication","source_fields","monster_inputs","source_documents","bootstrap_source_site"]:
		if not boot.assembly.get(key) is Dictionary:return Observe.missing("actual_Core_assembly_field:"+key,observed)
	for key: String in ["game_root","player_state","background"]:
		if not boot.assembly.source_scopes.get(key) is Dictionary:return Observe.missing("actual_Core_source_scope:"+key,observed)
	for key: String in ["seed","state"]:
		if not boot.assembly.world_random.get(key) is int:return Observe.missing("actual_original_World_RNG_state:"+key,observed)
	if not boot.assembly.get("journal_generation") is int or boot.assembly.journal_generation<=0:return Observe.missing("actual_Core_journal_generation",observed)
	if not boot.assembly.source_domain_publication.get("time_domains_simulation_seconds") is float:return Observe.missing("actual_original_TimeDomains_state",observed)
	if not boot.get("project_settings") is Dictionary or not boot.project_settings.has(preload("res://scripts/runtime_combat_spatial_index.gd").BUCKET_SIZE_SETTING):return Observe.missing("actual_original_spatial_bucket_setting",observed)
	if not actual.get("loading_pin_closure") is Dictionary:return Observe.missing("actual_world_Loading_pin_closure",observed)
	# The exact production assembler has already Native-captured and recursively
	# sealed this graph. Reuse that same immutable publication; final Host boot
	# still performs its independent owned Native capture before Source startup.
	# No mutable/unrecognized producer obtains this reuse path.
	var retained: Dictionary = _assembler.get("_world_assembly_result")
	if retained.get("success") != true or not is_same(retained.get("world_boot"),boot) or not boot.is_read_only(): return Observe.missing("actual_retained_immutable_World_assembly_required",observed)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"WORLD_PROVIDER_REUSED_ACTUAL_SEALED_GRAPH")
	return {"success":true,"world_boot":boot,"loading_pin_closure":actual.loading_pin_closure}
