extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures := 0
var _host: Object
var _tick := 0
var _closing := false
var _deadline := 0
func _ready() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	proof.record(ok,label)
	if not ok: failures += 1
func _run() -> void:
	check(FileAccess.file_exists("res://scripts/gameplay/source/main_original_service_birth_capture.gd"),"actual original service constructor producer exists")
	if failures != 0: _finish(); return
	var producer: Script = load("res://scripts/gameplay/source/main_original_service_birth_capture.gd")
	var before: int = get_child_count(true)
	var captured: Dictionary = producer.capture(self)
	check(captured.get("success") == true,"actual Main captures unchanged original service constructors without entering their READY bodies")
	check(get_child_count(true) == before,"capturing constructors does not add gameplay or physics Nodes to the real parent")
	if captured.get("success") != true: _finish(); return
	var publication: Dictionary = captured.publication
	var body: Dictionary = preload("res://scripts/gameplay/world/world_environment_boot_publication.gd")._capture_body_templates()
	check(body.get("ok") == true,"actual formal environment producer captures original native body policy before Source starts")
	var parent: Dictionary = preload("res://scripts/gameplay/source/main_original_process_scope.gd").capture_existing(self)
	var actors: Dictionary = preload("res://scripts/gameplay/source/main_original_actor_birth_templates.gd").capture_main(parent.scope,body.get("value",{}))
	check(actors.get("success") == true,"reviewed original actor constructors yield source-bound templates without legacy physics actors: "+str(actors.get("error","")))
	if actors.get("success") != true: _finish(); return
	publication = publication.duplicate(false)
	publication.actor_birth_templates = actors.templates
	var actor_kinds: Array = actors.templates.keys()
	actor_kinds.sort()
	check(actor_kinds == ["enemy","enemy_projectile","enemy_target_magic","field","fire_wall","loot","npc","player","projectile","summon","zone_portal"] and actors.templates.player.exact_player_contract,"exact eleven production actor kinds retain original attack variants and canonical zone_portal")
	check(actors.templates.get("zone_portal",{}).get("constructor_source_path") == "res://scripts/zone_portal.gd" and not actors.templates.has("portal"),"portal constructor publishes the same stable zone_portal ID requested by the real Source factory")
	check(actors.templates.fire_wall.source_callbacks.has("_process") and actors.templates.fire_wall.source_callbacks.has("_physics_process") and not actors.templates.field.source_callbacks.has("_process"),"fire wall retains its actual P/H source while generic ground field remains H-only")
	check(actors.templates.player.scope.inside_world == false and actors.templates.player.scope.parent_scope_id == 0 and not actors.templates.player.has("runtime_id"),"constructor publication allocates no future actor identity or Source child membership")
	check(publication.service_birth_scopes.size() == 6 and publication.service_callback_templates.size() == 6,"all six current production service kinds have constructor and callback source witnesses, including the original PlayerVisual")
	for kind: String in publication.service_birth_scopes:
		var scope: Dictionary = publication.service_birth_scopes[kind]
		check(scope.runtime_present and scope.life_generation == preload("res://scripts/gameplay/world/world_temporal_scope.gd").new().life_generation,"scope uses the genuine structural constructor lifetime:"+kind)
		check(not scope.inside_world and not scope.queued_for_retirement and scope.parent_scope_id == 0,"service birth does not pretend the original add_child already happened:"+kind)
		check(scope.effective_process_mode == Node.PROCESS_MODE_PAUSABLE,"original inherited parent qualification is captured:"+kind)
		var witness: Dictionary = publication.constructor_witnesses[kind]
		check(witness.actual_original_child_count == 0 and witness.original_class not in ["CharacterBody2D","Area2D"],"read-only constructor adds no physics actor or READY children:"+kind)
		if not witness.script_path.is_empty():
			var original: Script = load(witness.script_path)
			var node: Node = original.new()
			check(scope.process_processing_enabled == node.is_processing() and scope.physics_processing_enabled == node.is_physics_processing() and scope.process_mode == node.process_mode,"publication preserves actual original constructor flags:"+kind)
			check(witness.script_sha256 == original.get_source_code().sha256_text(),"published constructor source hash is the actual loaded original Script:"+kind)
			node.free()
	var timer: Dictionary = publication.service_callback_templates.node_timer.callbacks
	check(timer.original_internal_process.domain == "P" and timer.original_internal_process.internal and timer.original_internal_physics.domain == "H" and timer.original_internal_physics.internal,"Node Timer retains actual native INTERNAL H/P notification slots")
	check(publication.service_callback_templates.monster_visual.callbacks.has("_process") and publication.service_callback_templates.m30_summon_queue.callbacks.has("_physics_process") and publication.service_callback_templates.loot_runtime_manager.callbacks.has("_process"),"actual current original callbacks are captured from their defining Scripts")
	check(publication.service_callback_templates.player_visual.callbacks._process.entry == "res://scripts/player_visual.gd:_process","PlayerVisual retains its real defining P callback, not PlayerCharacter or a synthetic publisher entry")
	var detached := Node.new()
	check(not producer.capture(detached).get("success",false),"a detached prospective parent cannot supply a false inherited tree qualification")
	detached.free()
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115162,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	check(_host.start(preload("res://tests/framework/helpers/service_birth_scope_source_20261016.gd"),publication,config),"actual Native Host starts Source scope consumption without a fake World")
	_deadline = Time.get_ticks_usec()+20000000
func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.acquire_presentation(_tick+1,32)
	if not packet.is_empty():
		_tick = packet.tick; _host.ack_events(packet.through_ordinal)
		if packet.frame.get("done") == true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.passed,row.label)
			_host.request_close(); _closing = true
	if _closing and _host.status().get("join_complete") == true:
		check(_host.close_and_join(),"actual Source owns its scope retirement and releases external physics before Main exit")
		_host = null; _finish()
	elif Time.get_ticks_usec() > _deadline:
		check(false,"real scope publication consumer finishes inside its bounded component deadline")
		_host.request_close(); _closing = true
func _finish() -> void:
	var written: bool = proof.write_receipt("service_birth_capture_20261016",proof.records.size(),failures)
	print("SERVICE_BIRTH_CAPTURE_20261016_","PASS" if written and failures == 0 else "FAIL")
	get_tree().quit(0 if written and failures == 0 else 1)
