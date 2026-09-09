class_name AudioRuntimeService
extends Node

## Shared presentation-only audio service. Gameplay owns the success decision;
## this node only resolves an audited binding and plays it.

const CONTRACT_ID := "audio.runtime_service.v1"
const BINDINGS_PATH := "res://assets/data/audio/audio_bindings.runtime.json"
const RUNTIME_CONFIG_PATH := "res://assets/data/audio/audio_runtime_config.json"
const SFX_BUS_NAME := &"SFX"
const DEFAULT_USER_SFX_GAIN_LINEAR := 1.0
const PROJECT_SFX_GAIN_LINEAR := 0.5
const EVENT_POOL_SIZE := 24
const DEFAULT_MONSTER_POLYPHONY_LIMIT := 6
const DEFAULT_MONSTER_COMBAT_PROMPT_RATE_PER_SECOND := 3.0
const DEFAULT_MONSTER_ATTACK_RATE_PER_SECOND := 12.0
const DEFAULT_MONSTER_SESSION_REARM_SECONDS := 0.75
const DEFAULT_MONSTER_SESSION_LOS_GRACE_SECONDS := 1.25

## W4 production admission is deliberately centralized here. These are
## engineering starting values, not source-client facts; the checked-in JSON
## keeps the values reviewable and lets performance evidence bind to one
## configuration record without touching combat cadence or AI.
const MONSTER_ATTACK_SEMANTICS := ["attack_start", "attack_frame"]
const MONSTER_PROMPT_SEMANTICS := ["combat_prompt", "combat_entered", "engagement"]
const MONSTER_REJECTED_SEMANTICS := [
	"appear",
	"ambient",
	"hurt",
	"death",
	"death_secondary",
]
const TRANSIENT_LOS_REASONS := [
	"los_blocked",
	"los_interrupted",
	"los_short",
	"line_of_sight_lost",
	"path_blocked",
]
const REAL_DISENGAGE_REASONS := [
	"target_invalid",
	"target_dead",
	"safe_zone",
	"leash_expired",
	"world_exit",
	"session_exit",
	"explicit_disengage",
]

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
var _runtime_config: Dictionary = {}
var _user_sfx_gain_linear := DEFAULT_USER_SFX_GAIN_LINEAR
var _project_sfx_gain_linear := PROJECT_SFX_GAIN_LINEAR
var _sfx_enabled := true
var _monster_polyphony_limit := DEFAULT_MONSTER_POLYPHONY_LIMIT
var _monster_combat_prompt_rate_per_second := DEFAULT_MONSTER_COMBAT_PROMPT_RATE_PER_SECOND
var _monster_attack_rate_per_second := DEFAULT_MONSTER_ATTACK_RATE_PER_SECOND
var _monster_session_rearm_seconds := DEFAULT_MONSTER_SESSION_REARM_SECONDS
var _monster_session_los_grace_seconds := DEFAULT_MONSTER_SESSION_LOS_GRACE_SECONDS
var _monster_budget_window_started_msec := -1
var _monster_prompt_starts_in_window := 0
var _monster_attack_starts_in_window := 0
var _monster_sessions: Dictionary = {}
var _owner_release_seen: Dictionary = {}
var _metrics: Dictionary = {
	"requests": 0,
	"played": 0,
	"rejected": 0,
	"skipped": 0,
	"sfx_disabled": 0,
	"monster_prompt_admitted": 0,
	"monster_prompt_rejected": 0,
	"monster_attack_admitted": 0,
	"monster_attack_rejected": 0,
	"monster_polyphony_rejected": 0,
	"owner_release_duplicates": 0,
	"stream_lookup_attempts": 0,
	"stream_cache_misses": 0,
	"event_pool_rejected": 0,
}
var _clock_override_msec := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("stable_id", CONTRACT_ID)
	add_to_group("audio_runtime_service")
	_load_runtime_config()
	_ensure_sfx_bus()
	sync_sfx_enabled_from_bus()
	_build_voice_player()
	if _load_bindings():
		_build_event_players()
		prewarm_runtime_streams()
	_apply_sfx_gain()


