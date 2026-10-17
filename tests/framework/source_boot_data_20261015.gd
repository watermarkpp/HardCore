extends Node
const Publication := preload("res://scripts/gameplay/source/main_original_session_publication_provider.gd")
const Legacy := preload("res://scripts/gameplay/actors/enemy_legacy_context.gd")
const Source := preload("res://tests/framework/helpers/source_boot_data_owner_20261015.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failures := 0
var _host: Object
var _root: Node2D
var _tick := 0
var _closing := false
var _deadline := 0
func check(value: bool,label: String) -> void:
	_proof.record(value,label)
	if not value:_failures+=1
func _ready() -> void:
	var publisher: RefCounted=Publication.new()
	check(publisher.has_method("capture_original_enemy_shared_initialization"),"initial shared-state producer exists without requiring a previous Enemy")
	check(ResourceLoader.exists("res://scripts/gameplay/source/main_world_source_fields_capture.gd"),"real original Root field producer exists")
	if _failures>0:_finish();return
	check(Legacy._main_context==null,"actual fixture begins with no Main legacy Enemy context")
	var shared: Dictionary=publisher.call("capture_original_enemy_shared_initialization")
	check(shared.get("success")==true,"real Main observes original unconstructed shared state")
	check(Legacy._main_context==null,"capture does not manufacture a Main shared owner")
	_root=load("res://scenes/main.tscn").instantiate()
	var rng: RandomNumberGenerator=_root.get("_rng")
	var before: Dictionary={"seed":rng.seed,"state":rng.state}
	var capture: RefCounted=load("res://scripts/gameplay/source/main_world_source_fields_capture.gd").new()
	var fields: Dictionary=capture.call("capture_original_constructor_fields",_root)
	check(fields.get("success")==true,"actual original constructor fields captured: "+str(fields.get("errors",[])))
	if fields.get("success")!=true:
		print("SOURCE_FIELDS_CAPTURE_DIAGNOSTIC ",fields.get("details",{}))
		_finish();return
	check(fields.source_fields.fields.current_map_id==-1 and fields.source_fields.fields._zone_generation==0,"original pre-map values not rewritten")
	check(fields.world_random==before and rng.seed==before.seed and rng.state==before.state,"Root RNG observed without a draw or re-randomize")
	check(fields.source_fields.get("unbound_owner_fields")==["_feature_target_bound","_rng","_world_bootstrap_coordinator","_world_context"],"original Root owner objects use declared Source binding slots, never Main references")
	check(fields.source_fields.fields.size()>=100,"full original numeric Root field set, not a hand-picked default fixture")
	var decoded: Dictionary=preload("res://scripts/gameplay/source/source_constructor_value_codec.gd").decode(fields.source_fields)
	check(decoded.get("ok")==true and decoded.value._world_camera_presented_center==Vector2.INF and decoded.value._player_safe_zone_cache.ground_position_gu==Vector2.INF,"original no-position sentinels survive transport exactly")
	check(_root.get("_world_camera_presented_center")==Vector2.INF and _root.get("_player_safe_zone_cache").ground_position_gu==Vector2.INF,"encoding never changes original Main cache values")
	var tampered: Dictionary=fields.source_fields.duplicate(true)
	tampered.constructor_values.vector2_inf_paths.append(["current_map_id"])
	check(not preload("res://scripts/gameplay/source/source_constructor_value_codec.gd").decode(tampered).ok,"unknown sentinel location cannot bypass strict value validation")
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	check(graph.validate(fields.source_fields,false).get("success")==true,"runtime field graph contains no Main object")
	var settings: Dictionary={}
	for key: String in ["hardcore/performance/owner_decision_interval_ms","hardcore/performance/owner_optional_budget_enabled","hardcore/performance/ordinary_contact_instant_settle","hardcore/performance/ordinary_attack_visual_move_override"]:
		settings[key]=ProjectSettings.get_setting(key)
	var original_shared_code: Script=preload("res://scripts/gameplay/actors/enemy_shared_state.gd")
	_host=ClassDB.instantiate("HardCoreSimulationHost")
	var config: Dictionary={"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":16,"bridge_generation":115138,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	var started: bool=_host.start_clock_fixture(Source,{"shared":shared.publication,"fields":fields.source_fields,"settings":settings,"source_sha256":original_shared_code.get_source_code().sha256_text()},config)
	check(started,"actual Native S receives genuine Root/shared initialization data")
	if not started:_host=null;_finish();return
	_deadline=Time.get_ticks_usec()+5000000
func _process(_delta: float) -> void:
	if _host==null:return
	var packet: Dictionary=_host.acquire_presentation(_tick+1,16)
	if not packet.is_empty():
		_tick=int(packet.tick);_host.ack_events(int(packet.through_ordinal))
		if packet.frame.get("done")==true and not _closing:
			for row: Dictionary in packet.frame.checks:check(row.pass,row.label)
			_closing=true;_host.request_close()
	if _closing and _host.status().get("join_complete")==true:
		check(_host.close_and_join(),"actual Source-owned initialization state retires")
		_host=null;_finish()
	elif Time.get_ticks_usec()>_deadline and not _closing:
		check(false,"actual source boot data validation reaches endpoint")
		_closing=true;_host.request_close()
func _finish() -> void:
	if is_instance_valid(_root):_root.free()
	check(Legacy._main_context==null,"no Main Enemy shared owner remains after initialization")
	var written: bool=_proof.write_receipt("source_boot_data_20261015",_proof.records.size(),_failures)
	print("SOURCE_BOOT_DATA_20261015_","PASS" if written and _failures==0 else "FAIL"," checks=",_proof.records.size()," failures=",_failures)
	get_tree().quit(0 if written and _failures==0 else 1)
