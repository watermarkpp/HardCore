extends Node2D

## R1 monster struck runtime: attack-deadline semantics (negative allowed),
## committed attacks survive ordinary struck, ordinary struck never touches
## the walk cadence, direct magic postpones the walk tick (Lv<50), MAC-zero
## still postpones, anti-magic evasion postpones nothing, fire wall
## (MAGSTRUCK_MINE) never postpones, Lv50 immune to the walk delay, and
## poison ticks damage HP only.

const CombatRuntimeServiceScript := preload(
	"res://scripts/layers/runtime/combat_runtime_service.gd"
)
const MonsterStruckPolicy := preload("res://scripts/monster_struck_policy.gd")
const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")

var _checks := 0
var _combat_runtime: Node


class StruckVisualFixture:
	extends MonsterVisual
	func _ready() -> void:
		set_process(false)


class RuntimeEnemyFixture:
	extends EnemyActor
	func _ready() -> void:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		_initialize_spawn_facing_once()


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	assert(condition, "MONSTER_STRUCK_RUNTIME: " + label)
	_checks += 1


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true)
	_combat_runtime = CombatRuntimeServiceScript.new()
	add_child(_combat_runtime)
	_test_attack_deadline_allows_negative()
	await _test_committed_attack_survives_struck()
	await _test_ordinary_struck_keeps_walk_cadence()
	await _test_direct_magic_walk_delay()
	await _test_direct_magic_zero_damage_boundary()
	await _test_anti_magic_full_evasion()
	await _test_fire_wall_is_mine()
	await _test_fire_wall_pack_never_walk_locked()
	await _test_level_fifty_white_boar()
	await _test_poison_is_hp_only()
	print("MONSTER_STRUCK_RUNTIME_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _ground_to_screen_px(value: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(value)


func _make_enemy(monster_id: int, monster_level: int) -> EnemyActor:
	var enemy := RuntimeEnemyFixture.new()
	enemy.setup(GameData.get_monster_by_id(monster_id), null, false)
	enemy.environment_blocker = null
	enemy.set_physics_process(false)
	enemy.level = monster_level
	# Padding HP keeps every struck scenario non-lethal so the assertions
	# observe struck semantics instead of the death path.
	enemy.max_hp = 500
	enemy.current_hp = 500
	# The identity-projection fallback pair used by the melee-chain e2e test,
	# so committed-attack release snapshots resolve in a consistent context.
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen_px"),
		GroundUnitSpace.screen_delta_px_to_ground_delta_gu
	)
	add_child(enemy)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	var visual := StruckVisualFixture.new()
	visual.setup(enemy)
	enemy.visual = visual
	enemy.add_child(visual)
	return enemy


func _make_player() -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.set_physics_process(false)
	add_child(player)
	player.max_hp = 500
	player.current_hp = 500
	player.defense_min = 0
	player.defense_max = 0
	return player


## Section 34: the deadline must keep "already overdue" information.
func _test_attack_deadline_allows_negative() -> void:
	var enemy := await _make_enemy(18, 43)
	var delay := float(MonsterStruckPolicy.attack_delay_ms(43)) / 1000.0
	_check(is_equal_approx(delay, 0.02), "Lv43 struck penalty is 20ms")

	enemy._attack_timer = 0.5
	enemy._apply_source_struck_attack_delay()
	_check(is_equal_approx(enemy._attack_timer, 0.52), "Case A: 0.500 + 0.020 = 0.520")

	enemy._attack_timer = -0.05
	enemy._apply_source_struck_attack_delay()
	_check(is_equal_approx(enemy._attack_timer, -0.03), "Case B: overdue stays overdue")
	_check(enemy._attack_timer <= 0.0, "Case B: attack still ready")

	enemy._attack_timer = -0.01
	enemy._apply_source_struck_attack_delay()
	_check(is_equal_approx(enemy._attack_timer, 0.01), "Case C: -0.010 + 0.020 = +0.010")
	_check(enemy._attack_timer > 0.0, "Case C: 10ms of genuine wait appears")
	enemy.free()


## Section 35: a committed attack settles exactly once; the struck only
## shifts the NEXT deadline.
func _test_committed_attack_survives_struck() -> void:
	var player := _make_player()
	var enemy := await _make_enemy(18, 43)
	enemy._pending_attack_time = 0.2
	enemy._pending_attack_target = player
	enemy._pending_attack_damage = 5
	enemy._pending_attack_release_record = {
		"kind": "generic_melee",
		"target_instance_id": player.get_instance_id(),
		"target_combat_epoch": enemy._typed_player_combat_epoch(player),
	}
	var deadline_before := enemy._attack_timer
	enemy.take_damage(10, player)
	_check(enemy._pending_attack_time > 0.0, "committed attack is not cancelled by STRUCK")
	_check(
		is_equal_approx(enemy._pending_attack_time, 0.2),
		"pending impact timer untouched by STRUCK"
	)
	_check(
		enemy._attack_timer > deadline_before,
		"NEXT attack deadline slips by the struck penalty"
	)
	enemy._update_pending_attack(0.25)
	var hp_after_settle := player.current_hp
	_check(hp_after_settle == 495, "committed attack damage settles exactly once")
	enemy._update_pending_attack(0.25)
	_check(player.current_hp == hp_after_settle, "no duplicate settlement")
	player.free()
	enemy.free()


