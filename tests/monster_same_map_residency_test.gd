extends Node

## MonsterVisual residency regression:
##
## A same-map Home/revival transition must not advance the visual-streaming
## generation when the world is intentionally preserved.  This test keeps the
## old coordinator path as a negative control, then exercises the GameRoot
## helper through both the legacy Home alias and the actual death/revival UI
## entry point.  A real cross-map transition remains a generation fence.

const MainScene := preload("res://scenes/main.tscn")
const Fixtures := preload("res://tests/helpers/monster_streaming_test_fixtures.gd")

const LOADING_CONTRACT_ID := "ui.loading.transition.v1"
const BICH_RUNTIME_MAP_ID := 910001
# 217/4 are reference-only source maps and are correctly rejected by the
# formal projection gate.  910002 is a distinct implemented runtime map for
# the cross-generation fence half of this regression.
const CROSS_MAP_ID := 910002
const FORMAL_SAMPLE_IDS := [24, 26]
const WORLD_READY_TIMEOUT_MSEC := 30000
const TRANSITION_TIMEOUT_MSEC := 60000

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.set_synchronous_loading_for_tests(true)
	await _run_stale_generation_negative_control()
	MonsterVisual.reset_client_resource_cache()
	MonsterVisual.set_streaming_coordinator(null)

	# Fresh production-equivalent world. The initial bootstrap remains test-mode
	# deterministic; only the subsequent transitions use the production path so
	# the monster prefetch helper is actually exercised.
	PlayerState.reset_progress()
	PlayerState.test_mode = true
	_game = MainScene.instantiate()
	add_child(_game)
	await _wait_for_world_ready(_game)
	_game._monster_prefetch_enabled = true
	var selected := _select_formal_samples(_game)
	assert(selected.size() == FORMAL_SAMPLE_IDS.size(), "fresh formal sample actors missing")
	for enemy: EnemyActor in selected:
		_prepare_active_sample(enemy)
	var coordinator = _game._streaming_coordinator
	var generation_before := int(coordinator.current_world_generation())
	var keys_before := _sample_keys(selected)
	var ids_before := _sample_instance_ids(selected)

	# Public legacy "比奇城" route resolves to runtime 910001 and preserves the
	# same map. This checks the service-map/runtime-map alias at the real entry.
	await _run_production_same_map_transition(
		func() -> void:
			_game.change_zone("比奇城")
	)
	assert(
		int(coordinator.current_world_generation()) == generation_before,
		"legacy Home alias changed streaming generation on a preserved world",
	)
	_assert_samples_preserved(selected, coordinator, keys_before, ids_before)
	for enemy: EnemyActor in selected:
		_force_release_and_reentry(enemy)
		assert(
			not enemy.visual.active_resources.is_empty()
			and enemy.visual.uses_final_art(),
		"same-map legacy Home alias failed visual reactivation for monsterId=%d"
			% enemy.monster_id,
		)

	# Actual death UI entry: this is the device path that previously fenced the
	# living Bich actors and left overhead labels without body art.
	PlayerState.test_mode = false
	var death_ids := _sample_instance_ids(selected)
	var death_keys := _sample_keys(selected)
	_game.player._dead = true
	_game.player.current_hp = 0
	_game._on_player_death_requested()
	assert(_game.hud.death_revival_panel.visible, "death UI did not open")
	_game.hud.death_revival_panel.town_button.pressed.emit()
	assert(_game._map_transition_in_progress, "town revival did not start transition")
	_cover_active_transition(_game)
	await _wait_for_transition(_game)
	assert(
		int(_game.current_map_id) == BICH_RUNTIME_MAP_ID,
		"same-map revival left formal Bich runtime map",
	)
	assert(
		not _game.player._dead and _game.player.current_hp == _game.player.max_hp,
		"same-map revival did not complete player state",
	)
	assert(
		int(coordinator.current_world_generation()) == generation_before,
		"same-map death/revival advanced streaming generation",
	)
	_assert_samples_preserved(selected, coordinator, death_keys, death_ids)
	for enemy: EnemyActor in selected:
		_force_release_and_reentry(enemy)
		assert(
			not enemy.visual.active_resources.is_empty()
			and enemy.visual.uses_final_art(),
		"same-map revival failed visual reactivation for monsterId=%d" % enemy.monster_id,
		)

	# A genuine map change still fences the old generation and queues the old
	# zone actors. Keep this assertion after both preserved-world routes so the
	# helper cannot solve same-map revival by weakening cross-map teardown.
	var cross_generation_before := int(coordinator.current_world_generation())
	var cross_ids := _sample_instance_ids(selected)
	var cross_keys := _sample_keys(selected)
	await _run_production_cross_map_transition(CROSS_MAP_ID)
	assert(
		int(coordinator.current_world_generation()) > cross_generation_before,
		"cross-map transition did not advance streaming generation",
	)
	for index in range(selected.size()):
		assert(
			not coordinator.visual_subscription_is_current(
				cross_ids[index], cross_keys[index]
			),
		"cross-map transition retained old visual subscription",
		)
		assert(
			not is_instance_valid(selected[index])
			or selected[index].is_queued_for_deletion(),
			"cross-map transition retained old EnemyActor",
		)
	var other_same_map_generation := int(coordinator.current_world_generation())
	var preserved_status: Dictionary = _game._begin_monster_transition_prefetch(CROSS_MAP_ID)
	assert(
		bool(preserved_status.get("complete", false))
		and bool(preserved_status.get("preserved_world", false)),
		"implemented non-Bich same-map helper did not preserve world: %s"
		% preserved_status,
	)
	assert(
		int(coordinator.current_world_generation()) == other_same_map_generation,
		"implemented non-Bich same-map helper advanced streaming generation",
	)

	_game.queue_free()
	_game = null
	await get_tree().process_frame
	MonsterVisual.set_streaming_coordinator(null)
	MonsterVisual.reset_client_resource_cache()
	PlayerState.test_mode = previous_test_mode
	print(
		"MONSTER_SAME_MAP_RESIDENCY_PASS "
		+ "negative_stale_fence=true same_map_alias=true death_revival=true "
		+ "cross_map_fence=true ids=24,26"
	)
	get_tree().quit(0)


