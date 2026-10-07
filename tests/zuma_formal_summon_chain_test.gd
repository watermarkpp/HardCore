extends Node

## Formal producer/queue/materializer/cap/lifecycle regression. This uses main.tscn, the formal map publication path, GameRoot's
## real Boss signal receiver, M30 SummonQueue, and canonical materializer.

const FormalWorld := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const ZumaId := 160
const ZumaChildren := [156, 153, 150, 128]

var _game: Node
var _zuma: EnemyActor
var _signals: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await FormalWorld.wait_for_formal_world(self, _game, "zuma_formal_summon_chain")
	var player: PlayerCharacter = _game.player
	var published := await FormalWorld.publish_targets(self, _game, [{
		"id": ZumaId,
		"ground": FormalWorld.FIXTURE_GROUND_POSITION,
		"respawn": -1.0,
		"context": {"respawn_enabled": false, "spawn_slot_id": "test:formal:zuma:160"},
	}], "zuma_formal_summon_chain")
	assert(published.size() == 1, "formal Zuma target was not published")
	_zuma = published[0]
	assert(_zuma.monster_id == ZumaId and _zuma.is_boss, "formal target must be exact Zuma 160 Boss")
	assert(_zuma.max_hp == 3000, "canonical Zuma max HP must remain 3000")
	assert(_zuma.runtime_map_id == _game.current_map_id, "Boss map identity must be live")
	_game._set_player_world_position(_game._canonical_ground_gu_to_screen_px(
		FormalWorld.FIXTURE_GROUND_POSITION + Vector2(-1.5, 0.0)
	))
	_zuma.target = player
	_zuma.summon_requested.connect(_on_release)
	_zuma._rng.seed = 160
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	_zuma.set_physics_process(true)
	# One real source damage event leaves the formal 3000 HP Boss alive at 1 HP.
	# Subsequent waves are produced only by the real 8-second target-search
	# boundary; no stage cursor or combat clock is edited by the test.
	_zuma.take_damage(_zuma.max_hp - 1)
	var waves_deadline := Time.get_ticks_msec() + 37000
	while _signals.size() < 4 and Time.get_ticks_msec() < waves_deadline:
		await get_tree().process_frame
		var current_snapshot: Dictionary = _game.hc_m30_summon_snapshot()
		var source_slot := str(_zuma.get_meta("spawn_slot_id", ""))
		assert(_slot_children(source_slot, int(_game._zone_generation)).size() + int(current_snapshot.get("reserved_by_slot", {}).get(source_slot, 0)) <= 15)
	while int(_game.hc_m30_summon_snapshot().get("pending_batches", 0)) > 0 and Time.get_ticks_msec() < waves_deadline:
		await get_tree().process_frame
	assert(_signals.size() >= 4, "formal Boss did not produce four real 8-second search waves")
	var last_search_time := 0.0
	for release: Dictionary in _signals:
		assert(bool(release.has_target), "formal with-target clock case lost its live target")
		assert(float(release.action_time_s) - last_search_time + 0.000001 >= 8.0,
			"formal producer released a stage before its eight-second search boundary")
		last_search_time = float(release.action_time_s)
	assert(_signals.all(func(row: Dictionary) -> bool:
		return (int(row.count) >= 4 and int(row.count) <= 7
			and int(row.max_active) == 15
			and row.ids.all(func(raw: Variant) -> bool: return int(raw) in ZumaChildren))
	), "formal Boss release violated count/cap/child-ID authority")
	var snapshot: Dictionary = _game.hc_m30_summon_snapshot()
	print("ZUMA_QUEUE_FINAL_TRACE=", JSON.stringify({"signals":_signals,"snapshot":snapshot}))
	var slot := str(_zuma.get_meta("spawn_slot_id", ""))
	var live_children := _slot_children(slot, int(_game._zone_generation))
	var reserved := int(snapshot.get("reserved_by_slot", {}).get(slot, 0))
	assert(int(snapshot.get("pending_batches", 0)) == 0,
		"formal cap assertion requires the producer queue to settle pending batches")
	assert(live_children.size() == 15, "production SummonQueue must materialize exactly the Zuma cap15")
	assert(reserved == 0, "production SummonQueue must settle all reserved births")
	assert(live_children.size() + reserved <= 15, "production SummonQueue must enforce Zuma cap15")
	assert(int(_zuma.get_meta("m30_summon_release_serial", 0)) == _signals.size(),
		"one positive Boss release serial must correspond to each accepted signal")
	assert(live_children.all(func(child: EnemyActor) -> bool:
		return (not str(child.get_meta("summoner_spawn_slot", "")).is_empty()
			and int(child.monster_id) in ZumaChildren
			and child.runtime_map_id == _game.current_map_id)
	), "materialized children must retain producer context and stable IDs")
	assert(int(snapshot.get("requests", 0)) >= 4, "cap15 must include a further actual producer request")
	assert(int(snapshot.get("max_materializations_in_tick", 999)) <= 1)
	assert(int(snapshot.get("max_probes_in_tick", 999)) <= 8)
	print(JSON.stringify({"status":"PASS","waves":_signals,"snapshot":snapshot,"children":live_children.map(func(child): return {"id":child.monster_id,"instance_id":child.get_instance_id(),"slot":child.get_meta("summoner_spawn_slot"),"generation":child.get_meta("zone_generation")})}))
	# Retire the source through the real map transition and ensure no queued old
	# birth can materialize under a new zone generation.
	var old_generation := int(_game._zone_generation)
	var retire_map_id := 910003
	var retire_map_data: Dictionary = _game._runtime_named_map_data(GameData.get_map_by_id(retire_map_id))
	assert(int(retire_map_data.get("mapId", -1)) == retire_map_id,
		"formal retirement target must be an authored playable map")
	var transition := func() -> void:
		_game._load_zone(str(retire_map_data.get("name", "")), false, retire_map_data)
	assert(_game._begin_map_transition(transition, retire_map_id), "formal map transition must start")
	var transition_deadline := Time.get_ticks_msec() + 5000
	while _game._map_transition_in_progress and Time.get_ticks_msec() < transition_deadline:
		await get_tree().process_frame
	for _frame in range(20):
		await get_tree().process_frame
	assert(not _game._map_transition_in_progress and Time.get_ticks_msec() <= transition_deadline,
		"formal map transition must complete within its 5000ms fixture contract")
	assert(int(_game._zone_generation) != old_generation, "formal retirement did not advance generation")
	assert(_slot_children(slot, old_generation).is_empty(), "old source children survived retirement")
	assert(_slot_children(slot, int(_game._zone_generation)).is_empty(), "old source children leaked into new generation")
	print("ZUMA_FORMAL_SUMMON_CHAIN_PASS signals=%d children=%d" % [_signals.size(), _slot_children(slot, int(_game._zone_generation)).size()])
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _on_release(source: EnemyActor, ids: Array, count: int, max_active: int) -> void:
	assert(source == _zuma, "only formal Zuma source may release this chain")
	_signals.append({"ids": ids.duplicate(), "count": count, "max_active": max_active,
		"action_time_s": source._combat_action_time_s, "has_target": is_instance_valid(source.target),
		"queue_requests": int(_game.hc_m30_summon_snapshot().get("requests", 0)),
		"last_queued_release": source.get_meta("m30_last_queued_release", Vector2i(-1,-1)),
		"map_id": source.runtime_map_id, "generation": int(source.get_meta("zone_generation", -1)),
		"serial": int(source.get_meta("m30_summon_release_serial", 0))})

func _live_children() -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	for value: Variant in _game._active_enemy_cache.values():
		if value is EnemyActor and is_instance_valid(value) and value != _zuma:
			var child := value as EnemyActor
			if not str(child.get_meta("summoner_spawn_slot", "")).is_empty() and child.monster_id in ZumaChildren:
				result.append(child)
	return result

func _slot_children(slot: String, generation: int) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	for value: Variant in _game._active_enemy_cache.values():
		if value is EnemyActor and is_instance_valid(value):
			var child := value as EnemyActor
			if str(child.get_meta("summoner_spawn_slot", "")) == slot \
				and int(child.get_meta("zone_generation", -1)) == generation \
				and child.runtime_map_id == _game.current_map_id and child.current_hp > 0:
				result.append(child)
	return result
