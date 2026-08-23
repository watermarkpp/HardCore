extends Node

const EnemyScript := preload("res://scripts/enemy.gd")
const PlayerScript := preload("res://scripts/player.gd")
const SummonActorScript := preload("res://scripts/summon_actor.gd")
const ControllerScript := preload(
	"res://scripts/entrapment_boundary_controller.gd"
)
const SnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const TaoistRuntime := preload(
	"res://scripts/skills/runtimes/taoist_skill_runtime.gd"
)
const SkillRngScript := preload("res://scripts/skills/skill_rng.gd")

const MAP_ID := 71
const CENTER_CELL := Vector2i(10, 12)


func _ready() -> void:
	var caster := PlayerScript.new()
	var enemy := EnemyScript.new()
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground")
	)
	## Production targets have continuous ground coordinates inside their grid
	## cell. A large combat radius must not turn the eight-cell path barrier into
	## a tiny radius-reduced acceptance box.
	enemy.global_position = _ground_to_screen(
		Vector2(CENTER_CELL) + Vector2(0.42, -0.41)
	)
	enemy.combat_radius_gu = 0.33
	caster.global_position = _ground_to_screen(Vector2(CENTER_CELL) + Vector2(4.0, 0.0))
	var boundary_snapshot := _boundary_snapshot()
	var effect := _effect(enemy, caster, boundary_snapshot, 2.0)

	_verify_fail_closed_snapshot_contract(enemy, caster, effect, boundary_snapshot)
	_verify_strict_controller_and_movement(enemy, caster, effect, boundary_snapshot)
	_verify_attack_and_damage_policy(enemy, caster, effect, boundary_snapshot)
	_verify_player_entry_expiry_map_and_exit(enemy, caster, effect, boundary_snapshot)
	_verify_explicit_immunity_only(enemy, caster, effect, boundary_snapshot)
	_verify_runtime_locked_target_excludes_boundary_candidates(
		enemy, caster, boundary_snapshot
	)

	enemy.free()
	caster.free()
	print(
		"TAOIST_ENTRAPMENT_BOUNDARY_PRODUCTION_PASS: strict V2 ring, free interior AI, "
		+ "footpoint rollback, player-entry/expiry/map lifecycle, pet evasion and locked target"
	)
	get_tree().quit(0)


func _verify_fail_closed_snapshot_contract(
	enemy: EnemyActor,
	caster: PlayerCharacter,
	effect: Dictionary,
	boundary_snapshot: Dictionary
) -> void:
	var seven_cell_snapshot := boundary_snapshot.duplicate(true)
	var cells: Array = seven_cell_snapshot.geometry_cells_grid_steps.duplicate()
	var polygons: Array = seven_cell_snapshot.polygons_ground_gu.duplicate()
	cells.pop_back()
	polygons.pop_back()
	seven_cell_snapshot["geometry_cells_grid_steps"] = cells
	seven_cell_snapshot["polygons_ground_gu"] = polygons
	assert(not enemy.apply_entrapment(effect, seven_cell_snapshot, caster).valid)
	var wrong_map_effect := effect.duplicate(true)
	wrong_map_effect["runtime_map_id"] = MAP_ID + 1
	assert(not enemy.apply_entrapment(
		wrong_map_effect, boundary_snapshot, caster
	).valid)
	assert(not enemy.entrapment_active())


