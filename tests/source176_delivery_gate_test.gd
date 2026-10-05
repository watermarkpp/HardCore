extends Node2D

## source176 Task 1 delivery gate (docs/02 C1): every player-spell delivery
## through CombatRuntimeService.apply_enemy_direct_spell_damage is checked
## against the 33-skill reaction registry by stable id.
##
## Assertions:
## - unknown skill ids fail closed BEFORE any RNG consumption or damage;
## - AUTO (-1) resolves the per-skill family through the registry
##   (DIRECT -> walk-tick postponement semantics, MINE -> never postponed);
## - an explicit kind that contradicts the registry family fails closed;
## - explicit kinds that match the registry stay accepted (pre-R1 callers);
## - the registry table itself keeps the fixed DIRECT/MINE membership the
##   gate relies on.

const CombatRuntimeServiceScript := preload(
	"res://scripts/layers/runtime/combat_runtime_service.gd"
)
const SourceReactionRegistry := preload(
	"res://scripts/monster_source176/skill_reaction_registry.gd"
)
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
	assert(condition, "SOURCE176_DELIVERY_GATE: " + label)
	_checks += 1


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true)
	_combat_runtime = CombatRuntimeServiceScript.new()
	add_child(_combat_runtime)
	await _test_unknown_skill_fails_closed()
	await _test_unknown_skill_auto_fails_closed()
	await _test_mismatched_kind_fails_closed()
	await _test_auto_resolves_direct_family()
	await _test_auto_resolves_mine_family()
	await _test_explicit_direct_stays_accepted()
	_test_registry_membership_contract()
	print("SOURCE176_DELIVERY_GATE_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _ground_to_screen_px(value: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(value)


func _make_enemy(monster_id: int, monster_level: int) -> EnemyActor:
	var enemy := RuntimeEnemyFixture.new()
	enemy.setup(GameData.get_monster_by_id(monster_id), null, false)
	enemy.environment_blocker = null
	enemy.set_physics_process(false)
	enemy.level = monster_level
	enemy.max_hp = 500
	enemy.current_hp = 500
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
	visual.sprite = Sprite2D.new()
	visual.add_child(visual.sprite)
	var flat_texture := GradientTexture2D.new()
	flat_texture.width = 48
	flat_texture.height = 64
	visual.active_resources = {
		"idle": flat_texture, "walk": flat_texture, "attack": flat_texture, "hit": flat_texture, "death": flat_texture,
		"frame_counts": {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 4},
		"direction_mode": "mir2_north_first",
	}
	return enemy


func _assert_rejected(resolution: Dictionary, enemy: EnemyActor, hp_before: int, label: String) -> void:
	_check(not bool(resolution.get("success", true)), label + ": not a success")
	_check(
		str(resolution.get("failure_reason", "")) == "source176_delivery_kind_rejected",
		label + ": rejection reason recorded"
	)
	_check(int(resolution.get("final_damage", -1)) == 0, label + ": zero damage")
	_check(int(resolution.get("stable_skill_id", 0)) != 0 or resolution.has("stable_skill_id"), label + ": skill id reported")
	_check(enemy.current_hp == hp_before, label + ": HP untouched")


## Section 1: an unknown skill id must never silently become DIRECT.
func _test_unknown_skill_fails_closed() -> void:
	var enemy := await _make_enemy(18, 43)
	var hp_before := enemy.current_hp
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var state_before: int = rng.state
	var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"test.not_a_registry_skill",
		50,
		null,
		rng,
		Callable(),
		-1,
		{},
	)
	_assert_rejected(resolution, enemy, hp_before, "unknown id (default kind)")
	_check(rng.state == state_before, "unknown id (default kind): caller RNG untouched")
	enemy.free()


## Section 2: AUTO must not rescue an unknown id either.
func _test_unknown_skill_auto_fails_closed() -> void:
	var enemy := await _make_enemy(18, 43)
	var hp_before := enemy.current_hp
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var state_before: int = rng.state
	var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"test.not_a_registry_skill",
		50,
		null,
		rng,
		Callable(),
		-1,
		{},
		CombatRuntimeServiceScript.EnemyMagicDeliveryKind.AUTO,
	)
	_assert_rejected(resolution, enemy, hp_before, "unknown id (AUTO)")
	_check(rng.state == state_before, "unknown id (AUTO): caller RNG untouched")
	enemy.free()


## Section 3: an explicit kind that contradicts the registry fails closed.
func _test_mismatched_kind_fails_closed() -> void:
	var enemy := await _make_enemy(18, 43)
	var hp_before := enemy.current_hp
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"wizard.fire_wall",
		50,
		null,
		rng,
		Callable(),
		9,
		{},
		CombatRuntimeServiceScript.EnemyMagicDeliveryKind.DIRECT_MAGSTRUCK,
	)
	_assert_rejected(resolution, enemy, hp_before, "fire_wall declared DIRECT")
	_check(cadence.walk_tick_ms == tick_before, "fire_wall declared DIRECT: no walk delay")
	enemy.free()

	var enemy2 := await _make_enemy(18, 43)
	var hp_before2 := enemy2.current_hp
	var resolution2: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy2,
		"wizard.lightning",
		50,
		null,
		rng,
		Callable(),
		9,
		{},
		CombatRuntimeServiceScript.EnemyMagicDeliveryKind.MAGSTRUCK_MINE,
	)
	_assert_rejected(resolution2, enemy2, hp_before2, "lightning declared MINE")
	enemy2.free()