func _load_runtime_config() -> void:
	_runtime_config = {
		"schema_version": 1,
		"contract_id": "audio.runtime_budget.v1",
		"sfx_gain_linear": PROJECT_SFX_GAIN_LINEAR,
		"event_pool_size": EVENT_POOL_SIZE,
		"monster": {
			"polyphony_limit": DEFAULT_MONSTER_POLYPHONY_LIMIT,
			"combat_prompt_rate_per_second": DEFAULT_MONSTER_COMBAT_PROMPT_RATE_PER_SECOND,
			"attack_rate_per_second": DEFAULT_MONSTER_ATTACK_RATE_PER_SECOND,
			"session_rearm_seconds": DEFAULT_MONSTER_SESSION_REARM_SECONDS,
			"session_los_grace_seconds": DEFAULT_MONSTER_SESSION_LOS_GRACE_SECONDS,
		},
		"source": "engineering_initial_values",
	}
	if not FileAccess.file_exists(RUNTIME_CONFIG_PATH):
		_emit_diagnostic("missing_runtime_config", {"path": RUNTIME_CONFIG_PATH})
		return
	var file := FileAccess.open(RUNTIME_CONFIG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		_emit_diagnostic("runtime_config_load_failed", {"path": RUNTIME_CONFIG_PATH})
		return
	var candidate := (parsed as Dictionary).duplicate(true)
	var raw_scale: Variant = candidate.get("sfx_gain_linear", PROJECT_SFX_GAIN_LINEAR)
	var raw_pool: Variant = candidate.get("event_pool_size", EVENT_POOL_SIZE)
	var raw_monster: Variant = candidate.get("monster", {})
	if (
		typeof(raw_scale) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(raw_scale))
		or float(raw_scale) <= 0.0
		or float(raw_scale) > 1.0
		or typeof(raw_pool) not in [TYPE_INT, TYPE_FLOAT]
		or int(raw_pool) != EVENT_POOL_SIZE
		or not raw_monster is Dictionary
	):
		_emit_diagnostic("runtime_config_invalid", {"path": RUNTIME_CONFIG_PATH})
		return
	var monster := raw_monster as Dictionary
	var polyphony := int(monster.get("polyphony_limit", DEFAULT_MONSTER_POLYPHONY_LIMIT))
	var prompt_rate := float(monster.get("combat_prompt_rate_per_second", DEFAULT_MONSTER_COMBAT_PROMPT_RATE_PER_SECOND))
	var attack_rate := float(monster.get("attack_rate_per_second", DEFAULT_MONSTER_ATTACK_RATE_PER_SECOND))
	var rearm_seconds := float(monster.get("session_rearm_seconds", DEFAULT_MONSTER_SESSION_REARM_SECONDS))
	var los_grace_seconds := float(monster.get("session_los_grace_seconds", DEFAULT_MONSTER_SESSION_LOS_GRACE_SECONDS))
	if (
		polyphony <= 0
		or not is_finite(prompt_rate)
		or prompt_rate <= 0.0
		or not is_finite(attack_rate)
		or attack_rate <= 0.0
		or not is_finite(rearm_seconds)
		or rearm_seconds < 0.0
		or not is_finite(los_grace_seconds)
		or los_grace_seconds < 0.0
	):
		_emit_diagnostic("runtime_config_invalid", {"path": RUNTIME_CONFIG_PATH})
		return
	_runtime_config = candidate
	_project_sfx_gain_linear = float(raw_scale)
	_monster_polyphony_limit = polyphony
	_monster_combat_prompt_rate_per_second = prompt_rate
	_monster_attack_rate_per_second = attack_rate
	_monster_session_rearm_seconds = rearm_seconds
	_monster_session_los_grace_seconds = los_grace_seconds


