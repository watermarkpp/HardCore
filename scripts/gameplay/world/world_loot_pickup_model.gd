extends RefCounted
## One owner-local pickup state. Main owns only its physical view.
signal collected(item_name: String, pickup: Object)
signal gold_collected(amount: int, pickup: Object)
signal collection_rejected(item_name: String, message: String)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const COLLECTION_RADIUS_GU := 0.75
const OVERWEIGHT_RETRY_COOLDOWN_SECONDS := 5.0
var _owner := OS.get_thread_caller_id()
var _world_ref: WeakRef
var _preferences: RefCounted
var _descriptors: RefCounted
var _content: RefCounted
var _diagnostics: RefCounted
var _runtime_id := 0
var item_name := "金币"
var item_id := -1
var item_record: Dictionary = {}
var gold_amount := 0
var target: Object
var global_position := Vector2.ZERO
var _filter_threshold := 0
var filtered := false
var _overweight_retry_remaining := 0.0
var _collection_pending := false
var _collection_authority_check_count := 0
var _collection_manager: Object
var _visual_descriptor: Dictionary = {}
var _initialized := false
var _view_retired := false

func _init(world: RefCounted, preferences: RefCounted, descriptors: RefCounted) -> void:
	assert(_owner != OS.get_main_thread_id())
	_world_ref = weakref(world)
	_preferences = preferences
	_descriptors = descriptors
	_content = world.owner_services.GameData
	_diagnostics = world.diagnostics
func _world() -> RefCounted:
	assert(OS.get_thread_caller_id() == _owner and _world_ref.get_ref() != null)
	return _world_ref.get_ref()
func owner_thread_id() -> int: return _owner
func bind_runtime_actor_id(value: int) -> bool:
	if _runtime_id != 0 or value <= 0 or OS.get_thread_caller_id() != _owner: return false
	_runtime_id = value
	return true
func runtime_actor_id() -> int: return _runtime_id
func is_queued_for_retirement() -> bool:
	return _world().actor_handle_for_model(self).is_queued_for_retirement()
func is_inside_world() -> bool:
	return _world().actor_handle_for_model(self).is_inside_world()
func queue_free() -> void: _world().queue_cast_retirement(self)
func write_meta(key: StringName, value: Variant) -> void:
	_world().actor_metadata_write(_world().actor_handle_for_model(self), key, value)
func read_meta(key: StringName, fallback: Variant = null) -> Variant:
	return _world().actor_metadata_read(_world().actor_handle_for_model(self), key, fallback)
func belongs_to_world(world: RefCounted) -> bool: return _world_ref.get_ref() == world
func close_effect() -> void:
	# Exact original cast-exit checkpoint; no fabricated ActorRef or life epoch.
	if _initialized and not _view_retired:
		if not _world().emit_original_main_event(&"retire_loot_view", [_runtime_id]):
			_world().fault("actual_loot_view_retirement_publication_failed", {"runtime_id":_runtime_id})
			return
		_view_retired=true
	if _preferences.filter_changed.is_connected(_apply_filter): _preferences.filter_changed.disconnect(_apply_filter)
	target = null
	_collection_manager = null
func ground_visual_descriptor(name: String) -> Dictionary: return _descriptors.ground_visual_descriptor(name)
func ground_visual_descriptor_for_record(value: Dictionary) -> Dictionary: return _descriptors.ground_visual_descriptor_for_record(value)
func initialize_gameplay() -> bool:
	if _initialized or _runtime_id <= 0: return false
	_world().enter_cast_group(self, &"loot_pickups")
	if _visual_descriptor.is_empty(): _visual_descriptor = ground_visual_descriptor(item_name)
	var visual: Dictionary = _descriptors.instance_visual_facts(item_record)
	var catalog: Dictionary = item_record.get("output_record", {})
	if gold_amount <= 0 and str(catalog.get("kind", "")) == "equipment" and not bool(visual.affix_highlighted):
		_filter_threshold = _preferences.filter_threshold_for_item(int(visual.item_id))
	_preferences.filter_changed.connect(_apply_filter)
	_apply_filter(_preferences.filter_level)
	_initialized = true
	return _world().emit_original_main_event(&"create_loot_view", [_runtime_id, item_name, item_record, gold_amount, global_position, _visual_descriptor, visual, filtered])
func _apply_filter(level: int) -> void:
	filtered = _filter_threshold > 0 and level >= _filter_threshold
	if not filtered: _overweight_retry_remaining = 0.0
	if _initialized: _world().emit_original_main_event(&"loot_filter", [_runtime_id, filtered])
