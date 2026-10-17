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
	# This is a Native FIFO/pump component, not World adoption. Do not fake a
	# Core to satisfy the application's stricter World publisher contract.
	for index: int in 4:
		_check(_journal.append({"kind":"component_visible_label","text":"actual Source journal delivered","source_thread":OS.get_thread_caller_id(),"nested":{"array":[{"index":index,"packed_leaves":[PackedByteArray(),PackedByteArray([1,2]),PackedInt32Array(),PackedInt64Array(),PackedFloat32Array(),PackedFloat64Array(),PackedStringArray(),PackedVector2Array(),PackedVector3Array(),PackedColorArray(),PackedVector4Array()]}]}}),"real Source event appended in order")
		var prefix: Dictionary = _journal.freeze_prefix()
		var admission: Dictionary = host.try_register_published_original_main_prefix(prefix)
		_check(admission.get("status")=="READY","exact Native FIFO accepts prefix")
		_check(_journal.register_normal_publication(prefix),"exact admitted cumulative prefix registered")
func on_inputs(_domain: String,_packets: Array) -> bool: return true
func on_phase(phase: String,_frame: Dictionary) -> bool:
	if phase=="P_GROUP" and not _done:
		var receipt: Dictionary = _host.completed_original_main_prefix_receipt()
		if not receipt.is_empty() and int(receipt.get("through_ordinal",-1)) >= 4:
			_check(_journal.consume_normal_receipt(receipt),"Source journal retires only the actual Native/Main acknowledgement")
			_check(not _journal.has_pending() and _journal.applied_ordinal()==4,"one actual UI event was delivered and retired exactly once")
			_done = true
	if phase!="PUBLISH": return true
	return _host.publish_snapshot({"done":_done,"checks":_checks},[])
func close_session() -> bool: return _journal!=null and not _journal.has_pending()