func _effective_sfx_gain_linear() -> float:
	if not _sfx_enabled:
		return 0.0
	return clampf(_user_sfx_gain_linear * _project_sfx_gain_linear, 0.0, 1.0)


func _effective_sfx_gain_db() -> float:
	var gain := _effective_sfx_gain_linear()
	return linear_to_db(gain) if gain > 0.0 else -80.0


func _apply_sfx_gain() -> void:
	var gain_db := _effective_sfx_gain_db()
	if npc_voice_player != null and is_instance_valid(npc_voice_player):
		npc_voice_player.volume_db = gain_db
	for player: AudioStreamPlayer in _event_players:
		if player != null and is_instance_valid(player):
			player.volume_db = gain_db


## The project scale is applied from the raw user gain every time. Repeated
## calls therefore remain idempotent instead of compounding another 0.5.
func set_user_sfx_gain_linear(user_gain_linear: float) -> bool:
	if not is_finite(user_gain_linear) or user_gain_linear < 0.0:
		return false
	_user_sfx_gain_linear = clampf(user_gain_linear, 0.0, 1.0)
	_apply_sfx_gain()
	return true


func user_sfx_gain_linear() -> float:
	return _user_sfx_gain_linear


func effective_sfx_gain_linear() -> float:
	return _effective_sfx_gain_linear()


func project_sfx_gain_linear() -> float:
	return _project_sfx_gain_linear


func set_sfx_enabled(enabled: bool) -> void:
	_sfx_enabled = enabled
	_apply_sfx_gain()


func sync_sfx_enabled_from_bus() -> void:
	var bus_index := AudioServer.get_bus_index(SFX_BUS_NAME)
	if bus_index >= 0:
		_sfx_enabled = not AudioServer.is_bus_mute(bus_index)
	_apply_sfx_gain()


func is_sfx_enabled() -> bool:
	return _sfx_enabled


## Shared helper for any legacy player that is still active during integration.
## The caller passes the existing raw/user gain; the project scale is applied
## exactly once and the player is moved onto the SFX bus.
func route_sfx_player(player: AudioStreamPlayer, user_gain_linear := 1.0) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not is_finite(user_gain_linear) or user_gain_linear < 0.0:
		return false
	player.bus = SFX_BUS_NAME
	var gain := (
		clampf(user_gain_linear * _project_sfx_gain_linear, 0.0, 1.0)
		if _sfx_enabled
		else 0.0
	)
	player.volume_db = linear_to_db(gain) if gain > 0.0 else -80.0
	return true


func set_clock_for_test(now_msec: int) -> void:
	_clock_override_msec = now_msec


func clear_clock_override_for_test() -> void:
	_clock_override_msec = -1


func _now_msec() -> int:
	return _clock_override_msec if _clock_override_msec >= 0 else Time.get_ticks_msec()


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
	npc_voice_player.volume_db = _effective_sfx_gain_db()
	npc_voice_player.autoplay = false
	npc_voice_player.finished.connect(_on_npc_voice_finished)
	add_child(npc_voice_player)


func _build_event_players() -> void:
	for pool_index in EVENT_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "EventPlayer_%02d" % pool_index
		player.bus = SFX_BUS_NAME
		player.volume_db = _effective_sfx_gain_db()
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
	_apply_sfx_gain()
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
## participate in runtime resolution. Admission, owner/release de-duplication
## and SFX scaling all happen before a stream is touched.
func play_event(event_id: String, context: Dictionary = {}) -> Dictionary:
	return _play_event_internal(event_id, context, false, "")


