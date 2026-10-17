extends Node
## Actual Main Input/InputMap and original CircularTouchButton; packet crosses
## Native codec and is consumed by the real Source input owner. Not full World.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Source := preload("res://tests/framework/helpers/main_input_source_20261015.gd")
var _proof := Proof.new()
var _failed := 0
var _root: Node2D
var _host: Object
var _tick := 0
var _closing := false
var _deadline := 0
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	# Original keyboard actions are polled in P. A deferred call can otherwise
	# land in H, where Godot deliberately assigns action_press to the NEXT H.
	await get_tree().process_frame
	var path := "res://scripts/gameplay/source/main_original_world_input.gd"
	check(FileAccess.file_exists(path),"real Main input publisher exists")
	if not FileAccess.file_exists(path): _finish(); return
	_root = load("res://scenes/main.tscn").instantiate()
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":_root.get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"isolated.Main.input.component"}
	var publisher: RefCounted = load(path).new()
	check(publisher.configure_main(_root,world),"actual original Root identity binds once before gameplay starts")
	check(not publisher.configure_main(_root,world),"input publisher cannot reset its accepted sequence or world")
	var first: Dictionary = publisher.capture_original_main_input(0)
	check(first.get("success") == true,"actual InputMap and Input state produce the initial packet")
	if first.get("success") != true: _finish(); return
	check(first.publication.original_events.is_empty() and first.publication.sequence == 0,"initial snapshot does not invent an input callback")
	check(first.publication.actions.attack.pressed == Input.is_action_pressed("attack"),"attack action comes from the actual Main Input singleton")
	var button: Control = preload("res://scripts/circular_touch_button.gd").new()
	_root.add_child(button)
	check(publisher.bind_original_attack_button(button),"real original button binds to its owning Root")
	var context := {"actual_Main_capture":true,"world_context":world,"main_process_frame":Engine.get_process_frames(),"warehouse_page":2}
	Input.action_press(&"interact")
	var event: Dictionary = publisher.capture_original_main_input(1,&"warehouse_sort_requested",[],context)
	Input.action_release(&"interact")
	check(event.get("success") == true,"real event context accompanies the same input snapshot")
	if event.get("success") != true: _finish(); return
	check(event.publication.actions.interact.just_pressed,"actual Main action edge is captured before release, without synthetic packet data")
	check(event.publication.attack_button_snapshot == button.input_lifecycle_snapshot(),"actual button lifecycle diagnostic snapshot is retained exactly")
	check(event.publication.buttons.is_empty() and event.publication.button_owner_present,"no accepted lifecycle ownership is fabricated for the detached inactive button")
	check(event.publication.original_events[0].view_context.warehouse_page == 2,"warehouse page remains an actual Main view context value")
	context.warehouse_page = 3
	check(event.publication.original_events[0].view_context.warehouse_page == 2,"publication owns a value snapshot rather than an alias to later Main context")
	check(publisher.capture_original_main_input(1).get("success") != true,"accepted input sequence cannot be replayed")
	var bad: Dictionary = context.duplicate(true); bad.world_context = world.duplicate(true); bad.world_context.world_runtime_id += 1
	check(publisher.capture_original_main_input(2,&"warehouse_sort_requested",[],bad).get("success") != true,"foreign world context is rejected without spending the next sequence")
	check(publisher.capture_original_main_input(2,&"warehouse_sort_requested",[button],context).get("success") != true,"a Main Object cannot leak into Source input")
	var next: Dictionary = publisher.capture_original_main_input(2)
	check(next.get("success") == true,"invalid event did not consume the next genuine input sequence")
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115157,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	check(_host.start(Source,{"world_identity":world,"packets":[first.publication,event.publication,next.publication]},config),"actual Native Source receives snapshots through its real boot codec")
	_deadline = Time.get_ticks_usec()+20000000
func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.acquire_presentation(_tick+1,32)
	if not packet.is_empty():
		_tick = packet.tick; _host.ack_events(packet.through_ordinal)
		if packet.frame.get("done") == true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.pass,row.label)
			_closing = true; _host.request_close()
	if _closing and _host.status().get("join_complete") == true:
		check(_host.close_and_join(),"actual Source input component terminates before Main teardown")
		_host = null; _finish()
	elif Time.get_ticks_usec() > _deadline:
		check(false,"bounded Source input component completes"); _finish()
func _finish() -> void:
	set_process(false)
	if is_instance_valid(_root): _root.free()
	var written: bool = _proof.write_receipt("main_original_input_publication_20261015",_proof.records.size(),_failed)
	print("MAIN_ORIGINAL_INPUT_PUBLICATION_20261015_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
