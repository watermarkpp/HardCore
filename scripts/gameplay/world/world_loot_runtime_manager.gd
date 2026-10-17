extends RefCounted
const PickupModel := preload("res://scripts/gameplay/world/world_loot_pickup_model.gd")
var _owner := OS.get_thread_caller_id()
var _world_ref: WeakRef
var _preferences: RefCounted
var _diagnostics: RefCounted
func _init(world: RefCounted, preferences: RefCounted, source_bucket_size_gu: float) -> void:
	assert(_owner != OS.get_main_thread_id())
	_world_ref = weakref(world)
	_preferences = preferences
	_diagnostics = world.diagnostics
	_spatial_index = LootIndexScript.new(source_bucket_size_gu)
func _world() -> RefCounted:
	assert(OS.get_thread_caller_id() == _owner and _world_ref.get_ref() != null)
	return _world_ref.get_ref()
func owner_thread_id() -> int: return _owner
func initialize_gameplay() -> bool:
	_preferences.filter_changed.connect(_on_filter_changed)
	return true
func close() -> void:
	if _preferences.filter_changed.is_connected(_on_filter_changed): _preferences.filter_changed.disconnect(_on_filter_changed)
	clear_all()
	_player = null


## R3X-5: the sole runtime owner of ground-loot collection scheduling.  Loot
## nodes register once and are queried from a map-scoped spatial index on
## player movement, registration, retry deadlines, and a low-frequency
## fail-safe tick.  The inventory transaction and pickup signals remain owned
## by GameRoot/PlayerState exactly as before.

const LootIndexScript := preload("res://scripts/gameplay/world/world_loot_spatial_index.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")



var name_placement_count := 0

const CONTRACT_ID := "hardcore.loot.runtime_manager.map_scoped.v1"
const COLLECTION_RADIUS_GU := 0.75
const FAIL_SAFE_INTERVAL_SECONDS := 0.1
const GROUND_LIFETIME_SECONDS := 600.0
var _ground_age := 0.0
var _expiry_queue: Array = []
var _expiry_cursor := 0
var _audit_expiry_pending: Array = []
var _audit_expiry_pending_cursor := 0

var _spatial_index: RefCounted
var _player: Object
var _runtime_map_id := -1
var _zone_generation := -1
var _screen_to_ground := Callable()
var _ground_to_screen := Callable()
var collection_path_is_clear := Callable()
var _registration_sequence := 0
var _fail_safe_remaining := 0.0
var _collection_elapsed := 0.0
var _player_ground_gu := Vector2.INF
var _player_screen_position_px := Vector2.INF
var _registered_pickups: Dictionary = {}
var _registered_pickup_maps: Dictionary = {}
var _candidate_scratch: Array = []
var _previous_candidate_ids: Array[int] = []
var _candidate_ids: Dictionary = {}
var _logout_blocked_pickup_ids: Array[int] = []

var manager_player_event_count := 0
var manager_registration_check_count := 0
var manager_retry_check_count := 0
var manager_fail_safe_check_count := 0
var manager_exact_range_check_count := 0
var manager_collection_request_count := 0
var manager_visual_update_count := 0
var manager_full_scan_count := 0
var manager_visual_registry_scan_count := 0
var manager_visual_registry_entry_count := 0




func _on_filter_changed(_level: int) -> void:
	# Labels are updated by pickups synchronously. Resume auto-collection on
	# the next frame, after all signal subscribers have applied the new filter.
	_fail_safe_remaining = 0.0


func _place_new_pickup_name(pickup: Object) -> void:
	var profile_started_usec: Variant = _diagnostics.timing_start()
	_world().emit_original_main_event(&"place_loot_name", [pickup.runtime_actor_id()])
	name_placement_count += 1
	var elapsed_usec: Variant = _diagnostics.timing_elapsed_usec(profile_started_usec)
	if elapsed_usec > 0:
		_diagnostics.increment_performance_counter(&"loot_name_placements")
		_diagnostics.increment_performance_counter(&"loot_name_placement_usec", elapsed_usec)
		_diagnostics.record_performance_max(&"loot_name_placement_max_ms", float(elapsed_usec) / 1000.0)