func _play_event_internal(
	event_id: String,
	context: Dictionary,
	allow_restricted_monster_source: bool,
	requested_semantic_event: String,
) -> Dictionary:
	_metrics["requests"] = int(_metrics.get("requests", 0)) + 1
	var binding: Dictionary = _events.get(event_id, {}) as Dictionary
	if binding.is_empty() or str(binding.get("owner_kind", "")) == "npc":
		return _reject_event("missing_mapping", event_id, context)
	if str(binding.get("mapping_status", "")) not in ["EXACT", "SHARED_VERIFIED"]:
		return _reject_event("unresolved_mapping", event_id, context)
	var owner_kind := str(binding.get("owner_kind", ""))
	var semantic_event := str(binding.get("semantic_event", ""))
	if (
		owner_kind == "monster"
		and semantic_event in MONSTER_REJECTED_SEMANTICS
		and not allow_restricted_monster_source
	):
		return _reject_event_light("monster_event_not_allowed", event_id, context)
	if not _sfx_enabled:
		_metrics["sfx_disabled"] = int(_metrics.get("sfx_disabled", 0)) + 1
		return _reject_event_light("sfx_disabled", event_id, context)
	var owner_release_key := _owner_release_key(event_id, context)
	if not owner_release_key.is_empty() and _owner_release_seen.has(owner_release_key):
		_metrics["owner_release_duplicates"] = int(_metrics.get("owner_release_duplicates", 0)) + 1
		return _reject_event_light("duplicate_owner_release", event_id, context)
	var priority := int(binding.get("priority", 50))
	var admission_reason := _admission_reason(
		owner_kind,
		semantic_event,
		priority,
		allow_restricted_monster_source,
	)
	if not admission_reason.is_empty():
		if owner_kind == "monster" and (
			semantic_event in MONSTER_PROMPT_SEMANTICS
			or (allow_restricted_monster_source and semantic_event == "ambient")
		):
			_metrics["monster_prompt_rejected"] = int(_metrics.get("monster_prompt_rejected", 0)) + 1
		elif owner_kind == "monster" and semantic_event in MONSTER_ATTACK_SEMANTICS:
			_metrics["monster_attack_rejected"] = int(_metrics.get("monster_attack_rejected", 0)) + 1
		if admission_reason == "monster_polyphony_limit":
			_metrics["monster_polyphony_rejected"] = int(_metrics.get("monster_polyphony_rejected", 0)) + 1
		if admission_reason == "polyphony_limit":
			_metrics["event_pool_rejected"] = int(_metrics.get("event_pool_rejected", 0)) + 1
		return _reject_event_light(admission_reason, event_id, context)
	var runtime_paths := _valid_event_runtime_paths(binding.get("runtime_paths", []))
	if runtime_paths.is_empty():
		return _reject_event("missing_mapping", event_id, context)
	var selected_index := _select_event_variant(event_id, binding, runtime_paths.size(), context)
	var runtime_path := str(runtime_paths[selected_index])
	var stream := _stream_for(runtime_path)
	if stream == null:
		return _reject_event("load_failed", event_id, context, runtime_path)
	var pool_index := _acquire_event_player(priority)
	if pool_index < 0:
		_metrics["event_pool_rejected"] = int(_metrics.get("event_pool_rejected", 0)) + 1
		return _reject_event_light("polyphony_limit", event_id, context, runtime_path)
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
		"owner_kind": owner_kind,
		"semantic_event": semantic_event,
		"owner_release_key": owner_release_key,
	}
	player.play()
	if not owner_release_key.is_empty():
		_owner_release_seen[owner_release_key] = _now_msec()
	if owner_kind == "monster":
		_refresh_monster_budget_window()
		if allow_restricted_monster_source and semantic_event == "ambient":
			_monster_prompt_starts_in_window += 1
		elif semantic_event == "attack_start":
			_monster_attack_starts_in_window += 1
	var event := {
		"contract_id": CONTRACT_ID,
		"status": "played",
		"event_id": event_id,
		"semantic_event": requested_semantic_event if not requested_semantic_event.is_empty() else semantic_event,
		"source_semantic_event": semantic_event,
		"runtime_path": runtime_path,
		"variant_index": selected_index,
		"request_serial": _request_serial,
		"pool_index": pool_index,
		"context": context.duplicate(true),
	}
	_last_event = event.duplicate(true)
	_metrics["played"] = int(_metrics.get("played", 0)) + 1
	if owner_kind == "monster" and (
		semantic_event in MONSTER_PROMPT_SEMANTICS
		or (allow_restricted_monster_source and semantic_event == "ambient")
	):
		_metrics["monster_prompt_admitted"] = int(_metrics.get("monster_prompt_admitted", 0)) + 1
	elif owner_kind == "monster" and semantic_event in MONSTER_ATTACK_SEMANTICS:
		_metrics["monster_attack_admitted"] = int(_metrics.get("monster_attack_admitted", 0)) + 1
	event_started.emit(event.duplicate(true))
	return event