## Section 36: an ordinary struck never modifies the movement cadence.
func _test_ordinary_struck_keeps_walk_cadence() -> void:
	var player := _make_player()
	var enemy := await _make_enemy(18, 26)
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var hp_before := enemy.current_hp
	enemy.take_damage(7, player)
	_check(enemy.current_hp == hp_before - 7, "ordinary damage reduces HP")
	_check(cadence.walk_tick_ms == tick_before, "walk_tick_ms must not change")
	_check(not enemy._movement_step_active, "no committed step is cancelled")
	_check(enemy._attack_timer > 0.0, "attack deadline slips by the struck penalty")
	_check(enemy.visual.pending_struck_count() == 1, "struck visual event queued")
	player.free()
	enemy.free()


## Section 37: direct magic enters the MAC stage -> walk tick +800..1799.
## The roll comes from the TARGET's own RNG stream (the service must not
## consume the caller's spell-resolution RNG; its continuation is a validated
## parity contract). Seed it and mirror the draw with a probe RNG.
func _test_direct_magic_walk_delay() -> void:
	var enemy := await _make_enemy(18, 43)
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var hp_before := enemy.current_hp
	var deadline_before := enemy._attack_timer
	enemy._rng.seed = 20260916
	var probe_rng := RandomNumberGenerator.new()
	probe_rng.seed = 20260916
	var expected_roll := probe_rng.randi_range(0, 999)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"wizard.lightning",
		50,
		null,
		rng,
		Callable(),
		9,
		{},
	)
	_check(bool(resolution.get("success", false)), "direct magic dealt damage")
	_check(
		cadence.walk_tick_ms == tick_before + 800 + expected_roll,
		"walk tick postponed by exactly 800 + roll (%d)" % expected_roll
	)
	_check(enemy.current_hp < hp_before, "positive magic damage reduces HP")
	_check(
		enemy._attack_timer > deadline_before,
		"positive magic damage also slips the attack deadline"
	)
	_check(enemy.visual.pending_struck_count() == 1, "positive magic damage queues STRUCK")
	enemy.free()


## Section 38: MAC compresses damage to 0 AFTER the MAC stage was entered:
## walk delay stays, ordinary STRUCK does not happen.
func _test_direct_magic_zero_damage_boundary() -> void:
	var enemy := await _make_enemy(18, 43)
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var hp_before := enemy.current_hp
	var deadline_before := enemy._attack_timer
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"wizard.lightning",
		50,
		null,
		rng,
		Callable(self, "_zero_magic_defense"),
		9,
		{},
	)
	_check(not bool(resolution.get("success", false)), "zero final damage is not a success")
	_check(bool(resolution.get("enters_magic_defense_stage", false)), "MAC stage was entered")
	_check(int(resolution.get("final_damage", -1)) == 0, "MAC compressed damage to 0")
	_check(enemy.current_hp == hp_before, "HP unchanged")
	_check(
		cadence.walk_tick_ms > tick_before,
		"walk tick is still postponed at zero final damage"
	)
	_check(
		is_equal_approx(enemy._attack_timer, deadline_before),
		"attack deadline untouched at zero final damage"
	)
	_check(enemy.visual.pending_struck_count() == 0, "no STRUCK visual at zero damage")
	enemy.free()


## Section 39: anti-magic evasion happens BEFORE the MAC stage: nothing moves.
func _test_anti_magic_full_evasion() -> void:
	var enemy := await _make_enemy(18, 43)
	enemy.direct_spell_anti_magic_points = 10
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var hp_before := enemy.current_hp
	var deadline_before := enemy._attack_timer
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"wizard.lightning",
		50,
		null,
		rng,
		Callable(),
		9,
		{},
	)
	_check(bool(resolution.get("magic_evaded", false)), "anti-magic evaded the spell")
	_check(not bool(resolution.get("enters_magic_defense_stage", false)), "MAC stage never entered")
	_check(enemy.current_hp == hp_before, "HP unchanged")
	_check(cadence.walk_tick_ms == tick_before, "walk tick untouched on evasion")
	_check(
		is_equal_approx(enemy._attack_timer, deadline_before),
		"attack deadline untouched on evasion"
	)
	_check(enemy.visual.pending_struck_count() == 0, "no STRUCK visual on evasion")
	enemy.free()


