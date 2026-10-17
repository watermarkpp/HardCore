extends RefCounted
## Main receipt producer. The ledger records actual original function entry/return,
## including suspended awaits. It owns no profile, persistence queue or actor state.
const Overlay := preload("res://scripts/loading_transition_overlay.gd")
const LaunchLoading := preload("res://scripts/gameplay/source/main_boot_launch_loading.gd")
const Model := preload("res://scripts/gameplay/profile/profile_model.gd")
var _tree: SceneTree
var _transport: RefCounted
var _fatal: RefCounted
var _manifest: Dictionary
var _facade: WeakRef
var _checkpoint: Dictionary = {}
var _launch: WeakRef
var _overlay: WeakRef
var _closed: Array[Dictionary] = []
var _serial := 0
var _command_serial := 0
var _pending: Dictionary = {}
var _receipt_serial := 0
var _actual_launch_loading: RefCounted

func configure_main(tree: SceneTree, facade: Node, transport: RefCounted, fatal: RefCounted, manifest: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _tree != null or tree == null: return _fail("actual_Main_once_required")
	if not is_instance_valid(facade) or facade != tree.root.get_node_or_null("PlayerState") or not facade.get("_model") is Model: return _fail("actual_Main_loaded_facade_required")
	for method: String in ["submit_original_profile_command", "request_original_profile_notification", "verify_original_profile_command_receipt", "acknowledge_original_profile_command_receipt", "actual_original_profile_command_arities"]:
		if transport == null or not transport.has_method(method): return _fail("MISSING:reliable_source_command_transport:" + method)
	if fatal == null or not fatal.has_method("reject_original_main_profile_writer"): return _fail("MISSING:synchronous_source_domain_fault")
	if manifest.is_empty(): return _fail("actual_instrumented_source_manifest_required")
	for path: String in manifest:
		var loaded: Script = load(path)
		if loaded == null or loaded.get_source_code().sha256_text() != manifest[path].get("script_sha256"): return _fail("actual_receiver_source_mismatch:" + path)
	_tree = tree; _facade = weakref(facade); _transport = transport; _fatal = fatal; _manifest = manifest.duplicate(true)
	return {"success":true}

func bind_actual_original_launch_loading(owner: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _tree == null or _actual_launch_loading != null or owner == null or owner.get_script() != LaunchLoading: return false
	if owner.get("_tree") != _tree or owner.get("_facade") != _facade.get_ref() or owner.get("_content") != _tree.root.get_node_or_null("ContentLayers"): return false
	_actual_launch_loading = owner
	return true

func begin_original_character_launch(receiver: Node, world: Dictionary) -> Dictionary:
	if _tree == null or not _checkpoint.is_empty() or not is_instance_valid(receiver) or receiver != _tree.current_scene: return _fail("actual_current_CharacterSelect_required")
	if receiver.get_script().resource_path != "res://scripts/character_select.gd" or not _valid_world(world): return _fail("actual_character_launch_world_required")
	var facade: Node = _facade.get_ref()
	if world.profile_id != facade.get("_model").active_profile_id or receiver.selected_main_profile_id != world.profile_id or not receiver._launch_in_progress: return _fail("actual_loaded_selected_profile_required")
	var cover: Control = receiver.launch_loading_overlay
	if cover == null or cover.get_script() != Overlay: return _fail("actual_original_launch_overlay_required")
	var covered: Dictionary = cover.code_preparation_cover_receipt()
	if covered.is_empty(): return _fail("original_presented_cover_handshake_required")
	if receiver._launch_scene_preload_resource == null or receiver._launch_scene_preload_resource.resource_path != "res://scenes/main.tscn": return _fail("actual_main_scene_preload_required")
	_serial += 1
	_launch = weakref(receiver); _overlay = weakref(cover)
	_checkpoint = {"contract_id":"hardcore.main.root.checkpoint.v1", "serial":_serial, "kind":"character_launch", "receiver_id":receiver.get_instance_id(), "profile_id":world.profile_id, "world_context":world.duplicate(true), "process_frame":Engine.get_process_frames(), "physics_frame":Engine.get_physics_frames(), "covered":covered, "original_method":"_enter_selected_character"}
	# Disable the actual registered UI callbacks/inputs before checking await
	# ledgers. A callback already executing is never erased by this operation.
	_close_actual_ui_entries(receiver)
	var proof: Dictionary = verify_original_profile_ui_receiver_closure(_checkpoint)
	if proof.get("success") != true:
		abort_original_checkpoint(_checkpoint)
		return proof
	return {"success":true, "checkpoint":_checkpoint.duplicate(true)}

func _close_actual_ui_entries(root: Node) -> void:
	var flags := {"node":weakref(root), "process":root.is_processing(), "physics":root.is_physics_processing(), "input":root.is_processing_input(), "unhandled":root.is_processing_unhandled_input(), "unhandled_key":root.is_processing_unhandled_key_input(), "shortcut":root.is_processing_shortcut_input()}
	_closed.append(flags)
	root.set_process(false); root.set_physics_process(false); root.set_process_input(false); root.set_process_unhandled_input(false); root.set_process_unhandled_key_input(false); root.set_process_shortcut_input(false)
	if root is BaseButton:
		_closed.append({"button":weakref(root), "disabled":root.disabled})
		root.disabled = true
	if root is LineEdit:
		_closed.append({"edit":weakref(root), "editable":root.editable})
		root.editable = false
	for child: Node in root.get_children(): _close_actual_ui_entries(child)

func abort_original_checkpoint(checkpoint: Dictionary) -> Dictionary:
	if checkpoint != _checkpoint: return _fail("foreign_checkpoint_abort")
	for flags: Dictionary in _closed:
		if flags.has("node"):
			var node: Node = flags.node.get_ref()
			if not is_instance_valid(node): return _fail("actual_receiver_retired_before_abort")
			node.set_process(flags.process); node.set_physics_process(flags.physics); node.set_process_input(flags.input); node.set_process_unhandled_input(flags.unhandled); node.set_process_unhandled_key_input(flags.unhandled_key); node.set_process_shortcut_input(flags.shortcut)
		elif flags.has("button"):
			var button: BaseButton = flags.button.get_ref()
			if not is_instance_valid(button): return _fail("actual_button_retired_before_abort")
			button.disabled = flags.disabled
		else:
			var edit: LineEdit = flags.edit.get_ref()
			if not is_instance_valid(edit): return _fail("actual_edit_retired_before_abort")
			edit.editable = flags.editable
	_closed.clear(); _checkpoint = {}; _launch = null; _overlay = null
	return {"success":true}

func verify_original_profile_ui_receiver_closure(checkpoint: Dictionary) -> Dictionary:
	if not _checkpoint_current(checkpoint): return _fail("actual_loading_checkpoint_expired")
	if not _pending.is_empty(): return _fail("accepted_UI_commands_not_terminal")
	var receivers: Array[Dictionary] = []
	var scanned: Dictionary = _scan_receivers(_tree.root, receivers)
	if scanned.get("success") != true: return scanned
	return {"success":true, "checkpoint":checkpoint.duplicate(true), "producer_runtime_id":get_instance_id(), "receivers":receivers, "source_process_frame":Engine.get_process_frames(), "source_physics_frame":Engine.get_physics_frames()}

func _scan_receivers(node: Node, result: Array[Dictionary]) -> Dictionary:
	var script: Script = node.get_script()
	var direct := RegEx.create_from_string("\\bPlayerState\\.[A-Za-z_]")
	if script != null and direct.search(script.get_source_code()) != null:
		if node != _facade.get_ref():
			var path := script.resource_path
			if path=="res://scripts/game_root.gd" and node.get("_original_source_main_attachment")!=null:
				var attachment: RefCounted = node.get("_original_source_main_attachment")
				if attachment.get_script()!=preload("res://scripts/gameplay/world/world_main_root_attachment.gd"): return _fail("actual_Main_Root_attachment_source_required")
				var closed: Dictionary = attachment.verify_actual_original_Main_receiver_closure(node)
				if closed.get("success")!=true: return _fail("actual_guarded_Main_Root_callback_closure",closed)
				result.append(closed)
			else:
				if not _manifest.has(path) or script.get_source_code().sha256_text() != _manifest[path].script_sha256: return _fail("MISSING:uninstrumented_actual_Profile_receiver:" + path)
				var ledger: Variant = node.get("_original_main_callback_ledger")
				if not ledger is Dictionary: return _fail("actual_original_callback_ledger_missing:" + path)
				var allowed: String = "_enter_selected_character" if node == _launch.get_ref() else ""
				for method: String in ledger:
					if ledger[method] != (1 if method == allowed else 0): return _fail("actual_Main_receiver_not_terminal:" + path + ":" + method)
				if ledger.get(allowed,0) != 1 and not allowed.is_empty(): return _fail("checkpoint_outside_actual_original_launch_stack")
				result.append({"runtime_id":node.get_instance_id(), "script":path, "script_sha256":script.get_source_code().sha256_text(), "callbacks":ledger.duplicate(true)})
	for child: Node in node.get_children():
		var observed: Dictionary = _scan_receivers(child,result)
		if observed.get("success") != true: return observed
	return {"success":true}

func verify_original_main_source_checkpoint(checkpoint: Dictionary, facade: Node, content: Node, resources: Node) -> Dictionary:
	if _facade == null or facade != _facade.get_ref() or content != _tree.root.get_node_or_null("ContentLayers") or not is_instance_valid(resources): return _fail("actual_Main_source_receivers_mismatch")
	if resources.get_script().resource_path != "res://scripts/features/runtime/feature_resource_preparation.gd": return _fail("actual_legacy_resource_receiver_required")
	return verify_original_profile_ui_receiver_closure(checkpoint)

func observe_original_main_source_receiver_checkpoint(checkpoint: Dictionary, facade: Node, content: Node, resources: Node) -> Dictionary:
	var entry: Dictionary = verify_original_main_source_checkpoint(checkpoint,facade,content,resources)
	if entry.get("success") != true: return entry
	var model: RefCounted = facade.get("_model")
	var io: Dictionary = {"profile":model._json_persistence.work_snapshot(), "world":model._world_json_persistence.work_snapshot()}
	# The first observation may precede the original explicit transaction barrier.
	# Never claim completed accepted IO while those original queues still own it.
	if io.profile.get("pending") != 0 or io.world.get("pending") != 0:
		entry["io"] = io; entry["all_io_completed"] = false
		return entry
	for key: String in ["_background_save","_background_death","_item_save_plan","_clock_cleanup_pending","_clock_cleanup_active","_foreign_durable_receipts"]:
		var value: Variant = model.get(key)
		if not value is Dictionary or not value.is_empty(): return _fail("original_profile_obligation_pending:" + key)
	for key: String in ["_persistence_transaction_in_progress","_warehouse_transaction_locked","_workbench_transfer_pending","_warehouse_preparation_pending"]:
		if model.get(key) != false: return _fail("original_profile_transaction_pending:" + key)
	for key: String in ["_requests","_jobs","_work","_retirements","_applications","_deferred_completions"]:
		var value: Variant = resources.get(key)
		if not (value is Dictionary or value is Array) or not value.is_empty(): return _fail("accepted_resource_receiver_pending:" + key)
	if resources.get("_quantum_active") != false or resources.get("_applying_request") != 0 or resources.get("_code_world_handoff_id") != 0: return _fail("accepted_code_receiver_pending")
	entry["io"] = io; entry["all_io_completed"] = true
	return entry

func capture_original_profile_ui_view(source_state: Dictionary) -> Dictionary:
	# Borrow exact loaded source values; no hydrate/recalculate/save and no guessed
	# helper conversion. The Gate graph performs the detached immutable capture.
	if source_state.get("contract_id") != "profile.state.handoff.v2" or not source_state.get("source_fields") is Dictionary: return _fail("actual_loaded_source_fields_required")
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _facade == null or not is_instance_valid(_facade.get_ref()): return _fail("actual_Main_profile_projection_owner_required")
	var facade: Node = _facade.get_ref()
	var model: RefCounted = facade.get("_model")
	var gate: RefCounted = facade.get("_source_domain_gate")
	var witness: Dictionary = source_state.get("source_witness",{})
	if model == null or model.get_script() != Model or gate == null or gate.state() != "PREPARED" or witness.get("facade_object_id") != facade.get_instance_id() or witness.get("model_object_id") != model.get_instance_id() or model.get_script().get_source_code().sha256_text() != source_state.get("source_model_sha256"): return _fail("actual_same_prepared_Profile_projection_required")
	# These public properties are original read-only getters, not stored handoff
	# fields. Read the exact frozen Main model before its single authority commit;
	# never call setters, construct another model, or invent a display conversion.
	if model.profession_id != source_state.source_fields.get("_profession_id") or model.learned_skills != source_state.source_fields.get("_learned_skill_ids"): return _fail("prepared_Profile_getter_inputs_changed")
	var derived: Dictionary = {"profession_id":model.profession_id,"profession":model.profession,"learned_skills":model.learned_skills}
	# The actual 17-source manifest presently reads 21 plain Model properties.
	# New opaque helper consumers must supply an actual canonical read port;
	# field absence fails here rather than silently manufacturing a capability.
	var fields: Dictionary = {}
	for path: String in _manifest:
		for field: String in _manifest[path].read_fields:
			if source_state.source_fields.has(field): fields[field] = source_state.source_fields[field]
			elif derived.has(field): fields[field] = derived[field]
			else: return _fail("MISSING:actual_Profile_UI_read_field:"+field)
	fields[preload("res://scripts/gameplay/profile/profile_original_ui_queries.gd").FIELD] = preload("res://scripts/gameplay/profile/profile_original_ui_queries.gd").capture(model)
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary = graph.capture(fields,true,false)
	if captured.get("success")!=true: return _fail("MISSING:opaque_UI_field_canonical_view",captured)
	return {"success":true, "fields":captured.value}

func submit_original_profile_command(method: StringName, arguments: Array) -> Dictionary:
	if _tree == null: return _fail("actual_Main_router_unconfigured")
	if not preload("res://scripts/gameplay/source/profile_original_command_catalog.gd").accepts(str(method),arguments.size()): return _fail("original_command_arity_not_admitted")
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	if not graph.validate(arguments,false).get("success",false): return _fail("opaque_command_requires_canonical_port")
	var facade: Node = _facade.get_ref()
	var gate: RefCounted = facade.get("_source_domain_gate")
	if gate == null or gate.state() != "S": return _fail("actual_S_authority_not_committed")
	_command_serial += 1
	var packet := {"contract_id":"hardcore.profile.ui.command.v1", "command_id":_command_serial, "profile_id":gate.read_original_profile_view(&"active_profile_id"), "method":str(method), "arguments":arguments.duplicate(true)}
	_pending[_command_serial] = packet
	var received: Dictionary = await _transport.submit_original_profile_command(packet)
	if not _transport.verify_original_profile_command_receipt(packet,received):
		reject_original_main_profile_writer({"method":"foreign_or_missing_UI_command_receipt", "command_id":packet.command_id})
		return _fail("actual_reliable_S_receipt_required")
	if not _transport.acknowledge_original_profile_command_receipt(received): return _fail("actual_command_receipt_ACK_required")
	_pending.erase(packet.command_id)
	_receipt_serial += 1
	return {"success":true, "result":received.result, "receipt":received}

func request_original_profile_notification(what: int) -> void:
	if _transport == null or not _transport.request_original_profile_notification(what): reject_original_main_profile_writer({"method":"unaccepted_original_notification", "what":what})
func reject_original_main_profile_writer(fact: Dictionary) -> void:
	assert(_fatal != null)
	_fatal.reject_original_main_profile_writer(fact)
func verify_original_loading_source_site(site: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _actual_launch_loading == null or _checkpoint.is_empty(): return _fail("actual_original_Loading_owner_required")
	if site.size() == 2 and site.get("source_site") is Dictionary and site.get("release_map_scope") is Dictionary:
		var release_site: Dictionary = site.source_site
		if release_site.size() != 8 or release_site.get("domain") != "P" or release_site.get("clock_epoch") != 0 or release_site.get("bootstrap") != true: return _fail("actual_epoch0_Map_release_source_site_required")
		for key: String in ["entry_ordinal","observation_process_epoch","deadline_usec"]:
			if not release_site.get(key) is int or release_site[key] < (0 if key == "observation_process_epoch" else 1): return _fail("actual_Map_release_source_site_integer:"+key)
		if not (release_site.get("entry_id") is String or release_site.get("entry_id") is StringName) or str(release_site.entry_id).is_empty(): return _fail("actual_Map_release_source_entry_required")
		var release: Dictionary = _actual_launch_loading.verify_actual_original_map_release_source_site(release_site,site.release_map_scope)
		if release.get("success") != true or release.get("contract_id") != "hardcore.main.current_map_release.context.v1" or release.get("initial_launch_scope") != _actual_launch_loading.captured_scope() or release.get("requested_scope") != site.release_map_scope or release.get("world_context") != release_site.get("world_context"): return _fail("actual_Map_release_witness_required",release)
		release = release.duplicate(true)
		release.source_site = release_site.duplicate(true)
		return release
	if site.get("world_context") != _checkpoint.world_context:
		# An arrived world uses its actual current HUD/Map owner. The original
		# CharacterSelect checkpoint is retained as provenance, never reopened.
		if site.size() != 8 or site.get("domain") != "P" or not site.get("clock_epoch") is int or site.clock_epoch != 0 or site.get("bootstrap") != true: return _fail("actual_epoch0_current_Map_source_site_required")
		for key: String in ["entry_ordinal","observation_process_epoch","deadline_usec"]:
			if not site.get(key) is int or site[key] < (0 if key == "observation_process_epoch" else 1): return _fail("actual_current_Map_source_site_integer:"+key)
		if not (site.get("entry_id") is String or site.get("entry_id") is StringName) or str(site.entry_id).is_empty(): return _fail("actual_current_Map_source_entry_required")
		var actual: Dictionary = _actual_launch_loading.verify_actual_original_map_current_source_site(site)
		if actual.get("success") != true or actual.get("contract_id") != "hardcore.main.current_map_loading.context.v1" or actual.get("world_context") != site.world_context: return _fail("actual_current_Map_Loading_boundary_required",actual)
		var map_scope: Dictionary = actual.get("scope",{})
		if map_scope.get("actual_provenance",{}).get("initial_launch_scope") != _actual_launch_loading.captured_scope(): return _fail("actual_same_launch_Map_owner_required")
		return {"success":true,"producer_runtime_id":get_instance_id(),"source_site":site.duplicate(true),"loading_scope":map_scope.duplicate(true),"initial_launch_scope":_actual_launch_loading.captured_scope(),"current_map_loading_context":actual}
	if not _checkpoint_current(_checkpoint) or _actual_launch_loading == null or site.size() != 8 or site.get("domain") != "P" or site.get("world_context") != _checkpoint.world_context: return _fail("actual_original_Loading_source_site_required")
	for key: String in ["clock_epoch","entry_ordinal","observation_process_epoch","deadline_usec"]:
		if not site.get(key) is int: return _fail("actual_original_Loading_source_site_integer:"+key)
	if site.clock_epoch != 0 or site.get("bootstrap") != true or not site.bootstrap is bool or site.entry_ordinal <= 0 or site.observation_process_epoch != _checkpoint.process_frame or site.deadline_usec <= 0: return _fail("actual_original_launch_epoch0_source_site_required")
	if not (site.get("entry_id") is String or site.get("entry_id") is StringName) or str(site.entry_id).is_empty(): return _fail("actual_original_Loading_source_entry_required")
	# The actual code/cover owner revalidates retained physical resources now.
	# A later map/HUD loading scope must use its own real producer, not borrow
	# this original CharacterSelect's epoch0 launch permission.
	var checked: Dictionary = _actual_launch_loading.verify_actual_original_loading_scope(_actual_launch_loading.captured_scope())
	if checked.get("success") != true or not checked.get("loading_scope") is Dictionary: return _fail("actual_current_launch_Loading_scope_required",checked)
	var scope: Dictionary = checked.loading_scope
	if scope.get("receiver_id") != _checkpoint.receiver_id or scope.get("profile_id") != _checkpoint.profile_id or scope.get("facade_id") != _facade.get_ref().get_instance_id() or scope.get("covered") != _checkpoint.covered: return _fail("actual_checkpoint_Loading_owner_mismatch")
	return {"success":true, "checkpoint":_checkpoint.duplicate(true), "producer_runtime_id":get_instance_id(), "source_site":site.duplicate(true),"loading_scope":scope.duplicate(true)}
func _checkpoint_current(checkpoint: Dictionary) -> bool:
	if checkpoint.is_empty() or checkpoint != _checkpoint or _launch == null or _overlay == null: return false
	var receiver: Node = _launch.get_ref()
	var cover: Control = _overlay.get_ref()
	return is_instance_valid(receiver) and receiver == _tree.current_scene and receiver.is_inside_tree() and not receiver.is_queued_for_deletion() and is_instance_valid(cover) and cover.code_preparation_cover_current(checkpoint.covered) and receiver._launch_in_progress
func _valid_world(world: Dictionary) -> bool:
	if world.size() != 5 or world.get("contract_id") != "hardcore.execution.world_context.v1" or not world.get("world_runtime_id") is int or world.world_runtime_id <= 0 or not world.get("world_epoch") is int or world.world_epoch < 0 or not world.get("runtime_map_id") is int or not world.get("profile_id") is String or world.profile_id.is_empty(): return false
	# Same bounded constructor state already accepted by the actual Root/Native
	# capture. This is not map readiness or permission to reopen a later world.
	return world.runtime_map_id >= 0 or world.runtime_map_id == -1 and world.world_epoch == 0
func _fail(code: String, details: Dictionary = {}) -> Dictionary: return {"success":false, "errors":[code], "details":details}
