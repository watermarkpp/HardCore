extends RefCounted

## Actual owner-local publication reader and ordered rendering journal.
## Replies are results of the original Main resource/coordinator operations,
## never guessed from appearance metadata or converted to cold on absence.
const Direction := preload("res://scripts/gameplay/enemy/enemy_owner_visual_direction.gd")
var _owner := OS.get_thread_caller_id()
var _configured := false
var _catalog: Dictionary
var _phase: Dictionary
var _reply_cursor := 0
var _events: Array[Dictionary] = []
var _journal_sink: Callable
var _event_sequence := 0
var _overlay_sequence := 0
var _failure: Callable
var _failed := false

func owner_thread_id() -> int:
	return _owner

func configure_owner(catalog: Dictionary, fail_owner: Callable) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner or not fail_owner.is_valid():
		push_error("visual publications require once-only owner configuration and fail-owner callback")
		return false
	for key in ["appearances", "source_profiles", "direction_offsets", "ground_contact", "manual_alignment", "overhead"]:
		if not catalog.get(key) is Dictionary:
			push_error("visual catalog publication missing: " + key)
			return false
	if not _plain(catalog):
		push_error("visual catalog contains live Object/Resource/Callable")
		return false
	_catalog = _seal(catalog.duplicate(true))
	_failure = fail_owner
	_configured = true
	return true