## Section 40 (highest priority): fire wall ticks are RM_MAGSTRUCK_MINE.
func _test_fire_wall_is_mine() -> void:
	var enemy := await _make_enemy(18, 43)
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var hp_before := enemy.current_hp
	var deadline_before := enemy._attack_timer
	var mine_counter_before := RuntimeDiagnosticsScript.performance_counter(
		&"monster_magic_mine_struck_count"
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"wizard.fire_wall",
		12,
		null,
		rng,
		Callable(),
		-1,
		{},
		CombatRuntimeServiceScript.EnemyMagicDeliveryKind.MAGSTRUCK_MINE,
	)
	_check(bool(resolution.get("success", false)), "fire wall tick dealt positive damage")
	_check(cadence.walk_tick_ms == tick_before, "MINE must never postpone the walk tick")
	_check(enemy.current_hp < hp_before, "fire wall damage reduces HP")
	_check(
		enemy._attack_timer > deadline_before,
		"positive fire wall damage slips the attack deadline"
	)
	_check(enemy.visual.pending_struck_count() == 1, "positive fire wall damage queues STRUCK")
	_check(
		RuntimeDiagnosticsScript.performance_counter(&"monster_magic_mine_struck_count")
			== mine_counter_before + 1,
		"mine struck counter incremented"
	)
	enemy.free()


## Section 40 pack proof: 12+ monsters through mine ticks never walk-lock.
func _test_fire_wall_pack_never_walk_locked() -> void:
	var walk_delay_before := RuntimeDiagnosticsScript.performance_counter(
		&"monster_direct_magic_walk_delay_count"
	)
	var enemies: Array[EnemyActor] = []
	for index: int in range(12):
		var enemy := await _make_enemy(18, 43)
		var cadence = enemy._movement_cadence
		enemy.set_meta("struck_tick_before", cadence.walk_tick_ms)
		enemies.append(enemy)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for enemy: EnemyActor in enemies:
		_combat_runtime.apply_enemy_direct_spell_damage(
			enemy,
			"wizard.fire_wall",
			10,
			null,
			rng,
			Callable(),
			-1,
			{},
			CombatRuntimeServiceScript.EnemyMagicDeliveryKind.MAGSTRUCK_MINE,
		)
	for enemy: EnemyActor in enemies:
		var cadence = enemy._movement_cadence
		_check(
			cadence.walk_tick_ms == int(enemy.get_meta("struck_tick_before")),
			"packed fire wall AOE must never walk-lock a monster"
		)
		enemy.free()
	_check(
		RuntimeDiagnosticsScript.performance_counter(
			&"monster_direct_magic_walk_delay_count"
		) == walk_delay_before,
		"no direct-magic walk delay was recorded for mine ticks"
	)


## Section 41: Lv50 monsters keep ordinary struck but have no walk delay.
func _test_level_fifty_white_boar() -> void:
	var enemy := await _make_enemy(18, 50)
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var deadline_before := enemy._attack_timer
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"wizard.lightning",
		40,
		null,
		rng,
		Callable(),
		9,
		{},
	)
	_check(bool(resolution.get("success", false)), "Lv50 took positive magic damage")
	_check(cadence.walk_tick_ms == tick_before, "Lv50 has no walk-tick postponement")
	_check(
		is_equal_approx(
			enemy._attack_timer,
			deadline_before + float(MonsterStruckPolicy.attack_delay_ms(50)) / 1000.0
		),
		"Lv50 keeps the ordinary 20ms attack deadline penalty"
	)
	_check(enemy.visual.pending_struck_count() == 1, "Lv50 queues the ordinary STRUCK")
	enemy.free()


## Section 42: poison ticks are HP-only, ten ticks in a row.
func _test_poison_is_hp_only() -> void:
	var enemy := await _make_enemy(18, 26)
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var deadline_before := enemy._attack_timer
	enemy.apply_poison(3, 12.0, 1.0)
	for tick: int in range(10):
		var hp_before := enemy.current_hp
		enemy._update_status_effects(1.05)
		_check(enemy.current_hp == hp_before - 3, "poison tick %d reduced HP" % tick)
		_check(
			enemy.visual.pending_struck_count() == 0,
			"poison tick %d queued no STRUCK" % tick
		)
		_check(
			is_equal_approx(enemy._attack_timer, deadline_before),
			"poison tick %d did not slip the attack deadline" % tick
		)
	_check(cadence.walk_tick_ms == tick_before, "poison never touched the walk cadence")
	enemy.free()


func _zero_magic_defense(_skill_id: String, damage_after_evasion: int, _stats: Dictionary) -> int:
	return maxi(0, damage_after_evasion * 0)
