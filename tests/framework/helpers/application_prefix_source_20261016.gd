extends RefCounted
## Protocol component: real Session class + actual journal + concrete view
## transport, before any Profile/world adoption. No LIVE/ready claim.
const Session := preload("res://scripts/gameplay/source/source_session.gd")
const Journal := preload("res://scripts/gameplay/world/world_original_event_journal.gd")
const Applications := preload("res://scripts/gameplay/source/source_application_providers.gd")
var _host: Object
var _session: RefCounted
var _journal: RefCounted
var _view_transport: RefCounted
var _checks: Array[Dictionary] = []
var _done := false
func _check(ok: bool,label: String) -> void: _checks.append({"pass":ok,"label":label})
func _init(host: Object,boot: Dictionary) -> void:
	_host = host
	_check(host.bind_original_world_context(boot.world_identity),"actual Native Source binds the real component identity")
	_session = Session.new(); _session.set("_host",host)
	_journal = Journal.new(_session,int(host.capabilities().bridge_generation),1)
	_session.set("_journal",_journal)
	_view_transport = Applications.ViewTransport.new()
	_check(_view_transport.configure_owner(host) and _view_transport.bind_original_session(_session),"concrete view transport binds the actual same-thread Session class and real journal")
	_check(_journal.append({"kind":"component_visible_label","text":"actual Source journal delivered","source_thread":OS.get_thread_caller_id()}),"actual journal creates the event and its ordinal on S")
	var prefix: Dictionary = _journal.freeze_prefix()
	_check(not _view_transport.publish_original_world_view_prefix(prefix),"an unregistered journal prefix cannot be promoted as delivered")
	_check(host.status().get("unsettled_original_published_prefixes")==0,"rejected application publication does not enqueue an unregistered event")
	_check(_journal.register_normal_publication(prefix),"same Core journal producer registration precedes physical Native FIFO admission")
	_check(host.status().get("unsettled_original_published_prefixes")==0,"journal preparation does not duplicate the later Native publication")
	_check(_view_transport.publish_original_world_view_prefix(prefix),"concrete application transport admits the existing real Native published prefix")
	# Main may already have ACKed before this concurrent observation. The real
	# write/ACK/retirement assertions below establish delivery, not this count.
	_check(host.status().get("unsettled_original_published_prefixes")<=1,"actual delivery retains at most one pending Native prefix while Main may concurrently ACK")
	_check(_view_transport.publish_original_world_view_prefix(prefix),"backpressure replay confirms the same publication instead of creating a second FIFO event")
func on_inputs(_domain: String,_packets: Array) -> bool: return true
func on_phase(phase: String,_frame: Dictionary) -> bool:
	if phase=="P_GROUP" and not _done:
		var receipt: Dictionary = _host.completed_original_main_prefix_receipt()
		if not receipt.is_empty() and int(receipt.get("through_ordinal",-1)) >= 1:
			_check(_journal.consume_normal_receipt(receipt),"Source journal retires only the actual Native/Main acknowledgement")
			_check(not _journal.has_pending() and _journal.applied_ordinal()==1,"one actual UI event was delivered and retired exactly once")
			_done = true
	if phase!="PUBLISH": return true
	return _host.publish_snapshot({"done":_done,"checks":_checks},[])
func close_session() -> bool: return _journal!=null and not _journal.has_pending()
