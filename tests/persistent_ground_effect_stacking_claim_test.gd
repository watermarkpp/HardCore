extends Node

## Q2-B stacking and claim parity:
##   - overlapping effects each damage independently (no new manager rule)
##   - same release / different release / same caster / different caster
##   - fire-wall claim keys and windows behave exactly like the legacy path
##   - a target keeps being damaged across ticks while it stays inside

const Fixtures := preload(
	"res://tests/helpers/persistent_ground_effect_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Reference := preload(
	"res://tests/helpers/ground_effect_legacy_reference_tick.gd"
)
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)

const MAP_A := 9301
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemies: Array[EnemyActor] = []
var _effects: Array[GroundSkillEffect] = []
var _registration_effects: Array[GroundSkillEffect] = []
var _damage_log: Array[int] = []
var _caster_a: Node2D
var _caster_b: Node2D
var _case_count := 0
var _difference_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_caster_a = Node2D.new()
	_caster_a.name = "CasterA"
	add_child(_caster_a)
	_caster_b = Node2D.new()
	_caster_b.name = "CasterB"
	add_child(_caster_b)

	_stacking_case("two_effects_same_caster_null", null, null, 2, 2)
	_stacking_case("two_effects_different_casters", _caster_a, _caster_b, 2, 2)
	_stacking_case("same_release_duplicate_registration", null, null, 1, 2)
	_claim_case("same_caster_same_tick", _caster_a, _caster_a)
	_claim_case("different_caster_same_tick", _caster_a, _caster_b)
	_across_ticks_case("same_caster", _caster_a, _caster_a, 1)
	_across_ticks_case("different_casters", _caster_a, _caster_b, 2)

	assert(
		_difference_count == 0,
		"manager stacking/claim results must match legacy reference"
	)
	_cleanup()
	await get_tree().process_frame
	print("PERSISTENT_GROUND_EFFECT_STACKING_CLAIM_PASS cases=%d" % _case_count)
	get_tree().quit(0)


func _stacking_case(
	label: String,
	caster_a: Node2D,
	caster_b: Node2D,
	effect_count: int,
	expected_damage_per_tick: int
) -> void:
	_case_count += 1
	_fresh_world()
	_enemies.append(
		Fixtures.make_enemy(
			self,
			_index,
			1,
			MAP_A,
			Vector2.ZERO,
			0.25
		)
	)
	var releases: Array[String] = ["release_1", "release_1"]
	if effect_count == 2 and caster_a != caster_b:
		releases[1] = "release_2"
	for i: int in range(effect_count):
		_effects.append(
			Fixtures.create_effect(
				self,
				SKILL_ID,
				releases[i],
				MAP_A,
				Vector2.ZERO,
				2.0,
				5.0,
				60.0,
				3,
				caster_a if i == 0 else caster_b,
				Callable(self, "_record_damage")
			)
		)
		add_child(_effects[-1])
		Fixtures.register_effect(
			_manager,
			_effects[-1],
			i + 1,
			MAP_A,
			Callable(self, "_record_damage")
		)
		_registration_effects.append(_effects[-1])
	if effect_count == 1:
		# Same release, same node registered twice: old code had two sibling
		# nodes with identical data, so both ticked independently.
		Fixtures.register_effect(
			_manager,
			_effects[0],
			2,
			MAP_A,
			Callable(self, "_record_damage")
		)
		_registration_effects.append(_effects[0])
	var legacy_count := _run_legacy()
	_restore_hp()
	_damage_log.clear()
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var manager_count := _run_manager()
	assert(
		legacy_count == expected_damage_per_tick,
		"%s: legacy damage count %d must equal expected %d"
		% [label, legacy_count, expected_damage_per_tick]
	)
	assert(
		manager_count == expected_damage_per_tick,
		"%s: manager damage count %d must equal expected %d"
		% [label, manager_count, expected_damage_per_tick]
	)
	assert(
		manager_count == legacy_count,
		"%s: manager must match legacy damage count" % label
	)
	_cleanup_world()