## Exact monster-ID helper. Attack phases use their own source phase. The
## combat prompt deliberately reuses this ID's original ambient sample and is
## the only production path that may consume an ambient binding.
func play_monster_event(monster_id: int, semantic_event: String, context: Dictionary = {}) -> Dictionary:
	if monster_id <= 0 or semantic_event.is_empty():
		return _reject_event("invalid_event", "", context)
	if semantic_event in MONSTER_PROMPT_SEMANTICS:
		var owner_key := str(context.get("audio_owner_key", context.get("owner_key", "")))
		return play_monster_combat_prompt(monster_id, owner_key, context)
	if semantic_event in MONSTER_REJECTED_SEMANTICS:
		return _reject_event_light(
			"monster_event_not_allowed",
			"monster.%d.%s" % [monster_id, semantic_event],
			context,
		)
	return play_event("monster.%d.%s" % [monster_id, semantic_event], context)


## Start one presentation session for a real monster engagement. A session is
## keyed by the actor owner, so a target refresh or a short LOS interruption
## cannot replay the prompt. The source event remains `ambient` for an exact
## stable monster-ID reuse; the returned semantic event is `combat_prompt`.
func play_monster_combat_prompt(
	monster_id: int,
	audio_owner_key: String,
	context: Dictionary = {},
) -> Dictionary:
	if monster_id <= 0 or audio_owner_key.strip_edges().is_empty():
		return _reject_event("invalid_event", "", context)
	var owner_key := audio_owner_key.strip_edges()
	var now_msec := _now_msec()
	var session: Dictionary = _monster_sessions.get(owner_key, {}) as Dictionary
	if bool(session.get("active", false)):
		return _reject_event_light(
			"combat_session_duplicate",
			"monster.%d.ambient" % monster_id,
			context,
		)
	if now_msec < int(session.get("rearm_after_msec", 0)):
		return _reject_event_light(
			"combat_session_rearm_pending",
			"monster.%d.ambient" % monster_id,
			context,
		)
	var prompt_context := context.duplicate(true)
	prompt_context["audio_owner_key"] = owner_key
	prompt_context["release_id"] = str(
		context.get("session_id", "combat:%s:%d" % [owner_key, now_msec])
	)
	prompt_context["monster_combat_session"] = true
	var result := _play_event_internal(
		"monster.%d.ambient" % monster_id,
		prompt_context,
		true,
		"combat_prompt",
	)
	if str(result.get("status", "")) == "played":
		session["active"] = true
		session["monster_id"] = monster_id
		session["started_msec"] = now_msec
		session["last_activity_msec"] = now_msec
		session["rearm_after_msec"] = 0
		_monster_sessions[owner_key] = session
	return result


func set_monster_combat_session(
	monster_id: int,
	audio_owner_key: String,
	engaged: bool,
	reason := "",
	context: Dictionary = {},
) -> Dictionary:
	if engaged:
		return play_monster_combat_prompt(monster_id, audio_owner_key, context)
	return end_monster_combat_session(audio_owner_key, reason)


