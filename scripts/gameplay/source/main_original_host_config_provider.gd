extends RefCounted
const Observe:=preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
var _policy: RefCounted
func owner_thread_id() -> int:return OS.get_main_thread_id()
func configure_main(actual_policy: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _policy!=null:return false
	if actual_policy==null or not actual_policy.has_method("capture_actual_original_host_policy"):return false
	_policy=actual_policy;return true
func capture_actual_original_source_host_config(host: Object,blueprint: Dictionary,prepared: Dictionary) -> Dictionary:
	var root: Variant=blueprint.get("root")
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not root is Node2D or not root.is_inside_tree() or host==null or not host.is_class("HardCoreSimulationHost"):return Observe.missing("actual_Main_Host_root_required")
	var current: Dictionary=Observe.engine(root.get_tree())
	var deferred: Dictionary=preload("res://scripts/gameplay/source/main_source_admission.gd").capture_original_source_deferred_configuration()
	var observed: Dictionary={"engine_clock":current,"source_deferred":deferred,"project_settings":Observe.settings()}
	if _policy==null:return Observe.missing("actual_Host_generation_capacity_policy_producer_required",observed)
	var supplied: Dictionary=_policy.capture_actual_original_host_policy(host,blueprint,prepared)
	if supplied.get("success")!=true or not supplied.get("policy") is Dictionary:return Observe.missing("actual_original_Host_policy_rejected",observed)
	var policy: Dictionary=supplied.policy
	if policy.get("host_object_id")!=host.get_instance_id() or supplied.get("prepared_receipt")!=prepared.get("receipt"):return Observe.missing("actual_Host_policy_incarnation_or_prepared_receipt",observed)
	var config: Dictionary={}
	for key: String in ["bridge_generation","primitive_request_capacity","primitive_result_capacity","max_epochs_per_turn","timer_capacity","input_capacity","event_capacity","live_primitive_capacity"]:
		if not policy.get(key) is int or policy[key]<=0:return Observe.missing("actual_positive_Host_policy:"+key,observed)
		config[key]=policy[key]
	if config.live_primitive_capacity>config.event_capacity:return Observe.missing("actual_Host_live_capacity_exceeds_event_capacity",observed)
	config.physics_hz=current.physics_hz;config.source_process_frame=current.source_process_frame;config.source_physics_frame=current.source_physics_frame;config.source_deferred_max_pages=deferred.source_deferred_max_pages
	if config.physics_hz<=0 or config.source_deferred_max_pages<=0:return Observe.missing("actual_Engine_deferred_config_invalid",observed)
	return {"success":true,"config":config,"actual_engine_clock":current,"actual_policy_receipt":supplied}
