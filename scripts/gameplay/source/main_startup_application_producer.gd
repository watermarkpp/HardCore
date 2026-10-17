extends RefCounted
## Main owns this preparation graph for the entire launch transaction. A failed
## composition stays retained; it never resumes Main after Source admission.
const Application := preload("res://scripts/gameplay/source/main_boot_application.gd")
const Factory := preload("res://scripts/gameplay/source/main_original_boot_provider_factory.gd")
const Canonical := preload("res://scripts/gameplay/profile/profile_publication.gd")
const Catalog := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Published := preload("res://scripts/gameplay/content/published_static_catalogs.gd")
const Feature := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd")
const Facade := preload("res://scripts/features/runtime/feature_resource_main_facade.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Caster := preload("res://scripts/gameplay/world/world_caster_main_executor.gd")
var _facade: Node
var _content: Node
var _host: Object
var _physical: Node
var _feature: RefCounted
var _caster: RefCounted
var _catalog_lease: Dictionary = {}
var _canonical: Dictionary = {}
var _assembly: Dictionary = {}
var _stage := "NEW"
var _receipt: Dictionary = {}

static func original_phone_host_policy() -> Dictionary:
	# Bounded transport storage, not a CPU-core or monster cadence policy.
	# The two live lanes already share Session accounting; actual elapsed cost
	# and backpressure remain authoritative on the phone as on the PC.
	# SceneTree timers were not capped at the fixture count16. TimerLedger is
	# an on-demand std::list; this signed32bit identity bound allocates no
	# spare timers and preserves the original practical creation semantics.
	# The real empty-character admission already serializes to81056bytes.
	# Small component fixtures used64KiB, which cannot carry even that receipt.
	#4MiB is the explicit production wire ceiling for Profile/warehouse/lease
	# transactions. Three pre-reserved result slots cost12MiB; packet counts,
	# FIFO/backpressure, deadlines and all identity checks remain unchanged.
	return {"bridge_generation":115171,"primitive_request_capacity":4*1024*1024,"primitive_result_capacity":4*1024*1024,"max_epochs_per_turn":8,"timer_capacity":2147483647,"input_capacity":16,"event_capacity":32,"live_primitive_capacity":2}

func owner_thread_id() -> int: return OS.get_main_thread_id()
func _fail(error: String, details: Dictionary = {}) -> Dictionary:
	_receipt = {"success":false,"status":"BLOCKED","error":error,"stage":_stage,"details":details,"actual_producer_id":get_instance_id()}
	return _receipt.duplicate(true)

func prepare_main(facade: Node, explicit_policy: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _stage != "NEW" or not is_instance_valid(facade) or not facade.is_inside_tree() or facade != facade.get_tree().root.get_node_or_null("PlayerState"): return _fail("actual_once_Main_PlayerState_required")
	var checked: Dictionary = Application.validate_actual_host_policy(explicit_policy)
	if checked.get("success") != true: return _fail("actual_explicit_Host_policy_required",checked)
	if not ClassDB.class_exists("HardCoreSimulationHost") or not ClassDB.class_exists("HardCoreResourceObservation"): return _fail("actual_matching_Native_engine_required")
	_facade = facade; _content = facade.get_tree().root.get_node_or_null("ContentLayers")
	var gate: Variant = facade.get("_source_domain_gate")
	if _content == null or (gate != null and gate.state() != "MAIN") or facade.get_tree().root.has_meta(Application.ENTRY_META): return _fail("actual_unadmitted_Main_startup_required")
	_set_stage("ORIGINAL_FEATURE_PREPARATION")
	if not _content.is_loaded() or not GameData.is_loaded() or not _content.ensure_feature_catalog(): return _fail("actual_loaded_original_content_required")
	var legacy: Node = _content._feature_resources()
	if not is_instance_valid(legacy) or legacy.get_script() != preload("res://scripts/features/runtime/feature_resource_preparation.gd"): return _fail("actual_original_lazy_Feature_service_required")
	var original_profile: String = str(facade.get("active_profile_id"))
	var configuration: Dictionary = _content.feature_configuration()
	var plan: Dictionary = Lease.requirements(configuration.catalog,configuration.enabled_modules)
	if plan.get("success") != true: return _fail("actual_original_feature_requirements_failed",plan)
	var original_lease: Variant = configuration.get("resource_lease")
	if not plan.paths.is_empty() and (not original_lease is RefCounted or not original_lease.valid_for(configuration.catalog,configuration.enabled_modules)):
		if not await _content.reload_feature_catalog_async(): return _fail("actual_original_feature_preparation_failed",{"errors":_content.get("feature_load_errors")})
		configuration = _content.feature_configuration()
		plan = Lease.requirements(configuration.catalog,configuration.enabled_modules)
		original_lease = configuration.get("resource_lease")
	if not is_instance_valid(facade) or str(facade.get("active_profile_id")) != original_profile: return _fail("actual_selected_profile_changed_during_Main_preparation")
	_set_stage("CANONICAL_PUBLICATION")
	_canonical = Canonical.prepare_canonical()
	if _canonical.get("success") != true: return _fail("actual_canonical_profile_preparation_failed",_canonical)
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	_physical = Facade.new(); _physical.name = "HardCoreMainFeatureResources"
	_content.add_child(_physical)
	_feature = Feature.new()
	if not _feature.configure_original_source_owned_main(_physical,ClassDB.instantiate("HardCoreResourceObservation"),Callable(_host,"validate_original_primitive_ticket"),checked.policy.bridge_generation) or not _physical.configure_main(_feature): return _fail("actual_physical_Feature_vault_configuration_failed")
	var publication: Dictionary = {}
	if original_lease != null:
		publication = _feature.publish_actual_resource_lease(original_lease,plan)
		if publication.is_empty(): return _fail("actual_existing_Feature_lease_publication_failed")
	_catalog_lease = Published.acquire()
	if not Catalog.is_active(_catalog_lease): return _fail("actual_unique_catalogue_publication_failed")
	_caster = Caster.new()
	var services: Dictionary = {"feature_main":_feature,"caster_executor":_caster,"canonical_prepared":_canonical,"catalog_lease":_catalog_lease,"feature_publication":publication,"feature_live_reservation_usec":Application.actual_feature_reservation_policy(),"streaming_live_reservation_usec":Application.actual_streaming_reservation_policy(),"original_warm_reservation_usec":0}
	_set_stage("MAIN_CHANNEL_COMPOSITION")
	_assembly = Factory.create_application_main(_host,_facade,services,checked.policy)
	if _assembly.get("success") != true: return _fail("actual_Main_application_composition_failed",_assembly)
	var installed: Dictionary = _assembly.application.install_actual_launch_entry()
	if installed.get("success") != true: return _fail("actual_Main_application_entry_installation_failed",installed)
	_set_stage("MAIN_CHANNELS_BOUND")
	_receipt = {"success":true,"stage":_stage,"actual_producer_id":get_instance_id(),"actual_host_id":_host.get_instance_id(),"actual_application_id":_assembly.application.get_instance_id(),"launch_readiness":installed.preparation}
	return _receipt.duplicate(true)

func actual_application() -> RefCounted: return _assembly.get("application")
func actual_host() -> Object: return _host
func actual_receipt() -> Dictionary: return _receipt.duplicate(true)

func _set_stage(value: String) -> void:
	_stage = value
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,value)

func retire_actual_unstarted_preparation() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _stage != "MAIN_CHANNELS_BOUND" or _assembly.get("success") != true or _host == null: return _fail("actual_bound_unstarted_preparation_required")
	var retired: Dictionary = _assembly.application.retire_actual_uncommitted_entry()
	if retired.get("success") != true: return _fail("actual_unstarted_application_retirement_failed",retired)
	if not Published.release_after_host_quiescence(_catalog_lease): return _fail("actual_Native_aborted_catalogue_retirement_failed",retired)
	if is_instance_valid(_physical): _physical.free()
	_assembly = {}; _canonical = {}; _catalog_lease = {}
	_feature = null; _physical = null; _caster = null; _host = null
	_set_stage("RETIRED_BEFORE_START")
	return retired

func retire_actual_started_terminal_preparation(application: RefCounted, receipt: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _stage != "MAIN_CHANNELS_BOUND" or application == null or not is_same(actual_application(),application) or not application.verify_actual_started_terminal_owner_retirement(self,receipt) or _host == null: return _fail("actual_same_started_terminal_application_required")
	var native: Dictionary = _host.status()
	if native.get("close_quiescent") != true or native.get("join_complete") != true or native.get("running") != false or not Published.release_after_host_quiescence(_catalog_lease): return _fail("actual_started_catalogue_reader_quiescence_required")
	if is_instance_valid(_physical): _physical.free()
	_assembly = {}; _canonical = {}; _catalog_lease = {}
	_feature = null; _physical = null; _caster = null; _host = null
	_stage = "RETIRED_AFTER_CLOSE"
	return {"success":true,"status":"READY","actual_producer_id":get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames()}
