extends Node

## Q2-B no group scan: manager-owned effects never call
## get_nodes_in_group("enemies"); their node-side damage path stays closed so
## damage is applied exactly once per manager tick (no double damage).

const Fixtures := preload(
	"res://tests/helpers/persistent_ground_effect_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)

const MAP_A := 9801
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemies: Array[EnemyActor] = []
var _effects: Array[GroundSkillEffect] = []
var _damage_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	_manager = Fixtures.new_manager(_index)
	var inside_positions := [
		Vector2(0, 0),
		Vector2(0.3, 0),
		Vector2(0, 0.3),
		Vector2(0.2, 0.2),
	]
	var outside_positions := [
		Vector2(8, 0),
		Vector2(0, 8),
		Vector2(-8, 0),
		Vector2(0, -8),
	]
	for i: int in range(4):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 1,
				MAP_A,
				inside_positions[i],
				0.25
			)
		)
	for i: int in range(4):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 5,
				MAP_A,
				outside_positions[i],
				0.25
			)
		)
	for i: int in range(2):
		_effects.append(
			Fixtures.create_effect(
				self,
				SKILL_ID,
				"q2b:no_scan:%d" % i,
				MAP_A,
				Vector2.ZERO,
				2.0,
				1.0,
				60.0,
				3,
				null,
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
		assert(
			_effects[-1].manager_owned_damage_ticks,
			"registered effects must be manager-owned"
		)

	_manager.tick_frame(1.0)
	_manager.tick_frame(1.0)
	# Let real physics frames run: if the old node-side scan were still open,
	# every frame would add 2 effects x 4 inside enemies of extra damage.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var diagnostics: Dictionary = _manager.persistent_ground_effect_diagnostics()
	assert(
		int(diagnostics.get("group_scan_count", -1)) == 0,
		"manager must never perform a group scan"
	)
	assert(
		int(diagnostics.get("group_nodes_examined", -1)) == 0,
		"manager must never examine group nodes"
	)
	assert(
		_damage_count == 2 * 2 * 4,
		"damage must be exactly two ticks x two effects x four inside enemies"
	)
	_cleanup()
	await get_tree().process_frame
	print("PERSISTENT_GROUND_EFFECT_NO_GROUP_SCAN_PASS damage=%d" % _damage_count)
	get_tree().quit(0)


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for effect: GroundSkillEffect in _effects:
		if is_instance_valid(effect):
			effect.queue_free()


func _record_damage(enemy: EnemyActor, amount: int) -> void:
	_damage_count += 1
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