func _run_stale_generation_negative_control() -> void:
	var coordinator = Fixtures.make_coordinator()
	var player := Fixtures.make_player(self)
	var enemies: Array[EnemyActor] = []
	for index in range(FORMAL_SAMPLE_IDS.size()):
		enemies.append(
			Fixtures.make_enemy(
				self,
				player,
				int(FORMAL_SAMPLE_IDS[index]),
				index + 1,
				BICH_RUNTIME_MAP_ID,
				Vector2(80.0 + index * 96.0, 120.0),
			)
		)
	await get_tree().process_frame
	for enemy: EnemyActor in enemies:
		_prepare_active_sample(enemy)
		assert(
			not enemy.visual.active_resources.is_empty()
			and enemy.visual.uses_final_art(),
			"negative-control formal art did not activate for monsterId=%d" % enemy.monster_id,
		)
	var keys := _sample_keys(enemies)
	var ids := _sample_instance_ids(enemies)
	var generation_before := int(coordinator.current_world_generation())
	coordinator.begin_map_prefetch(FORMAL_SAMPLE_IDS)
	assert(int(coordinator.current_world_generation()) > generation_before)
	for index in range(enemies.size()):
		_force_release_and_reentry(enemies[index])
		assert(
			enemies[index].visual.active_resources.is_empty(),
			"negative control did not reproduce stale subscription blank body",
		)
		assert(
			not coordinator.visual_subscription_is_current(ids[index], keys[index]),
			"negative control visual unexpectedly remained subscribed",
		)
	for enemy: EnemyActor in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame


func _select_formal_samples(game: Node) -> Array[EnemyActor]:
	var found: Dictionary = {}
	for value: Variant in game.get_tree().get_nodes_in_group("enemies"):
		if not value is EnemyActor or not is_instance_valid(value):
			continue
		var enemy := value as EnemyActor
		if int(enemy.monster_id) in FORMAL_SAMPLE_IDS and not found.has(enemy.monster_id):
			found[enemy.monster_id] = enemy
	var result: Array[EnemyActor] = []
	for monster_id: int in FORMAL_SAMPLE_IDS:
		if found.has(monster_id):
			result.append(found[monster_id] as EnemyActor)
	return result