func manager_visual_tick(delta_seconds: float) -> void:
	_world().emit_original_main_event(&"loot_visual_tick", [_runtime_id, delta_seconds])

func setup(label_text: String, player_target: Object) -> void:
	item_name = label_text
	item_id = -1
	item_record = {}
	gold_amount = 0
	target = player_target
	_visual_descriptor = ground_visual_descriptor(item_name)
	var catalog_record: Variant = _content.get_item_record(label_text)
	if (
		not catalog_record.is_empty()
		and str(catalog_record.get("name", "")) == label_text
	):
		item_id = _catalog_item_id(catalog_record)
		if item_id >= 0:
			item_record = {
				"item_id": item_id,
				"canonical_item_id": item_id,
				"canonical_name": label_text,
				"item_name": label_text,
				"name": label_text,
				"output_item_id": item_id,
				"output_record": catalog_record.duplicate(true),
				"identity_status": "catalog_compatibility",
			}

func setup_item_record(identity_record: Dictionary, player_target: Object) -> void:
	item_record = identity_record.duplicate(true)
	item_id = int(item_record.get(
		"item_id",
		item_record.get("canonical_item_id", -1),
	))
	item_name = str(item_record.get(
		"item_name",
		item_record.get("name", item_record.get("canonical_name", "")),
	))
	gold_amount = 0
	target = player_target
	_visual_descriptor = ground_visual_descriptor_for_record(item_record)

func setup_gold(amount: int, player_target: Object) -> void:
	item_name = "金币"
	item_id = -1
	item_record = {}
	gold_amount = maxi(1, amount)
	target = player_target
	_visual_descriptor = ground_visual_descriptor(item_name)

func _catalog_item_id(record: Dictionary) -> int:
	for key: String in ["item_id", "itemId", "stableItemId", "id"]:
		if not record.has(key):
			continue
		var value: Variant = record.get(key, -1)
		if value is String and not (value as String).is_valid_int():
			continue
		var parsed: Variant = int(value)
		if parsed >= 0:
			return parsed
	return -1

func set_collection_manager(manager: Object) -> void:
	_collection_manager = manager

func manager_evaluate_collection(in_range: bool, delta_seconds: float) -> bool:
	manager_advance_time(delta_seconds)
	if is_queued_for_retirement() or filtered:
		return false
	if not in_range:
		manager_reset_attempt_context()
		return false
	if (
		_collection_pending
		or _overweight_retry_remaining > 0.0
		or not is_instance_valid(target)
	):
		return false
	_collection_authority_check_count += 1
	_diagnostics.increment_performance_counter(
		&"loot_collection_authority_checks"
	)
	_collection_pending = true
	if gold_amount > 0:
		# Gold does not enter inventory: no weight / capacity gate.
		gold_collected.emit(gold_amount, self)
	else:
		collected.emit(item_name, self)
	return true

func manager_advance_time(delta_seconds: float) -> void:
	_overweight_retry_remaining = maxf(
		0.0,
		_overweight_retry_remaining - maxf(0.0, delta_seconds),
	)

func manager_reset_attempt_context() -> void:
	if not _collection_pending:
		# Leaving the pickup radius starts a fresh attempt context.
		_overweight_retry_remaining = 0.0

func _arm_collection_retry_cooldown() -> void:
	_overweight_retry_remaining = OVERWEIGHT_RETRY_COOLDOWN_SECONDS

func retry_cooldown_remaining() -> float:
	return _overweight_retry_remaining

func collection_pending() -> bool:
	return _collection_pending

func collection_authority_check_count() -> int:
	return _collection_authority_check_count

func confirm_collect() -> void:
	if not _collection_pending:
		return
	_collection_pending = false
	queue_free()

func reject_collection(message := "超过负重，无法拾取。") -> void:
	if not _collection_pending:
		return
	_collection_pending = false
	_arm_collection_retry_cooldown()
	collection_rejected.emit(item_name, message)

static func target_is_within_collection_range_screen_px(
	pickup_screen_position_px: Vector2,
	target_screen_position_px: Vector2
) -> bool:
	var target_delta_ground_gu: Variant = (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			target_screen_position_px - pickup_screen_position_px
		)
	)
	return (
		target_delta_ground_gu.length_squared()
		< COLLECTION_RADIUS_GU * COLLECTION_RADIUS_GU
	)
