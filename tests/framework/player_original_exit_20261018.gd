extends Node
const Source := preload("res://tests/framework/helpers/player_original_exit_source_20261018.gd")
const BodyCapture := preload("res://scripts/gameplay/world/world_environment_boot_publication.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
var _host: Object
var _root: Node2D
var _last_tick := 0
var _closing := false
var _deadline := 0
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed += 1
func _ready() -> void:
	check(ProjectSettings.get_setting("physics/2d/external_owner_mode",false) == true,"exact fixture-scoped external-owner configuration")
	if _failed > 0: _finish(); return
	var factory: String = FileAccess.get_file_as_string("res://scripts/gameplay/actors/actor_runtime_factory.gd")
	check(not factory.contains("model.combat_epoch = context.life_generation"),"static source guard: factory does not overwrite original PlayerModel life from temporal scope")
	var body: Dictionary = BodyCapture._capture_body_templates()
	check(body.get("ok") == true,"actual original shape/filter/motion template captured before S claim")
	if body.get("ok") != true: _finish(); return
	var motion: Dictionary = body.value.motion.duplicate(true)
	motion.footprint_points = body.value.footprints.player.footprint_points
	motion.position_screen_px = Vector2.ZERO
	motion.merge(body.value.filters.player)
	_root = load("res://scenes/main.tscn").instantiate()
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":_root.get_instance_id(),"world_epoch":_root.get("_zone_generation"),"runtime_map_id":_root.get("current_map_id"),"profile_id":"original_player_birth_fixture"}
	var area := {"gravity":ProjectSettings.get_setting("physics/2d/default_gravity"),"gravity_vector":ProjectSettings.get_setting("physics/2d/default_gravity_vector"),"linear_damp":ProjectSettings.get_setting("physics/2d/default_linear_damp"),"angular_damp":ProjectSettings.get_setting("physics/2d/default_angular_damp")}
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115127,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	var actual_boot: Dictionary = {"area":area,"motion":motion,"world_identity":world}
	var graph: Object = ClassDB.instantiate("HardCoreContentValueGraph")
	var frozen: Dictionary = graph.capture(actual_boot,true,false)
	check(frozen.get("success") == true,"actual runtime boot preserves original named motion fields")
	var started: bool = _host.start(Source,actual_boot,config)
	check(started,"actual production Host claims original backend for this Source component")
	if not started: _host = null; _finish(); return
	_deadline = Time.get_ticks_usec()+25000000
func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.acquire_presentation(_last_tick+1,32)
	if not packet.is_empty():
		_last_tick = int(packet.tick); _host.ack_events(int(packet.through_ordinal))
		if packet.frame.get("done") == true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.passed,row.label)
			_closing = true; _host.request_close()
	if _closing and _host.status().get("join_complete") == true:
		check(_host.close_and_join(),"actual S closes body/registry/leases before Main join")
		_host = null
		_finish()
	elif Time.get_ticks_usec() > _deadline:
		check(false,"actual player lifecycle component exceeded bounded test deadline")
		_finish()
func _finish() -> void:
	set_process(false)
	if is_instance_valid(_root): _root.free()
	var written: bool = _proof.write_receipt("player_original_exit_20261018",_proof.records.size(),_failed)
	print("PLAYER_ORIGINAL_EXIT_20261018_", "PASS" if written and _failed == 0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
