class_name TownMusicController
extends Node

## Main-city music is deliberately a small, event-driven presentation service.
## GameRoot owns the map and safe-area authorities; this node only owns the
## delayed playback lifecycle and the Music-bus player.

const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const MapTeleportRuntimePolicyScript := preload(
	"res://scripts/layers/runtime/map_teleport_runtime_policy.gd"
)

const CONTRACT_ID := "audio.town_music.v1"
const LOADING_TRANSITION_CONTRACT_ID := "ui.loading.transition.v1"
const TOWN_MUSIC_PATH := "res://assets/audio/town/main_city_bgm.ogg"
const SOURCE_RECORD_PATH := "res://assets/audio/town/main_city_bgm.source.json"
const MUSIC_BUS_NAME := &"Music"
const DELAY_SECONDS := 6.0
const DEFAULT_VOLUME_LINEAR := 0.70
const TOWN_AREA_POLICY_ID := "gameplay.main_city.safe_area.v1"

## These are the exact direct-city map IDs already exposed by the formal map
## teleport policy. A map ID alone is not enough to enter this set: playback
## also requires a point inside the map's compiled safe-area geometry.
const MAIN_CITY_MAP_IDS: Dictionary = MapTeleportRuntimePolicyScript.DIRECT_CITY_LABELS

signal delay_scheduled(request: Dictionary)
signal music_started(request: Dictionary)
signal music_stopped(request: Dictionary)

var delay_seconds := DELAY_SECONDS
var music_player: AudioStreamPlayer
var delay_timer: Timer
var _delay_callback := Callable()

var _entry_serial := 0
var _active_map_id := -1
var _active_transition_id := ""
var _town_area_id := ""
var _in_town := false
var _loading_finished := false
var _music_started_for_entry := false
var _delay_armed_for_entry := false
var _waiting_for_track_finish := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("stable_id", CONTRACT_ID)
	_ensure_music_bus()
	_build_audio_nodes()


func _build_audio_nodes() -> void:
	delay_timer = Timer.new()
	delay_timer.name = "TownMusicDelay"
	delay_timer.one_shot = true
	delay_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(delay_timer)

	music_player = AudioStreamPlayer.new()
	music_player.name = "TownMusicPlayer"
	music_player.bus = MUSIC_BUS_NAME
	music_player.volume_db = linear_to_db(DEFAULT_VOLUME_LINEAR)
	music_player.autoplay = false
	var stream := load(TOWN_MUSIC_PATH) as AudioStream
	if stream != null:
		music_player.stream = stream
		if stream is AudioStreamOggVorbis:
			# One city entry owns one complete track. A later entry must cross the
			# leave/re-enter boundary before another play() is permitted.
			(stream as AudioStreamOggVorbis).loop = false
	music_player.finished.connect(_on_music_finished)
	add_child(music_player)


func _ensure_music_bus() -> void:
	var bus_index := AudioServer.get_bus_index(MUSIC_BUS_NAME)
	if bus_index >= 0:
		return
	AudioServer.add_bus()
	bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, MUSIC_BUS_NAME)
	AudioServer.set_bus_send(bus_index, &"Master")
	# Do not set mute here. The system menu remains the only owner of the
	# Music/SFX enabled state and may mute this bus later through AudioServer.


static func is_main_city_map(map_id: int) -> bool:
	return MAIN_CITY_MAP_IDS.has(map_id)


static func town_entry_id(map_id: int) -> String:
	if not is_main_city_map(map_id):
		return ""
	# Safe-area geometry answers "am I in town?"; the map-level entry ID
	# answers "did I leave town?". This keeps multiple authored safe areas in
	# one city from restarting the same entry's six-second gate.
	return "main_city.%d" % map_id