func configure_player(player: Object) -> void:
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
	_collection_elapsed = 0.0
	_player_ground_gu = Vector2.INF
	_candidate_scratch.clear()
	_previous_candidate_ids.clear()
	_candidate_ids.clear()
	_logout_blocked_pickup_ids.clear()
	return _refresh_player_ground()


func clear_map(runtime_map_id: int) -> void:
	if runtime_map_id != _runtime_map_id:
		_spatial_index.clear_map(runtime_map_id)
		var removed_ids: Array[int] = []
		for raw_id: Variant in _registered_pickup_maps.keys():
			if int(_registered_pickup_maps.get(raw_id, -1)) == runtime_map_id:
				removed_ids.append(int(raw_id))
		for pickup_id: int in removed_ids:
			_registered_pickup_maps.erase(pickup_id)
			_registered_pickups.erase(pickup_id)
			_previous_candidate_ids.erase(pickup_id)
			_candidate_ids.erase(pickup_id)
			_logout_blocked_pickup_ids.erase(pickup_id)
		_candidate_scratch.clear()
		return
	clear_all()


func clear_all() -> void:
	_audit_expiry_pending.clear()
	_audit_expiry_pending_cursor = 0
	_expiry_queue.clear()
	_expiry_cursor = 0
	_ground_age = 0.0
	_spatial_index.clear_all()
	_registered_pickups.clear()
	_registered_pickup_maps.clear()
	_candidate_scratch.clear()
	_previous_candidate_ids.clear()
	_candidate_ids.clear()
	_logout_blocked_pickup_ids.clear()
	_collection_elapsed = 0.0
	_player_ground_gu = Vector2.INF


func register_pickup(pickup: Object) -> bool:
	if not is_instance_valid(pickup):
		return false
	var ground_position: Variant = _screen_position_to_ground(pickup.global_position)
	if not ground_position.is_finite():
		return false
	var pickup_id: Variant = pickup.runtime_actor_id()
	_registration_sequence += 1
	if not _spatial_index.register(
		pickup_id,
		_runtime_map_id,
		ground_position,
		_registration_sequence,
		pickup,
	):
		return false
	_diagnostics.increment_performance_counter(&"loot_spatial_registers")
	_registered_pickups[pickup_id] = weakref(pickup)
	_place_new_pickup_name(pickup)
	_registered_pickup_maps[pickup_id] = _runtime_map_id
	_expiry_queue.append({"pickup": weakref(pickup), "deadline": _ground_age + GROUND_LIFETIME_SECONDS})
	pickup.set_collection_manager(self)
	pickup.write_meta("loot_runtime_map_id", _runtime_map_id)
	pickup.write_meta("loot_zone_generation", _zone_generation)
	pickup.write_meta("loot_registration_order", _registration_sequence)
	_world().connect_actor_exit_once(pickup, 
		_on_pickup_tree_exiting.bind(pickup_id),
		Object.CONNECT_ONE_SHOT,
	)
	manager_registration_check_count += 1
	_diagnostics.increment_performance_counter(
		&"loot_manager_registration_checks"
	)
	# A drop generated under the player's feet is eligible immediately; it does
	# not wait for the next manager timer tick.
	if is_instance_valid(_player):
		if _refresh_player_ground():
			var in_range: Variant = (
				_player_ground_gu.distance_squared_to(ground_position)
				< COLLECTION_RADIUS_GU * COLLECTION_RADIUS_GU
			)
			_check_registered_pickup(pickup, ground_position, 0.0)
			if in_range and not pickup.is_queued_for_retirement():
				if not _previous_candidate_ids.has(pickup_id):
					_previous_candidate_ids.append(pickup_id)
	return true