## Only explicit real disengagements close a session. LOS/path interruptions
## are intentionally ignored so a wall corner cannot create a new prompt.
func end_monster_combat_session(audio_owner_key: String, reason := "explicit_disengage") -> Dictionary:
	var owner_key := audio_owner_key.strip_edges()
	if owner_key.is_empty():
		return {"status": "invalid_event", "reason": "missing_audio_owner_key"}
	if reason in TRANSIENT_LOS_REASONS:
		return {
			"status": "ignored",
			"reason": "transient_los",
			"audio_owner_key": owner_key,
		}
	if reason.is_empty():
		reason = "explicit_disengage"
	if reason not in REAL_DISENGAGE_REASONS:
		return {
			"status": "ignored",
			"reason": "non_disengage_transition",
			"audio_owner_key": owner_key,
		}
	var session: Dictionary = _monster_sessions.get(owner_key, {}) as Dictionary
	if session.is_empty() or not bool(session.get("active", false)):
		return {"status": "already_inactive", "audio_owner_key": owner_key}
	session["active"] = false
	session["ended_msec"] = _now_msec()
	session["last_end_reason"] = reason
	session["rearm_after_msec"] = _now_msec() + int(_monster_session_rearm_seconds * 1000.0)
	_monster_sessions[owner_key] = session
	return {
		"status": "ended",
		"reason": reason,
		"audio_owner_key": owner_key,
		"rearm_after_msec": int(session["rearm_after_msec"]),
	}


func monster_combat_session_snapshot(audio_owner_key := "") -> Dictionary:
	if not audio_owner_key.is_empty():
		var session: Variant = _monster_sessions.get(audio_owner_key, {})
		return (session as Dictionary).duplicate(true) if session is Dictionary else {}
	return _monster_sessions.duplicate(true)


func notify_monster_los_interrupted(audio_owner_key: String) -> Dictionary:
	return end_monster_combat_session(audio_owner_key, "los_interrupted")


## Kept as a compatibility surface for old callers. Ambient walk/turn audio is
## no longer a production event; it consumes neither an RNG roll nor a stream.
func play_monster_ambient_if_due(
	monster_id: int,
	client_frame: int,
	audio_owner_key: String,
	context: Dictionary = {}
) -> Dictionary:
	if monster_id <= 0 or audio_owner_key.is_empty():
		return _reject_event("invalid_event", "", context)
	return _skipped_event(
		"ambient_disabled",
		"monster.%d.ambient" % monster_id,
		context,
	)


## Primary Actor.pas emits two independent layers on a confirmed player
## physical hit: m_nStruckWeaponSound, then m_nStruckSound. The first source
## branch applies integer division a second time after m_btWeapon div 2; keep
## that exact behavior rather than normalizing it to the swing family.
func play_player_physical_contact(classic_weapon_shape: int, context: Dictionary = {}) -> Dictionary:
	if classic_weapon_shape < 0:
		return _reject_event("invalid_event", "player.contact", context)
	var layer_results: Array[Dictionary] = []
	var weapon_event_id := _player_contact_weapon_event(classic_weapon_shape)
	if not weapon_event_id.is_empty():
		layer_results.append(play_event(weapon_event_id, context))
	var body_event_id := _player_contact_body_event(classic_weapon_shape)
	layer_results.append(play_event(body_event_id, context))
	var played_count := 0
	for result: Dictionary in layer_results:
		if str(result.get("status", "")) == "played":
			played_count += 1
	return {
		"contract_id": CONTRACT_ID,
		"status": "played" if played_count > 0 else "not_played",
		"classic_weapon_shape": classic_weapon_shape,
		"played_layer_count": played_count,
		"layers": layer_results,
		"context": context.duplicate(true),
	}


func _player_contact_weapon_event(classic_weapon_shape: int) -> String:
	var source_second_division := floori(float(classic_weapon_shape) / 2.0)
	match source_second_division:
		6, 20:
			return "player.contact.weapon.short"
		1, 8, 12, 18, 21:
			return "player.contact.weapon.wood"
		2, 5, 9, 13, 14, 22:
			return "player.contact.weapon.sword"
		4, 10, 15, 16, 17, 23:
			return "player.contact.weapon.blade"
		3, 7, 11:
			return "player.contact.weapon.axe"
		24:
			return "player.contact.weapon.club"
		_:
			return ""


