extends Node

const CasterGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")
const GroundEffect := preload("res://scripts/ground_effect.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

const GROUND_EXACT_SKILLS: Array[String] = [
	"wizard.repulsion_ring",
	"wizard.exploding_flame",
	"wizard.fire_wall",
	"wizard.hell_lightning",
	"wizard.ice_storm",
	"taoist.mass_invisibility",
	"taoist.magic_defense",
	"taoist.defense",
	"taoist.entrapment",
	"taoist.mass_healing",
]


func _test_absolute_context() -> Dictionary:
	return Snapshot.make_absolute_runtime_context(
		"test_map",
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_test_ground_to_screen")
	)


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _test_screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)


func _ready() -> void:
	_verify_exact_union_builders_preserve_holes()
	_verify_area_damage_consumes_release_union()
	_verify_persistent_ground_effect_consumes_shared_union()
	print(
		"CASTER_GROUND_EXACT_SNAPSHOT_PASS: exact cell unions preserve holes and "
		+ "are shared by instant area damage and persistent ground ticks"
	)
	get_tree().quit(0)


func _verify_exact_union_builders_preserve_holes() -> void:
	var ring_cells: Array[Vector2i] = []
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			if x != 0 or y != 0:
				ring_cells.append(Vector2i(x, y))
	for skill_id: String in GROUND_EXACT_SKILLS:
		var snapshot := CasterGeometry.create_exact_cell_union_release_snapshot(
			skill_id,
			"%s:release:3" % skill_id,
			Vector2.ZERO,
			ring_cells,
			_test_absolute_context()
		)
		assert(Snapshot.has_legacy_base_contract(snapshot))
		assert(snapshot.is_read_only())
		assert(snapshot.shape_type == Snapshot.SHAPE_CELL_UNION)
		assert(snapshot.geometry_cells_grid_steps.size() == 8)
		assert(not Snapshot.intersects_target_combat_footprint_ground_gu(
			snapshot, Vector2.ZERO, 0.0
		))
		assert(Snapshot.intersects_target_combat_footprint_ground_gu(
			snapshot, Vector2(0.4, 0.0), 0.10
		))
		var contact := CasterGeometry.declared_cells_intersect_actor_footprint(
			ring_cells,
			Vector2(0.4, 0.0),
			0.10,
			snapshot,
			_test_absolute_context()
		)
		assert(contact.intersects and contact.snapshot_consumed)
		assert(contact.skill_footprint_snapshot == snapshot)


func _verify_area_damage_consumes_release_union() -> void:
	var inside := _enemy_at_ground_gu(Vector2(10.6, 10.0), 0.10)
	var outside := _enemy_at_ground_gu(Vector2(10.601, 10.0), 0.10)
	var result := CasterRuntime.execute_cast(
		{
			"skill_id": "wizard.exploding_flame",
			"success": true,
			"operation": "area_damage",
			"damage": 10,
			"damage_before_evasion": 10,
			"geometry_cells": [Vector2i(10, 10)],
			"visual": {},
			"release_id": "wizard.exploding_flame:release:5",
		},
		{
			"affected_targets": [inside, outside],
			"anti_magic_roll": 999,
			"snapshot_coordinate_context": _test_absolute_context(),
		}
	)
	assert(Snapshot.has_legacy_base_contract(result.skill_footprint_snapshot))
	assert(result.skill_footprint_snapshot.shape_type == Snapshot.SHAPE_CELL_UNION)
	assert(result.applied_count == 1)
	assert(inside.current_hp == 90)
	assert(outside.current_hp == 100)
	inside.free()
	outside.free()


func _verify_persistent_ground_effect_consumes_shared_union() -> void:
	var cells: Array[Vector2i] = [
		Vector2i(3, 4),
		Vector2i(4, 4),
		Vector2i(3, 5),
		Vector2i(4, 5),
	]
	var snapshot := CasterGeometry.create_exact_cell_union_release_snapshot(
		"wizard.fire_wall",
		"wizard.fire_wall:release:9",
		Vector2(3.0, 4.0),
		cells,
		_test_absolute_context()
	)
	var effect := GroundEffect.new()
	effect.setup_ground_unit_effect(
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(3.0, 4.0)),
		7,
		0.5,
		5.0,
		Color.WHITE,
		"wizard.fire_wall",
		1.0,
		22.08,
		"wizard.fire_wall:release:9",
		snapshot,
		_test_absolute_context()
	)
	effect.configure_runtime_resolution(
		null,
		Callable(),
		false,
		Callable(),
		Callable(self, "_test_screen_to_ground")
	)
	assert(effect.skill_footprint_snapshot == snapshot)
	var touching := _enemy_at_ground_gu(Vector2(4.6, 5.0), 0.10)
	var separated := _enemy_at_ground_gu(Vector2(4.601, 5.0), 0.10)
	assert(effect.runtime_target_is_inside(touching))
	assert(not effect.runtime_target_is_inside(separated))
	effect.free()
	touching.free()
	separated.free()


func _enemy_at_ground_gu(center_ground_gu: Vector2, radius_gu: float) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = radius_gu
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.monster_data = {"antiMagic": 0}
	return enemy