func _verify_strict_controller_and_movement(
	enemy: EnemyActor,
	caster: PlayerCharacter,
	effect: Dictionary,
	boundary_snapshot: Dictionary
) -> void:
	var result := enemy.apply_entrapment(effect, boundary_snapshot, caster)
	assert(result.valid)
	assert(enemy.entrapment_active())
	assert(enemy.control_time == 0.0)
	var state := enemy.entrapment_state_snapshot()
	assert(state.contract_id == ControllerScript.CONTRACT_ID)
	assert(state.boundary_cell_count == 8)
	assert(state.center_cell == CENTER_CELL)
	## A non-integer footpoint close to the edge remains a valid center occupant,
	## even though its combat circle overlaps the neighboring boundary cell.
	assert(
		not enemy._entrapment_controller.movement_candidate_blocked(
			Vector2(CENTER_CELL) + Vector2(0.42, -0.41),
			Vector2(CENTER_CELL) + Vector2(0.49, -0.49),
			enemy.combat_radius_gu
		)
	)
	assert(
		not enemy._entrapment_controller.movement_candidate_blocked(
			Vector2(CENTER_CELL) + Vector2(0.49, -0.49),
			Vector2(CENTER_CELL) + Vector2(0.5, -0.49),
			enemy.combat_radius_gu
		)
	)
	## Exact half-cell contact follows the project's inclusive geometry rule;
	## only a position clearly inside the ring is rejected.
	assert(
		enemy._entrapment_controller.movement_candidate_blocked(
			Vector2(CENTER_CELL) + Vector2(0.5, -0.49),
			Vector2(CENTER_CELL) + Vector2(0.501, -0.49),
			enemy.combat_radius_gu
		)
	)
	## A single large candidate step cannot tunnel beyond the eight cells.
	assert(
		enemy._entrapment_controller.movement_candidate_blocked(
			Vector2(CENTER_CELL),
			Vector2(CENTER_CELL) + Vector2(3.0, 0.0),
			enemy.combat_radius_gu
		)
	)
	enemy.clear_entrapment("test_reset")


func _verify_attack_and_damage_policy(
	enemy: EnemyActor,
	caster: PlayerCharacter,
	effect: Dictionary,
	boundary_snapshot: Dictionary
) -> void:
	assert(enemy.apply_entrapment(effect, boundary_snapshot, caster).valid)
	var summon := SummonActorScript.new()
	assert(not enemy.accepts_external_attack_from(summon))
	assert(enemy.accepts_external_attack_from(caster))
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.take_damage(5, caster)
	assert(enemy.current_hp == 95)
	assert(enemy.entrapment_active())
	enemy.apply_poison(1, 1.0, 1.0)
	enemy._update_status_effects(1.0)
	assert(enemy.current_hp == 94)
	assert(enemy.entrapment_active())
	summon.free()
	enemy.clear_entrapment("test_reset")


func _verify_player_entry_expiry_map_and_exit(
	enemy: EnemyActor,
	caster: PlayerCharacter,
	effect: Dictionary,
	boundary_snapshot: Dictionary
) -> void:
	assert(enemy.apply_entrapment(effect, boundary_snapshot, caster).valid)
	caster.global_position = _ground_to_screen(
		Vector2(CENTER_CELL + Vector2i.RIGHT)
	)
	enemy._update_entrapment_state(0.01)
	assert(not enemy.entrapment_active())
	assert(
		enemy.entrapment_state_snapshot().last_end_reason
		== "player_entered_boundary"
	)
	caster.global_position = _ground_to_screen(
		Vector2(CENTER_CELL) + Vector2(4.0, 0.0)
	)
	var short_effect := effect.duplicate(true)
	short_effect["duration_seconds"] = 0.02
	assert(enemy.apply_entrapment(short_effect, boundary_snapshot, caster).valid)
	enemy._update_entrapment_state(0.03)
	assert(enemy.entrapment_state_snapshot().last_end_reason == "duration_expired")
	assert(enemy.apply_entrapment(effect, boundary_snapshot, caster).valid)
	enemy.runtime_map_id = MAP_ID + 1
	enemy._update_entrapment_state(0.01)
	assert(enemy.entrapment_state_snapshot().last_end_reason == "map_transition")
	enemy.runtime_map_id = MAP_ID
	assert(enemy.apply_entrapment(effect, boundary_snapshot, caster).valid)
	enemy._exit_tree()
	assert(not enemy.entrapment_active())
	assert(enemy.entrapment_state_snapshot().last_end_reason == "exit_tree")