func unregister_pickup(pickup_or_id: Variant) -> void:
	var pickup_id: int = (
		pickup_or_id.runtime_actor_id()
		if pickup_or_id is Object and is_instance_valid(pickup_or_id)
		else int(pickup_or_id)
	)
	if pickup_id <= 0:
		return
	_spatial_index.unregister(pickup_id)
	_diagnostics.increment_performance_counter(&"loot_spatial_unregisters")
	_registered_pickups.erase(pickup_id)
	_registered_pickup_maps.erase(pickup_id)
	_previous_candidate_ids.erase(pickup_id)
	_logout_blocked_pickup_ids.erase(pickup_id)


func update_pickup_position(pickup: Object) -> bool:
	if not is_instance_valid(pickup):
		return false
	var ground_position: Variant = _screen_position_to_ground(pickup.global_position)
	return _spatial_index.update_pickup(pickup.runtime_actor_id(), ground_position)


func player_position_changed(position_px: Vector2) -> void:
	if not position_px.is_finite():
		return
	_player_screen_position_px = position_px
	manager_player_event_count += 1
	_diagnostics.increment_performance_counter(&"loot_manager_player_events")
	if not _refresh_player_ground():
		return
	# Movement remains an immediate collection trigger, but it consumes the
	# manager's accumulated game-time clock instead of discarding the time since
	# the previous scheduled pass.  The fail-safe schedule is still reset here
	# so a movement event does not cause an immediate duplicate query.
	var elapsed_since_collection_pass: Variant = _collection_elapsed
	_collection_elapsed = 0.0
	_fail_safe_remaining = FAIL_SAFE_INTERVAL_SECONDS
	_run_collection_pass(elapsed_since_collection_pass)


func flush_for_logout() -> Dictionary:
	# Logout is a synchronous boundary.  Run one final nearby query so a loot
	# node generated immediately before the close request cannot be silently
	# left behind by the low-frequency scheduler.
	if not _refresh_player_ground():
		var retry_blocked_ids: Variant = _logout_retry_blocked_ids_snapshot()
		var pending_count: Variant = _pending_logout_candidate_count()
		var registered_count: Variant = _registered_pickups.size()
		var unsettled: Variant = (
			registered_count > 0
			or pending_count > 0
			or not retry_blocked_ids.is_empty()
		)
		return {
			"success": not unsettled,
			"reason": (
				"loot_manager_projection_unavailable_with_unsettled_loot"
				if unsettled
				else "loot_manager_projection_unavailable_no_candidates"
			),
			"pending_candidates": pending_count,
			"logout_retry_blocked_count": retry_blocked_ids.size(),
			"logout_retry_blocked_pickup_ids": retry_blocked_ids,
			"registered_pickup_count": registered_count,
		}
	_run_collection_pass(0.0)
	return {
		"success": true,
		"reason": "",
		"pending_candidates": _pending_logout_candidate_count(),
		"logout_retry_blocked_count": _logout_blocked_pickup_ids.size(),
		"logout_retry_blocked_pickup_ids": _logout_blocked_pickup_ids.duplicate(),
		"registered_pickup_count": _registered_pickups.size(),
	}


func diagnostics_snapshot() -> Dictionary:
	var index_snapshot: Variant = _spatial_index.diagnostics_snapshot()
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
		# Static loot has no scheduled presentation pass. Retain the diagnostic
		# fields (zero) for existing Device Lab consumers.
		"manager_full_scan_count": manager_full_scan_count,
		"collection_full_scan_count": manager_full_scan_count,
		"visual_registry_scan_count": manager_visual_registry_scan_count,
		"visual_registry_entry_count": manager_visual_registry_entry_count,
		"logout_retry_blocked_count": _logout_blocked_pickup_ids.size(),
		"logout_retry_blocked_pickup_ids": _logout_blocked_pickup_ids.duplicate(),
		"spatial_index": index_snapshot,
	}


