extends "res://tests/canonical_skill_production_entry_test.gd"

## Formal field controller / GameRoot / CombatRuntime / canonical ID160 HP regression.

const GroundEffectScript := preload("res://scripts/ground_effect.gd")
const FormalWorldSkillFixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")

const ZUMA_ID := 160
const SKILL_ID := "wizard.fire_wall"
const FIXTURE_GROUND := Vector2(40.5, 13.5)
var _fixture_mc := 40 # Test fixture input, not a user MC claim.
const RANK5_MORE_MULTIPLIER := 1.21
const FIXED_ZUMA_MAC := 20
var _expected_rank3_raw := 46
var _expected_rank5_raw := 56

var _game: Node
var _zuma: EnemyActor
var _owners: Array[FireWallFieldController] = []
var _summon_requests: Array[Dictionary] = []
var _tick_receipts: Array[Dictionary] = []
var _observing := false
var _seen_damage_applications := 0
var _last_hp := 0
var _last_physics_tick := -1
func _fixture_magic_attack() -> int:
	return 40


func _run() -> void:
	_fixture_mc = _fixture_magic_attack()
	assert(_fixture_mc in [40, 47], "field fixture must use an explicit audited MC boundary")
	_expected_rank3_raw = 46 if _fixture_mc == 40 else 53
	_expected_rank5_raw = 56 if _fixture_mc == 40 else 64
	process_physics_priority = 10000
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "法师"
	# This is an explicit formal rank5 fixture. It is not a claim about the
	# player's saved proficiency or device MC.
	PlayerState.learned_skills = {"火墙": 3}
	PlayerState.add_item("木剑")
	var weapon_index := -1
	for item_index: int in PlayerState.inventory.size():
		if str(PlayerState.inventory[item_index].get("name", "")) == "木剑":
			weapon_index = item_index
			break
	assert(weapon_index >= 0)
	PlayerState.inventory[weapon_index]["modifiers"] = [{"stat": "skill_level", "scope": "skill:wizard.fire_wall", "value": 2}]
	assert(PlayerState.equip_inventory_index(weapon_index).begins_with("已装备"))
	PlayerState.recalculate_stats()
	assert(PlayerState.effective_skill_level("火墙") == 5)
	GroundEffectScript.reset_runtime_tick_claims_for_tests()

	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	var published: Array[EnemyActor] = await FormalWorldSkillFixture.publish_targets(
		self,
		_game,
		[{
			"id": ZUMA_ID,
			"ground": FIXTURE_GROUND,
			"respawn": -1.0,
			"context": {
				"respawn_enabled": false,
				"spawn_slot_id": "test:formal_skill:zuma_rank5_firewall:160",
			},
		}],
		"zuma rank5 firewall production",
	)
	assert(published.size() == 1)
	_zuma = published[0]
	assert(_zuma.monster_id == ZUMA_ID and _zuma.is_boss)
	assert(_zuma.max_hp == 3000 and _zuma.current_hp == 3000)
	assert(_zuma.magic_defense == FIXED_ZUMA_MAC)
	assert(_zuma.direct_spell_magic_defense_min == FIXED_ZUMA_MAC)
	assert(_zuma.direct_spell_magic_defense_max == FIXED_ZUMA_MAC)
	# Freeze only the Boss actor's own AI physics. GameRoot, field controllers,
	# spatial queries, CombatRuntimeService and the formal callback remain live.
	_zuma.set_physics_process(false)
	_zuma.summon_requested.connect(_on_zuma_summon_requested)
	_clear_ambient_targets()
	_game._set_player_world_position(
		_game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND + Vector2(-2.0, 0.0))
	)
	# Freeze an explicit MC40/40 fixture through the same stat snapshot consumed
	# by the canonical planner; extra context cannot override formal MC.
	PlayerState.computed_stats["magic_min"] = _fixture_mc
	PlayerState.computed_stats["magic_max"] = _fixture_mc
	_game.player.current_mp = 100000
	_game._skill_cast_target = _zuma

	var center := Vector2i(FIXTURE_GROUND.floor())
	var first := _cast_rank5_field(center, "first")
	assert(first != null)
	assert(first.tick_interval == 1.0)
	assert(first.raw_power == _expected_rank5_raw)
	assert(_owners.size() == 1)

	# Same caster + same tile must refresh the existing owner, not create one.
	var same_tile := _cast_rank5_field(center, "same_tile")
	assert(same_tile == first)
	assert(first.refresh_count == 1)
	assert(_owners.size() == 1)

	# Different centers overlap the same real Boss. The global claim remains
	# caster:skill:target, so two controllers cannot damage the target twice in
	# one tick. The target must remain in both formal 3x3 snapshots.
	var second := _cast_rank5_field(center + Vector2i(1, 0), "different_center")
	assert(second != null and second != first)
	assert(_owners.size() == 2)
	assert(_zuma.current_hp == 3000)
	var summon_count_before := _summon_requests.size()

	await _observe_three_real_ticks()
	assert(_tick_receipts.size() >= 3)
	assert(_summon_requests.size() == summon_count_before,
		"FireWall callback must not synchronously emit Boss summon_requested")
	for receipt: Dictionary in _tick_receipts:
		assert(int(receipt.get("mac_min", -1)) == FIXED_ZUMA_MAC)
		assert(int(receipt.get("mac_max", -1)) == FIXED_ZUMA_MAC)
		assert(int(receipt.get("raw_power", -1)) == _expected_rank5_raw)
		assert(int(receipt.get("hp_delta", -1)) == _expected_rank5_raw - FIXED_ZUMA_MAC)
		assert(int(receipt.get("summon_request_count", -1)) == summon_count_before)
	# Same caster/twin-controller overlap is one accepted claim per target per
	# tick. Do not assert per-controller damage; inspect aggregate target HP and
	# aggregate application counts instead.
	assert(_zuma.current_hp == 3000 - _tick_receipts.size() * (_expected_rank5_raw - FIXED_ZUMA_MAC))

	print(JSON.stringify({
		"status": "PASS",
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"fixture_mc_min": _fixture_mc,
		"fixture_mc_max": _fixture_mc,
		"target_id": ZUMA_ID,
		"target_instance_id": _zuma.get_instance_id(),
		"caster_instance_id": _game.player.get_instance_id(),
		"field_ids": _owners.map(func(owner): return owner.get_instance_id()),
		"release_ids": _owners.map(func(owner): return owner._release_id),
		"rank": 5,
		"rank3_raw": _expected_rank3_raw,
		"rank5_raw": _expected_rank5_raw,
		"rank5_multiplier": RANK5_MORE_MULTIPLIER,
		"mac": FIXED_ZUMA_MAC,
		"tick_ms": 1000,
		"tick_receipts": _tick_receipts,
		"summon_requests": _summon_requests,
	}))
	print("ZUMA_RANK5_FIREWALL_PRODUCTION_PASS")
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _cast_rank5_field(center: Vector2i, label: String) -> FireWallFieldController:
	_game._skill_cast_target = _zuma
	var cast: Dictionary = _game._execute_canonical_skill(
		SKILL_ID,
		_game.player.global_position,
		Vector2.RIGHT,
		0,
		{"target_tile": center},
	)
	assert(bool(cast.get("accepted", false)), "%s cast rejected: %s" % [label, cast])
	var effective_rank := int(cast.get(
		"effective_skill_rank",
		cast.get("canonical_plan", {}).get("effective_rank", -1),
	))
	assert(effective_rank == 5,
		"%s did not enter formal rank5 path: %s" % [label, cast])
	var plan: Dictionary = cast.get("canonical_plan", {})
	var actions: Array = plan.get("gameplay_actions", [])
	assert(actions.size() == 1 and actions[0] is Dictionary)
	var effect: Dictionary = actions[0]
	assert(int(effect.get("tick_interval_ms", -1)) == 1000)
	assert(int(effect.get("raw_power_rank3", -1)) == _expected_rank3_raw)
	assert(int(effect.get("raw_power", -1)) == _expected_rank5_raw)
	assert(int(effect.get("raw_power", -1)) == roundi(float(effect.get("raw_power_rank3", -1)) * RANK5_MORE_MULTIPLIER))
	var ids: Array = cast.get("execution_result", {}).get("spawned_ground_effect_ids", [])
	assert(ids.size() == 1, "%s must expose one field owner: %s" % [label, ids])
	var owner := instance_from_id(int(ids[0])) as FireWallFieldController
	assert(owner != null and owner.source_actor == _game.player)
	assert(owner.raw_power == _expected_rank5_raw)
	if owner not in _owners:
		_owners.append(owner)
	return owner