func _player_contact_body_event(classic_weapon_shape: int) -> String:
	match classic_weapon_shape:
		1, 2, 4, 5, 6, 9, 10, 13, 14, 15, 16, 17:
			return "player.contact.body.sword"
		3, 11:
			return "player.contact.body.axe"
		8, 12, 18:
			return "player.contact.body.long"
		_:
			return "player.contact.body.fist"


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
	_owner_release_seen.clear()
	for owner_key: String in _monster_sessions.keys():
		var session: Dictionary = _monster_sessions[owner_key]
		if bool(session.get("active", false)):
			session["active"] = false
			session["ended_msec"] = _now_msec()
			session["last_end_reason"] = reason
			session["rearm_after_msec"] = _now_msec()
			_monster_sessions[owner_key] = session


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
		"runtime_config": _runtime_config.duplicate(true),
		"binding_count": _bindings.size(),
		"event_count": _events.size(),
		"item_route_identity_count": _item_event_routes.size(),
		"event_ids": _events.keys(),
		"event_pool_size": _event_players.size(),
		"active_event_count": _active_event_count(),
		"active_monster_event_count": _active_monster_event_count(),
		"monster_polyphony_limit": _monster_polyphony_limit,
		"monster_combat_prompt_rate_per_second": _monster_combat_prompt_rate_per_second,
		"monster_attack_rate_per_second": _monster_attack_rate_per_second,
		"sfx_enabled": _sfx_enabled,
		"user_sfx_gain_linear": _user_sfx_gain_linear,
		"project_sfx_gain_linear": _project_sfx_gain_linear,
		"effective_sfx_gain_linear": _effective_sfx_gain_linear(),
		"active_npc_id": active_npc_id(),
		"active_runtime_path": _active_runtime_path if is_npc_voice_active() else "",
		"request_serial": _request_serial,
		"last_event": _last_event.duplicate(true),
	}


func metrics_snapshot() -> Dictionary:
	var result := _metrics.duplicate(true)
	result["active_event_count"] = _active_event_count()
	result["active_monster_event_count"] = _active_monster_event_count()
	result["sfx_enabled"] = _sfx_enabled
	result["effective_sfx_gain_linear"] = _effective_sfx_gain_linear()
	result["project_sfx_gain_linear"] = _project_sfx_gain_linear
	result["monster_polyphony_limit"] = _monster_polyphony_limit
	result["monster_prompt_rate_per_second"] = _monster_combat_prompt_rate_per_second
	result["monster_attack_rate_per_second"] = _monster_attack_rate_per_second
	return result


func reset_metrics_for_test(reset_sessions := false) -> void:
	for key: Variant in _metrics.keys():
		_metrics[key] = 0
	_monster_budget_window_started_msec = -1
	_monster_prompt_starts_in_window = 0
	_monster_attack_starts_in_window = 0
	_owner_release_seen.clear()
	if reset_sessions:
		_monster_sessions.clear()


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


func _admission_reason(
	owner_kind: String,
	semantic_event: String,
	new_priority: int,
	is_combat_prompt := false,
) -> String:
	# This is intentionally a pure read of current budget/pool state. No stream
	# lookup, variant load or player stop happens until it returns an admission.
	if _find_event_player_candidate(new_priority) < 0:
		return "polyphony_limit"
	if owner_kind != "monster":
		return ""
	if _active_monster_event_count() >= _monster_polyphony_limit:
		return "monster_polyphony_limit"
	_refresh_monster_budget_window()
	if is_combat_prompt:
		if _monster_prompt_starts_in_window >= _monster_combat_prompt_rate_per_second:
			return "monster_prompt_rate_limit"
	elif semantic_event == "attack_start":
		if _monster_attack_starts_in_window >= _monster_attack_rate_per_second:
			return "monster_attack_rate_limit"
	return ""