func _process(delta: float) -> void:
	_expire_ground_loot(maxf(0.0, delta))
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
	var safe_delta: Variant = maxf(0.0, delta)
	_collection_elapsed += safe_delta
	_fail_safe_remaining -= safe_delta
	if _fail_safe_remaining <= 0.0:
		_fail_safe_remaining = FAIL_SAFE_INTERVAL_SECONDS
		manager_fail_safe_check_count += 1
		_diagnostics.increment_performance_counter(
			&"loot_manager_fail_safe_checks"
		)
		_run_collection_pass(_collection_elapsed)
		_collection_elapsed = 0.0


func _expire_ground_loot(delta: float) -> void:
	_ground_age += delta
	var work_left: Variant = 32
	# Revisit at most eight earlier pending transactions, once each this pass.
	# Never delete a pickup while its inventory transaction is unresolved.
	var pending_visits: Variant = mini(8, _audit_expiry_pending.size() - _audit_expiry_pending_cursor)
	for _visit in range(pending_visits):
		var entry: Dictionary = _audit_expiry_pending[_audit_expiry_pending_cursor]
		_audit_expiry_pending_cursor += 1
		work_left -= 1
		var pickup: Object = entry.pickup.get_ref()
		if not is_instance_valid(pickup) or pickup.is_queued_for_retirement():
			continue
		if not _registered_pickups.has(pickup.runtime_actor_id()):
			continue
		if pickup.collection_pending():
			_audit_expiry_pending.append(entry)
		else:
			pickup.queue_free()
	# Birth deadlines stay sorted. Pending records leave this queue so one
	# slow/failed transaction cannot block every later expiration.
	for _step in range(work_left):
		if _expiry_cursor >= _expiry_queue.size():
			break
		var entry: Dictionary = _expiry_queue[_expiry_cursor]
		var pickup: Object = entry.pickup.get_ref()
		if is_instance_valid(pickup) and not pickup.is_queued_for_retirement():
			if float(entry.deadline) > _ground_age:
				break
			if _registered_pickups.has(pickup.runtime_actor_id()):
				if pickup.collection_pending():
					_audit_expiry_pending.append(entry)
				else:
					pickup.queue_free()
		_expiry_cursor += 1
	if _expiry_cursor == _expiry_queue.size():
		_expiry_queue.clear()
		_expiry_cursor = 0
	elif _expiry_cursor >= 1024:
		_expiry_queue = _expiry_queue.slice(_expiry_cursor)
		_expiry_cursor = 0
	if _audit_expiry_pending_cursor == _audit_expiry_pending.size():
		_audit_expiry_pending.clear()
		_audit_expiry_pending_cursor = 0
	elif _audit_expiry_pending_cursor >= 1024:
		_audit_expiry_pending = _audit_expiry_pending.slice(_audit_expiry_pending_cursor)
		_audit_expiry_pending_cursor = 0



func _run_collection_pass(delta_seconds: float) -> void:
	if not _player_ground_gu.is_finite():
		return
	_candidate_scratch.clear()
	_logout_blocked_pickup_ids.clear()
	_diagnostics.increment_performance_counter(&"loot_spatial_queries")
	_diagnostics.increment_performance_counter(
		&"loot_collection_spatial_queries"
	)
	_spatial_index.query_nearby_into(
		_runtime_map_id,
		_player_ground_gu,
		COLLECTION_RADIUS_GU,
		_candidate_scratch,
	)
	_diagnostics.increment_performance_counter(
		&"loot_spatial_candidates",
		_candidate_scratch.size(),
	)
	_diagnostics.increment_performance_counter(
		&"loot_collection_candidates",
		_candidate_scratch.size(),
	)
	_candidate_ids.clear()
	for raw_pickup: Variant in _candidate_scratch:
		if not raw_pickup is PickupModel or not is_instance_valid(raw_pickup):
			continue
		var pickup: Variant = raw_pickup
		var pickup_id: Variant = pickup.runtime_actor_id()
		_candidate_ids[pickup_id] = true
		_check_registered_pickup(
			pickup,
			_spatial_index.ground_position_for(pickup_id),
			delta_seconds,
		)
		if (
			not pickup.is_queued_for_retirement()
			and not pickup.collection_pending()
			and pickup.retry_cooldown_remaining() > 0.0
		):
			_logout_blocked_pickup_ids.append(pickup_id)
	for pickup_id: int in _previous_candidate_ids:
		if _candidate_ids.has(pickup_id):
			continue
		var raw_ref: Variant = _registered_pickups.get(pickup_id, null)
		var pickup: Variant = raw_ref.get_ref() if raw_ref is WeakRef else null
		if pickup is PickupModel and is_instance_valid(pickup):
			(pickup).manager_reset_attempt_context()
	_previous_candidate_ids.clear()
	for raw_pickup: Variant in _candidate_scratch:
		if raw_pickup is PickupModel and is_instance_valid(raw_pickup):
			_previous_candidate_ids.append((raw_pickup).runtime_actor_id())