func _verify_explicit_immunity_only(
	enemy: EnemyActor,
	caster: PlayerCharacter,
	effect: Dictionary,
	boundary_snapshot: Dictionary
) -> void:
	enemy.is_boss = true
	assert(not enemy.apply_entrapment(effect, boundary_snapshot, caster).valid)
	assert(enemy.control_immunity_snapshot().immune)
	enemy.is_boss = false
	enemy.monster_data = {"controlImmune": true}
	assert(not enemy.apply_entrapment(effect, boundary_snapshot, caster).valid)
	enemy.monster_data = {"specialMonster": true}
	enemy.behavior_profile = {"movement": {"stationary": true}}
	assert(not enemy.control_immunity_snapshot().immune)
	assert(enemy.apply_entrapment(effect, boundary_snapshot, caster).valid)
	enemy.clear_entrapment("test_reset")


func _verify_runtime_locked_target_excludes_boundary_candidates(
	enemy: EnemyActor,
	caster: PlayerCharacter,
	boundary_snapshot: Dictionary
) -> void:
	var plan := {
		"accepted": true,
		"effect_success": true,
		"resource_commit": true,
		"resource_commit_required": true,
		"effects": [],
	}
	var context := {
		"input_mode": "production_canonical",
		"runtime_map_id": MAP_ID,
		"caster_runtime_id": caster.get_instance_id(),
		"target_instance_id": enemy.get_instance_id(),
		"target_is_monster": true,
		"target_is_boss": false,
		"target_control_immune": false,
		"target_within_level_gate": true,
		"primary_stat_roll": 4,
		"geometry_cells": _boundary_cells(),
		"skill_footprint_snapshot": boundary_snapshot,
		"targets": [
			{
				"hostile_monster": true,
				"target_instance_id": enemy.get_instance_id(),
				"within_level_gate": true,
			},
			{
				"hostile_monster": true,
				"target_instance_id": 9002,
				"within_level_gate": true,
			},
			{
				"hostile_monster": true,
				"target_instance_id": 9003,
				"is_boss": true,
			},
		],
	}
	TaoistRuntime._resolve_entrapment(
		plan,
		3,
		context,
		SkillRngScript.new(23)
	)
	assert(plan.effect_success and plan.resource_commit)
	assert(plan.effects[0].target_instance_ids == [enemy.get_instance_id()])
	assert(plan.effects[0].trapped_count == 1)
	assert(plan.effects[0].boundary_ring_candidate_count == 3)
	assert(plan.effects[0].boundary_ring_candidates_are_not_trap_targets)
	assert(plan.effects[0].duration_seconds == 52)
	assert(plan.effects[0].boundary_cell_count == 8)
	assert(plan.effects[0].caster_instance_id == caster.get_instance_id())
	assert(not plan.effects[0].break_on_damage)
	assert(not plan.effects[0].generic_root)


func _effect(
	enemy: EnemyActor,
	caster: PlayerCharacter,
	boundary_snapshot: Dictionary,
	duration_seconds: float
) -> Dictionary:
	return {
		"type": "monster_boundary_control",
		"controller_contract_id": ControllerScript.CONTRACT_ID,
		"target_instance_ids": [enemy.get_instance_id()],
		"trapped_count": 1,
		"caster_instance_id": caster.get_instance_id(),
		"runtime_map_id": MAP_ID,
		"duration_seconds": duration_seconds,
		"boundary_snapshot": boundary_snapshot,
		"boundary_cell_count": 8,
		"generic_root": false,
	}


func _boundary_snapshot() -> Dictionary:
	return SnapshotScript.create_cell_union(
		"taoist.entrapment",
		"entrapment-production-test",
		Vector2(CENTER_CELL),
		_boundary_cells(),
		SnapshotScript.make_absolute_runtime_context(
			MAP_ID,
			Vector2(CENTER_CELL),
			Vector2(CENTER_CELL),
			Callable(self, "_ground_to_screen")
		)
	)


func _boundary_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			if x == 0 and y == 0:
				continue
			cells.append(CENTER_CELL + Vector2i(x, y))
	return cells


func _ground_to_screen(ground_position_gu: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(ground_position_gu)


func _screen_to_ground(screen_position_px: Vector2) -> Vector2:
	return GroundUnitSpace.screen_delta_px_to_ground_delta_gu(screen_position_px)
