extends Node

## Q2-B stable order: multiple effects expiring in the same frame must be
## processed in registration (creation) order; targets inside one effect must
## be processed in the stable combat order; the whole sequence must be
## reproducible tick after tick (no Dictionary / bucket iteration order).

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

const MAP_A := 9401
const SKILL_ID := "wizard.fire_wall"
const REGISTRATION_ORDER := [5, 1, 4, 2, 3, 6]

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemies: Array[EnemyActor] = []
var _effects: Array[GroundSkillEffect] = []
var _effect_labels: Array[String] = []
var _damage_log: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_fresh_world()
	var positions := [
		Vector2(0, 0),
		Vector2(0.3, 0),
		Vector2(0, 0.3),
		Vector2(0.2, 0.2),
	]
	for i: int in range(4):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 1,
				MAP_A,
				positions[i],
				0.25
			)
		)
	for effect_index: int in range(REGISTRATION_ORDER.size()):
		var effect_id := int(REGISTRATION_ORDER[effect_index])
		var label := "E%d" % effect_id
		_effect_labels.append(label)
		_effects.append(
			Fixtures.create_effect(
				self,
				SKILL_ID,
				"q2b:order:%s" % label,
				MAP_A,
				Vector2.ZERO,
				2.0,
				1.0,
				60.0,
				3,
				null,
				Callable(self, "_record_labeled_damage").bind(label)
			)
		)
		add_child(_effects[-1])
		Fixtures.register_effect(
			_manager,
			_effects[-1],
			effect_id,
			MAP_A,
			Callable(self, "_record_labeled_damage").bind(label)
		)

	var legacy_order := _run_legacy()
	_restore_hp()
	_damage_log.clear()
	var manager_order := _run_manager()
	assert(
		manager_order == legacy_order,
		"manager damage order must equal legacy creation/stable order"
	)
	assert(
		manager_order == _expected_order(),
		"manager damage order must follow registration sequence + stable order"
	)
	# Repeat ticks: the order must be byte-for-byte reproducible.
	for _repeat: int in range(3):
		_damage_log.clear()
		_restore_hp()
		var repeated := _run_manager()
		assert(
			repeated == manager_order,
			"stable order must be reproducible across ticks"
		)
	assert(
		_manager.registered_effect_count() == 6,
		"all six effects must remain registered for the order test"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"PERSISTENT_GROUND_EFFECT_STABLE_ORDER_PASS effects=%d targets=%d"
		% [_effects.size(), _enemies.size()]
	)
	get_tree().quit(0)


func _run_legacy() -> Array[String]:
	var order: Array[String] = []
	for effect_index: int in range(_effects.size()):
		var result: Dictionary = Reference.legacy_tick(
			_effects[effect_index],
			_enemies,
			true,
			Callable(self, "_record_labeled_damage").bind(
				_effect_labels[effect_index]
			)
		)
		for enemy_id: int in result.get("damage_order", []):
			order.append("%s:%d" % [_effect_labels[effect_index], enemy_id])
	return order


func _run_manager() -> Array[String]:
	_manager.tick_frame(1.0)
	return _damage_log.duplicate()


func _expected_order() -> Array[String]:
	var result: Array[String] = []
	for label: String in _effect_labels:
		for i: int in range(_enemies.size()):
			result.append("%s:%d" % [label, _enemies[i].get_instance_id()])
	return result


func _fresh_world() -> void:
	_index = SpatialIndexScript.new()
	_manager = Fixtures.new_manager(_index)
	_enemies.clear()
	_effects.clear()
	_effect_labels.clear()
	_damage_log.clear()


func _restore_hp() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.current_hp = 10000


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for effect: GroundSkillEffect in _effects:
		if is_instance_valid(effect):
			effect.queue_free()


func _record_labeled_damage(
	enemy: EnemyActor,
	_amount: int,
	label: String
) -> void:
	_damage_log.append("%s:%d" % [label, enemy.get_instance_id()])
	enemy.take_damage(_amount, null)


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
