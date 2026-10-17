extends "res://tests/framework/main_visual_qualification_bridge_20261016.gd"
## Genuine Native header -> actual physical renderer retirement component.
## Full Source final-free/CPS/binding COMMITTED acceptance is a separate gate.
const RetirementContract := preload("res://scripts/gameplay/world/world_source_application_contract.gd")
var _retirement_started := false
func _init() -> void:
	source_script = preload("res://tests/framework/helpers/renderer_retirement_source_20261016.gd")

func _process(_delta: float) -> void:
	if _retirement_started or _host == null: return
	# Own the terminal branch: the base fixture frees the Main tree immediately
	# when Source joins, including a join racing the ACK in this same callback.
	var next: Dictionary = _host.inspect_next_original_published_prefix()
	if next.get("status") == "READY":
		var applied: Dictionary = _prefix.apply_prefix(next.prefix)
		if applied.get("status") == "APPLIED":
			var ack: Dictionary = {"bridge_generation":next.prefix.bridge_generation,"journal_generation":next.prefix.journal_generation,"through_ordinal":next.prefix.through_ordinal,"applied":true}
			check(_host.ack_published_original_main_prefix(next.prefix,ack) and _prefix.confirm_prefix_acknowledged(next.prefix,ack),"genuine Main writes retire through the same Native FIFO")
	var packet: Dictionary = _host.acquire_presentation(_tick+1,32)
	if not packet.is_empty():
		_tick = packet.tick; _host.ack_events(packet.through_ordinal)
		if packet.frame.get("done") == true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.passed,row.label)
			check(_qualifications == 2,"both actual visual qualifications apply exactly once")
			_host.request_close(); _closing = true
	if _closing and _host.status().get("join_complete") == true:
		_retirement_started = true
		_run_physical_retirement()
	elif Time.get_ticks_usec() > _deadline and not _deadline_reported:
		_deadline_reported = true
		check(false,"actual journal receiver finishes within its original bounded deadline")
		_host.request_close(); _closing = true

func _run_physical_retirement() -> void:
	var ids: Array = _registry.get("_actors").keys()
	check(ids.size() == 2,"the actual claimed Native headers created two known actors")
	if ids.size() != 2: _finish(); return
	var row: Dictionary = {}
	var without_visual: Dictionary = {}
	for id: int in ids:
		var candidate: Dictionary = _registry.get("_actors")[id]
		if candidate.visual_header.is_empty(): without_visual = candidate
		else: row = candidate
	check(not row.is_empty() and not without_visual.is_empty(),"real ACTOR_HEADER-only and VISUAL_HEADER rows are distinguished")
	if row.is_empty() or without_visual.is_empty(): _finish(); return
	var identity: Dictionary = row.identity.duplicate(true)
	var forged: Dictionary = identity.duplicate(true); forged.life_generation += 1
	check(_registry.capture_original_actor_free_state(forged).get("status") == "INVALID","a different life cannot obtain another actor's actual retirement fact")
	var wrong_world: Dictionary = identity.duplicate(true); wrong_world.world.world_epoch += 1
	check(_registry.capture_original_actor_free_state(wrong_world).get("status") == "INVALID","a current-world guess cannot replace an original retiring header world")
	var premap: Dictionary = identity.duplicate(true); premap.world.runtime_map_id = -1; premap.world.world_epoch = 0; premap.life_generation = 0
	check(RetirementContract.accepts("actor_view_free_state",[premap]) and RetirementContract.accepts("world_view_exit_state",[premap.world]),"strict cleanup schema preserves the real premap life-zero identity")
	var invalid_formal: Dictionary = premap.duplicate(true); invalid_formal.world.runtime_map_id = 913203
	check(not RetirementContract.accepts("actor_view_free_state",[invalid_formal]) and not RetirementContract.accepts("actor_view_free_state",[identity,identity]),"formal life-zero and extra operands remain invalid")
	var before: Dictionary = _registry.capture_original_actor_free_state(identity)
	check(before.get("status") == "PENDING" and _registry.get("_retiring").size() == 1,"real queue_free remains pending and retains the exact requested identity")
	var without_identity: Dictionary = without_visual.identity.duplicate(true)
	check(_registry.capture_original_actor_free_state(without_identity).get("status") == "PENDING","an actor with no visual service still requires actual Node destruction")
	var node: WeakRef = weakref(row.view)
	await get_tree().process_frame
	var actual: Dictionary = _registry.capture_original_actor_free_state(identity)
	check(node.get_ref() == null and actual.get("status") == "READY" and actual.get("actual_node_absent") == true,"receipt waits for the real actor and visual Node storage to disappear")
	check(actual.get("actor_identity") == identity and actual.get("service_id") == _last_service,"original header identity and true visual service survive physical destruction")
	check(actual.get("actual_assets",{}).get("structural_only") == true and actual.get("renderer_registration_retired") == false,"header-only without AssetPort still retains the actual renderer registration debt")
	check(_vault.get("_renderers").has(_last_service) and _registry.get("_retiring").size() == 2,"physical absence cannot erase an unretired original visual registration")
	check(_registry.capture_original_actor_free_state(identity) == actual,"duplicate physical polling returns the same evidence without replaying queue_free")
	var no_visual: Dictionary = _registry.capture_original_actor_free_state(without_identity)
	check(no_visual.get("status") == "READY" and no_visual.get("service_id") == 0 and no_visual.get("metadata_released") == true and no_visual.get("renderer_registration_retired") == true,"actual no-visual Node absence releases precisely its own metadata without inventing a renderer")
	check(_registry.capture_original_actor_free_state(without_identity).get("status") == "INVALID","a new request after final receipt removal cannot borrow an unbounded tombstone")
	var unknown: Dictionary = identity.duplicate(true); unknown.runtime_id += 1
	check(_registry.capture_original_actor_free_state(unknown).get("status") == "INVALID","an empty table lookup is never proof that a requested actor was freed")
	check(_host.close_and_join(),"actual protocol Source joins before its Main fixture storage is released")
	_host = null; _root.free()
	_finish()

func _finish() -> void:
	var written: bool = proof.write_receipt("renderer_retirement_physical_20261016",proof.records.size(),failed)
	print("RENDERER_RETIREMENT_PHYSICAL_20261016_","PASS" if written and failed == 0 else "FAIL")
	get_tree().quit(0 if written and failed == 0 else 1)
