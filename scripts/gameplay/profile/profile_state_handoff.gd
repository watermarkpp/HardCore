extends RefCounted
## Loaded Main state -> unique factory-created S owner. No load/init/recalc/save.
const Model := preload("res://scripts/gameplay/profile/profile_model.gd")
const Working := preload("res://scripts/gameplay/world/world_runtime_working_graph.gd")
const LegacyRuntime := preload("res://scripts/gameplay/profile/legacy_profile_runtime_port.gd")
const Runtime := preload("res://scripts/gameplay/profile/profile_runtime_port.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const CONTRACT := "profile.state.handoff.v2"
const RNG_FIELDS := ["_durability_rng","_blessing_oil_rng","_relic_instance_rng","_relic_proc_rng"]
const SOURCE_FIELDS := [
  "_feature_base_stats",
  "feature_errors",
  "_startup_save_upgrade_pending",
  "_startup_save_upgrade_in_progress",
  "startup_save_upgrade_result",
  "_startup_save_upgrade_phase",
  "_startup_source_backup_verified",
  "_item_transaction_journal",
  "level",
  "_profession_id",
  "profession_identity_errors",
  "gender",
  "later_content_enabled",
  "game_mode_id",
  "experience",
  "gold",
  "gold_overflow_records",
  "inventory",
  "forge_tray",
  "synthesis_tray",
  "warehouse_inventory",
  "shared_warehouse_path",
  "shared_warehouse_transaction_log_path",
  "_shared_warehouse_initialized",
  "_active_profile_legacy_warehouse_pending",
  "_warehouse_transaction_locked",
  "_persistence_transaction_in_progress",
  "_test_fail_shared_write",
  "_test_fail_profile_write",
  "_test_fail_warehouse_rollback_write",
  "equipment",
  "_learned_skill_ids",
  "skill_identity_errors",
  "quick_slots",
  "quick_item_slots",
  "equip_cycle_cursor",
  "equipment_transaction_revision",
  "_last_equipment_transaction_result",
  "_attack_skill_ids",
  "_attack_ring_ids",
  "warrior_runtime_state",
  "taoist_main_pet_runtime_states",
  "quest_states",
  "world_monster_respawn_state",
  "_world_clock_changes",
  "_death_event_sequence",
  "_world_clock_generation",
  "_profile_saved_death_event_sequence",
  "_profile_backup_death_event_sequence",
  "_world_clock_snapshot_sequence",
  "_world_clock_backup_sequence",
  "_world_clock_dirty",
  "_clock_cleanup_pending",
  "_clock_cleanup_active",
  "_clock_cleanup_completed",
  "saved_map_id",
  "saved_position",
  "saved_ground_position_gu",
  "saved_ground_position_gu_valid",
  "base_stats",
  "computed_stats",
  "computed_special_effects",
  "test_mode",
  "durability_event_commit_count",
  "active_profile_id",
  "character_name",
  "_autosave_elapsed",
  "_durability_save_pending",
  "_durability_save_elapsed",
  "_durability_mutation_revision",
  "_world_mutation_revision",
  "_background_save",
  "_background_death",
  "_item_save_revision",
  "_item_saved_revision",
  "_item_save_plan",
  "_item_save_failed",
  "_workbench_transfer_pending",
  "_durability_visual_pending",
  "_durability_visual_elapsed",
  "profile_index_path",
  "profile_directory",
  "test_roster_reset_marker_path",
  "last_save_result",
  "last_load_result",
  "_save_blocked_profile_id",
  "_save_blocked_reason",
  "_consumed_shop_sell_quote_ids",
  "_relic_proc_state",
  "_relic_proc_equipment_snapshot",
  "_loot_batch_debug",
  "_last_runtime_commit_profile",
  "_atomic_write_generation",
  "_validated_profile_path",
  "_validated_profile_bytes",
  "_atomic_write_phases",
  "_last_json_promotion",
  "_last_atomic_write_failure",
  "_last_save_phase_profile",
  "_last_loot_batch_profile",
  "_last_death_settlement_profile",
  "_loot_inventory_catalog_cache",
  "_item_instance_serial",
  "_test_transaction_counters",
  "_shop_quote_debug",
  "_consumed_shop_buy_quote_ids",
  "_shop_buy_quote_serial",
  "_shop_pricing_session_nonce",
  "last_receive_result",
  "_test_force_atomic_write_failure",
  "temporary_item_buffs",
  "temporary_item_buff_revision",
  "_json_parse_snapshots",
  "_foreign_durable_receipts",
  "_shared_digest_cache",
  "_shared_digest_snapshots",
  "_warehouse_preparation_pending",
  "_warehouse_validation_scope",
  "_warehouse_validated_collections",
  "_ui_l1_buy_quote_rows"
]
const SOURCE_MODEL_SHA256 := "727fcb7d79ceac7bd6035e485e30ad2563f0de95b49c8ce463d463b893be3f21"

static func _fail(reason: String) -> Dictionary: return {"ok":false,"errors":[reason]}

static func _persistence_idle(service: RefCounted, kind: String) -> bool:
	return service != null and service.get_script()==Model.JsonPersistenceService and service.assert_owner() and service.owner_context().kind==kind and service._queue.is_empty() and not service._pump_active

static func _container_modes(value: Variant, path: Array, sources: Array, modes: Array) -> void:
	if not (value is Dictionary or value is Array): return
	for previous: Variant in sources:
		if is_same(previous,value): return
	sources.append(value)
	if value is Dictionary:
		for key: Variant in value:
			var child: Array=path.duplicate(); child.append(key)
			_container_modes(value[key],child,sources,modes)
	else:
		for index in range(value.size()):
			var child: Array=path.duplicate(); child.append(index)
			_container_modes(value[index],child,sources,modes)
	modes.append({"path":path,"read_only":value.is_read_only()})

static func _at_path(roots: Dictionary, path: Array) -> Variant:
	var value: Variant=roots
	for key: Variant in path:
		if not (value is Dictionary or value is Array): return null
		if value is Dictionary and not value.has(key): return null
		if value is Array and (not key is int or key<0 or key>=value.size()): return null
		value=value[key]
	return value

static func _rng_binding(rng: RandomNumberGenerator, originals: Array, states: Array) -> int:
	if rng==null: return -1
	for index in range(originals.size()):
		if is_same(originals[index],rng): return index
	originals.append(rng)
	states.append({"seed":rng.seed,"state":rng.state})
	return states.size()-1

static func _read_source_document(path: String) -> Dictionary:
	# Read only: never recover/promote/quarantine or invoke a save writer.
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null: return {"ok":false}
	var bytes: PackedByteArray=file.get_buffer(file.get_length())
	file.close()
	var parsed: Variant=JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary: return {"ok":false}
	var hash_state:=HashingContext.new()
	hash_state.start(HashingContext.HASH_SHA256); hash_state.update(bytes)
	return {"ok":true,"path":path,"bytes_sha256":hash_state.finish().hex_encode(),"bytes":bytes,"document":parsed}

static func _valid_document_witness(value: Dictionary) -> bool:
	if value.get("ok")!=true or not value.get("path") is String or value.path.is_empty() or not value.get("bytes") is PackedByteArray or not value.get("document") is Dictionary or not value.get("bytes_sha256") is String: return false
	var hash_state:=HashingContext.new(); hash_state.start(HashingContext.HASH_SHA256); hash_state.update(value.bytes)
	return hash_state.finish().hex_encode()==value.bytes_sha256 and JSON.parse_string(value.bytes.get_string_from_utf8())==value.document

static func capture_main(source: RefCounted, facade: Node) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not source is Model or not is_instance_valid(facade) or not facade.is_inside_tree() or facade.is_queued_for_deletion(): return _fail("actual_Main_profile_facade_required")
	if facade.get_script()!=preload("res://scripts/player_state.gd") or not is_same(facade.get("_model"),source) or not is_same(facade.get_tree().root.get_node_or_null("PlayerState"),facade): return _fail("canonical_Main_autoload_model_binding_required")
	if not source._configured or source._owner_thread_id!=OS.get_main_thread_id() or source._runtime_port.get_script()!=LegacyRuntime or not is_same(source._runtime_port._facade.get_ref(),facade): return _fail("actual_original_Main_ports_required")
	if source._runtime_port.profile_is_owned_by_gameplay() or source._taoist_main_pets_persistence_provider.is_valid(): return _fail("old_world_must_complete_original_exit_barrier")
	if source.active_profile_id.is_empty() or source.last_load_result.get("success")!=true or source.last_load_result.get("contract_id")!=Model.SAVE_RESULT_CONTRACT_ID or source.last_load_result.get("path")!=source._profile_path(source.active_profile_id): return _fail("actual_successfully_loaded_profile_required")
	if source._startup_save_upgrade_pending or source._startup_save_upgrade_in_progress or source._persistence_transaction_in_progress or source._warehouse_transaction_locked or source._workbench_transfer_pending or source._warehouse_preparation_pending or source._warehouse_validation_scope: return _fail("profile_source_transaction_not_quiescent")
	if not _persistence_idle(source._json_persistence,"legacy_main") or not _persistence_idle(source._world_json_persistence,"legacy_main"): return _fail("accepted_JSON_writer_queue_must_finish_original_barrier")
	if source._item_save_revision>source._item_saved_revision: return _fail("accepted_item_save_revision_not_committed")
	for name: String in ["_background_save","_background_death","_item_save_plan","_clock_cleanup_pending","_clock_cleanup_active","_foreign_durable_receipts"]:
		if not source.get(name).is_empty(): return _fail("accepted_profile_obligation:"+name)
	for name: String in ["_clock_cleanup_worker","_warehouse_active_preparation"]:
		if source.get(name)!=null: return _fail("original_terminal_receipt_barrier_required:"+name)
	var disk:=_read_source_document(source.last_load_result.path)
	var shared:=_read_source_document(source.shared_warehouse_path)
	if not disk.ok or disk.document.get("profile_id")!=source.active_profile_id or not shared.ok or not source._shared_warehouse_initialized: return _fail("actual_profile_and_account_warehouse_documents_required")
	var decoded_shared: Dictionary=Model.ItemExtensionCodec.decode_document(shared.document,source._content_port)
	if decoded_shared.get("status")!=Model.ItemExtensionCodec.KNOWN_VALID or not decoded_shared.document.get("warehouse_inventory") is Array: return _fail("actual_account_warehouse_wire_document_invalid")
	# Runtime records may include the original load-time durability migration;
	# wire records may be v3 item envelopes. Never equate the wire to live data
	# or decode/reload it into the target a second time.
	shared["decoded_runtime_document"]=decoded_shared.document
	shared["actual_loaded_runtime_inventory"]=source.warehouse_inventory
	var roots: Dictionary={}
	for name: String in SOURCE_FIELDS: roots[name]=source.get(name)
	var loadout: RefCounted=source._feature_loadout
	if loadout==null or loadout.get_script()!=Model.FeatureLoadout or source._skill_progression==null or source._skill_progression.get_script()!=Model.SkillProgressionServiceScript: return _fail("actual_original_profile_helper_required")
	roots["_handoff_loadout"]={"bundle":loadout._bundle,"signature":loadout._signature,"compile_count":loadout.compile_count,"last_errors":loadout.last_errors}
	roots["_handoff_skill_progression"]=source._skill_progression._progress
	roots["_handoff_content_cache"]={"pricing_policy_cache":source._content_port.pricing_policy_cache,"pricing_policy_hash":source._content_port.pricing_policy_hash,"profession_growth_source_path":source._content_port.profession_growth_source_path}
	var originals: Array=[]
	var states: Array=[]
	var bindings: Dictionary={}
	for name: String in RNG_FIELDS: bindings[name]=_rng_binding(source.get(name),originals,states)
	var helpers: Dictionary={}
	var item: RefCounted=source._item_transaction_port
	if item!=null:
		if item.get_script()!=Model.ItemTransactionPort or not is_same(item._owner.get_ref(),source) or not item._active.is_empty(): return _fail("active_or_foreign_item_transaction_helper")
		helpers["_item_transaction_port"]={"present":true,"_active":item._active,"_issued_context":item._issued_context,"_issued_epoch":item._issued_epoch}
	else: helpers["_item_transaction_port"]={"present":false}
	for name: String in ["_enhancement_service","_relic_synthesis_service"]:
		var helper: RefCounted=source.get(name)
		if helper==null:
			helpers[name]={"present":false}
			continue
		var expected: Script=Model.EquipmentEnhancementServiceScript if name=="_enhancement_service" else Model.RelicSynthesisServiceScript
		if helper.get_script()!=expected or not is_same(helper._player_ref.get_ref(),source): return _fail("foreign_quote_helper:"+name)
		var busy: bool=helper._enhancement_transaction_in_progress if name=="_enhancement_service" else helper._busy
		if busy: return _fail("active_quote_helper:"+name)
		var state: Dictionary={"present":true,"_session_id":helper._session_id,"_serial":helper._serial,"_issued":helper._issued}
		if name=="_enhancement_service": state["_consumed"]=helper._consumed
		helpers[name]=state
		bindings[name]=_rng_binding(helper._rng,originals,states)
	roots["_handoff_helpers"]=helpers
	var persistence: Dictionary={}
	for name: String in ["_json_persistence","_world_json_persistence"]:
		var service: RefCounted=source.get(name)
		persistence[name]={"completed_count":service.completed_count,"maximum_completion_latency_usec":service.maximum_completion_latency_usec}
	var resource: Dictionary={"present":loadout._resources!=null}
	if loadout._resources!=null:
		var lease: RefCounted=loadout._resources
		if lease.get_script()!=Lease or lease.is_domain(): return _fail("actual_original_Main_feature_lease_required")
		var paths: Array=lease._resources.keys(); paths.sort()
		resource={"present":true,"signature":lease._signature,"catalog_revision":lease._catalog_revision,"enabled_modules":lease._enabled_modules,"paths":paths}
	var modes: Array=[]
	_container_modes(roots,[],[],modes)
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	if graph==null: return _fail("real_native_alias_preserving_value_graph_required")
	var captured: Dictionary=graph.capture({"contract_id":CONTRACT,"source_model_sha256":SOURCE_MODEL_SHA256,"source_fields":roots,"rng_states":states,"rng_bindings":bindings,"persistence":persistence,"container_modes":modes,"resource":resource,"active_profile_id":source.active_profile_id,
		"source_witness":{"facade_object_id":facade.get_instance_id(),"model_object_id":source.get_instance_id(),"actual_load_receipt":source.last_load_result,"source_process_frame":Engine.get_process_frames(),"profile_document":disk,"shared_document":shared}},true,false)
	return {"ok":captured.success,"publication":captured.value if captured.success else {},"errors":captured.get("errors",[])}

static func adopt_owner(target: RefCounted, publication: Dictionary, feature_resource_lease: RefCounted = null) -> Dictionary:
	if OS.get_thread_caller_id()==OS.get_main_thread_id() or not target is Model or not target._configured or target._owner_thread_id!=OS.get_thread_caller_id() or not target._content_port.simulation_owner or target._runtime_port.get_script()!=Runtime: return _fail("actual_factory_created_same_S_profile_required")
	if publication.get("contract_id")!=CONTRACT or publication.get("source_model_sha256")!=SOURCE_MODEL_SHA256: return _fail("canonical_profile_handoff_publication_required")
	for key: String in ["source_fields","rng_bindings","persistence","resource","source_witness"]:
		if not publication.get(key) is Dictionary: return _fail("missing_profile_state:"+key)
	if not publication.get("rng_states") is Array or not publication.get("container_modes") is Array: return _fail("invalid_rng_or_container_state")
	if not _persistence_idle(target._json_persistence,"simulation") or not _persistence_idle(target._world_json_persistence,"simulation") or not target.active_profile_id.is_empty(): return _fail("target_profile_must_be_unadopted_and_quiescent")
	var expected: Array=SOURCE_FIELDS.duplicate(); expected.append_array(["_handoff_loadout","_handoff_skill_progression","_handoff_content_cache","_handoff_helpers"])
	var actual: Array=publication.source_fields.keys(); expected.sort(); actual.sort()
	if actual!=expected or publication.source_fields.active_profile_id!=publication.get("active_profile_id") or str(publication.active_profile_id).is_empty(): return _fail("missing_unknown_or_foreign_profile_fields")
	var witness: Dictionary=publication.source_witness
	if not witness.get("actual_load_receipt") is Dictionary or witness.actual_load_receipt.get("success")!=true or witness.actual_load_receipt.get("path")!=publication.source_fields.last_load_result.get("path") or not witness.get("profile_document") is Dictionary or not witness.get("shared_document") is Dictionary: return _fail("actual_source_load_and_warehouse_witness_required")
	if witness.profile_document.get("ok")!=true or witness.shared_document.get("ok")!=true or witness.profile_document.document.get("profile_id")!=publication.active_profile_id or witness.shared_document.get("actual_loaded_runtime_inventory")!=publication.source_fields.warehouse_inventory: return _fail("actual_load_or_account_warehouse_witness_mismatch")
	if not _valid_document_witness(witness.profile_document) or not _valid_document_witness(witness.shared_document) or witness.profile_document.path!=witness.actual_load_receipt.path or witness.shared_document.path!=publication.source_fields.shared_warehouse_path: return _fail("source_document_bytes_digest_or_path_mismatch")
	if target._mode_port.active_mode!=publication.source_fields.game_mode_id: return _fail("loaded_Main_mode_and_published_S_mode_mismatch")
	var resource: Dictionary=publication.resource
	if not resource.get("present") is bool: return _fail("original_resource_presence_required")
	if resource.present:
		if feature_resource_lease==null or not feature_resource_lease.is_domain(): return _fail("actual_same_S_feature_retention_required")
		var accepted: Dictionary=feature_resource_lease.domain_publication()
		for key: String in ["signature","catalog_revision","enabled_modules","paths"]:
			if accepted.get(key)!=resource.get(key): return _fail("source_feature_lease_identity_mismatch:"+key)
	elif feature_resource_lease!=null: return _fail("unexpected_source_feature_lease")
	var restored: Dictionary=Working.restore_runtime_roots(publication.source_fields)
	if not restored.ok: return restored
	var loadout: Variant=restored.value._handoff_loadout
	var helpers: Variant=restored.value._handoff_helpers
	var cache: Variant=restored.value._handoff_content_cache
	if not loadout is Dictionary or not loadout.get("bundle") is Dictionary or not loadout.get("signature") is String or not loadout.get("compile_count") is int or not loadout.get("last_errors") is Array or not restored.value._handoff_skill_progression is Dictionary: return _fail("invalid_original_loadout_or_progression")
	if not cache is Dictionary or not cache.get("pricing_policy_cache") is Dictionary or not cache.get("pricing_policy_hash") is String or cache.get("profession_growth_source_path")!=target._content_port.profession_growth_source_path: return _fail("source_content_cache_or_catalog_mismatch")
	if not helpers is Dictionary or helpers.size()!=3: return _fail("invalid_helper_state")
	var rng_expected: Array=RNG_FIELDS.duplicate()
	for name: String in ["_item_transaction_port","_enhancement_service","_relic_synthesis_service"]:
		var helper: Variant=helpers.get(name)
		if not helper is Dictionary or not helper.get("present") is bool: return _fail("missing_helper_presence:"+name)
		if not helper.present: continue
		if name=="_item_transaction_port":
			if not helper.get("_active") is Dictionary or not helper._active.is_empty() or not helper.get("_issued_context") is String or not helper.get("_issued_epoch") is String: return _fail("invalid_item_transaction_state")
		else:
			if not helper.get("_session_id") is String or not helper.get("_serial") is int or not helper.get("_issued") is Dictionary: return _fail("invalid_quote_capability_state")
			if name=="_enhancement_service" and not helper.get("_consumed") is Dictionary: return _fail("invalid_consumed_quote_state")
			rng_expected.append(name)
	var binding_names: Array=publication.rng_bindings.keys(); rng_expected.sort(); binding_names.sort()
	if binding_names!=rng_expected: return _fail("unknown_missing_rng_binding")
	for binding: Variant in publication.rng_bindings.values():
		if not binding is int or binding< -1 or binding>=publication.rng_states.size(): return _fail("invalid_rng_group_binding")
	for name: String in ["_enhancement_service","_relic_synthesis_service"]:
		if helpers[name].present and publication.rng_bindings[name]<0: return _fail("nonnull_quote_helper_requires_original_rng")
	for state: Variant in publication.rng_states:
		if not state is Dictionary or state.size()!=2 or not state.get("seed") is int or not state.get("state") is int: return _fail("invalid_original_rng_state")
	for name: String in ["_json_persistence","_world_json_persistence"]:
		var state: Variant=publication.persistence.get(name)
		if not state is Dictionary or not state.get("completed_count") is int or not state.get("maximum_completion_latency_usec") is int: return _fail("invalid_original_persistence_state")
	var restored_modes: Array=[]
	_container_modes(restored.value,[],[],restored_modes)
	if restored_modes.size()!=publication.container_modes.size(): return _fail("missing_original_container_metadata")
	for index in range(restored_modes.size()):
		var row: Variant=publication.container_modes[index]
		if not row is Dictionary or row.get("path")!=restored_modes[index].path or not row.get("read_only") is bool: return _fail("original_container_alias_or_metadata_mismatch")
	# All shape/provenance checks precede target mutation or helper creation.
	# RNG state reconstruction preserves groups/independence and consumes no draw.
	var random: Array=[]
	for state: Dictionary in publication.rng_states:
		var rng:=RandomNumberGenerator.new(); rng.seed=state.seed; rng.state=state.state
		random.append(rng)
	var item: RefCounted
	var enhancement: RefCounted
	var relic: RefCounted
	if helpers._item_transaction_port.present:
		item=Model.ItemTransactionPort.new(target,target._content_port,target._feature_port)
		item._active=helpers._item_transaction_port._active; item._issued_context=helpers._item_transaction_port._issued_context; item._issued_epoch=helpers._item_transaction_port._issued_epoch
	for name: String in ["_enhancement_service","_relic_synthesis_service"]:
		if not helpers[name].present: continue
		var state: Dictionary=helpers[name].duplicate(false)
		var binding: int=publication.rng_bindings[name]
		if binding<0: return _fail("nonnull_quote_helper_requires_original_rng")
		state["rng"]=random[binding]
		if name=="_enhancement_service": enhancement=Model.EquipmentEnhancementServiceScript.new(target,target._content_port,state)
		else: relic=Model.RelicSynthesisServiceScript.new(target,target._content_port,state)
	for row: Dictionary in publication.container_modes:
		if row.read_only: _at_path(restored.value,row.path).make_read_only()
	for name: String in SOURCE_FIELDS: target.set(name,restored.value[name])
	target._skill_progression._progress=restored.value._handoff_skill_progression
	target._feature_loadout._bundle=loadout.bundle; target._feature_loadout._signature=loadout.signature; target._feature_loadout.compile_count=loadout.compile_count; target._feature_loadout.last_errors=loadout.last_errors
	target._feature_loadout.set_resource_lease(feature_resource_lease)
	target._content_port.pricing_policy_cache=cache.pricing_policy_cache; target._content_port.pricing_policy_hash=cache.pricing_policy_hash
	target._item_transaction_port=item; target._enhancement_service=enhancement; target._relic_synthesis_service=relic
	for name: String in RNG_FIELDS:
		var binding: int=publication.rng_bindings[name]
		target.set(name,random[binding] if binding>=0 else null)
	for name: String in ["_json_persistence","_world_json_persistence"]:
		var service: RefCounted=target.get(name)
		service.completed_count=publication.persistence[name].completed_count; service.maximum_completion_latency_usec=publication.persistence[name].maximum_completion_latency_usec
	return {"ok":true,"active_profile_id":target.active_profile_id,"source_field_count":SOURCE_FIELDS.size(),"loaded_profile_sha256":witness.profile_document.bytes_sha256,"loaded_shared_warehouse_sha256":witness.shared_document.bytes_sha256}
