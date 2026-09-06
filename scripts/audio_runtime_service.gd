class_name AudioRuntimeService
extends Node

## Shared presentation-only audio service. Gameplay owns the success decision;
## this node only resolves an audited binding and plays it.

const CONTRACT_ID := "audio.runtime_service.v1"
const BINDINGS_PATH := "res://assets/data/audio/audio_bindings.runtime.json"
const SFX_BUS_NAME := &"SFX"
const DEFAULT_NPC_VOLUME_LINEAR := 1.0
const EVENT_POOL_SIZE := 24

signal npc_voice_started(request: Dictionary)
signal npc_voice_stopped(request: Dictionary)
signal npc_voice_finished(request: Dictionary)
signal event_started(request: Dictionary)
signal event_finished(request: Dictionary)
signal audio_diagnostic(event: Dictionary)

var npc_voice_player: AudioStreamPlayer

var _bindings: Dictionary = {}
var _events: Dictionary = {}
var _item_event_routes: Dictionary = {}
var _stream_cache: Dictionary = {}
var _rng_by_npc: Dictionary = {}
var _rng_by_event: Dictionary = {}
var _event_players: Array[AudioStreamPlayer] = []
var _event_slots: Array[Dictionary] = []
var _event_round_robin := 0
var _active_npc_id := ""
var _active_runtime_path := ""
var _request_serial := 0
var _last_event: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("stable_id", CONTRACT_ID)
	add_to_group("audio_runtime_service")
	_ensure_sfx_bus()
	_build_voice_player()
	if _load_bindings():
		_build_event_players()
		prewarm_runtime_streams()


func _ensure_sfx_bus() -> void:
	var bus_index := AudioServer.get_bus_index(SFX_BUS_NAME)
	if bus_index >= 0:
		return
	AudioServer.add_bus()
	bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, SFX_BUS_NAME)
	AudioServer.set_bus_send(bus_index, &"Master")


func _build_voice_player() -> void:
	npc_voice_player = AudioStreamPlayer.new()
	npc_voice_player.name = "NpcVoicePlayer"
	npc_voice_player.bus = SFX_BUS_NAME
	npc_voice_player.volume_db = linear_to_db(DEFAULT_NPC_VOLUME_LINEAR)
	npc_voice_player.autoplay = false
	npc_voice_player.finished.connect(_on_npc_voice_finished)
	add_child(npc_voice_player)


func _build_event_players() -> void:
	for pool_index in EVENT_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "EventPlayer_%02d" % pool_index
		player.bus = SFX_BUS_NAME
		player.volume_db = 0.0
		player.autoplay = false
		player.finished.connect(_on_event_finished.bind(pool_index))
		_event_players.append(player)
		_event_slots.append({})
		add_child(player)