func _plain(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal: return false
	if value is Dictionary:
		for key in value:
			if not _plain(key) or not _plain(value[key]): return false
	elif value is Array:
		for item in value:
			if not _plain(item): return false
	return true

func _seal(value: Variant) -> Variant:
	if value is Dictionary:
		for key in value: _seal(value[key])
		value.make_read_only()
	elif value is Array:
		for item in value: _seal(item)
		value.make_read_only()
	return value

func _require(condition: bool, reason: String) -> bool:
	if condition and not _failed: return true
	_failed = true
	push_error("Enemy visual owner publication rejected: " + reason)
	_failure.call(reason)
	assert(false, reason)
	return false

func reject_original_process_qualification(service_id: int) -> void:
	_require(false, "original visual process qualification write failed: " + str(service_id))

func phase_is_valid() -> bool:
	return not _failed and not _phase.is_empty() and _reply_cursor == _phase.replies.size()

func begin_original_phase(publication: Dictionary) -> bool:
	if not _require(_configured and OS.get_thread_caller_id() == _owner, "wrong owner/unconfigured"): return false
	if not _phase.is_empty() and not _require(_reply_cursor == _phase.replies.size(), "previous phase has unconsumed original replies"): return false
	for key in ["phase_sequence", "world_generation", "viewports", "replies"]:
		if not _require(publication.has(key), "missing phase field " + key): return false
	if not _require(publication.viewports is Dictionary and publication.replies is Array and _plain(publication), "phase contains live objects or wrong containers"): return false
	if not _phase.is_empty() and not _require(int(publication.phase_sequence) > int(_phase.phase_sequence), "phase sequence was replayed/reordered"): return false
	_phase = _seal(publication.duplicate(true))
	_reply_cursor = 0
	return true

func _consume(operation: StringName, service_id: int, arguments: Array) -> Variant:
	if not _require(not _phase.is_empty() and _reply_cursor < _phase.replies.size(), "missing original operation reply " + str(operation)):
		return null # fail_owner must stop this world; never an empty successful query.
	var reply: Dictionary = _phase.replies[_reply_cursor]
	if not _require(reply.get("operation") == operation and int(reply.get("service_id", 0)) == service_id and reply.get("arguments") == arguments and reply.has("result"), "reply operation/identity/arguments/order mismatch"):
		return null
	_reply_cursor += 1
	return reply.result

func _known(table: String, id: int) -> Dictionary:
	var key := str(id)
	_require(_configured and _catalog[table].has(key), "unknown canonical monster publication " + table + ":" + key)
	return _catalog[table][key]

func appearance_profile(id: int) -> Dictionary: return _known("appearances", id)
func profile_for_id(id: int) -> Dictionary: return _known("source_profiles", id)
func direction_offsets(id: int) -> Dictionary: return _known("direction_offsets", id)
func ground_contact_manifest() -> Dictionary: return _catalog.ground_contact
func manual_alignment_manifest() -> Dictionary: return _catalog.manual_alignment
func overhead_anchor_manifest() -> Dictionary: return _catalog.overhead

func monster_id(data: Dictionary) -> int:
	if data.has("monster_id"): return _coerce_positive_id(data.get("monster_id"))
	if data.has("monsterId"): return _coerce_positive_id(data.get("monsterId"))
	return -1

func _coerce_positive_id(value: Variant) -> int:
	if value is int:
		var integer_value := int(value)
		return integer_value if integer_value > 0 else -1
	if value is String:
		var token := String(value)
		if token.is_empty(): return -1
		for index in range(token.length()):
			var codepoint := token.unicode_at(index)
			if codepoint < 48 or codepoint > 57: return -1
		var parsed := int(token)
		return parsed if parsed > 0 else -1
	return -1

func emit_visual(service_id: int, operation: StringName, arguments: Array) -> void:
	if not _require(_configured and OS.get_thread_caller_id() == _owner and service_id > 0 and _plain(arguments), "invalid render journal event"): return
	_event_sequence += 1
	_append_original_event({"sequence": _event_sequence, "service_id": service_id, "operation": operation, "arguments": _seal(arguments.duplicate(true))})

func take_events() -> Array[Dictionary]:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	var result := _events
	_events = []
	return result

func current_world_generation() -> int:
	_require(not _phase.is_empty(), "world generation not published")
	return int(_phase.world_generation)

func register_visual(visual: RefCounted, monster: int, map_id: int, generation: int, key: String, paths: Dictionary, spawn_serial: int) -> void:
	emit_visual(visual.source_object_id(), &"coordinator_register_visual", [monster, map_id, generation, key, paths, spawn_serial])

func request_visual_resources(visual: RefCounted, mapping: Dictionary, monster: int, request_async: bool) -> Variant:
	var args := [mapping, monster, request_async]
	emit_visual(visual.source_object_id(), &"coordinator_request_resources", args)
	return _consume(&"request_visual_resources", visual.source_object_id(), args)

func visual_subscription_is_current(service_id: int, key: String) -> bool:
	var result: Variant = _consume(&"visual_subscription_is_current", service_id, [key])
	_require(result is bool, "subscription response is not boolean")
	return result

func notify_visual_applied(service_id: int, key: String, generation: int) -> void:
	emit_visual(service_id, &"coordinator_notify_applied", [key, generation])

func release_visual_resource(service_id: int, key: String) -> void:
	emit_visual(service_id, &"coordinator_release_resource", [key])

func unregister_visual(service_id: int) -> void:
	emit_visual(service_id, &"coordinator_unregister_visual", [])

func complete_synchronous_profile(service_id: int, mapping: Dictionary) -> Dictionary:
	var result: Variant = _consume(&"complete_synchronous_profile", service_id, [mapping])
	_require(result is Dictionary, "synchronous profile not completed by Main")
	return result

func viewport_snapshot(service_id: int) -> Dictionary:
	_require(not _phase.is_empty() and _phase.viewports.has(service_id), "viewport snapshot missing for visual")
	var result: Dictionary = _phase.viewports[service_id]
	_require(result.has("viewport_available") and result.get("canvas_transform") is Transform2D and result.get("visible_rect") is Rect2, "viewport snapshot incomplete")
	return result

func request_profile(profile: Dictionary, direction: int) -> void:
	# Non-visual global effect prewarm event retains original call order.
	_event_sequence += 1
	_append_original_event({"sequence": _event_sequence, "operation": &"source_request_profile", "arguments": _seal([profile, direction].duplicate(true))})

func prewarm_for_monster_id(id: int) -> void:
	_event_sequence += 1
	_append_original_event({"sequence": _event_sequence, "operation": &"projectile_prewarm", "arguments": [id]})

func _direction16_for_line(origin: Vector2, target: Vector2) -> int:
	return Direction._direction16_for_line(origin, target)

class Overlay:
	extends RefCounted
	var journal: RefCounted
	var service_id: int
	var serial: int
	var _visible := true
	var visible: bool:
		get: return _visible
		set(value):
			_visible = value
			journal.emit_visual(service_id, &"attack_overlay_visible", [serial, value])
	func setup(monster: int, direction8: int, direction16: int, frame_seconds: float, ground_offset: Vector2) -> void:
		journal.emit_visual(service_id, &"attack_overlay_setup", [serial, monster, direction8, direction16, frame_seconds, ground_offset])
	func queue_free() -> void:
		journal.emit_visual(service_id, &"attack_overlay_queue_free", [serial])

func create_attack_overlay(service_id: int) -> RefCounted:
	_overlay_sequence += 1
	var overlay := Overlay.new()
	overlay.journal = self
	overlay.service_id = service_id
	overlay.serial = _overlay_sequence
	emit_visual(service_id, &"attack_overlay_create", [overlay.serial])
	return overlay

func attach_attack_overlay(service_id: int, overlay: RefCounted) -> void:
	emit_visual(service_id, &"attack_overlay_attach", [overlay.serial])

func configure_original_journal(sink: Callable) -> bool:
	if not _configured or _journal_sink.is_valid() or not sink.is_valid() or not _events.is_empty(): return false
	_journal_sink = sink
	return true

func _append_original_event(event: Dictionary) -> void:
	if _journal_sink.is_valid():
		_require(_journal_sink.call(event) == true, "original world journal rejected visual event")
	else:
		_events.append(event)