## Resolve the authoritative town area from GameRoot's already-compiled
## safe-area set. Returning an empty dictionary is fail-closed and means that
## even a direct-city map is not treated as town when its geometry is missing.
static func town_area_at(
	map_id: int,
	safe_areas: Array,
	player_ground_gu: Vector2,
) -> Dictionary:
	if not is_main_city_map(map_id) or not player_ground_gu.is_finite():
		return {}
	for area_index: int in range(safe_areas.size()):
		var raw_area: Variant = safe_areas[area_index]
		if (
			not raw_area is Dictionary
			or not WorldSpatialRulesScript.point_inside_safe_zone_ground_gu(
				player_ground_gu,
				raw_area as Dictionary,
			)
		):
			continue
		var area := (raw_area as Dictionary).duplicate(true)
		var area_id := str(area.get(
			"semantic_id",
			area.get("area_id", area.get("zone_id", "")),
		))
		if area_id.is_empty():
			# 910001 receives a formal runtime circle from the bridge and does not
			# carry an authored semantic_id; index it deterministically instead.
			area_id = "safe_area.%d.%d" % [map_id, area_index]
		area["area_id"] = area_id
		area["policy_id"] = TOWN_AREA_POLICY_ID
		return area
	return {}


## Called before the destination map is built. This invalidates an old map's
## pending six-second callback while deliberately preserving an already-playing
## BGM until its natural end.
func begin_map_transition(map_id: int, transition_id: String) -> void:
	_entry_serial += 1
	_active_map_id = map_id
	_active_transition_id = transition_id
	_town_area_id = ""
	_in_town = false
	_loading_finished = false
	_music_started_for_entry = false
	_delay_armed_for_entry = false
	_cancel_delay()
	# A started city track belongs to the presentation session, not to the
	# current map node.  Keep it playing across map changes; a later city entry
	# waits for the natural end before arming its own six-second delay.


## Called after _load_zone and actor staging have completed, while Loading is
## still visible. The caller passes GameRoot's compiled active safe areas and
## the canonical player ground coordinate; no map-wide fallback is allowed.
func set_map_context(
	map_id: int,
	safe_areas: Array,
	player_ground_gu: Vector2,
	transition_id: String,
) -> bool:
	if map_id != _active_map_id or transition_id != _active_transition_id:
		return false
	var area := town_area_at(map_id, safe_areas, player_ground_gu)
	if area.is_empty():
		set_town_presence(false)
		return false
	set_town_presence(true, town_entry_id(map_id))
	return true


## A map may expose a town area while the player walks out of it before the
## delayed start. GameRoot can call this cheap edge-triggered method whenever
## its safe-area cache changes; re-entry starts a fresh once-only delay.
func set_town_presence(in_town: bool, _area_id := "") -> void:
	if not in_town or not is_main_city_map(_active_map_id):
		if (
			not _in_town
			and not _delay_armed_for_entry
			and not _music_started_for_entry
		):
			return
		_entry_serial += 1
		_in_town = false
		_town_area_id = ""
		_music_started_for_entry = false
		_cancel_delay()
		# Leaving the safe area must not truncate a track that has already begun.
		# `cancel()` remains the explicit character/app/world-exit stop boundary.
		return
	var resolved_area_id := town_entry_id(_active_map_id)
	if _in_town and _town_area_id == resolved_area_id:
		return
	_in_town = true
	_town_area_id = resolved_area_id
	_music_started_for_entry = false
	_delay_armed_for_entry = false
	_entry_serial += 1
	if _loading_finished:
		_arm_delay()


## HUD forwards LoadingTransitionOverlay.transition_finished here. The
## transition ID is checked so an old finish event cannot arm a new map.
func on_loading_transition_finished(request: Dictionary) -> bool:
	if (
		str(request.get("contract_id", ""))
		!= LOADING_TRANSITION_CONTRACT_ID
		or str(request.get("transition_id", "")) != _active_transition_id
		or _active_transition_id.is_empty()
	):
		return false
	if _loading_finished:
		return false
	_loading_finished = true
	if _in_town and not _music_started_for_entry:
		_arm_delay()
	return true