func _load_bindings() -> bool:
	_bindings.clear()
	_events.clear()
	_item_event_routes.clear()
	if not FileAccess.file_exists(BINDINGS_PATH):
		_emit_diagnostic("missing_mapping", {"path": BINDINGS_PATH})
		return false
	var file := FileAccess.open(BINDINGS_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		_emit_diagnostic("load_failed", {"path": BINDINGS_PATH})
		return false
	var raw_bindings: Variant = (parsed as Dictionary).get("bindings", {})
	if not raw_bindings is Dictionary:
		_emit_diagnostic("load_failed", {"path": BINDINGS_PATH, "reason": "bindings_not_dictionary"})
		return false
	for raw_id: Variant in (raw_bindings as Dictionary).keys():
		var canonical_id := str(raw_id)
		var raw_binding: Variant = (raw_bindings as Dictionary).get(raw_id)
		if raw_binding is Dictionary and not canonical_id.is_empty():
			_bindings[canonical_id] = (raw_binding as Dictionary).duplicate(true)
	var raw_events: Variant = (parsed as Dictionary).get("events", {})
	if raw_events is Dictionary:
		for raw_id: Variant in (raw_events as Dictionary).keys():
			var event_id := str(raw_id)
			var raw_event: Variant = (raw_events as Dictionary).get(raw_id)
			if raw_event is Dictionary and not event_id.is_empty():
				_events[event_id] = (raw_event as Dictionary).duplicate(true)
	var raw_item_routes: Variant = (parsed as Dictionary).get("item_event_routes", {})
	if raw_item_routes is Dictionary:
		for raw_key: Variant in (raw_item_routes as Dictionary).keys():
			var stable_item_key := str(raw_key)
			var raw_route: Variant = (raw_item_routes as Dictionary).get(raw_key)
			if raw_route is Dictionary and not stable_item_key.is_empty():
				_item_event_routes[stable_item_key] = (raw_route as Dictionary).duplicate(true)
	return not _bindings.is_empty() or not _events.is_empty()


func reload_bindings() -> bool:
	for player in _event_players:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_event_players.clear()
	_event_slots.clear()
	_event_round_robin = 0
	_stream_cache.clear()
	var loaded := _load_bindings()
	if loaded:
		_build_event_players()
		prewarm_runtime_streams()
	return loaded


## Called during world/service initialization so interaction never performs a
## first-use synchronous resource load. Missing files remain diagnostics and
## do not change the gameplay result.
func prewarm_runtime_streams() -> Dictionary:
	var result := {"loaded": 0, "missing": 0, "failed": 0, "npc_loaded": 0, "event_loaded": 0}
	for raw_binding: Variant in _bindings.values():
		if not raw_binding is Dictionary:
			continue
		for runtime_path: String in _valid_runtime_paths((raw_binding as Dictionary).get("runtime_paths", [])):
			_prewarm_one(runtime_path, result, "npc")
	for raw_event: Variant in _events.values():
		if not raw_event is Dictionary:
			continue
		for runtime_path: String in _valid_event_runtime_paths((raw_event as Dictionary).get("runtime_paths", [])):
			_prewarm_one(runtime_path, result, "event")
	return result


func _prewarm_one(runtime_path: String, result: Dictionary, kind: String) -> void:
	if _stream_cache.has(runtime_path):
		if _stream_cache[runtime_path] is AudioStream:
			result["loaded"] += 1
			result["%s_loaded" % kind] = int(result.get("%s_loaded" % kind, 0)) + 1
		else:
			result["failed"] += 1
		return
	if not ResourceLoader.exists(runtime_path) and not FileAccess.file_exists(runtime_path):
		result["missing"] += 1
		_emit_diagnostic("missing_mapping", {"path": runtime_path})
		return
	var stream: AudioStream = null
	if ResourceLoader.exists(runtime_path):
		stream = load(runtime_path) as AudioStream
	elif runtime_path.to_lower().ends_with(".wav"):
		# Newly generated/raw test assets may not have an editor import remap yet.
		# AudioStreamWAV parses the exact file bytes; exported builds normally use
		# ResourceLoader after the export/import pipeline creates the remap.
		stream = AudioStreamWAV.load_from_file(runtime_path)
	_stream_cache[runtime_path] = stream
	if stream == null:
		result["failed"] += 1
		_emit_diagnostic("load_failed", {"path": runtime_path})
	else:
		result["loaded"] += 1
		result["%s_loaded" % kind] = int(result.get("%s_loaded" % kind, 0)) + 1


## Exact event-ID entrypoint for audited player/skill/interaction callsites.
## The caller supplies a stable event ID; filenames and display names never
## participate in runtime resolution. Event players are separate from the
## single NPC voice player so a weapon cue and skill cue may overlap as in the
## source client without interrupting the NPC interaction voice.
func play_event(event_id: String, context: Dictionary = {}) -> Dictionary:
	var binding: Dictionary = _events.get(event_id, {}) as Dictionary
	if binding.is_empty() or str(binding.get("owner_kind", "")) == "npc":
		return _reject_event("missing_mapping", event_id, context)
	if str(binding.get("mapping_status", "")) not in ["EXACT", "SHARED_VERIFIED"]:
		return _reject_event("unresolved_mapping", event_id, context)
	var runtime_paths := _valid_event_runtime_paths(binding.get("runtime_paths", []))
	if runtime_paths.is_empty():
		return _reject_event("missing_mapping", event_id, context)
	var selected_index := _select_event_variant(event_id, binding, runtime_paths.size(), context)
	var runtime_path := str(runtime_paths[selected_index])
	var stream := _stream_for(runtime_path)
	if stream == null:
		return _reject_event("load_failed", event_id, context, runtime_path)
	var priority := int(binding.get("priority", 50))
	var pool_index := _acquire_event_player(priority)
	if pool_index < 0:
		return _reject_event("polyphony_limit", event_id, context, runtime_path)
	var player := _event_players[pool_index]
	if player == null or not is_instance_valid(player):
		return _reject_event("not_prewarmed", event_id, context, runtime_path)
	player.stream = stream
	if player.playing:
		player.stop()
	_request_serial += 1
	_event_slots[pool_index] = {
		"event_id": event_id,
		"runtime_path": runtime_path,
		"priority": priority,
		"request_serial": _request_serial,
	}
	player.play()
	var event := {
		"contract_id": CONTRACT_ID,
		"status": "played",
		"event_id": event_id,
		"runtime_path": runtime_path,
		"variant_index": selected_index,
		"request_serial": _request_serial,
		"pool_index": pool_index,
		"context": context.duplicate(true),
	}
	_last_event = event.duplicate(true)
	event_started.emit(event.duplicate(true))
	return event


## Exact monster-ID helper. The semantic suffix is still checked through the
## generated event dictionary; names and appearance numbers are never runtime
## fallbacks.
func play_monster_event(monster_id: int, semantic_event: String, context: Dictionary = {}) -> Dictionary:
	if monster_id <= 0 or semantic_event.is_empty():
		return _reject_event("invalid_event", "", context)
	return play_event("monster.%d.%s" % [monster_id, semantic_event], context)


## Source-exact ambient cadence: Actor.pas evaluates Random(8) == 1 only on
## walk/turn client frame 1. The per-actor audio RNG never touches gameplay
## RNG, so muting audio cannot alter combat, AI or drops.
func play_monster_ambient_if_due(
	monster_id: int,
	client_frame: int,
	audio_owner_key: String,
	context: Dictionary = {}
) -> Dictionary:
	if monster_id <= 0 or audio_owner_key.is_empty():
		return _reject_event("invalid_event", "", context)
	var event_id := "monster.%d.ambient" % monster_id
	if client_frame != 1:
		return _skipped_event("not_ambient_frame", event_id, context)
	var rng_key := "monster_ambient:%d:%s" % [monster_id, audio_owner_key]
	var roll := _rng_for_event(rng_key).randi_range(0, 7)
	if roll != 1:
		var skipped_context := context.duplicate(true)
		skipped_context["audio_roll"] = roll
		return _skipped_event("ambient_probability", event_id, skipped_context)
	var played_context := context.duplicate(true)
	played_context["audio_owner_key"] = audio_owner_key
	played_context["audio_roll"] = roll
	return play_event(event_id, played_context)


## Stable-key/type route for committed item operations. Valid key namespaces:
## item:<canonical item_id>, service:<serviceIndex>, currency:gold.
func play_item_event(stable_item_key: String, semantic_event: String, context: Dictionary = {}) -> Dictionary:
	var route: Dictionary = _item_event_routes.get(stable_item_key, {}) as Dictionary
	if route.is_empty():
		return _reject_event("missing_item_route", "", context)
	var events: Dictionary = route.get("events", {}) as Dictionary
	var event_id := str(events.get(semantic_event, ""))
	if event_id.is_empty():
		return _reject_event("silent_or_unmapped_item_event", "", context)
	var routed_context := context.duplicate(true)
	routed_context["stable_item_key"] = stable_item_key
	routed_context["item_semantic_event"] = semantic_event
	return play_event(event_id, routed_context)


## World/session teardown entrypoint. NPC voice and pooled SFX have independent
## lifecycles during play, but both stop at the explicit outer lifecycle end.
func stop_all_audio(reason := "world_exit") -> void:
	stop_npc_voice(reason)
	stop_all_events(reason)


func stop_all_events(_reason := "cancelled") -> void:
	for pool_index in _event_players.size():
		var player := _event_players[pool_index]
		if player.playing:
			player.stop()
		_event_slots[pool_index] = {}


## Caller contract: call this only after the NPC interaction has succeeded.
## `canonical_npc_id` is exact-ID only; display-name fallbacks would make an
## audio mapping silently cross service identities.
func play_npc_interaction_success(canonical_npc_id: String, context: Dictionary = {}) -> Dictionary:
	var binding: Dictionary = _bindings.get(canonical_npc_id, {}) as Dictionary
	if binding.is_empty() or str(binding.get("owner_kind", "")) != "npc":
		return _reject("missing_mapping", canonical_npc_id, context)
	if str(binding.get("semantic_event", "")) != "interaction_success":
		return _reject("invalid_event", canonical_npc_id, context)
	var runtime_paths := _valid_runtime_paths(binding.get("runtime_paths", []))
	if runtime_paths.is_empty():
		_stop_npc_voice_for_replacement_failure()
		return _reject("missing_mapping", canonical_npc_id, context)
	var rng := _rng_for(canonical_npc_id)
	var selected_index := rng.randi_range(0, runtime_paths.size() - 1)
	var runtime_path := str(runtime_paths[selected_index])
	var stream := _stream_for(runtime_path)
	if stream == null:
		# A failed replacement must never leave the previous NPC voice playing;
		# that would make the visible NPC and audible NPC disagree. Prewarming
		# makes this branch diagnostic-only in the normal runtime path.
		_stop_npc_voice_for_replacement_failure()
		return _reject("load_failed", canonical_npc_id, context, runtime_path)

	_request_serial += 1
	if npc_voice_player != null and npc_voice_player.playing:
		npc_voice_player.stop()
		npc_voice_stopped.emit({
			"contract_id": CONTRACT_ID,
			"reason": "replaced_by_new_npc",
			"npc_id": _active_npc_id,
			"runtime_path": _active_runtime_path,
			"request_serial": _request_serial,
		})
	_active_npc_id = canonical_npc_id
	_active_runtime_path = runtime_path
	npc_voice_player.stream = stream
	npc_voice_player.play()
	_last_event = {
		"contract_id": CONTRACT_ID,
		"status": "played",
		"npc_id": canonical_npc_id,
		"runtime_path": runtime_path,
		"variant_index": selected_index,
		"request_serial": _request_serial,
		"context": context.duplicate(true),
	}
	npc_voice_started.emit(_last_event.duplicate(true))
	return _last_event.duplicate(true)


## Closing a shop/warehouse/quest panel must not call this method. The
## lifecycle owner should call it for character switch, logout or app exit.
func stop_npc_voice(reason := "cancelled") -> void:
	if npc_voice_player == null or not npc_voice_player.playing:
		return
	npc_voice_player.stop()
	_request_serial += 1
	var event := {
		"contract_id": CONTRACT_ID,
		"reason": reason,
		"npc_id": _active_npc_id,
		"runtime_path": _active_runtime_path,
		"request_serial": _request_serial,
	}
	_last_event = event.duplicate(true)
	npc_voice_stopped.emit(event)
	_active_npc_id = ""
	_active_runtime_path = ""


func is_npc_voice_active() -> bool:
	return npc_voice_player != null and npc_voice_player.playing


func active_npc_id() -> String:
	return _active_npc_id if is_npc_voice_active() else ""


func set_rng_seed(canonical_npc_id: String, seed: int) -> void:
	if canonical_npc_id.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_rng_by_npc[canonical_npc_id] = rng


func set_event_rng_seed(event_rng_key: String, seed: int) -> void:
	if event_rng_key.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_rng_by_event[event_rng_key] = rng


func state_snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"binding_count": _bindings.size(),
		"event_count": _events.size(),
		"item_route_identity_count": _item_event_routes.size(),
		"event_ids": _events.keys(),
		"event_pool_size": _event_players.size(),
		"active_event_count": _active_event_count(),
		"active_npc_id": active_npc_id(),
		"active_runtime_path": _active_runtime_path if is_npc_voice_active() else "",
		"request_serial": _request_serial,
		"last_event": _last_event.duplicate(true),
	}


