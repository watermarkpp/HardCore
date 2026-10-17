extends Node
## Actual authoritative content -> Native boot codec -> original Source
## identity/target-bound consumers. No actor births or world-ready claim.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Source := preload("res://tests/framework/helpers/main_world_content_source_20261016.gd")
var _proof := Proof.new()
var _failed := 0
var _host: Object
var _lease: Dictionary
var _tick := 0
var _closing := false
var _deadline := 0
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var path := "res://scripts/gameplay/source/main_world_content_publication.gd"
	check(FileAccess.file_exists(path),"actual Main World content producer exists")
	if not FileAccess.file_exists(path): _finish(); return
	check(ContentLayers.is_loaded() and GameData.is_loaded() and ContentLayers.ensure_feature_catalog(),"real original authoritative content is loaded before catalogue publication")
	_lease = Gate.publish(str(GameData.database_revision))
	check(Gate.is_active(_lease),"actual catalogue owner issues the immutable read lease")
	var code: Script = load(path)
	check(code.capture({}).get("success") != true,"absent catalogue lease cannot publish World content")
	var bundle: Dictionary = code.capture(_lease)
	check(bundle.get("success") == true,"original metadata publishers produce all required World content values: "+str(bundle.get("error","")))
	if bundle.get("success") != true: _finish(); return
	var publication: Dictionary = bundle.publication
	check(publication.monster_inputs.inputs.size() == GameData.monsters.size(),"all current canonical runtime monsters are retained")
	check(publication.source_documents["res://assets/data/monster_target_ring_profiles.json"] == FileAccess.get_file_as_bytes("res://assets/data/monster_target_ring_profiles.json"),"Source receives exact original parser bytes without a rewritten policy")
	check(publication.action_timing.catalog_lease == _lease and publication.caster_visual.catalog_lease == _lease,"numeric timing and Caster visual metadata share the same real catalogue lease")
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"isolated.World.content.component"}
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115158,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	check(_host.start(Source,{"world_identity":world,"content":publication,"catalog_lease":_lease},config),"real Native Source receives the full content value graph")
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
		check(_host.close_and_join(),"actual Source metadata owner releases reader before Main join")
		_host = null; _finish()
	elif Time.get_ticks_usec() > _deadline:
		check(false,"bounded actual Source content component terminates"); _finish()
func _finish() -> void:
	set_process(false)
	if not _lease.is_empty(): check(Gate.release_after_host_quiescence(_lease),"actual catalogue read lease retires after Source component shutdown")
	var written: bool = _proof.write_receipt("main_world_content_publication_20261016",_proof.records.size(),_failed)
	print("MAIN_WORLD_CONTENT_PUBLICATION_20261016_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
