extends Node
## Actual Native FIFO -> production structural registry -> physical renderer ->
## qualification receipt -> Native ACK. Protocol scope; no Enemy factory/LIVE.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Prefix := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd")
const Registry := preload("res://scripts/gameplay/presentation/main_actor_visual_registry.gd")
const Bridge := preload("res://scripts/gameplay/presentation/main_original_visual_phase_bridge.gd")
var proof := Proof.new()
var failed := 0
var _host: Object
var _root: Node2D
var _prefix: RefCounted
var _registry: RefCounted
var _bridge: RefCounted
var _vault: RefCounted
var _world: Dictionary
var _tick := 0
var _closing := false
var _deadline := 0
var _deadline_reported := false
var _qualifications := 0
var _last_service := 0
var source_script: Script = preload("res://tests/framework/helpers/main_visual_qualification_source_20261016.gd")
func check(ok: bool,label: String) -> void:
	proof.record(ok,label)
	if not ok: failed += 1; print("VISUAL_QUALIFICATION_CHECK_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	_root = Node2D.new(); add_child(_root)
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	_prefix = Prefix.new(_host,self)
	_bridge = Bridge.new()
	_vault = preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd").new()
	_world = {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":_root.get_instance_id(),"world_epoch":1,"runtime_map_id":913203,"profile_id":"isolated.visual.protocol"}
	var generation := 115163
	check(_vault.configure_main(Callable(_host,"validate_original_primitive_ticket"),ClassDB.instantiate("HardCoreResourceObservation"),generation),"actual configured Main resource vault is used")
	check(_bridge.configure_main(_root,_world,_host,_prefix,_vault,generation),"one genuine claimed-prefix/physical-vault receiver binds on Main")
	_registry = Registry.new()
	check(_registry.configure_original_structural_main(_root,_world,_bridge),"production structural registry uses the actual Main qualification receiver")
	check(_registry.bind_original_enemy_header_channel(_prefix,_vault),"actual Native prefix and physical renderer registration channel binds")
	check(not _bridge.publish_visual_process_qualification(1,true),"a method call outside a claimed Source event cannot manufacture qualification")
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":generation,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	check(_host.start(source_script,{"world":_world},config),"real Source produces this bounded protocol without creating a fake WorldCore")
	_deadline = Time.get_ticks_usec()+20000000
func apply_original_main_journal_event(event: Dictionary) -> bool:
	if event.get("kind") == "original_world_presentation": return _registry.apply_original_enemy_structural_header(event)
	if event.get("kind") != "enemy_visual": return false
	var visual: Dictionary = event.event
	var ok: bool = _registry.apply_original_enemy_visual_event(visual)
	check(ok,"production registry consumes the genuine original arguments field")
	if not ok: return false
	_last_service = visual.service_id
	var actual: Dictionary = _bridge.inspect_actual_original_visual_qualification(_last_service)
	check(actual.get("status") == "READY" and actual.source_process_enabled == visual.arguments[0] and actual.original_journal_ordinal == event.ordinal,"actual receiver receipt matches Source event and physical Main renderer")
	check(actual.physical_Main_process_enabled == false and actual.physical_Main_physics_enabled == false,"Main creates no second original animation or gameplay tick")
	check(not _bridge.publish_visual_process_qualification(_last_service,not bool(visual.arguments[0])),"a different requested value cannot borrow the current actual Native event")
	_qualifications += 1
	return true
func _process(_delta: float) -> void:
	if _host == null: return
	var next: Dictionary = _host.inspect_next_original_published_prefix()
	if next.get("status") == "READY":
		var applied: Dictionary = _prefix.apply_prefix(next.prefix)
		if applied.get("status") == "APPLIED":
			var ack := {"bridge_generation":next.prefix.bridge_generation,"journal_generation":next.prefix.journal_generation,"through_ordinal":next.prefix.through_ordinal,"applied":true}
			check(_host.ack_published_original_main_prefix(next.prefix,ack) and _prefix.confirm_prefix_acknowledged(next.prefix,ack),"genuine Main writes are acknowledged through the same Native FIFO")
	var packet: Dictionary = _host.acquire_presentation(_tick+1,32)
	if not packet.is_empty():
		_tick = packet.tick; _host.ack_events(packet.through_ordinal)
		if packet.frame.get("done") == true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.passed,row.label)
			check(_qualifications == 2,"both original qualification changes apply exactly once")
			_host.request_close(); _closing = true
	if _closing and _host.status().get("join_complete") == true:
		check(_host.close_and_join(),"actual Source and external physics complete before Main drops the Host")
		_host = null
		_root.free()
		check(_bridge.inspect_actual_original_visual_qualification(_last_service).get("status") == "MISSING","real renderer tree exit retires its qualification receipt")
		_finish()
	elif Time.get_ticks_usec() > _deadline and not _deadline_reported:
		_deadline_reported = true
		check(false,"actual journal receiver finishes within bounded deadline"); _host.request_close(); _closing = true
func _finish() -> void:
	var written: bool = proof.write_receipt("main_visual_qualification_bridge_20261016",proof.records.size(),failed)
	print("MAIN_VISUAL_QUALIFICATION_BRIDGE_20261016_","PASS" if written and failed == 0 else "FAIL")
	get_tree().quit(0 if written and failed == 0 else 1)