func _rng_for(canonical_npc_id: String) -> RandomNumberGenerator:
	var existing: Variant = _rng_by_npc.get(canonical_npc_id)
	if existing is RandomNumberGenerator:
		return existing as RandomNumberGenerator
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_rng_by_npc[canonical_npc_id] = rng
	return rng


func _rng_for_event(event_id: String) -> RandomNumberGenerator:
	var existing: Variant = _rng_by_event.get(event_id)
	if existing is RandomNumberGenerator:
		return existing as RandomNumberGenerator
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_rng_by_event[event_id] = rng
	return rng


func _select_event_variant(
	event_id: String,
	binding: Dictionary,
	variant_count: int,
	context: Dictionary
) -> int:
	var requested := int(context.get("variant_index", -1))
	if requested >= 0 and requested < variant_count:
		return requested
	if variant_count <= 1:
		return 0
	if str(binding.get("variant_policy", "")) == "context.gender_male_female":
		var gender := str(context.get("gender", "")).strip_edges().to_lower()
		return 1 if gender in ["female", "f", "女", "女战士"] else 0
	return _rng_for_event(event_id).randi_range(0, variant_count - 1)


func _acquire_event_player(new_priority: int) -> int:
	if _event_players.is_empty():
		return -1
	for offset in _event_players.size():
		var pool_index := (_event_round_robin + offset) % _event_players.size()
		if not _event_players[pool_index].playing:
			_event_round_robin = (pool_index + 1) % _event_players.size()
			return pool_index
	var candidate := -1
	var candidate_priority := 2147483647
	var candidate_serial := 2147483647
	for pool_index in _event_slots.size():
		var slot := _event_slots[pool_index]
		var priority := int(slot.get("priority", 0))
		var serial := int(slot.get("request_serial", 0))
		if priority < candidate_priority or (priority == candidate_priority and serial < candidate_serial):
			candidate = pool_index
			candidate_priority = priority
			candidate_serial = serial
	if candidate < 0 or new_priority < candidate_priority:
		return -1
	_event_players[candidate].stop()
	_event_slots[candidate] = {}
	_event_round_robin = (candidate + 1) % _event_players.size()
	return candidate


