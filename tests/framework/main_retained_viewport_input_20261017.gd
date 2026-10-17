extends Node
## Real Main measurements and InputMap, plus real Native rejection and explicit
## value-schema checks. Only full World can prove the positive committed seam.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Publisher := preload("res://scripts/gameplay/source/main_original_world_input.gd")
const ViewportPort := preload("res://scripts/gameplay/world/world_visual_viewport_port.gd")
var proof := Proof.new()
var failed := 0
func check(ok: bool, label: String) -> void:
	proof.record(ok,label)
	if not ok: failed += 1; print("RETAINED_VIEWPORT_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	await get_tree().process_frame
	var measured_root := Node2D.new(); add_child(measured_root)
	var before := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":measured_root.get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"retained.viewport.schema"}
	var publication: Dictionary = ViewportPort.capture_original_main(measured_root,before,7)
	check(not publication.is_empty() and publication.visible_rect == measured_root.get_viewport().get_visible_rect(),"actual physical Main viewport measurement, not a fabricated rectangle")
	var context := {"actual_Main_capture":true,"world_context":before.duplicate(true),"main_process_frame":Engine.get_process_frames(),"actual_hud_observation":{}}
	var schema_owner := Publisher.new()
	var method: StringName = &"_is_retained_viewport_context"
	var has_gate: bool = schema_owner.has_method(method)
	check(has_gate,"production Main publisher exposes an observation-only value-schema gate")
	check(has_gate and schema_owner.call(method,&"world_viewport_publication",[publication],context,before),"exact original viewport/context schema accepted; this is NOT Native authority")
	for kind: StringName in [&"mobile_attack_started",&"skill_input_started",&"notification",&"warehouse_sort_requested",&"shop_buy_requested",&"source_frames_texture_demand"]:
		check(has_gate and not schema_owner.call(method,kind,[publication],context,before),"retained observation privilege never authorizes " + String(kind))
	var changed: Dictionary = context.duplicate(true); changed.world_context.profile_id = "foreign"
	check(has_gate and not schema_owner.call(method,&"world_viewport_publication",[publication],changed,before),"foreign Profile context rejected")
	changed = context.duplicate(true); changed.world_context.world_runtime_id += 1
	check(has_gate and not schema_owner.call(method,&"world_viewport_publication",[publication],changed,before),"foreign physical Root rejected")
	changed = context.duplicate(true); changed.world_context.world_epoch += 1
	check(has_gate and not schema_owner.call(method,&"world_viewport_publication",[publication],changed,before),"old observation context cannot be relabeled after arrival")
	changed = context.duplicate(true); changed.actual_Main_capture = false
	check(has_gate and not schema_owner.call(method,&"world_viewport_publication",[publication],changed,before),"missing original Main capture rejected")
	changed = context.duplicate(true); changed.main_process_frame = Engine.get_process_frames()+1
	check(has_gate and not schema_owner.call(method,&"world_viewport_publication",[publication],changed,before),"future observation frame rejected")
	changed = context.duplicate(true); changed.erase("actual_hud_observation")
	check(has_gate and not schema_owner.call(method,&"world_viewport_publication",[publication],changed,before),"omitted HUD observation rejected")
	var reidentified: Dictionary = publication.duplicate(true); reidentified.world_identity.world_epoch += 1
	check(has_gate and not schema_owner.call(method,&"world_viewport_publication",[reidentified],context,before),"measurement identity remains exactly the original capture")
	check(has_gate and not schema_owner.call(method,&"world_viewport_publication",[publication,publication],context,before),"multiple measurement arguments cannot bypass the one-observation gate")
	check(publication.is_read_only() and publication.world_identity == before and publication.sequence == 7,"schema checks preserve the immutable original measurement")
	var root: Node2D = load("res://scenes/main.tscn").instantiate()
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":root.get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"retained.viewport.actual.publisher"}
	var publisher := Publisher.new()
	check(publisher.configure_main(root,world),"real original Root configures actual InputMap publisher")
	var initial: Dictionary = publisher.capture_original_main_input(0)
	check(initial.get("success") == true and initial.publication.world_context == world,"actual initial InputMap sample uses this original Root identity")
	var after: Dictionary = world.duplicate(true); after.runtime_map_id = 910001; after.world_epoch += 1
	var transaction := {"contract_id":"hardcore.source.map_arrival.v2","before_world":world,"after_world":after,"source_root_id":publisher.get_instance_id(),"world_core_id":publisher.get_instance_id(),"registry_id":publisher.get_instance_id(),"owner_session_id":1,"player_runtime_id":1,"player_identity":{"world":after,"runtime_id":1,"life_generation":1},"coordinator_generation":1,"transition_id":"schema-only-no-native-cas","loading_scope":{},"finish_identity":{},"finish_reply":{}}
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	check(not host.verify_committed_original_map_arrival(transaction),"real Native Host rejects this uncommitted schema-only transaction")
	check(not publisher.commit_actual_original_map_arrival(transaction),"publisher cannot create arrival authority without an actual Native Host")
	check(publisher.get("_world") == world,"rejected unverified arrival cannot mutate publisher world")
	var args_count := 0
	for row: Dictionary in publisher.get_method_list():
		if row.name == "commit_actual_original_map_arrival": args_count = row.args.size()
	check(args_count == 2,"publisher requires the real Native Host at its commit boundary")
	if args_count == 2:
		check(not publisher.call("commit_actual_original_map_arrival",transaction,host),"unstarted actual Host still cannot authorize the uncommitted transaction")
	var event_context := {"actual_Main_capture":true,"world_context":world,"main_process_frame":Engine.get_process_frames(),"warehouse_page":2}
	var current: Dictionary = publisher.capture_original_main_input(1,&"warehouse_sort_requested",[],event_context)
	check(current.get("success") == true and current.publication.world_context == world,"failed commit leaves ordinary real Main input and its next serial usable")
	check(publisher.has_method("_can_capture_retained_viewport") and not publisher.call("_can_capture_retained_viewport",&"world_viewport_publication",[publication],context),"publisher with no committed Host seam cannot authorize even a schema-valid measurement")
	root.free(); measured_root.free(); host = null
	var written: bool = proof.write_receipt("main_retained_viewport_input_20261017",proof.records.size(),failed)
	print("MAIN_RETAINED_VIEWPORT_INPUT_", "PASS" if written and failed == 0 else "FAIL")
	get_tree().quit(0 if written and failed == 0 else 1)
