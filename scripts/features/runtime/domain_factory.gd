extends RefCounted

const Context := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Combat := preload("res://scripts/features/runtime/domain_combat_port.gd")
const Clock := preload("res://scripts/features/runtime/domain_clock_port.gd")
const Cues := preload("res://scripts/features/presentation/domain_presentation_port.gd")
const Controller := preload("res://scripts/features/runtime/domain_controller.gd")
const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const Profile := preload("res://scripts/gameplay/profile/profile_model.gd")
const Resources := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Child := preload("res://scripts/features/contracts/child_action_lease.gd")
const REQUIRED_OWNER_METHODS := ["feature_world_is_active", "feature_world_paused", "feature_actor_in_owner_scope", "feature_actor_commit_projection",
	"feature_budget_mark_pending", "feature_budget_begin", "feature_budget_end", "feature_simulation_usec",
	"retain_feature_resource_publication", "release_feature_resource_retention", "feature_resource_retention_supports_path",
	"enqueue_feature_presentation", "feature_cue_is_supported", "feature_action_resource_lease",
	"feature_child_plan_context", "feature_child_query_actor_ids", "execute_feature_child_action", "fault"]

static func validate_required(owner: RefCounted, registry: RefCounted, profile: RefCounted) -> Dictionary:
	var errors: Array[String] = []
	if OS.get_thread_caller_id() == OS.get_main_thread_id(): errors.append("real_simulation_owner_required")
	if owner == null or owner is Resource: errors.append("owner_local_world_core_required")
	if not registry is Registry or not profile is Profile: errors.append("canonical_registry_and_profile_required")
	if not errors.is_empty(): return {"success":false,"errors":errors}
	for method: String in REQUIRED_OWNER_METHODS:
		if not owner.has_method(method): errors.append("missing_owner_service:"+method)
	if registry.capture_world().is_empty() or profile._owner_thread_id != OS.get_thread_caller_id() or not profile._configured or not profile._content_port.simulation_owner:
		errors.append("configured_same_s_identity_profile_required")
	if not registry.capture_world().is_empty() and profile.active_profile_id != registry.capture_world().profile_id: errors.append("feature_profile_identity_mismatch")
	for name: String in ["_mode_port", "_runtime_port", "_diagnostics_port"]:
		var port: Variant = profile.get(name)
		if not port is RefCounted or (port.get_script() != null and "legacy_" in str(port.get_script().resource_path)): errors.append("main_profile_port_forbidden:"+name)
	if profile._feature_port == null or profile._feature_port._source is Node: errors.append("main_feature_owner_forbidden")
	if not Gate.has_active_reader(): errors.append("published_catalog_reader_required")
	var declared: Dictionary = Resources.declarations()
	if not declared.success or not Resources._result.is_read_only(): errors.append("feature_resource_catalog_not_published")
	if not Child._catalog_attempted or Child._definitions.is_empty() or not Child._definitions.is_read_only(): errors.append("child_definitions_not_published")
	return {"success":errors.is_empty(),"errors":errors}

static func create(owner: RefCounted, registry: RefCounted, profile: RefCounted, existing_world: RefCounted = null) -> Dictionary:
	var checked := validate_required(owner,registry,profile)
	if not checked.success: return checked
	var world: RefCounted = existing_world if existing_world != null else Context.new()
	if existing_world == null:
		if not world.configure_domain(registry,owner): return {"success":false,"errors":["feature_world_context_rejected"]}
	elif world.get_script() != Context or world.get("_domain_registry") != registry or world.current_effect_owner() != owner:
		return {"success":false,"errors":["feature_existing_world_context_rejected"]}
	var clock := Clock.new(owner)
	var combat := Combat.new(world)
	var cues := Cues.new(world)
	var runtime := Runtime.new()
	if not runtime.configure(world,clock,combat,cues): return {"success":false,"errors":["feature_runtime_domain_rejected"]}
	if not runtime.configure_child_executor(Callable(owner,"execute_feature_child_action")): return {"success":false,"errors":["feature_child_executor_rejected"]}
	var controller := Controller.new(owner,profile,world,clock,runtime,combat,cues)
	return {"success":true,"controller":controller,"world":world,"clock":clock,"combat":combat,"presentation":cues,"runtime":runtime}