func _active_event_count() -> int:
	var count := 0
	for player in _event_players:
		if player.playing:
			count += 1
	return count


func _valid_runtime_paths(raw_paths: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_paths is Array:
		return result
	for raw_path: Variant in raw_paths as Array:
		var path := str(raw_path)
		if (
			path.begins_with("res://assets/audio/npc/")
			and not path.contains("..")
			and path.to_lower().ends_with(".wav")
			and not result.has(path)
		):
			result.append(path)
	return result


func _valid_event_runtime_paths(raw_paths: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_paths is Array:
		return result
	for raw_path: Variant in raw_paths as Array:
		var path := str(raw_path)
		if (
			(
				path.begins_with("res://assets/audio/sfx/client/")
				or path.begins_with("res://assets/audio/warrior/")
				or path.begins_with("res://assets/audio/skills/")
			)
			and not path.contains("..")
			and path.to_lower().ends_with(".wav")
			and not result.has(path)
		):
			result.append(path)
	return result


func _stream_for(runtime_path: String) -> AudioStream:
	if _stream_cache.has(runtime_path):
		return _stream_cache[runtime_path] as AudioStream
	# Runtime interaction is deliberately not a cold-load path.  A missing
	# cache entry means initialization/prewarm was incomplete; fail closed and
	# let the caller's diagnostic/replacement policy handle it.
	_emit_diagnostic("not_prewarmed", {"path": runtime_path})
	return null


func _reject(reason: String, canonical_npc_id: String, context: Dictionary, runtime_path := "") -> Dictionary:
	var event := {
		"contract_id": CONTRACT_ID,
		"status": reason,
		"npc_id": canonical_npc_id,
		"runtime_path": runtime_path,
		"context": context.duplicate(true),
	}
	_last_event = event.duplicate(true)
	_emit_diagnostic(reason, event)
	return event


func _reject_event(reason: String, event_id: String, context: Dictionary, runtime_path := "") -> Dictionary:
	var event := {
		"contract_id": CONTRACT_ID,
		"status": reason,
		"event_id": event_id,
		"runtime_path": runtime_path,
		"context": context.duplicate(true),
	}
	_last_event = event.duplicate(true)
	_emit_diagnostic(reason, event)
	return event


func _skipped_event(reason: String, event_id: String, context: Dictionary) -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"status": "skipped",
		"reason": reason,
		"event_id": event_id,
		"context": context.duplicate(true),
	}


func _stop_npc_voice_for_replacement_failure() -> void:
	if npc_voice_player != null and npc_voice_player.playing:
		stop_npc_voice("replacement_unavailable")


func _emit_diagnostic(reason: String, details: Dictionary) -> void:
	var event := {"contract_id": CONTRACT_ID, "reason": reason}
	for key: Variant in details.keys():
		event[str(key)] = details[key]
	audio_diagnostic.emit(event)


func _on_npc_voice_finished() -> void:
	var event := {
		"contract_id": CONTRACT_ID,
		"npc_id": _active_npc_id,
		"runtime_path": _active_runtime_path,
		"request_serial": _request_serial,
	}
	npc_voice_finished.emit(event)
	_active_npc_id = ""
	_active_runtime_path = ""


func _on_event_finished(pool_index: int) -> void:
	if pool_index < 0 or pool_index >= _event_slots.size():
		return
	var slot := _event_slots[pool_index].duplicate(true)
	_event_slots[pool_index] = {}
	if slot.is_empty():
		return
	slot["contract_id"] = CONTRACT_ID
	slot["pool_index"] = pool_index
	event_finished.emit(slot)
