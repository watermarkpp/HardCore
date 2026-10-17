extends Node

## Boundary/schema checks use a real Main measurement and the production Scope
## on another Thread. They do not manufacture a Core, Session or Native CAS.
## The full-world fixture separately proves the actual committed positive path.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Port := preload("res://scripts/gameplay/world/world_visual_viewport_port.gd")
const TemporalScope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")
var _proof := Proof.new()
var _failed := 0
func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1; print("VIEWPORT_ARRIVAL_BINDING_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _scope() -> RefCounted:
	var scope := TemporalScope.new()
	var configured: bool = scope.configure_source({"runtime_present":true,"life_generation":1,"inside_world":true,"queued_for_retirement":false,"parent_scope_id":1,"can_process":true,"process_processing_enabled":true,"physics_processing_enabled":true,"ordinary_p_enabled":true,"raw_h_enabled":true,"physics_priority":0,"process_priority":0,"process_mode":0})
	return scope if configured else null
func _source_checks(publication: Dictionary) -> Dictionary:
	var rows: Array = []
	var port := Port.new()
	var scope := _scope()
	rows.append([scope != null,"actual production temporal scope constructed on its Source thread"])
	var before: Dictionary = publication.world_identity
	var after: Dictionary = before.duplicate(true)
	after.runtime_map_id = 910001; after.world_epoch += 1
	# Exact value-schema fixture only; empty leaf receipts cannot authorize CAS.
	var transaction := {"contract_id":"hardcore.source.map_arrival.v2","before_world":before,"after_world":after,"source_root_id":port.get_instance_id(),"world_core_id":port.get_instance_id(),"registry_id":scope.get_instance_id(),"owner_session_id":1,"player_runtime_id":1,"player_identity":{"world":after,"runtime_id":1,"life_generation":1},"coordinator_generation":1,"transition_id":"value-schema-only","loading_scope":{},"finish_identity":{},"finish_reply":{}}
	var has_boundary: bool = port.has_method("_arrival_preserves_viewport_binding")
	rows.append([has_boundary,"production viewport has a separate explicit map-arrival binding gate"])
	if has_boundary:
		rows.append([port.call("_arrival_preserves_viewport_binding",transaction,before,scope),"value schema allows one contiguous same-Root same-Profile binding only; not Native authorization"])
		for field: String in ["world_runtime_id","profile_id","world_epoch"]:
			var changed: Dictionary = transaction.duplicate(true)
			if field == "profile_id": changed.after_world[field] = "foreign_profile"
			else: changed.after_world[field] += 1
			changed.player_identity.world = changed.after_world
			rows.append([not port.call("_arrival_preserves_viewport_binding",changed,before,scope),"value gate rejects foreign/skipped after-world " + field])
		rows.append([not port.call("_arrival_preserves_viewport_binding",transaction,after,scope),"already advanced binding rejects stale before-world replay"])
		var missing: Dictionary = transaction.duplicate(true); missing.erase("finish_reply")
		rows.append([not port.call("_arrival_preserves_viewport_binding",missing,before,scope),"incomplete arrival transaction cannot transfer measurement binding"])
		rows.append([scope.queue_retirement() and not port.call("_arrival_preserves_viewport_binding",transaction,before,scope),"actual queued Root scope rejects binding transfer"])
		scope = _scope()
		rows.append([scope.exit_at_original_checkpoint() and not port.call("_arrival_preserves_viewport_binding",transaction,before,scope),"actual exited Root scope rejects binding transfer"])
		rows.append([scope.free_at_original_checkpoint() and not port.call("_arrival_preserves_viewport_binding",transaction,before,scope),"actual final-free Root scope rejects binding transfer"])
		rows.append([not port.call("_arrival_preserves_viewport_binding",transaction,before,null),"missing original Root scope never authorizes transfer"])
	var has_commit: bool = port.has_method("commit_original_map_arrival_transaction")
	rows.append([has_commit,"production binding requires an explicit committed-transaction operation"])
	if has_commit: rows.append([not port.call("commit_original_map_arrival_transaction",transaction),"unconfigured port cannot turn a schema-valid transaction into committed authority"])
	rows.append([publication.is_read_only() and publication.world_identity == before and publication.sequence == 7,"Source boundary tests leave original Main measurement provenance immutable"])
	return {"rows":rows,"uncommitted_transaction":transaction}
func _run() -> void:
	var root := Node2D.new()
	add_child(root)
	var before := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":root.get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"viewport_boundary_fixture"}
	var publication: Dictionary = Port.capture_original_main(root,before,7)
	check(not publication.is_empty() and publication.visible_rect == root.get_viewport().get_visible_rect() and publication.canvas_transform == root.get_canvas_transform(),"real original Main viewport and canvas measurement")
	var foreign: Dictionary = before.duplicate(true); foreign.world_runtime_id += 1
	check(Port.capture_original_main(root,foreign,8).is_empty(),"actual Main capture rejects another physical Root identity")
	var worker := Thread.new()
	check(worker.start(Callable(self,"_source_checks").bind(publication)) == OK,"separate real Source thread starts")
	while worker.is_alive(): await get_tree().process_frame
	var result: Dictionary = worker.wait_to_finish()
	for row: Array in result.rows: check(row[0],row[1])
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	check(not host.verify_committed_original_map_arrival(result.uncommitted_transaction),"actual Native host rejects schema-only transaction with no real settled map CAS")
	var core: String = FileAccess.get_file_as_string("res://scripts/gameplay/world/world_simulation_core.gd")
	var begin: int = core.find("func commit_original_source_map_arrival_context(")
	var end: int = core.find("\nvar _last_original_map_arrival",begin)
	var arrival: String = core.substr(begin,end-begin)
	var preflight: int = arrival.find("viewport.can_commit_original_map_arrival_transaction(transaction)")
	var native_commit: int = arrival.find("_host.commit_original_map_arrival(self,transaction)")
	var core_commit: int = arrival.find("_world_identity = transaction.after_world")
	var viewport_commit: int = arrival.find("viewport.commit_original_map_arrival_transaction(transaction)")
	var reopen: int = arrival.find("_begin_original_entry(&\"P\",\"GameRoot._load_zone:after_actual_arrival\")")
	check(preflight >= 0 and preflight < native_commit,"static production wiring preflights viewport before Native CAS")
	check(viewport_commit > native_commit and viewport_commit > core_commit and viewport_commit < reopen,"static production wiring binds viewport after actual CAS before same-P Root continuation")
	root.free()
	var written: bool = _proof.write_receipt("viewport_arrival_binding_20261017",_proof.records.size(),_failed)
	print("VIEWPORT_ARRIVAL_BINDING_", "PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
