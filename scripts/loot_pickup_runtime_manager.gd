class_name LootPickupRuntimeManager
extends Node

## R3X-5: the sole runtime owner of ground-loot collection scheduling.  Loot
## nodes register once and are queried from a map-scoped spatial index on
## player movement, registration, retry deadlines, and a low-frequency
## fail-safe tick.  The inventory transaction and pickup signals remain owned
## by GameRoot/PlayerState exactly as before.

const LootIndexScript := preload("res://scripts/runtime_loot_spatial_index.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")

const CONTRACT_ID := "hardcore.loot.runtime_manager.map_scoped.v1"
const COLLECTION_RADIUS_GU := 0.75
const FAIL_SAFE_INTERVAL_SECONDS := 0.1
const VISUAL_UPDATE_INTERVAL_SECONDS := 1.0 / 30.0

var _spatial_index: LootIndexScript = LootIndexScript.new()
var _player: PlayerCharacter
var _runtime_map_id := -1
var _zone_generation := -1
var _screen_to_ground := Callable()
var _ground_to_screen := Callable()
var _registration_sequence := 0
var _fail_safe_remaining := 0.0
var _visual_update_remaining := 0.0
var _collection_elapsed := 0.0
var _player_ground_gu := Vector2.INF
var _player_screen_position_px := Vector2.INF
var _registered_pickups: Dictionary = {}
var _candidate_scratch: Array = []
var _previous_candidate_ids: Array[int] = []
var _candidate_ids: Dictionary = {}

var manager_player_event_count := 0
var manager_registration_check_count := 0
var manager_retry_check_count := 0
var manager_fail_safe_check_count := 0
var manager_exact_range_check_count := 0
var manager_collection_request_count := 0
var manager_visual_update_count := 0
var manager_full_scan_count := 0


func _ready() -> void:
	set_process(true)


func configure_player(player: PlayerCharacter) -> void:
	_player = player
	if is_instance_valid(_player):
		_player_screen_position_px = _player.global_position


func configure_map(
	runtime_map_id: int,
	zone_generation: int,
	screen_to_ground: Callable,
	ground_to_screen: Callable,
) -> bool:
	if (
		runtime_map_id != _runtime_map_id
		or zone_generation != _zone_generation
	):
		clear_all()
	_runtime_map_id = runtime_map_id
	_zone_generation = zone_generation
	_screen_to_ground = screen_to_ground if screen_to_ground is Callable else Callable()
	_ground_to_screen = ground_to_screen if ground_to_screen is Callable else Callable()
	_fail_safe_remaining = 0.0
	_visual_update_remaining = 0.0
	_collection_elapsed = 0.0
	_player_ground_gu = Vector2.INF
	_candidate_scratch.clear()
	_previous_candidate_ids.clear()
	_candidate_ids.clear()
	return _refresh_player_ground()


func clear_map(runtime_map_id: int) -> void:
	if runtime_map_id != _runtime_map_id:
		_spatial_index.clear_map(runtime_map_id)
		return
	clear_all()


func clear_all() -> void:
	_spatial_index.clear_all()
	_registered_pickups.clear()
	_candidate_scratch.clear()
	_previous_candidate_ids.clear()
	_candidate_ids.clear()
	_player_ground_gu = Vector2.INF


func register_pickup(pickup: LootPickup) -> bool:
	if not is_instance_valid(pickup):
		return false
	var ground_position := _screen_position_to_ground(pickup.global_position)
	if not ground_position.is_finite():
		return false
	var pickup_id := pickup.get_instance_id()
	_registration_sequence += 1
	if not _spatial_index.register(
		pickup_id,
		_runtime_map_id,
		ground_position,
		_registration_sequence,
		pickup,
	):
		return false
	RuntimeDiagnosticsScript.increment_performance_counter(&"loot_spatial_registers")
	_registered_pickups[pickup_id] = weakref(pickup)
	pickup.set_collection_manager(self)
	pickup.set_meta("loot_runtime_map_id", _runtime_map_id)
	pickup.set_meta("loot_zone_generation", _zone_generation)
	pickup.set_meta("loot_registration_order", _registration_sequence)
	pickup.tree_exiting.connect(
		_on_pickup_tree_exiting.bind(pickup_id),
		CONNECT_ONE_SHOT,
	)
	manager_registration_check_count += 1
	RuntimeDiagnosticsScript.increment_performance_counter(
		&"loot_manager_registration_checks"
	)
	# A drop generated under the player's feet is eligible immediately; it does
	# not wait for the next manager timer tick.
	if is_instance_valid(_player):
		_refresh_player_ground()
		_check_registered_pickup(pickup, ground_position, 0.0)
	return true


