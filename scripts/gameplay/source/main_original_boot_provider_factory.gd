extends RefCounted
## Fixed real Main capture classes. External owners remain explicit: this
## constructor does not fill absent identities, Loading proofs or pin facts.
const Publisher:=preload("res://scripts/gameplay/source/main_original_boot_publisher.gd")
const Blueprint:=preload("res://scripts/gameplay/source/main_original_blueprint_provider.gd")
const WorldPublication:=preload("res://scripts/gameplay/source/main_original_world_publication_provider.gd")
const SessionPublication:=preload("res://scripts/gameplay/source/main_original_session_publication_provider.gd")
const LoadingPins:=preload("res://scripts/gameplay/source/main_original_loading_pin_provider.gd")
const Config:=preload("res://scripts/gameplay/source/main_original_host_config_provider.gd")
const Observe:=preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
static func create_main(host: Object,facade: Node,actual: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or host==null or not host.is_class("HardCoreSimulationHost") or not is_instance_valid(facade) or not facade.is_inside_tree():return Observe.missing("actual_Main_Host_facade_required")
	var required: Dictionary={"launch_loading":["capture_actual_original_launch_loading_scope"],"root_transport":["verify_actual_original_source_root_launch","verify_actual_Main_physics_constructor_preflight","bind_actual_original_source_root","original_source_root_ready","service_original_source_world_main_views","submit_original_world_hud_event","submit_original_root_notification","submit_original_root_ui_cancel","record_actual_original_source_root_exit"],"world_identity":["capture_actual_original_prepared_world_identity"],"world_assembly":["capture_actual_original_world_loading_assembly"],"session_fields":["capture_actual_original_selected_session_fields"],"physical_pin_closure":["inspect_actual_original_world_loading_pins","release_actual_original_world_loading_pins"],"host_policy":["capture_actual_original_host_policy"],"caster_executor":["inspect_actual_original_loading_pins","release_original_loading_pin_closure"],"feature_main":["export_boot_value"]}
	var missing: Array[String]=[]
	for key: String in required:
		var owner: Variant=actual.get(key)
		if not owner is RefCounted:missing.append(key+":actual_Main_owner");continue
		if key not in ["feature_main","caster_executor"] and (not owner.has_method("owner_thread_id") or owner.owner_thread_id()!=OS.get_main_thread_id()):missing.append(key+":actual_Main_thread");continue
		for method: String in required[key]:
			if not owner.has_method(method):missing.append(key+"."+method)
	if actual.get("feature_main") is RefCounted and actual.feature_main.get_script()!=preload("res://scripts/features/runtime/feature_resource_main_primitives.gd"):missing.append("actual_fixed_Feature_Main_script")
	if actual.get("caster_executor") is RefCounted and actual.caster_executor.get_script()!=preload("res://scripts/gameplay/world/world_caster_main_executor.gd"):missing.append("actual_fixed_Caster_Main_script")
	for key: String in ["canonical_prepared","catalog_lease","feature_publication"]:
		if not actual.get(key) is Dictionary:missing.append(key+":actual_publication")
	if not missing.is_empty():return Observe.missing("actual_Main_boot_producers_unavailable",{"required":missing,"engine_clock":Observe.engine(facade.get_tree()),"project_settings":Observe.settings()})
	var blueprint: RefCounted=Blueprint.new()
	if not blueprint.configure_main(host,actual.launch_loading,actual.root_transport,actual.world_identity):return Observe.missing("actual_blueprint_capture_configuration")
	var world: RefCounted=WorldPublication.new()
	if not world.configure_main(actual.world_assembly):return Observe.missing("actual_World_capture_configuration")
	var session: RefCounted=SessionPublication.new()
	if not session.configure_main(facade,actual.feature_main,actual.canonical_prepared,actual.catalog_lease,actual.feature_publication,actual.session_fields):return Observe.missing("actual_Session_capture_configuration")
	var pins: RefCounted=LoadingPins.new()
	if not pins.configure_main(actual.caster_executor,actual.physical_pin_closure):return Observe.missing("actual_pin_capture_configuration")
	var config: RefCounted=Config.new()
	if not config.configure_main(actual.host_policy):return Observe.missing("actual_Host_policy_configuration")
	var publisher: RefCounted=Publisher.new()
	var configured: Dictionary=publisher.configure_main(host,facade,blueprint,world,session,pins,config)
	if configured.get("success")!=true:return configured
	return {"success":true,"publisher":publisher,"blueprint":blueprint,"world_publications":world,"session_publications":session,"pins":pins,"config":config}

## Construct the concrete Main application roles, retaining the existing real
## Feature vault/Caster executor and original published catalog/schema values.
## Source/physics admission is not implied by creating or registering this entry.
static func create_application_main(host: Object, facade: Node, existing: Dictionary, explicit_policy: Dictionary) -> Dictionary:
	var application: RefCounted = load("res://scripts/gameplay/source/main_boot_application.gd").new()
	var configured: Dictionary = application.configure_main(host,facade,existing,explicit_policy)
	if configured.get("success") != true: return configured
	var composed: Dictionary = create_main(host,facade,application.actual_producers())
	if composed.get("success") != true: return composed
	if not application.retain_actual_factory_assembly(composed): return Observe.missing("actual_Main_application_assembly_retention")
	var channels: Dictionary = application.compose_actual_original_main_channels()
	if channels.get("success") != true:
		# Retain the precise partial graph. Native bindings and actual listener
		# owners cannot be discarded or replaced by a second preparation graph.
		return {"success":false,"status":channels.get("status","INVALID"),"error":"actual_Main_application_channel_composition_failed","details":channels,"application":application,"assembly":composed}
	var result: Dictionary = composed.duplicate(false)
	result.application = application
	return result