func _check_registered_pickup(
	pickup: Object,
	pickup_ground_gu: Vector2,
	delta_seconds: float,
) -> void:
	if not is_instance_valid(pickup) or pickup.is_queued_for_retirement():
		return
	# Admission has already accepted this exact source. Its receipt owner
	# decides completion; movement passes must not repeat terrain queries.
	if pickup.collection_pending():
		return
	var in_range: Variant = (
		pickup_ground_gu.is_finite()
		and _player_ground_gu.distance_squared_to(pickup_ground_gu)
		< COLLECTION_RADIUS_GU * COLLECTION_RADIUS_GU
	)
	if in_range and collection_path_is_clear.is_valid():
		in_range = bool(collection_path_is_clear.call(pickup))
	manager_exact_range_check_count += 1
	_diagnostics.increment_performance_counter(
		&"loot_manager_exact_range_checks"
	)
	if pickup.retry_cooldown_remaining() > 0.0:
		manager_retry_check_count += 1
		_diagnostics.increment_performance_counter(
			&"loot_manager_retry_checks"
		)
	if pickup.manager_evaluate_collection(in_range, delta_seconds):
		manager_collection_request_count += 1
		_diagnostics.increment_performance_counter(
			&"loot_manager_collection_requests"
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
	if not _registered_pickups.has(pickup_id):
		return
	_spatial_index.unregister(pickup_id)
	_diagnostics.increment_performance_counter(&"loot_spatial_unregisters")
	_registered_pickups.erase(pickup_id)
	_registered_pickup_maps.erase(pickup_id)
	_previous_candidate_ids.erase(pickup_id)
	_logout_blocked_pickup_ids.erase(pickup_id)


func _pending_logout_candidate_count() -> int:
	var count: Variant = 0
	for raw_ref: Variant in _registered_pickups.values():
		if not raw_ref is WeakRef:
			continue
		var pickup: Variant = (raw_ref as WeakRef).get_ref()
		if pickup is PickupModel and is_instance_valid(pickup):
			if not (pickup).is_queued_for_retirement() and (pickup).collection_pending():
				count += 1
	return count


func _logout_retry_blocked_ids_snapshot() -> Array[int]:
	var result: Array[int] = _logout_blocked_pickup_ids.duplicate()
	for raw_ref: Variant in _registered_pickups.values():
		if not raw_ref is WeakRef:
			continue
		var pickup: Variant = (raw_ref as WeakRef).get_ref()
		if not pickup is PickupModel or not is_instance_valid(pickup):
			continue
		var pickup_object: Variant = pickup
		if (
			not pickup_object.is_queued_for_retirement()
			and not pickup_object.collection_pending()
			and pickup_object.retry_cooldown_remaining() > 0.0
		):
			var pickup_id: Variant = pickup_object.runtime_actor_id()
			if not result.has(pickup_id):
				result.append(pickup_id)
	return result
