extends RefCounted
## Native journal/receiver protocol fixture. Scoped native ObjectIDs and header
## inputs below do not claim original Enemy factory, AI, asset or World readiness.
const Session := preload("res://scripts/gameplay/source/source_session.gd")
const Journal := preload("res://scripts/gameplay/world/world_original_event_journal.gd")
const Header := preload("res://scripts/gameplay/presentation/enemy_birth_structural_header.gd")
var _host: Object
var _session: RefCounted
var _journal: RefCounted
var _actor_id: Object
var _visual_id: Object
var _checks: Array[Dictionary] = []
var _done := false
var _expected_through := 4
func _check(ok: bool,label: String) -> void: _checks.append({"passed":ok,"label":label})
func _init(host: Object,boot: Dictionary) -> void:
	_host = host
	_actor_id = Object.new(); _visual_id = Object.new()
	_check(OS.get_thread_caller_id() != OS.get_main_thread_id(),"real Native Source owns this bounded journal/receiver protocol")
	_check(host.bind_original_world_context(boot.world),"actual Native world context is bound for the protocol input")
	_session = Session.new(); _session.set("_host",host)
	_journal = Journal.new(_session,int(host.capabilities().bridge_generation),1); _session.set("_journal",_journal)
	var site := {"clock_epoch":0,"domain":&"P","entry_id":"isolated.visual.qualification.protocol","entry_ordinal":1,"bootstrap":true,"observation_process_epoch":int(host.current_clock_frame().source_process_frame),"world_context":boot.world,"deadline_usec":Time.get_ticks_usec()+1000000}
	for kind: String in ["ACTOR_HEADER","VISUAL_HEADER"]:
		var ordinal: int = 1 if kind == "ACTOR_HEADER" else 2
		var header := {"contract_id":Header.CONTRACT,"header_kind":kind,"actor_identity":{"world":boot.world,"runtime_id":_actor_id.get_instance_id(),"life_generation":1},"event_identity":{"bridge_generation":int(host.capabilities().bridge_generation),"journal_generation":1,"event_ordinal":ordinal},"sequence":ordinal,"source_site":site}
		if kind == "VISUAL_HEADER": header.visual_service_id = _visual_id.get_instance_id()
		_check(Header.validate(header,kind),"protocol header passes the real immutable structural contract:"+kind)
		_check(_journal.append({"kind":"original_world_presentation","operation":StringName(kind),"arguments":[Header.capture(header)],"source_site":site}),"actual Source journal assigns the header ordinal:"+kind)
	for enabled: bool in [true,false]:
		_check(_journal.append({"kind":"enemy_visual","source_site":site,"event":{"sequence":3 if enabled else 4,"service_id":_visual_id.get_instance_id(),"operation":&"visual_process_enabled","arguments":[enabled]}}),"real journal carries exact original visual arguments/qualification:"+str(enabled))
	_append_fixture_events(boot,site)
	var prefix: Dictionary = _journal.freeze_prefix()
	_check(_journal.register_normal_publication(prefix) and host.register_published_original_main_prefix(prefix),"one actual Native FIFO carries the complete header and qualification prefix")
func on_inputs(_domain: String,_packets: Array) -> bool: return true
func on_phase(phase: String,_frame: Dictionary) -> bool:
	if phase == "P_GROUP" and not _done:
		var receipt: Dictionary = _host.completed_original_main_prefix_receipt()
		if not receipt.is_empty() and int(receipt.get("through_ordinal",-1)) >= _expected_through:
			_check(_journal.consume_normal_receipt(receipt) and not _journal.has_pending(),"actual Main ACK retires the same four Source journal events")
			_done = true
	return _host.publish_snapshot({"done":_done,"checks":_checks},[]) if phase == "PUBLISH" else true
func _append_fixture_events(_boot: Dictionary,_site: Dictionary) -> void:
	pass # Default protocol contains only the original four fixture events.
func close_session() -> bool:
	if not _done or _journal.has_pending(): return false
	_actor_id.free(); _visual_id.free()
	_actor_id = null; _visual_id = null; _session = null; _journal = null
	return true
