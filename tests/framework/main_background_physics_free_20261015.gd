extends Node
## Actual external S owner plus Main display construction. Not a game World,
## Loading resource closure or performance/device acceptance.
const Source := preload("res://tests/framework/helpers/premap_context_source_20261015.gd")
const Gothic := preload("res://scripts/layers/presentation/gothic_bich_camp_builder.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
var _host: Object
var _tick := 0
var _deadline := 0
var _closing := false
var _baseline_collisions: Array = []
var _baseline_visuals: Array[String] = []
var _display_root: Node2D
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func _ready() -> void: _run.call_deferred()
func _visual_signature(node: Node,result: Array[String]) -> void:
	if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D: return
	if node is Sprite2D: result.append(JSON.stringify([node.get_class(),node.texture.resource_path if node.texture != null else "",node.position,node.z_index,node.z_as_relative]))
	elif node is PointLight2D: result.append(JSON.stringify([node.get_class(),node.texture.resource_path if node.texture != null else "",node.position]))
	for child: Node in node.get_children(true): _visual_signature(child,result)
func _run() -> void:
	var timer_default: Variant = ClassDB.class_get_property_default_value("HardCoreSimulationTimer","time_left")
	var margin_default: Variant = ClassDB.class_get_property_default_value("HardCoreSimulationActorMotion2D","collision_safe_margin")
	check(timer_default is float and timer_default == 0.0,"actual Native metadata reads only the uncreated timer constructor default")
	check(margin_default is float and margin_default >= 0.0,"actual Native metadata reads the uncreated motion's constructor margin without claiming a world")
	var original_root := Node2D.new()
	var original_background := Node2D.new()
	original_root.add_child(original_background)
	var original: Dictionary = Gothic.build(original_background,Vector2(12,34))
	_baseline_collisions = original.collisions.duplicate(true)
	_visual_signature(original_root,_baseline_visuals);_baseline_visuals.sort()
	check(not _baseline_collisions.is_empty() and not _baseline_visuals.is_empty(),"unchanged original builder produces real visual Nodes and collision definitions before handoff")
	original_root.free() # All baseline physics objects leave Main BEFORE external ownership.
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"isolated.Main.visual.component"}
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115156,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	check(_host.start(Source,{"world_identity":world},config),"actual Source claims the external Physics2D backend before Main display creation")
	_deadline = Time.get_ticks_usec()+20000000
func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.acquire_presentation(_tick+1,32)
	if not packet.is_empty():
		_tick = packet.tick
		_host.ack_events(packet.through_ordinal)
		if packet.frame.get("done") == true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.pass,row.label)
			_verify_actual_Main_display()
			_closing = true
			_host.request_close()
	if _closing and _host.status().get("join_complete") == true:
		check(_host.close_and_join(),"real external owner releases physics and finishes TLS before Main exits")
		_host = null
		_finish()
	elif Time.get_ticks_usec() > _deadline:
		check(false,"bounded Main display/external-owner fixture terminates")
		_finish()
func _verify_actual_Main_display() -> void:
	check(_host.status().get("running") == true and _host.status().get("owner_thread") != OS.get_main_thread_id(),"the independent real Source still owns physics during Main display work")
	var path := "res://scripts/gameplay/world/world_main_background.gd"
	check(FileAccess.file_exists(path),"actual Main Background display implementation exists, not only same-name calls")
	if not FileAccess.file_exists(path): return
	var renderer: Node2D = load(path).new()
	check(renderer.configure_original_Main_visual_only(),"renderer configures its actual visual role before tree membership")
	_display_root = Node2D.new();add_child(_display_root);_display_root.add_child(renderer)
	check(renderer.original_visual_environment_is_physics_free(),"actual entered Main display contains no physics Objects or shapes")
	var descriptor := {"kind":"gothic_camp","payload":{"home":Vector2(12,34)}}
	var actual: Node = renderer.build_original_visual_map_item(descriptor)
	check(actual != null,"real Gothic display Nodes build while S owns Physics2D")
	check(renderer.original_visual_environment_is_physics_free(),"Gothic visuals never create a second Main collision authority")
	check(renderer.get("_gothic_camp_built").get("collisions") == _baseline_collisions,"all original collision definitions remain available to the Source build instead of deleting gameplay obstacles")
	var signatures: Array[String] = [];_visual_signature(_display_root,signatures);signatures.sort()
	check(signatures == _baseline_visuals,"same actual textures, positions, z-order and lights survive visual/physical separation")
	_display_root.free();_display_root = null
func _finish() -> void:
	set_process(false)
	if is_instance_valid(_display_root): _display_root.free()
	var written: bool = _proof.write_receipt("main_background_physics_free_20261015",_proof.records.size(),_failed)
	print("MAIN_BACKGROUND_PHYSICS_FREE_20261015_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
