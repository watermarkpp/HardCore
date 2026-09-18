extends Node2D


const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const MonsterUnitAdapterScript := preload("res://scripts/monster_unit_adapter.gd")

## Stable monsterIds carrying the authored static dormant contract. 154 is
## retired source-only and intentionally absent; 124 is the separate burrow
## ambush mechanic covered by its own scenario below.
const DORMANT_MONSTER_IDS: Array[int] = [153, 155, 156, 157, 158, 159, 160]
const BURROW_AMBUSH_MONSTER_ID := 124

## 10 GU is beyond every current dormant wake range (default 190px/32 =
## 5.9375 GU, authored boss wakeRange 64px/32 = 2.0 GU) and still inside the
## ordinary 12 GU * 1.5 leash envelope, so a damaged attacker stays retargetable
## without any proximity wake and without widening any range.
const RANGED_DAMAGE_DISTANCE_GU := 10.0

var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)

	await _test_birth_dormant_contract(player)
	await _test_damage_wake_beyond_wake_range(player)
	await _test_threat_retarget_survives_wake(player)
	await _test_zero_damage_never_wakes(player)
	await _test_lethal_damage_needs_no_wake(player)
	await _test_burrow_ambush_is_not_woken(player)

	player.queue_free()
	print("MONSTER_DORMANT_DAMAGE_WAKE_PASS checks=%d" % _checks)
	get_tree().quit(0)


## Scenario A: the fix must not remove the authored dormant profiles. Every
## runtime dormant monster still spawns asleep.
func _test_birth_dormant_contract(player: PlayerCharacter) -> void:
	for monster_id: int in DORMANT_MONSTER_IDS:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
		assert(
			enemy.monster_id == monster_id,
			"monster %d must resolve to its stable canonical identity" % monster_id,
		)
		assert(
			enemy.dormant,
			"monster %d must keep the authored dormant birth state" % monster_id,
		)
		_checks += 2
		enemy.free()
	_checks += 1


## Scenario B: a hit from a live attacker at 10 GU (outside every wake range,
## proven by the proximity contrast below) wakes the dormant actor immediately.
## The player never needs to walk into the wake range.
func _test_damage_wake_beyond_wake_range(player: PlayerCharacter) -> void:
	for monster_id: int in DORMANT_MONSTER_IDS:
		var enemy := await _make_dormant_enemy(monster_id, player)
		player.global_position = _ground_position_from_enemy(
			enemy,
			Vector2(RANGED_DAMAGE_DISTANCE_GU, 0.0),
		)
		assert(
			RANGED_DAMAGE_DISTANCE_GU > _wake_range_gu(enemy),
			"monster %d test distance must stay outside its authored wake range" % monster_id,
		)
		# Proximity contrast: at this distance the first-acquisition policy
		# still rejects the player, so only the damage path may wake the actor.
		enemy._retarget(0.0)
		assert(
			enemy.target == null,
			"monster %d must not proximity-acquire a 10 GU player" % monster_id,
		)
		enemy.target = null
		enemy._threat_table.clear()
		enemy._retarget_timer = 99.0
		var hp_before := enemy.current_hp
		enemy.take_damage(1, player, {})
		assert(
			enemy.current_hp == hp_before - 1,
			"monster %d must receive the actual HP damage" % monster_id,
		)
		assert(
			not enemy.dormant,
			"monster %d must wake from actual received damage" % monster_id,
		)
		assert(
			enemy._retarget_timer <= 0.0,
			"monster %d damage wake must trigger the next retarget decision" % monster_id,
		)
		assert(
			enemy._threat_for(player) > 0.0,
			"monster %d attacker must own threat before the retarget" % monster_id,
		)
		enemy._retarget(0.0)
		assert(
			enemy.target == player,
			"monster %d must fight back through the threat/retarget system" % monster_id,
		)
		_checks += 8
		enemy.queue_free()
		await get_tree().process_frame


## Scenario C: the wake must not hard-assign `target = attacker`. The existing
## threat/stability/retarget authority keeps deciding, in both directions.
func _test_threat_retarget_survives_wake(player: PlayerCharacter) -> void:
	for monster_id: int in DORMANT_MONSTER_IDS:
		var enemy := await _make_dormant_enemy(monster_id, player)
		player.global_position = _ground_position_from_enemy(
			enemy,
			Vector2(RANGED_DAMAGE_DISTANCE_GU, 0.0),
		)
		enemy.take_damage(1, player, {})
		assert(not enemy.dormant, "monster %d must wake before the retarget check" % monster_id)
		enemy._retarget(0.0)
		assert(enemy.target == player, "monster %d retarget must choose the attacker" % monster_id)

		# A second live combat target lands a much heavier hit. With the
		# authored 0.45 s stability window expired, the challenger threat must
		# win the retarget decision - a forced `target = attacker` lock inside
		# the wake path would have prevented exactly this switch.
		var alternate := Node2D.new()
		add_child(alternate)
		alternate.global_position = _ground_position_from_enemy(enemy, Vector2(1.0, 0.0))
		enemy.take_damage(40, alternate, {})
		# Force the next decision tick explicitly (boss retargeting stays
		# rate-limited while a target is held; the test drives the decision
		# instead of waiting out the authored cadence).
		enemy._target_stable_remaining_seconds = 0.0
		enemy._retarget_timer = 0.0
		enemy._retarget(0.0)
		assert(
			enemy.target == alternate,
			"monster %d must let the threat system switch to the heavier attacker" % monster_id,
		)

		# And the reverse: a weaker repeat hit must not steal the target back.
		enemy.take_damage(1, player, {})
		enemy._target_stable_remaining_seconds = 0.0
		enemy._retarget_timer = 0.0
		enemy._retarget(0.0)
		assert(
			enemy.target == alternate,
			"monster %d target stability must survive a weaker challenger" % monster_id,
		)
		_checks += 5
		alternate.queue_free()
		enemy.queue_free()
		await get_tree().process_frame