func _observe_three_real_ticks() -> void:
	var deadline := Time.get_ticks_msec() + 7000
	_seen_damage_applications = 0
	_last_hp = _zuma.current_hp
	_last_physics_tick = -1
	_observing = true
	while _tick_receipts.size() < 3 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_observing = false
	assert(_tick_receipts.size() >= 3,
		"real physics FireWall field did not produce three ticks before timeout")


func _physics_process(_delta: float) -> void:
	if not _observing:
		return
	# Observe after every controller physics callback. Process-frame observation
	# can run after several catch-up ticks and cannot identify the actual tick.
	var aggregate_apps := 0
	var aggregate_claims := 0
	for owner: FireWallFieldController in _owners:
		aggregate_apps += owner.damage_application_count
		aggregate_claims += owner.claim_success_count
	if aggregate_apps <= _seen_damage_applications:
		return
	assert(aggregate_apps == _seen_damage_applications + 1,
		"same-caster overlapping controllers applied twice in one claim window")
	assert(_zuma.current_hp < _last_hp)
	var physics_tick := Engine.get_physics_frames()
	if _last_physics_tick >= 0:
		assert(physics_tick - _last_physics_tick >= 60,
			"FireWall applications were less than one 60Hz physics second apart")
	for owner: FireWallFieldController in _owners:
		for candidate: Variant in owner._target_node_scratch:
			assert(candidate == _zuma,
				"formal fixture isolation failed: non-Boss target entered FireWall coverage")
	var hp_after := _zuma.current_hp
	_tick_receipts.append({
		"timestamp_msec": Time.get_ticks_msec(),
		"physics_tick": physics_tick,
		"physics_tick_gap": physics_tick - _last_physics_tick if _last_physics_tick >= 0 else -1,
		"hp_before": _last_hp,
		"hp_after": hp_after,
		"hp_delta": _last_hp - hp_after,
		"actual_raw_power": _owners[0].raw_power,
		"field_ids": _owners.map(func(owner): return owner.get_instance_id()),
		"release_ids": _owners.map(func(owner): return owner._release_id),
		"caster_instance_id": _game.player.get_instance_id(),
		"target_instance_id": _zuma.get_instance_id(),
		"claim_key": "%d:%s:%d" % [_game.player.get_instance_id(), SKILL_ID, _zuma.get_instance_id()],
		"raw_power": _expected_rank5_raw,
		"mac_min": _zuma.direct_spell_magic_defense_min,
		"mac_max": _zuma.direct_spell_magic_defense_max,
		"claim_success_count": aggregate_claims,
		"damage_application_count": aggregate_apps,
		"summon_request_count": _summon_requests.size(),
	})
	_seen_damage_applications = aggregate_apps
	_last_hp = hp_after
	_last_physics_tick = physics_tick

func _on_zuma_summon_requested(
	_enemy: EnemyActor,
	monster_ids: Array,
	count: int,
	max_active: int,
) -> void:
	_summon_requests.append({
		"timestamp_msec": Time.get_ticks_msec(),
		"monster_ids": monster_ids.duplicate(),
		"count": count,
		"max_active": max_active,
	})


func _clear_ambient_targets() -> void:
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and value != _zuma:
			(value as EnemyActor).set_combat_position(
				_game.player.global_position + Vector2(3000.0, 3000.0),
				&"formal_firewall_isolation")