func _refresh_monster_budget_window() -> void:
	var now_msec := _now_msec()
	if (
		_monster_budget_window_started_msec < 0
		or now_msec - _monster_budget_window_started_msec >= 1000
	):
		_monster_budget_window_started_msec = now_msec
		_monster_prompt_starts_in_window = 0
		_monster_attack_starts_in_window = 0


func _active_monster_event_count() -> int:
	var count := 0
	for pool_index: int in _event_slots.size():
		var slot: Dictionary = _event_slots[pool_index]
		if (
			str(slot.get("owner_kind", "")) == "monster"
			and pool_index < _event_players.size()
			and _event_players[pool_index] != null
			and _event_players[pool_index].playing
		):
			count += 1
	return count


func _owner_release_key(event_id: String, context: Dictionary) -> String:
	var owner_key := str(
		context.get("audio_owner_key", context.get("owner_key", ""))
	).strip_edges()
	var release_id := str(
		context.get("release_id", context.get("session_id", ""))
	).strip_edges()
	if owner_key.is_empty() or release_id.is_empty():
		return ""
	return "%s|%s|%s" % [owner_key, event_id, release_id]


func _find_event_player_candidate(new_priority: int) -> int:
	if _event_players.is_empty():
		return -1
	for pool_index: int in _event_players.size():
		var player := _event_players[pool_index]
		if player != null and is_instance_valid(player) and not player.playing:
			return pool_index
	var candidate := -1
	var candidate_priority := 2147483647
	var candidate_serial := 2147483647
	for pool_index: int in _event_slots.size():
		var slot := _event_slots[pool_index]
		var priority := int(slot.get("priority", 0))
		var serial := int(slot.get("request_serial", 0))
		if priority < candidate_priority or (
			priority == candidate_priority and serial < candidate_serial
		):
			candidate = pool_index
			candidate_priority = priority
			candidate_serial = serial
	if candidate < 0 or new_priority < candidate_priority:
		return -1
	return candidate


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
	_metrics["stream_lookup_attempts"] = int(_metrics.get("stream_lookup_attempts", 0)) + 1
	if _stream_cache.has(runtime_path):
		return _stream_cache[runtime_path] as AudioStream
	# Runtime interaction is deliberately not a cold-load path.  A missing
	# cache entry means initialization/prewarm was incomplete; fail closed and
	# let the caller's diagnostic/replacement policy handle it.
	_metrics["stream_cache_misses"] = int(_metrics.get("stream_cache_misses", 0)) + 1
	_emit_diagnostic("not_prewarmed", {"path": runtime_path})
	return null


func _reject(reason: String, canonical_npc_id: String, context: Dictionary, runtime_path := "") -> Dictionary:
	_metrics["rejected"] = int(_metrics.get("rejected", 0)) + 1
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
	_metrics["rejected"] = int(_metrics.get("rejected", 0)) + 1
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


func _reject_event_light(
	reason: String,
	event_id: String,
	context: Dictionary = {},
	runtime_path := "",
) -> Dictionary:
	# Admission failures intentionally avoid deep-copying a potentially large
	# diagnostic context before the hot-path request has been accepted.
	_metrics["rejected"] = int(_metrics.get("rejected", 0)) + 1
	var event := {
		"contract_id": CONTRACT_ID,
		"status": reason,
		"event_id": event_id,
		"runtime_path": runtime_path,
	}
	if context.has("source"):
		event["context_source"] = str(context.get("source", ""))
	_last_event = event.duplicate(true)
	_emit_diagnostic(reason, event)
	return event


func _skipped_event(reason: String, event_id: String, context: Dictionary) -> Dictionary:
	_metrics["skipped"] = int(_metrics.get("skipped", 0)) + 1
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
