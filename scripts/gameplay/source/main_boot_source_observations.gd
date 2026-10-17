extends RefCounted
const SpatialIndex:=preload("res://scripts/runtime_combat_spatial_index.gd")
const FrameBudget:=preload("res://scripts/layers/runtime/execution/frame_budget.gd")
static func missing(code: String,observed: Dictionary={}) -> Dictionary:return {"success":false,"status":"MISSING","error":code,"actual_observed":observed}
static func capture(value: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not ClassDB.class_exists("HardCoreContentValueGraph"):return missing("actual_Main_native_capture_required")
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var started: int = Time.get_ticks_usec()
	var actual: Dictionary=graph.capture(value,true,false)
	if ProjectSettings.get_setting("hardcore/diagnostics/main_boot_trace",false) and int(actual.get("nodes",0)) > 100000:
		print("HC_MAIN_BOOT_GRAPH_CAPTURE ",JSON.stringify({"nodes":actual.get("nodes"),"memo_entries":actual.get("memo_entries"),"success":actual.get("success"),"elapsed_usec":Time.get_ticks_usec()-started}))
	return {"success":true,"publication":actual.value} if actual.get("success")==true else missing("actual_nonplain_Main_boot_observation",actual)
static func engine(tree: SceneTree) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or tree==null:return {}
	return {"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"paused":tree.paused,"max_physics_steps_per_frame":Engine.max_physics_steps_per_frame,"physics_jitter_fix":Engine.physics_jitter_fix,"observed_usec":Time.get_ticks_usec()}
static func settings() -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id():return {}
	var values: Dictionary = {SpatialIndex.BUCKET_SIZE_SETTING:float(ProjectSettings.get_setting(SpatialIndex.BUCKET_SIZE_SETTING,SpatialIndex.DEFAULT_BUCKET_SIZE_GU)),"hardcore/performance/frame_optional_budget_usec":int(ProjectSettings.get_setting("hardcore/performance/frame_optional_budget_usec",FrameBudget.DEFAULT_BUDGET_USEC)),"hardcore/performance/frame_progress_budget_usec":int(ProjectSettings.get_setting("hardcore/performance/frame_progress_budget_usec",FrameBudget.DEFAULT_PROGRESS_BUDGET_USEC)),"physics/common/physics_ticks_per_second":ProjectSettings.get_setting("physics/common/physics_ticks_per_second"),"physics/common/max_physics_steps_per_frame":ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame"),"hardcore/diagnostics/main_boot_trace":bool(ProjectSettings.get_setting("hardcore/diagnostics/main_boot_trace",false))}
	# Capture the whole custom namespace, including proof that other custom
	# settings were absent. S can then use the ORIGINAL caller's fallback for
	# an absent key without inventing or duplicating gameplay defaults here.
	for property: Dictionary in ProjectSettings.get_property_list():
		var name: String = property.name
		if name.begins_with("hardcore/") and ProjectSettings.has_setting(name): values[name] = ProjectSettings.get_setting(name)
	values["__hardcore_source_settings_capture__"] = {"contract_id":"hardcore.settings.complete_namespace.v1","prefix":"hardcore/"}
	return values
static func node(node: Node) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not is_instance_valid(node):return {}
	var mode: int=node.process_mode;var ancestor: Node=node
	while mode==Node.PROCESS_MODE_INHERIT and ancestor.get_parent()!=null:
		ancestor=ancestor.get_parent();mode=ancestor.process_mode
	if mode==Node.PROCESS_MODE_INHERIT:mode=Node.PROCESS_MODE_PAUSABLE # pinned Node fallback
	var script: Script=node.get_script()
	return {"actual_node_id":node.get_instance_id(),"script_path":script.resource_path if script!=null else "","loaded_script_sha256":script.get_source_code().sha256_text() if script!=null else "","runtime_present":true,"inside_world":node.is_inside_tree(),"queued_for_retirement":node.is_queued_for_deletion(),"parent_scope_id":node.get_parent().get_instance_id() if node.get_parent()!=null else 0,"can_process":node.can_process() if node.is_inside_tree() else false,"process_processing_enabled":node.is_processing(),"physics_processing_enabled":node.is_physics_processing(),"ordinary_p_enabled":node.has_method("_process"),"raw_h_enabled":node.has_method("_physics_process"),"process_priority":node.process_priority,"physics_priority":node.process_physics_priority,"process_mode":node.process_mode,"effective_process_mode":mode,"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames()}