## Section 4: AUTO resolves the DIRECT family with full R1 semantics.
func _test_auto_resolves_direct_family() -> void:
	var enemy := await _make_enemy(18, 43)
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var hp_before := enemy.current_hp
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
		CombatRuntimeServiceScript.EnemyMagicDeliveryKind.AUTO,
	)
	_check(not resolution.has("failure_reason"), "AUTO lightning: no rejection")
	_check(bool(resolution.get("success", false)), "AUTO lightning: dealt damage")
	_check(
		cadence.walk_tick_ms == tick_before + 800 + expected_roll,
		"AUTO lightning: walk tick postponed by 800 + target roll (%d)" % expected_roll
	)
	_check(enemy.current_hp < hp_before, "AUTO lightning: HP reduced")
	enemy.free()


## Section 5: AUTO resolves MINE for the ground-burn family: damage stays,
## the walk tick must never move.
func _test_auto_resolves_mine_family() -> void:
	var enemy := await _make_enemy(18, 43)
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var hp_before := enemy.current_hp
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"wizard.fire_wall",
		50,
		null,
		rng,
		Callable(),
		9,
		{},
		CombatRuntimeServiceScript.EnemyMagicDeliveryKind.AUTO,
	)
	_check(not resolution.has("failure_reason"), "AUTO fire_wall: no rejection")
	_check(bool(resolution.get("success", false)), "AUTO fire_wall: positive tick dealt damage")
	_check(enemy.current_hp < hp_before, "AUTO fire_wall: HP reduced")
	_check(cadence.walk_tick_ms == tick_before, "AUTO fire_wall: walk tick never postponed")
	enemy.free()


## Section 6: explicit matching kinds keep pre-R1 call sites accepted.
func _test_explicit_direct_stays_accepted() -> void:
	var enemy := await _make_enemy(18, 43)
	var cadence = enemy._movement_cadence
	var tick_before: int = cadence.walk_tick_ms
	var hp_before := enemy.current_hp
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
		CombatRuntimeServiceScript.EnemyMagicDeliveryKind.DIRECT_MAGSTRUCK,
	)
	_check(not resolution.has("failure_reason"), "explicit DIRECT lightning: no rejection")
	_check(bool(resolution.get("success", false)), "explicit DIRECT lightning: dealt damage")
	_check(
		cadence.walk_tick_ms == tick_before + 800 + expected_roll,
		"explicit DIRECT lightning: walk tick postponed by 800 + roll"
	)
	_check(enemy.current_hp < hp_before, "explicit DIRECT lightning: HP reduced")
	enemy.free()


## Section 7: the membership contract the gate relies on - the nine
## traditional direct damage spells, the one mine family member, and the
## non-damage families that must never reach the damage pipeline label.
func _test_registry_membership_contract() -> void:
	var direct_ids := [
		"wizard.fireball",
		"wizard.great_fireball",
		"wizard.hellfire",
		"wizard.lightning",
		"wizard.exploding_flame",
		"wizard.laser",
		"wizard.hell_lightning",
		"wizard.ice_storm",
		"taoist.soul_fire_talisman",
	]
	for skill_id: String in direct_ids:
		_check(
			SourceReactionRegistry.family(skill_id) == &"DIRECT",
			"registry: %s is DIRECT" % skill_id
		)
	_check(
		SourceReactionRegistry.family("wizard.fire_wall") == &"MINE",
		"registry: fire_wall is MINE"
	)
	_check(
		SourceReactionRegistry.family("taoist.healing") == &"HEAL"
		and SourceReactionRegistry.family("taoist.poison") == &"POISON"
		and SourceReactionRegistry.family("wizard.holy_word") == &"INSTANT_KILL"
		and SourceReactionRegistry.family("taoist.summon_skeleton") == &"SUMMON",
		"registry: dedicated pipelines keep their own families"
	)
	_check(
		SourceReactionRegistry.family("test.not_a_registry_skill") == &"UNKNOWN",
		"registry: unknown id maps to UNKNOWN, never DIRECT"
	)
	var errors := SourceReactionRegistry.validate_ids(_registry_id_list())
	_check(errors.is_empty(), "registry: no duplicate and complete self coverage")


func _registry_id_list() -> PackedStringArray:
	var ids := PackedStringArray()
	for skill_id: String in SourceReactionRegistry.FAMILIES:
		ids.append(skill_id)
	return ids