func unregister_pickup(pickup_or_id: Variant) -> void:
	var pickup_id: int = (
		pickup_or_id.get_instance_id()
		if pickup_or_id is Object and is_instance_valid(pickup_or_id)
		else int(pickup_or_id)
	)
	if pickup_id <= 0:
		return
	_spatial_index.unregister(pickup_id)
	RuntimeDiagnosticsScript.increment_performance_counter(&"loot_spatial_unregisters")
	_registered_pickups.erase(pickup_id)
	_previous_candidate_ids.erase(pickup_id)


func update_pickup_position(pickup: LootPickup) -> bool:
	if not is_instance_valid(pickup):
		return false
	var ground_position := _screen_position_to_ground(pickup.global_position)
	return _spatial_index.update_pickup(pickup.get_instance_id(), ground_position)


func player_position_changed(position_px: Vector2) -> void:
	if not position_px.is_finite():
		return
	_player_screen_position_px = position_px
	manager_player_event_count += 1
	RuntimeDiagnosticsScript.increment_performance_counter(&"loot_manager_player_events")
	_refresh_player_ground()
	_collection_elapsed = 0.0
	_fail_safe_remaining = FAIL_SAFE_INTERVAL_SECONDS
	_run_collection_pass(0.0)


func flush_for_logout() -> Dictionary:
	# Logout is a synchronous boundary.  Run one final nearby query so a loot
	# node generated immediately before the close request cannot be silently
	# left behind by the low-frequency scheduler.
	if not _refresh_player_ground():
		return {
			"success": true,
			"reason": "loot_manager_projection_unavailable_no_candidates",
			"pending_candidates": 0,
		}
	_run_collection_pass(0.0)
	return {
		"success": true,
		"reason": "",
		"pending_candidates": 0,
		"registered_pickup_count": _registered_pickups.size(),
	}


func diagnostics_snapshot() -> Dictionary:
	var index_snapshot := _spatial_index.diagnostics_snapshot()
	return {
		"contract_id": CONTRACT_ID,
		"runtime_map_id": _runtime_map_id,
		"zone_generation": _zone_generation,
		"registered_pickup_count": _registered_pickups.size(),
		"candidate_scratch_count": _candidate_scratch.size(),
		"manager_player_event_count": manager_player_event_count,
		"manager_registration_check_count": manager_registration_check_count,
		"manager_retry_check_count": manager_retry_check_count,
		"manager_fail_safe_check_count": manager_fail_safe_check_count,
		"manager_exact_range_check_count": manager_exact_range_check_count,
		"manager_collection_request_count": manager_collection_request_count,
		"manager_visual_update_count": manager_visual_update_count,
		"manager_full_scan_count": manager_full_scan_count,
		"spatial_index": index_snapshot,
	}


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	# Movement/teleport setters normally notify the manager immediately.  Keep
	# the fail-safe robust for direct position writes with one cheap vector
	# comparison, without re-running the formal projection every render frame.
	if (
		not _player_ground_gu.is_finite()
		or _player.global_position != _player_screen_position_px
	) and not _refresh_player_ground():
		return
	var safe_delta := maxf(0.0, delta)
	_collection_elapsed += safe_delta
	_fail_safe_remaining -= safe_delta
	_visual_update_remaining -= safe_delta
	if _fail_safe_remaining <= 0.0:
		_fail_safe_remaining = FAIL_SAFE_INTERVAL_SECONDS
		manager_fail_safe_check_count += 1
		RuntimeDiagnosticsScript.increment_performance_counter(
			&"loot_manager_fail_safe_checks"
		)
		_run_collection_pass(_collection_elapsed)
		_collection_elapsed = 0.0
	if _visual_update_remaining <= 0.0:
		_visual_update_remaining = VISUAL_UPDATE_INTERVAL_SECONDS
		_update_visuals(safe_delta)


