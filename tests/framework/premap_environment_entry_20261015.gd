extends Node
## Actual formal content capture -> Native immutable boot -> S BootLoader.
## No fake map runtime, no full-world boot or copied-user-save claim.
const Source := preload("res://tests/framework/helpers/premap_environment_source_20261015.gd")
const Boot := preload("res://scripts/gameplay/world/world_environment_boot_publication.gd")
const Background := preload("res://scripts/world_background.gd")
const App := preload("res://scripts/gameplay/source/main_boot_application.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _publisher: RefCounted = Boot.new()
var _proof := Proof.new()
var _failed := 0
var _host: Object
var _root: Node2D
var _background: Node2D
var _tick := 0
var _closing := false
var _deadline := 0
func check(value: bool,label: String) -> void:
	_proof.record(value,label)
	if not value: _failed+=1
func _ready() -> void:
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"original profile operations are isolated")
	check(_publisher.has_method("capture_before_first_map"),"real pre-map environment capture is implemented")
	if _failed>0: _finish();return
	PlayerState.test_mode=true
	PlayerState.reset_progress(false)
	var isolated: String="user://premap_environment_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory=isolated.path_join("characters")
	PlayerState.profile_index_path=isolated.path_join("profiles.json")
	PlayerState.shared_warehouse_path=isolated.path_join("warehouse.json")
	PlayerState.shared_warehouse_transaction_log_path=isolated.path_join("warehouse.transaction.json")
	PlayerState._shared_warehouse_initialized=false
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))==OK,"isolated original profile directory")
	PlayerState.test_mode=false
	var created: String=PlayerState.create_character("MapEntry115")
	check(created.is_empty(),"real profile created: "+created)
	if not created.is_empty(): _finish();return
	check(PlayerState.select_character(PlayerState.active_profile_id),"real selected profile loaded")
	_root=load("res://scenes/main.tscn").instantiate()
	_background=Background.new()
	check(_background.defer_initial_legacy_build_to_coordinator(),"original initial Background build remains assigned to the map coordinator")
	var identity: Dictionary=App.inspect_original_root_identity(_root,PlayerState)
	check(identity.get("success")==true,"actual original Root and selected profile identity")
	if identity.get("success")!=true: _finish();return
	var target: int=GameData.service_home_runtime_map_id(false)
	var maps: Array[int]=[target]
	var policy: Dictionary={"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":16}
	var generation: String=PlayerState._world_clock_generation
	var captured: Dictionary=App.capture_actual_original_pre_map_environment(_root,PlayerState,get_tree(),identity.world,policy)
	check(captured.get("ok")==true,"formal content and physical defaults captured without activating destination: "+str(captured.get("errors",[])))
	if captured.get("ok")!=true: _finish();return
	check(captured.boot.world_clock_generation==generation,"real Main application producer preserves the loaded Profile's exact original clock generation")
	check(captured.boot.pre_map_context.prepared_map_ids.has(target),"real Main application resolves the original home target without activating it")
	check(_root.current_map_id==-1 and _root._zone_generation==0 and _background.zone_data.is_empty(),"capture never advances Root map or environment zone")
	check(_background.get_child_count()==0 and _background.get("_source_collision_shape_count")==0,"capture creates no environment collision actors")
	check(captured.boot.pre_map_context.source_sha256==_background.get_script().get_source_code().sha256_text(),"prepared background source is actual loaded original script")
	check(captured.boot.world_identity==identity.world,"canonical five-field identity is preserved")
	var current_profile_path: String=PlayerState._profile_path(PlayerState.active_profile_id)
	var profile_hash: String=FileAccess.get_sha256(current_profile_path)
	_host=ClassDB.instantiate("HardCoreSimulationHost")
	var config: Dictionary=policy.duplicate(true)
	config.physics_hz=Engine.physics_ticks_per_second
	config.bridge_generation=115134
	config.source_process_frame=Engine.get_process_frames();config.source_physics_frame=Engine.get_physics_frames()
	config.primitive_request_capacity=65536;config.primitive_result_capacity=65536
	config.source_deferred_max_pages=int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256
	var started: bool=_host.start(Source,{"world_identity":identity.world,"environment":captured.boot,"target_map":target},config)
	check(started,"real Native Source receives immutable formal environment")
	check(FileAccess.get_sha256(current_profile_path)==profile_hash,"content preparation does not rewrite selected profile")
	if not started: _host=null;_finish();return
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
		check(_host.close_and_join(),"actual Source owner closes before Main capture objects")
		_host=null;_finish()
	elif Time.get_ticks_usec()>_deadline and not _closing:
		check(false,"formal environment Source validation reached deadline")
		_closing=true;_host.request_close()
func _finish() -> void:
	if is_instance_valid(_background):_background.free()
	if is_instance_valid(_root):_root.free()
	PlayerState.test_mode=true
	var written: bool=_proof.write_receipt("premap_environment_entry_20261015",_proof.records.size(),_failed)
	print("PREMAP_ENVIRONMENT_ENTRY_20261015_","PASS" if written and _failed==0 else "FAIL"," checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed==0 else 1)
