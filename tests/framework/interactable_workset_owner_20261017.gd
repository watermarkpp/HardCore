extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const LegacyRules := preload("res://scripts/profession_rules.gd")
const Source := preload("res://tests/framework/helpers/interactable_workset_owner_source_20261017.gd")
var _proof := Proof.new()
var _failed := 0
var _host: Object
var _main_owner_id := 0
var _tick := 0
var _closing := false
var _deadline := 0
func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var cases: Array = [
		{"id":"empty","values":[],"limit":7},
		{"id":"zero","values":["火球术"],"limit":0},
		{"id":"negative","values":["雷电术"],"limit":-1},
		{"id":"duplicates_aliases","values":["火球术","wizard.fireball","雷电术","火球术","invalid",""],"limit":7},
		{"id":"cap_seven","values":["火球术","雷电术","冰咆哮","爆裂火焰","火墙","治愈术","施毒术","灵魂火符","基本剑术"],"limit":7},
		{"id":"priority_one","values":["雷电术","火球术"],"limit":1},
		{"id":"unknown","values":["not_a_skill",123,""],"limit":7}]
	for row: Dictionary in cases: row.expected = Registry.workset_skill_order(row.values,int(row.limit))
	var owner: RefCounted = LegacyRules._owner()
	_main_owner_id = owner.get_instance_id()
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":16,"bridge_generation":115217,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	var started: bool = _host.start_clock_fixture(Source,{"cases":cases,"main_owner_id":_main_owner_id,"growth_path":owner.get("_growth_source_path")},config)
	check(started,"real Native Host starts the owner-local workset component")
	if not started:
		_host = null
		_finish()
		return
	_deadline = Time.get_ticks_usec()+5000000
func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.acquire_presentation(_tick+1,16)
	if not packet.is_empty():
		_tick = int(packet.tick); _host.ack_events(int(packet.through_ordinal))
		if packet.frame.get("done") == true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.passed,row.label)
			_closing = true; _host.request_close()
	if _closing and _host.status().get("join_complete") == true:
		check(_host.close_and_join(),"actual Source owner closes before Main component exit")
		check(LegacyRules._owner().get_instance_id() == _main_owner_id,"Source workset leaves the original Main owner unchanged")
		_host = null
		_finish()
	elif Time.get_ticks_usec() > _deadline:
		check(false,"actual workset Source component exceeded its bounded deadline")
		_host.request_close(); _closing = true
func _finish() -> void:
	set_process(false)
	var written: bool = _proof.write_receipt("interactable_workset_owner_20261017",_proof.records.size(),_failed)
	print("INTERACTABLE_WORKSET_OWNER_20261017_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
