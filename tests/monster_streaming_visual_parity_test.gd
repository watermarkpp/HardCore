extends Node

## Q2-D visual/streaming parity: request order, resource selection, dedup and
## apply order must match the legacy per-instance poll semantics; failure
## states must match too.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Reference := preload(
	"res://tests/helpers/monster_visual_legacy_streaming_reference.gd"
)

var _coordinator
var _player: PlayerCharacter
var _enemies: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = Fixtures.make_coordinator()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(false)
	var catalog := Fixtures.catalog_ids()
	var monster_ids := [
		catalog[0], catalog[3], catalog[7], catalog[0],
		catalog[11], catalog[3], catalog[21], catalog[7],
	]
	for i: int in range(monster_ids.size()):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_player,
				monster_ids[i],
				i + 1
			)
		)
	await get_tree().process_frame
	# Expected plan: first-request order with dedup.
	var key_by_enemy: Array[String] = []
	for enemy: EnemyActor in _enemies:
		var mapping = enemy.visual._client_mapping_for(enemy.monster_data)
		key_by_enemy.append(enemy.visual._client_resource_cache_key(mapping))
	var expected: Dictionary = Reference.old_request_plan(
		key_by_enemy,
		key_by_enemy
	)
	var actual_order: Array = _coordinator.request_order()
	assert(
		actual_order.size() == (expected.get("request_order", []) as Array).size(),
		"request order size mismatch"
	)
	for i: int in range(actual_order.size()):
		assert(
			str(actual_order[i])
			== str((expected.get("request_order", []) as Array)[i]),
			"request order mismatch at %d" % i
		)
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		int(diag.get("unique_request_count", 0))
		== int(expected.get("unique_request_count", 0)),
		"unique request count mismatch"
	)
	assert(
		int(diag.get("duplicate_request_count", 0))
		== int(expected.get("duplicate_request_count", 0)),
		"duplicate request count mismatch"
	)
	# Complete every request through the coordinator poll.
	var deadline := Time.get_ticks_msec() + 20000
	while (
		_coordinator.pending_request_count() > 0
		and Time.get_ticks_msec() < deadline
	):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	var apply_order: Array = _coordinator.apply_order()
	var expected_apply: Array = expected.get("apply_order", [])
	assert(
		apply_order.size() == expected_apply.size(),
		"apply order size mismatch"
	)
	for i: int in range(apply_order.size()):
		assert(
			str(apply_order[i]) == str(expected_apply[i]),
			"apply order mismatch at %d" % i
		)
	# Resource selection parity: every visual with a client mapping must end
	# with the classic client WIL profile.
	var applied := 0
	for enemy: EnemyActor in _enemies:
		if not is_instance_valid(enemy):
			continue
		Fixtures.drive_residency_activation(enemy.visual)
		if (
			not enemy.visual.active_resources.is_empty()
			and str(enemy.visual.active_resources.get("animation_source", ""))
				== "classic_client_wil"
		):
			applied += 1
	assert(
		applied == _enemies.size(),
		"every visual must select the classic client WIL resource"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"MONSTER_STREAMING_VISUAL_PARITY_PASS unique=%d duplicates=%d applied=%d"
		% [
			int(diag.get("unique_request_count", 0)),
			int(diag.get("duplicate_request_count", 0)),
			applied,
		]
	)
	get_tree().quit(0)


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
