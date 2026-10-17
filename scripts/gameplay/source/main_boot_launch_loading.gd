extends RefCounted
## Main observations of the ORIGINAL opaque overlay and physical code lease.
## Capturing this scope never starts a second Loading state machine.
const Observe := preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const EntryData := preload("res://scripts/features/generated/internal_code_preparation_catalog_data.gd")
const Overlay := preload("res://scripts/loading_transition_overlay.gd")
var _tree: SceneTree
var _facade: Node
var _content: Node
var _receiver: WeakRef
var _lease: RefCounted
var _result: Dictionary
var _scope: Dictionary
var _code_transfer: Dictionary
var _code_root: WeakRef
var _initial_world_handoff: Dictionary
var _terminal_code_lease: WeakRef
var _terminal_code_release: Dictionary

func owner_thread_id() -> int: return OS.get_main_thread_id()

func configure_main(tree: SceneTree, facade: Node, content: Node) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _tree != null or tree == null: return false
	if facade != tree.root.get_node_or_null("PlayerState") or content != tree.root.get_node_or_null("ContentLayers"): return false
	_tree = tree; _facade = facade; _content = content
	return true

func capture_actual_original_launch_loading_scope(receiver: Node, result: Dictionary) -> Dictionary:
	if not _actual_receiver(receiver): return _blocked("actual_current_CharacterSelect_launch_required")
	if result != receiver.get("_launch_code_result") or result.get("success") != true: return _blocked("actual_original_code_result_required")
	var lease: Variant = result.get("lease")
	if not lease is RefCounted or lease.get_script() != Lease: return _blocked("actual_original_code_lease_required")
	if not _content.is_internal_code_retention_current(result, receiver): return _blocked("actual_original_code_retention_not_current")
	# The original internal-code entry retains CasterAnimation, separately from
	# the PackedScene's genuine GameRoot Script. resource_at() owns prepared
	# shader inputs; it never promised to contain either retained Script.
	var code: Variant = result.get("resource")
	if not code is Script or code.resource_path != EntryData.REGISTERED_TARGETS.get("framework.code.caster_animation.v1") or not is_same(lease.get("_retained_code_resource"),code): return _blocked("actual_original_retained_code_entry_required")
	var overlay: Variant = receiver.get("launch_loading_overlay")
	var presented: Dictionary = capture_original_presented_cover(overlay)
	if presented.get("success") != true: return presented
	var cover: Dictionary = presented.covered
	var observed: Dictionary = {"contract_id":"hardcore.main.launch_loading.scope.v1",
		"producer_runtime_id":get_instance_id(), "receiver_id":receiver.get_instance_id(),
		"facade_id":_facade.get_instance_id(), "code_lease_id":lease.get_instance_id(),
		"code_script_path":code.resource_path,"code_script_sha256":code.get_source_code().sha256_text(),
		"profile_id":str(receiver.get("selected_main_profile_id")),
		"launch_generation":receiver.get("_launch_code_generation"), "covered":cover,
		"source_process_frame":Engine.get_process_frames(), "source_physics_frame":Engine.get_physics_frames()}
	if not _scope.is_empty():
		if not is_same(_receiver.get_ref(), receiver) or not is_same(_lease, lease): return _blocked("actual_single_launch_Loading_owner_required")
		return verify_actual_original_loading_scope(_scope)
	var copied: Dictionary = Observe.capture(observed)
	if copied.get("success") != true: return copied
	_receiver = weakref(receiver); _lease = lease; _result = result; _scope = copied.publication
	return {"success":true, "scope":_scope.duplicate(true), "loading_scope":_scope.duplicate(true)}