func _prepare_active_sample(enemy: EnemyActor) -> void:
	enemy.set_physics_process(false)
	enemy.set_process(false)
	if is_instance_valid(enemy.primary_target):
		enemy.global_position = enemy.primary_target.global_position
	else:
		var viewport := enemy.get_viewport()
		if viewport != null:
			enemy.global_position = viewport.get_visible_rect().get_center()
	if enemy.visual.active_resources.is_empty():
		enemy.visual._resource_residency_timer = 0.0
		enemy.visual._process(0.13)
	if enemy.visual.active_resources.is_empty():
		enemy.visual._activate_resources()
	assert(
		not enemy.visual.active_resources.is_empty()
		and enemy.visual.uses_final_art(),
		"formal sample failed to activate for monsterId=%d" % enemy.monster_id,
	)


func _force_release_and_reentry(enemy: EnemyActor) -> void:
	assert(is_instance_valid(enemy) and is_instance_valid(enemy.visual))
	var anchor := (
		enemy.primary_target.global_position
		if is_instance_valid(enemy.primary_target)
		else enemy.global_position
	)
	enemy.global_position = anchor + Vector2(5000.0, 5000.0)
	enemy.visual._resource_residency_timer = 0.0
	enemy.visual.streaming_residency_poll(Time.get_ticks_msec())
	assert(
		enemy.visual.active_resources.is_empty(),
		"sample did not release resources outside viewport guard",
	)
	enemy.global_position = anchor
	enemy.visual._resource_residency_timer = 0.0
	enemy.visual.streaming_residency_poll(Time.get_ticks_msec())


func _assert_samples_preserved(
	enemies: Array[EnemyActor],
	coordinator,
	keys: Array[String],
	ids: Array[int],
) -> void:
	for index in range(enemies.size()):
		var enemy := enemies[index]
		assert(is_instance_valid(enemy) and not enemy.is_queued_for_deletion())
		assert(
			coordinator.visual_subscription_is_current(ids[index], keys[index]),
			"same-map route lost visual subscription for monsterId=%d" % enemy.monster_id,
		)
		assert(
			not enemy.visual.active_resources.is_empty()
			and enemy.visual.uses_final_art(),
			"same-map route lost active formal art for monsterId=%d" % enemy.monster_id,
		)


func _sample_keys(enemies: Array[EnemyActor]) -> Array[String]:
	var result: Array[String] = []
	for enemy: EnemyActor in enemies:
		var mapping := enemy.visual._client_mapping_for(enemy.monster_data)
		result.append(enemy.visual._client_resource_cache_key(mapping))
	return result


func _sample_instance_ids(enemies: Array[EnemyActor]) -> Array[int]:
	var result: Array[int] = []
	for enemy: EnemyActor in enemies:
		result.append(enemy.visual.get_instance_id())
	return result


func _run_production_same_map_transition(operation: Callable) -> void:
	PlayerState.test_mode = false
	operation.call()
	assert(_game._map_transition_in_progress, "same-map production transition was not accepted")
	_cover_active_transition(_game)
	await _wait_for_transition(_game)
	assert(not _game._map_transition_in_progress)


func _run_production_cross_map_transition(map_id: int) -> void:
	PlayerState.test_mode = false
	var accepted: bool = _game._request_map_travel(map_id)
	assert(
		accepted,
		"cross-map production request rejected map=%d current=%d input=%s projection=%s"
		% [
			map_id,
			int(_game.current_map_id),
			_game.gameplay_input_gate_snapshot(),
			_game._resolve_projection_profile_for_map(map_id),
		],
	)
	assert(_game._map_transition_in_progress, "cross-map production transition was not accepted")
	_cover_active_transition(_game)
	await _wait_for_transition(_game)
	assert(int(_game.current_map_id) == map_id, "cross-map arrival mismatch")


func _cover_active_transition(game: Node) -> void:
	game.hud.loading_transition_covered.emit({
		"contract_id": LOADING_CONTRACT_ID,
		"transition_id": game._active_map_transition_id,
	})


func _wait_until_ready(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + WORLD_READY_TIMEOUT_MSEC
	while (
		(bool(game._world_bootstrap_in_progress) or bool(game._map_transition_in_progress))
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame
	assert(
		not bool(game._world_bootstrap_in_progress)
		and not bool(game._map_transition_in_progress),
		"world bootstrap did not reach READY",
	)


func _wait_for_world_ready(game: Node) -> void:
	await _wait_until_ready(game)
	assert(
		game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.READY,
		"world bootstrap stage is not READY",
	)


func _wait_for_transition(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + TRANSITION_TIMEOUT_MSEC
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(not game._map_transition_in_progress, "map transition did not reach READY")


func _ground_to_screen(value: Vector2) -> Vector2:
	return value