func cancel(reason := "cancelled") -> void:
	_entry_serial += 1
	_loading_finished = false
	_in_town = false
	_town_area_id = ""
	_music_started_for_entry = false
	_delay_armed_for_entry = false
	_cancel_delay()
	_stop_music(reason)


func is_delay_pending() -> bool:
	return _delay_armed_for_entry and (
		_waiting_for_track_finish
		or (delay_timer != null and not delay_timer.is_stopped())
	)


func is_music_active() -> bool:
	return music_player != null and music_player.playing


func state_snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"map_id": _active_map_id,
		"transition_id": _active_transition_id,
		"entry_serial": _entry_serial,
		"town_area_id": _town_area_id,
		"in_town": _in_town,
		"loading_finished": _loading_finished,
		"delay_pending": is_delay_pending(),
		"music_started_for_entry": _music_started_for_entry,
		"waiting_for_track_finish": _waiting_for_track_finish,
		"music_active": is_music_active(),
	}


func _arm_delay() -> void:
	if (
		delay_timer == null
		or not _in_town
		or not is_main_city_map(_active_map_id)
		or _music_started_for_entry
		or _delay_armed_for_entry
	):
		return
	_delay_armed_for_entry = true
	if is_music_active():
		# Do not restart or overlap the current one-shot.  The natural finished
		# callback below will arm this same entry after the old track ends.
		_waiting_for_track_finish = true
		return
	_waiting_for_track_finish = false
	_delay_callback = Callable(self, "_on_delay_timeout").bind(_entry_serial)
	delay_timer.timeout.connect(_delay_callback)
	delay_timer.start(maxf(0.0, delay_seconds))
	delay_scheduled.emit({
		"contract_id": CONTRACT_ID,
		"map_id": _active_map_id,
		"transition_id": _active_transition_id,
		"entry_serial": _entry_serial,
		"delay_seconds": maxf(0.0, delay_seconds),
		"area_id": _town_area_id,
	})


func _cancel_delay() -> void:
	_delay_armed_for_entry = false
	_waiting_for_track_finish = false
	if (
		delay_timer != null
		and _delay_callback.is_valid()
		and delay_timer.timeout.is_connected(_delay_callback)
	):
		delay_timer.timeout.disconnect(_delay_callback)
	_delay_callback = Callable()
	if delay_timer != null and not delay_timer.is_stopped():
		delay_timer.stop()


func _on_delay_timeout(expected_entry_serial: int) -> void:
	if delay_timer != null and _delay_callback.is_valid() and delay_timer.timeout.is_connected(_delay_callback):
		delay_timer.timeout.disconnect(_delay_callback)
	_delay_callback = Callable()
	_delay_armed_for_entry = false
	if (
		expected_entry_serial != _entry_serial
		or
		not _loading_finished
		or not _in_town
		or not is_main_city_map(_active_map_id)
		or _music_started_for_entry
		or is_music_active()
		or music_player == null
		or music_player.stream == null
	):
		return
	_music_started_for_entry = true
	music_player.play()
	music_started.emit({
		"contract_id": CONTRACT_ID,
		"map_id": _active_map_id,
		"transition_id": _active_transition_id,
		"entry_serial": _entry_serial,
		"area_id": _town_area_id,
	})


func _stop_music(reason: String) -> void:
	if music_player == null or not music_player.playing:
		return
	music_player.stop()
	music_stopped.emit({
		"contract_id": CONTRACT_ID,
		"map_id": _active_map_id,
		"transition_id": _active_transition_id,
		"reason": reason,
	})


func _on_music_finished() -> void:
	# The stream is intentionally one-shot. Keep the current entry's started
	# latch set so a natural end cannot restart it. If a new city entry arrived
	# while this track was playing, its deferred gate is now safe to arm.
	var should_arm_deferred_entry := (
		_waiting_for_track_finish
		and _in_town
		and _loading_finished
		and not _music_started_for_entry
	)
	_waiting_for_track_finish = false
	if should_arm_deferred_entry:
		_delay_armed_for_entry = false
		_arm_delay()