func verify_actual_original_loading_scope(scope: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _scope.is_empty() or scope != _scope or _receiver == null: return _blocked("actual_captured_launch_scope_required")
	var receiver: Node = _receiver.get_ref()
	if not _actual_receiver(receiver) or receiver.get("_launch_code_generation") != scope.launch_generation: return _blocked("actual_launch_scope_retired")
	var overlay: Control = receiver.get("launch_loading_overlay")
	var consumer: Node = receiver
	if not _code_transfer.is_empty():
		consumer = _code_root.get_ref() if _code_root != null else null
		if not is_instance_valid(consumer) or consumer.get_instance_id() != _code_transfer.actual_root_id or _code_transfer.loading_scope != _scope: return _blocked("actual_transferred_code_consumer_retired")
	if not overlay.code_preparation_cover_current(scope.covered) or not _content.is_internal_code_retention_current(_result,consumer): return _blocked("actual_launch_cover_or_code_retention_changed")
	if receiver.get("_launch_code_result").get("lease") != _lease or _lease.get_instance_id() != scope.code_lease_id: return _blocked("actual_launch_code_lease_changed")
	var retained: Variant = _result.get("resource")
	if not retained is Script or retained.resource_path != scope.get("code_script_path") or retained.get_source_code().sha256_text() != scope.get("code_script_sha256") or not is_same(_lease.get("_retained_code_resource"),retained): return _blocked("actual_launch_retained_script_changed")
	return {"success":true, "scope":_scope.duplicate(true), "loading_scope":_scope.duplicate(true)}

func claim_actual_original_code_for_prepared_root(root: Node2D, feature: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _scope.is_empty() or not _code_transfer.is_empty() or feature == null or feature.get_script() != preload("res://scripts/features/runtime/feature_resource_main_primitives.gd") or not feature.is_executing_original_primitive(): return _blocked("actual_once_admitted_initial_code_transfer_required")
	if verify_actual_original_loading_scope(_scope).get("success") != true or actual_original_loading_scope(feature.get("_source_request").get("site",{}).get("world_context",{})) != _scope: return _blocked("actual_same_covered_Root_code_transfer_required")
	var receiver: Node = _receiver.get_ref()
	var physical_owner: Node = feature.get("_facade")
	if physical_owner == null or physical_owner.get_script() != preload("res://scripts/features/runtime/feature_resource_main_facade.gd") or not is_same(physical_owner.get("_primitives"),feature) or _content.get("_feature_resource_service") != physical_owner: return _blocked("actual_committed_physical_code_lease_owner_required")
	if not physical_owner.transfer_prepared_world_code_retention(_result,receiver,root,_scope): return _blocked("actual_prepared_Root_code_retention_transfer_failed")
	_code_root = weakref(root)
	_code_transfer = {"contract_id":"hardcore.main.initial_code_transfer.v1","loading_scope":_scope.duplicate(true),"actual_root_id":root.get_instance_id(),"actual_previous_id":receiver.get_instance_id(),"actual_lease_id":_lease.get_instance_id(),"actual_owner_id":physical_owner.get_instance_id(),"actual_primitive_identity":feature.get("_source_request").get("identity",{}).duplicate(true),"actual_Main_process_frame":Engine.get_process_frames()}
	# The same result retains the same Script/Shader lease; only its real
	# consumer moved through CodePlan.transfer_loaded_retention_context.
	return {"success":true,"status":"READY","result":_result.duplicate(false),"receipt":_code_transfer.duplicate(true)}

func _actual_receiver(receiver: Node) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _tree == null or not is_instance_valid(receiver): return false
	if receiver.get_script() != preload("res://scripts/character_select.gd") or receiver != _tree.current_scene or not receiver.is_inside_tree() or receiver.get_tree() != _tree or receiver.is_queued_for_deletion() or not receiver.get("_launch_in_progress"): return false
	var model: RefCounted = _facade.get("_model")
	return model != null and not str(model.get("active_profile_id")).is_empty() and model.get("active_profile_id") == receiver.get("selected_main_profile_id")

func captured_scope() -> Dictionary: return _scope.duplicate(true)

func finish_actual_original_world_handoff(root: Node2D, transport: RefCounted, views: RefCounted, registry: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _tree == null or _scope.is_empty() or not _initial_world_handoff.is_empty(): return _blocked("actual_once_initial_World_handoff_required")
	var receiver: Control = _receiver.get_ref() if _receiver != null else null
	if not is_instance_valid(receiver) or receiver != _tree.current_scene or receiver.get_script() != preload("res://scripts/character_select.gd") or not receiver.is_inside_tree() or receiver.is_queued_for_deletion() or not receiver.get("_launch_in_progress") or receiver.get("_launch_code_generation") != _scope.launch_generation: return _blocked("same_live_covered_CharacterSelect_required")
	if not is_instance_valid(root) or root.get_script() != preload("res://scripts/game_root.gd") or root.get_parent() != _tree.root or not root.is_inside_tree() or root.is_queued_for_deletion() or root.get("_original_source_main_attachment") == null: return _blocked("actual_guarded_same_Main_Root_required")
	if transport == null or transport.get_script() == null or transport.get_script().resource_path != "res://scripts/gameplay/source/main_session_transport.gd" or transport.get("_tree") != _tree or transport.get("_facade") != _facade or transport.get("_state") != "S" or int(transport.get("_model_id")) == 0: return _blocked("actual_adopted_S_transport_required")
	var host: Object = transport.get("_host")
	if host == null or not host.is_class("HardCoreSimulationHost"): return _blocked("actual_Native_Source_Host_required")
	var native: Dictionary = host.status()
	if native.get("started") != true or native.get("running") != true or native.get("close_requested") == true or not str(native.get("fault","")).is_empty() or _facade.get("_source_domain_gate").state() != "S": return _blocked("same_live_Source_owner_required")
	var world: Dictionary = transport.get("_world")
	if world.get("profile_id") != _scope.profile_id or world.get("profile_id") != receiver.get("selected_main_profile_id") or world.get("profile_id") != _facade.get("active_profile_id") or world.get("world_runtime_id") != root.get_instance_id() or world.get("runtime_map_id",-1) < 0 or world.get("world_epoch",0) <= 0 or root.get("current_map_id") != world.runtime_map_id or root.get("_zone_generation") != world.world_epoch: return _blocked("actual_same_Profile_first_map_arrival_required")
	if views == null or views.get_script() == null or views.get_script().resource_path != "res://scripts/gameplay/world/world_main_views.gd" or views.get("_root") != root or views.get("_world") != world or views.get("_transport") != transport: return _blocked("same_actual_Main_World_views_required")
	var arrival: Dictionary = views.get("_last_map_arrival")
	if arrival.get("after_world") != world or not host.verify_committed_original_map_arrival(arrival): return _blocked("actual_Native_committed_first_map_receipt_required")
	if registry == null or registry.get_script() == null or registry.get_script().resource_path != "res://scripts/gameplay/presentation/main_actor_visual_registry.gd" or views.get("_renderer_registry") != registry: return _blocked("actual_original_player_renderer_registry_required")
	var player: Node = registry.actual_original_player_view(world)
	if not is_instance_valid(player) or not player.is_inside_tree() or player.is_queued_for_deletion(): return _blocked("actual_original_player_view_required")
	if _code_transfer.is_empty() or _code_root == null or _code_root.get_ref() != root or _code_transfer.get("actual_root_id") != root.get_instance_id() or _code_transfer.get("loading_scope") != _scope or not _content.is_internal_code_retention_current(_result,root): return _blocked("actual_transferred_Root_code_retention_required")
	var overlay: Control = receiver.get("launch_loading_overlay")
	if not is_instance_valid(overlay) or not overlay.code_preparation_cover_current(_scope.covered): return _blocked("actual_current_opaque_initial_cover_required")
	# This is the already constructed guarded Root, never a second scene/model.
	# Keep the old receiver/producer alive and disabled until real terminal
	# cleanup: the original launch callback is still unwinding on this stack.
	# Its old code-result reference must not retire Root's transferred lease.
	receiver.set("_launch_code_result",{})
	_tree.current_scene = root
	overlay.hide(); receiver.hide(); receiver.process_mode = Node.PROCESS_MODE_DISABLED
	_initial_world_handoff = {"contract_id":"hardcore.main.initial_World_handoff.v1","world_context":world.duplicate(true),"actual_root_id":root.get_instance_id(),"actual_receiver_id":receiver.get_instance_id(),"actual_player_view_id":player.get_instance_id(),"actual_profile_model_id":transport.get("_model_id"),"actual_Main_process_frame":Engine.get_process_frames()}
	return {"success":true,"status":"READY","receipt":_initial_world_handoff.duplicate(true)}

func is_actual_retained_launch_receiver(receiver: Node) -> bool:
	# Disabled Nodes still receive Window notifications. The historical launcher
	# must not handle WM_CLOSE in parallel with the actual current Source Root.
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and not _initial_world_handoff.is_empty() and _receiver != null and is_instance_valid(receiver) and _receiver.get_ref() == receiver and receiver.get_instance_id() == _initial_world_handoff.get("actual_receiver_id")

func release_actual_original_terminal_code_observation(source_exit: Dictionary, feature: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _tree == null or feature == null or feature.get_script() != preload("res://scripts/features/runtime/feature_resource_main_primitives.gd") or not feature.is_executing_original_primitive(): return _blocked("actual_Main_admitted_code_release_required")
	var request: Dictionary = feature.get("_source_request")
	var root: Node2D = _code_root.get_ref() if _code_root != null else null
	var application: Variant = _tree.root.get_meta(&"hardcore_original_main_boot_application",null)
	if not application is RefCounted or not is_same(application.get("_loading"),self) or application.get("_actual_source_root_exit") != source_exit or application.get("_actual_caster_pins_released") != true or request.get("operation") != "feature.source_admission_release_pins" or source_exit.get("fact",{}).get("world_context") != request.get("site",{}).get("world_context") or not is_instance_valid(root) or not root.is_inside_tree() or root.get_instance_id() != source_exit.get("actual_root_id"): return _blocked("actual_same_Source_final_and_Caster_release_required")
	if _terminal_code_lease == null:
		if _lease == null or _lease.get_instance_id() != _code_transfer.get("actual_lease_id") or _lease.get("_original_physical_lease_id") != _lease.get_instance_id() or _code_transfer.get("actual_root_id") != root.get_instance_id() or _code_transfer.get("loading_scope") != _scope: return _blocked("actual_transferred_physical_code_lease_required")
		var physical_owner: Node = feature.get("_facade")
		if physical_owner == null or _lease.get("_owner") == null or _lease.get("_owner").get_ref() != physical_owner or _content.get("_feature_resource_service") != physical_owner or not _content.is_internal_code_retention_current(_result,root): return _blocked("actual_same_code_lease_Root_and_physical_owner_required")
		var resources: Array[Dictionary] = []
		for path: String in _lease.get("_resources"):
			resources.append({"resource_path":path,"actual_resource_id":_lease.get("_resources")[path].get_instance_id()})
		var retained: Script = _lease.get("_retained_code_resource")
		if retained == null: return _blocked("actual_code_retention_Script_missing")
		_terminal_code_release = {"contract_id":"hardcore.main.initial_code_observation_release.v1","actual_lease_id":_lease.get_instance_id(),"actual_code_script_id":retained.get_instance_id(),"actual_code_script_path":retained.resource_path,"actual_code_script_sha256":retained.get_source_code().sha256_text(),"actual_physical_owner_id":physical_owner.get_instance_id(),"actual_root_id":root.get_instance_id(),"actual_resources":resources,"loading_scope":_scope.duplicate(true)}
		_terminal_code_lease = weakref(_lease)
		# Drop the last Main observer refs in the actual admitted primitive.
		# Lease PREDELETE invokes its original owner.retire_resources; those real
		# retirements are captured in this primitive's existing reply, not lost
		# after live_feature_closed. Do not strip Root's genuine GameRoot Script.
		_result = {}; _lease = null
	if _terminal_code_lease.get_ref() != null:
		return {"success":false,"status":"PENDING","error":"actual_code_lease_still_owned","actual_lease_id":_terminal_code_release.actual_lease_id}
	_terminal_code_release.success = true; _terminal_code_release.status = "READY"
	_terminal_code_release.actual_lease_PREDELETE_observed = true
	_terminal_code_release.actual_Main_process_frame = Engine.get_process_frames()
	return _terminal_code_release.duplicate(true)

func actual_retained_terminal_receiver() -> Node:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _tree == null or _receiver == null or _initial_world_handoff.is_empty(): return null
	var receiver: Node = _receiver.get_ref()
	if not is_instance_valid(receiver) or receiver.get_script() != preload("res://scripts/character_select.gd") or receiver.get_instance_id() != _initial_world_handoff.get("actual_receiver_id") or not receiver.is_inside_tree() or receiver.is_queued_for_deletion() or not receiver.get("_launch_code_result").is_empty() or not receiver.get("_launch_scene_preload_requests").is_empty(): return null
	for depth: Variant in receiver.get("_original_main_callback_ledger").values():
		if depth != 0: return null
	return receiver

func retire_actual_original_terminal_receiver(terminal: Dictionary, transport: RefCounted) -> Dictionary:
	var receiver: Node = actual_retained_terminal_receiver()
	if receiver == null or transport == null or transport.get_script() != preload("res://scripts/gameplay/source/main_session_transport.gd") or transport.get("_state") != "CLOSED" or terminal.get("success") != true or terminal != transport.get("_terminal") or terminal.get("receipt",{}).get("owner_session_id") != transport.get("_session_id"): return _blocked("actual_retained_receiver_and_same_Main_terminal_required")
	var id: int = receiver.get_instance_id()
	if _tree.current_scene == receiver: return _blocked("actual_hidden_old_receiver_required")
	receiver.free()
	if is_instance_id_valid(id): return _blocked("actual_old_receiver_final_free_missing")
	# Original Source already retired the code result at Root step3. Drop only
	# this observation's references, without a duplicate lease retirement call.
	_receiver = null; _lease = null; _result = {}; _scope = {}; _code_transfer = {}; _code_root = null
	_actual_map_owner = null
	return {"success":true,"status":"READY","actual_receiver_id":id,"actual_Main_process_frame":Engine.get_process_frames()}

func actual_original_loading_scope(world: Dictionary) -> Dictionary:
	# This owner proves only the original initial CharacterSelect cover. A
	# target map, later map transition or another Root cannot borrow it.
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or world.size() != 5 or world.get("contract_id") != "hardcore.execution.world_context.v1" or world.get("runtime_map_id") != -1 or world.get("world_epoch") != 0 or world.get("profile_id") != _scope.get("profile_id") or not world.get("world_runtime_id") is int: return {}
	if verify_actual_original_loading_scope(_scope).get("success") != true: return {}
	var root: Object = instance_from_id(world.world_runtime_id)
	if not root is Node2D or not root.is_inside_tree() or root.is_queued_for_deletion() or root.get_script() != preload("res://scripts/game_root.gd"): return {}
	var attachment: Variant = root.get("_original_source_main_attachment")
	if not attachment is RefCounted or attachment.get_script() != preload("res://scripts/gameplay/world/world_main_root_attachment.gd") or not attachment.get("_root") is WeakRef or attachment.get("_root").get_ref() != root or attachment.get("_loading_scope") != _scope: return {}
	var transport: Variant = attachment.get("_transport")
	if not transport is RefCounted or transport.get("_loading") != self or transport.get("_scope") != _scope or transport.get("_aborting") == true or transport.get("_exited") == true: return {}
	return _scope.duplicate(true)

static func capture_original_presented_cover(overlay: Variant) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not overlay is Control or overlay.get_script() != Overlay: return _blocked("actual_original_Loading_overlay_required")
	var cover: Dictionary = overlay.code_preparation_cover_receipt()
	if cover.is_empty() or not overlay.code_preparation_cover_current(cover): return _blocked("actual_presented_Loading_cover_required")
	return {"success":true,"covered":cover.duplicate(true)}

func forget_actual_uncommitted_scope() -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	# Drop only this observation's references. The original code coordinator
	# still owns and retires its physical lease through the unchanged launch.
	_receiver = null; _lease = null; _result = {}; _scope = {}

static func _blocked(code: String) -> Dictionary:
	return {"success":false, "status":"BLOCKED", "error":code}

## Map-only delegation. The initial launch/code claim and its immutable scope
## remain owned by the methods above; current HUD cover has a distinct witness.
var _actual_map_owner: RefCounted
func bind_actual_original_map_loading_owner(producer: RefCounted, executor: RefCounted, leaf: RefCounted, root: Node2D, hud: Node, descriptor: Dictionary) -> Dictionary:
	if _actual_map_owner != null: return _blocked("actual_Map_owner_already_bound")
	_actual_map_owner = preload("res://scripts/gameplay/source/main_original_map_loading_owner.gd").new()
	return _actual_map_owner.configure_main(self,producer,executor,leaf,root,hud,descriptor)
func capture_actual_original_map_cover(world: Dictionary) -> Dictionary:
	return _actual_map_owner.capture_current_cover(world) if _actual_map_owner != null else _blocked("actual_Map_cover_owner_required")
func capture_actual_original_map_current_context(world: Dictionary) -> Dictionary:
	return _actual_map_owner.capture_current_context(world) if _actual_map_owner != null else _blocked("actual_Map_owner_required")
func verify_actual_original_map_current_source_site(site: Dictionary) -> Dictionary:
	return _actual_map_owner.verify_current_source_site(site) if _actual_map_owner != null else _blocked("actual_Map_owner_required")
func verify_actual_original_map_release_source_site(site: Dictionary, scope: Dictionary) -> Dictionary:
	return _actual_map_owner.verify_release_source_site(site,scope) if _actual_map_owner != null else _blocked("actual_Map_owner_required")
func capture_actual_original_map_loading_scope(producer: RefCounted, descriptor: Dictionary, transition: String, generation: int, map_id: int) -> Dictionary:
	return _actual_map_owner.capture_scope(producer,descriptor,transition,generation,map_id) if _actual_map_owner != null else _blocked("actual_Map_owner_required")
func verify_actual_original_map_loading_scope(producer: RefCounted, scope: Dictionary, descriptor: Dictionary) -> bool:
	return _actual_map_owner != null and _actual_map_owner.verify_scope(producer,scope,descriptor)
func capture_actual_original_map_publication_receipt(producer: RefCounted, scope: Dictionary, publication: Dictionary, coordinator: RefCounted, leaf: RefCounted) -> Dictionary:
	return _actual_map_owner.capture_publication(producer,scope,publication,coordinator,leaf) if _actual_map_owner != null else _blocked("actual_Map_owner_required")
func verify_actual_original_map_publication_receipt(producer: RefCounted, scope: Dictionary, publication: Dictionary, receipt: Dictionary) -> bool:
	return _actual_map_owner != null and _actual_map_owner.verify_publication(producer,scope,publication,receipt)
func can_apply_actual_original_map_arrival(producer: RefCounted, transaction: Dictionary) -> bool:
	return _actual_map_owner != null and _actual_map_owner.can_apply_arrival(producer,transaction)
func apply_actual_original_map_arrival(producer: RefCounted, transaction: Dictionary) -> bool:
	return _actual_map_owner != null and _actual_map_owner.apply_arrival(producer,transaction)
func prepare_actual_original_map_scope_release(producer: RefCounted, scope: Dictionary) -> Dictionary:
	return _actual_map_owner.prepare_release(producer,scope) if _actual_map_owner != null else _blocked("actual_Map_owner_required")
func commit_actual_original_map_scope_release(producer: RefCounted, scope: Dictionary, retained: Dictionary, descriptor: Dictionary) -> Dictionary:
	return _actual_map_owner.commit_release(producer,scope,retained,descriptor) if _actual_map_owner != null else _blocked("actual_Map_owner_required")
func service_actual_original_map_owner_retirement(producer: RefCounted) -> Dictionary:
	return _actual_map_owner.begin_terminal(producer) if _actual_map_owner != null else _blocked("actual_Map_owner_required")
func capture_actual_original_map_owner_terminal(producer: RefCounted, descriptor: Dictionary, scope: Dictionary, facts: Dictionary) -> Dictionary:
	return _actual_map_owner.capture_terminal(producer,descriptor,scope,facts) if _actual_map_owner != null else _blocked("actual_Map_owner_required")
func verify_actual_original_map_owner_terminal(producer: RefCounted, descriptor: Dictionary, scope: Dictionary, facts: Dictionary, receipt: Dictionary) -> bool:
	return _actual_map_owner != null and _actual_map_owner.verify_terminal(producer,descriptor,scope,facts,receipt)
func inspect_actual_original_map_owner() -> Dictionary:
	return _actual_map_owner.inspect_lifecycle() if _actual_map_owner != null else _blocked("actual_Map_owner_required")