func _run_collection_pass(delta_seconds: float) -> void:
	if not _player_ground_gu.is_finite():
		return
	_candidate_scratch.clear()
	RuntimeDiagnosticsScript.increment_performance_counter(&"loot_spatial_queries")
	RuntimeDiagnosticsScript.increment_performance_counter(
		&"loot_collection_spatial_queries"
	)
	_spatial_index.query_nearby_into(
		_runtime_map_id,
		_player_ground_gu,
		COLLECTION_RADIUS_GU,
		_candidate_scratch,
	)
	RuntimeDiagnosticsScript.increment_performance_counter(
		&"loot_spatial_candidates",
		_candidate_scratch.size(),
	)
	RuntimeDiagnosticsScript.increment_performance_counter(
		&"loot_collection_candidates",
		_candidate_scratch.size(),
	)
	_candidate_ids.clear()
	for raw_pickup: Variant in _candidate_scratch:
		if not raw_pickup is LootPickup or not is_instance_valid(raw_pickup):
			continue
		var pickup := raw_pickup as LootPickup
		var pickup_id := pickup.get_instance_id()
		_candidate_ids[pickup_id] = true
		_check_registered_pickup(
			pickup,
			_spatial_index.ground_position_for(pickup_id),
			delta_seconds,
		)
	for pickup_id: int in _previous_candidate_ids:
		if _candidate_ids.has(pickup_id):
			continue
		var raw_ref: Variant = _registered_pickups.get(pickup_id, null)
		var pickup: Variant = raw_ref.get_ref() if raw_ref is WeakRef else null
		if pickup is LootPickup and is_instance_valid(pickup):
			(pickup as LootPickup).manager_reset_attempt_context()
	_previous_candidate_ids.clear()
	for raw_pickup: Variant in _candidate_scratch:
		if raw_pickup is LootPickup and is_instance_valid(raw_pickup):
			_previous_candidate_ids.append((raw_pickup as LootPickup).get_instance_id())


func _check_registered_pickup(
	pickup: LootPickup,
	pickup_ground_gu: Vector2,
	delta_seconds: float,
) -> void:
	if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
		return
	var in_range := (
		pickup_ground_gu.is_finite()
		and _player_ground_gu.distance_squared_to(pickup_ground_gu)
		< COLLECTION_RADIUS_GU * COLLECTION_RADIUS_GU
	)
	manager_exact_range_check_count += 1
	RuntimeDiagnosticsScript.increment_performance_counter(
		&"loot_manager_exact_range_checks"
	)
	if pickup.retry_cooldown_remaining() > 0.0:
		manager_retry_check_count += 1
		RuntimeDiagnosticsScript.increment_performance_counter(
			&"loot_manager_retry_checks"
		)
	if pickup.manager_evaluate_collection(in_range, delta_seconds):
		manager_collection_request_count += 1
		RuntimeDiagnosticsScript.increment_performance_counter(
			&"loot_manager_collection_requests"
		)


func _update_visuals(delta_seconds: float) -> void:
	# Visual motion is intentionally manager-owned and low-frequency.  Invalid
	# weak refs are cleaned by the index query; no collection work is performed
	# here and no LootPickup has an individual process callback.
	for raw_ref: Variant in _registered_pickups.values():
		if not raw_ref is WeakRef:
			continue
		var pickup: Variant = (raw_ref as WeakRef).get_ref()
		if pickup is LootPickup and is_instance_valid(pickup):
			if (pickup as CanvasItem).is_visible_in_tree():
				(pickup as LootPickup).manager_visual_tick(delta_seconds)
				manager_visual_update_count += 1
				RuntimeDiagnosticsScript.increment_performance_counter(
					&"loot_manager_visual_updates"
				)


func _refresh_player_ground() -> bool:
	if not is_instance_valid(_player):
		return false
	_player_screen_position_px = _player.global_position
	_player_ground_gu = _screen_position_to_ground(_player_screen_position_px)
	return _player_ground_gu.is_finite()


func _screen_position_to_ground(position_px: Vector2) -> Vector2:
	if not position_px.is_finite():
		return Vector2.INF
	if _screen_to_ground.is_valid():
		var value: Variant = _screen_to_ground.call(position_px)
		if value is Vector2 and (value as Vector2).is_finite():
			return value as Vector2
	if _runtime_map_id >= 0:
		# A mapped manager must not reinterpret screen pixels as absolute ground
		# units when its formal projection provider is unavailable.
		return Vector2.INF
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(position_px)


func _on_pickup_tree_exiting(pickup_id: int) -> void:
	_spatial_index.unregister(pickup_id)
	_registered_pickups.erase(pickup_id)
	_previous_candidate_ids.erase(pickup_id)