## Scenario D: zero actual damage must never wake a dormant actor.
func _test_zero_damage_never_wakes(player: PlayerCharacter) -> void:
	for monster_id: int in DORMANT_MONSTER_IDS:
		var enemy := await _make_dormant_enemy(monster_id, player)
		enemy.dormant = true
		enemy._retarget_timer = 99.0
		var hp_before := enemy.current_hp
		enemy.take_damage(0, player, {})
		assert(
			enemy.current_hp == hp_before,
			"monster %d zero damage must not change HP" % monster_id,
		)
		assert(
			enemy.dormant,
			"monster %d must stay dormant without actual received damage" % monster_id,
		)
		assert(
			enemy._retarget_timer == 99.0,
			"monster %d zero damage must not schedule a wake retarget" % monster_id,
		)
		_checks += 3
		enemy.queue_free()
		await get_tree().process_frame


## Scenario E: a lethal hit must flow straight into the normal death pipeline
## without entering the combat wake state first.
func _test_lethal_damage_needs_no_wake(player: PlayerCharacter) -> void:
	for monster_id: int in DORMANT_MONSTER_IDS:
		var enemy := await _make_dormant_enemy(monster_id, player)
		player.global_position = _ground_position_from_enemy(
			enemy,
			Vector2(RANGED_DAMAGE_DISTANCE_GU, 0.0),
		)
		enemy.take_damage(enemy.current_hp + 1000, player, {})
		assert(
			enemy.current_hp == 0,
			"monster %d lethal damage must reach zero HP" % monster_id,
		)
		assert(
			enemy.dormant,
			"monster %d must not enter the combat wake state on death" % monster_id,
		)
		assert(
			enemy._death_pending,
			"monster %d must enter the normal death pipeline" % monster_id,
		)
		assert(
			enemy.target == null,
			"monster %d death must not start a pursuit" % monster_id,
		)
		_checks += 4
		enemy.free()
		await get_tree().process_frame


## Scenario F: burrow ambush is a separate authored mechanic. Monster 124
## (触龙神) keeps `_burrowed` until its own emergeRange contract fires; generic
## received damage must never pull it out of the ground.
func _test_burrow_ambush_is_not_woken(player: PlayerCharacter) -> void:
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(BURROW_AMBUSH_MONSTER_ID), player, false)
	assert(
		enemy._burrowed,
		"monster 124 must keep the authored burrow ambush state",
	)
	assert(
		enemy.dormant,
		"monster 124 must spawn dormant inside its burrow ambush",
	)
	_checks += 2
	player.global_position = _ground_position_from_enemy(
		enemy,
		Vector2(RANGED_DAMAGE_DISTANCE_GU, 0.0),
	)
	var hp_before := enemy.current_hp
	enemy.take_damage(1, player, {})
	assert(
		enemy.current_hp == hp_before - 1,
		"monster 124 generic damage still lands on HP",
	)
	assert(
		enemy._burrowed,
		"monster 124 must stay burrowed through generic received damage",
	)
	assert(
		enemy.dormant,
		"monster 124 must stay dormant through generic received damage",
	)
	enemy._wake_dormant_from_received_damage(player, 1)
	assert(
		enemy._burrowed,
		"monster 124 wake helper must keep the burrow contract",
	)
	assert(
		enemy.dormant,
		"monster 124 wake helper must keep the dormant burrow state",
	)
	_checks += 5
	enemy.free()
	await get_tree().process_frame


func _make_dormant_enemy(monster_id: int, player: PlayerCharacter) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
	assert(enemy.dormant, "monster %d must spawn dormant" % monster_id)
	enemy.global_position = Vector2.ZERO
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().process_frame
	enemy.target = null
	enemy._threat_table.clear()
	return enemy


## Mirrors the production dormant wake-range read (the two-step behavior
## profile + stoneWake fallback) without changing any range value.
func _wake_range_gu(enemy: EnemyActor) -> float:
	var wake_range_gu := MonsterUnitAdapterScript.range_gu(
		enemy.behavior_profile,
		"wake_range_gu",
		"wakeRange",
		MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(190.0),
	)
	var stone_wake: Dictionary = enemy.boss_rule.get("mechanics", {}).get("stoneWake", {})
	return MonsterUnitAdapterScript.range_gu(
		stone_wake,
		"wake_range_gu",
		"wakeRange",
		wake_range_gu,
	)


func _ground_position_from_enemy(enemy: EnemyActor, delta_ground_gu: Vector2) -> Vector2:
	return enemy.global_position + (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(delta_ground_gu)
	)