func _claim_case(
	label: String,
	caster_a: Node2D,
	caster_b: Node2D
) -> void:
	_case_count += 1
	_fresh_world()
	_enemies.append(
		Fixtures.make_enemy(
			self,
			_index,
			1,
			MAP_A,
			Vector2.ZERO,
			0.25
		)
	)
	for i: int in range(2):
		_effects.append(
			Fixtures.create_effect(
				self,
				SKILL_ID,
				"q2b:claim:%s:%d" % [label, i],
				MAP_A,
				Vector2.ZERO,
				2.0,
				5.0,
				60.0,
				3,
				caster_a if i == 0 else caster_b,
				Callable(self, "_record_damage")
			)
		)
		add_child(_effects[-1])
		Fixtures.register_effect(
			_manager,
			_effects[-1],
			i + 1,
			MAP_A,
			Callable(self, "_record_damage")
		)
		_registration_effects.append(_effects[-1])
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var legacy_count := _run_legacy()
	var legacy_keys := GroundSkillEffect._runtime_tick_claims.keys()
	_restore_hp()
	_damage_log.clear()
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var manager_count := _run_manager()
	var manager_keys := GroundSkillEffect._runtime_tick_claims.keys()
	var diagnostics: Dictionary = _manager.persistent_ground_effect_diagnostics()
	assert(
		manager_count == legacy_count,
		"%s: claim parity damage count legacy=%d manager=%d"
		% [label, legacy_count, manager_count]
	)
	assert(
		legacy_keys.size() == manager_keys.size(),
		"%s: claim key set size must match legacy=%d manager=%d"
		% [label, legacy_keys.size(), manager_keys.size()]
	)
	for key: Variant in legacy_keys:
		assert(
			manager_keys.has(key),
			"%s: claim key %s must be reused verbatim" % [label, key]
		)
	if caster_a == caster_b:
		assert(
			int(diagnostics.get("claim_rejection_count", 0)) == 1,
			"%s: same-caster second effect must be claim-rejected" % label
		)
	else:
		assert(
			int(diagnostics.get("claim_rejection_count", 0)) == 0,
			"%s: different caster claims must not reject" % label
		)
	_cleanup_world()


func _across_ticks_case(
	label: String,
	caster_a: Node2D,
	caster_b: Node2D,
	expected_per_tick: int
) -> void:
	_case_count += 1
	_fresh_world()
	_enemies.append(
		Fixtures.make_enemy(
			self,
			_index,
			1,
			MAP_A,
			Vector2.ZERO,
			0.25
		)
	)
	for i: int in range(2):
		_effects.append(
			Fixtures.create_effect(
				self,
				SKILL_ID,
				"q2b:across:%d" % i,
				MAP_A,
				Vector2.ZERO,
				2.0,
				1.0,
				60.0,
				3,
				caster_a if i == 0 else caster_b,
				Callable(self, "_record_damage")
			)
		)
		add_child(_effects[-1])
		Fixtures.register_effect(
			_manager,
			_effects[-1],
			i + 1,
			MAP_A,
			Callable(self, "_record_damage")
		)
		_registration_effects.append(_effects[-1])
	# Tick 1: legacy claim rules decide how many effects damage.
	var legacy_tick_1 := _run_legacy()
	_restore_hp()
	_damage_log.clear()
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var manager_tick_1 := _run_manager()
	assert(
		legacy_tick_1 == manager_tick_1 and manager_tick_1 == expected_per_tick,
		"%s across-ticks tick 1 must match legacy (%d)" % [label, expected_per_tick]
	)
	# Tick 2 after the claim window expires: both effects damage again, proving
	# the target keeps being damaged across ticks (no persistent hit set).
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_damage_log.clear()
	var manager_tick_2 := _run_manager()
	assert(
		manager_tick_2 == expected_per_tick,
		"%s across-ticks tick 2 must match the claim contract (%d), got %d"
		% [label, expected_per_tick, manager_tick_2]
	)
	assert(
		_damage_log.count(_enemies[0].get_instance_id()) == expected_per_tick,
		"%s target must keep taking damage across ticks while inside" % label
	)
	_cleanup_world()


func _run_legacy() -> int:
	var total := 0
	for effect: GroundSkillEffect in _registration_effects:
		var result: Dictionary = Reference.legacy_tick(
			effect,
			_enemies,
			true,
			Callable(self, "_record_damage")
		)
		total += int(result.get("damage_count", 0))
	return total


func _run_manager() -> int:
	_manager.tick_frame(1.0)
	return _damage_log.size()


func _fresh_world() -> void:
	_cleanup_world()
	_index = SpatialIndexScript.new()
	_manager = Fixtures.new_manager(_index)
	_enemies.clear()
	_effects.clear()
	_registration_effects.clear()
	_damage_log.clear()


func _restore_hp() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.current_hp = 10000


func _cleanup_world() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for effect: GroundSkillEffect in _effects:
		if is_instance_valid(effect):
			effect.queue_free()
	_enemies.clear()
	_effects.clear()
	_registration_effects.clear()
	_damage_log.clear()


func _cleanup() -> void:
	_cleanup_world()
	if _caster_a != null and is_instance_valid(_caster_a):
		_caster_a.queue_free()
	if _caster_b != null and is_instance_valid(_caster_b):
		_caster_b.queue_free()


func _record_damage(enemy: EnemyActor, amount: int) -> void:
	_damage_log.append(enemy.get_instance_id())
	enemy.take_damage(amount, null)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)


func _snapshot_contains_enemy(
	enemy: EnemyActor,
	snapshot: Dictionary
) -> bool:
	return Snapshot.intersects_target_combat_footprint_ground_gu(
		snapshot,
		GroundUnit.screen_delta_px_to_ground_delta_gu(enemy.global_position),
		enemy.combat_radius_gu
	)
