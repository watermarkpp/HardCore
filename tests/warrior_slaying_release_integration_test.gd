extends Node

const RootScript = preload("res://scripts/game_root.gd")
const Router = preload("res://scripts/skills/skill_runtime_router.gd")
const ReleaseGeometry = preload("res://scripts/skills/combat_release_geometry.gd")

class ObservedRoot extends RootScript:
	var selected_seed := 1
	var modifier_records: Array[Dictionary] = []
	var damage_records: Array[Dictionary] = []

	func _next_canonical_seed() -> int:
		return selected_seed

	func _commit_warrior_melee_modifier_events(modifiers: Dictionary) -> void:
		modifier_records.append(modifiers.duplicate(true))
		super._commit_warrior_melee_modifier_events(modifiers)

	func _apply_physical_hit(enemy: EnemyActor, damage: int, accuracy_bonus := 0) -> bool:
		damage_records.append({"target": enemy.get_instance_id(), "damage": damage, "accuracy": accuracy_bonus})
		return super._apply_physical_hit(enemy, damage, accuracy_bonus)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.learned_skills = {"基本剑术": 3, "攻杀剑术": 3, "刺杀剑术": 3, "半月弯刀": 3, "烈火剑法": 3}
	PlayerState.recalculate_stats(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.set_script(ObservedRoot)
	add_child(game)
	for frame in range(1200):
		await get_tree().process_frame
		if not game._world_bootstrap_in_progress and not game._map_transition_in_progress:
			break
	assert(game.gameplay_input_is_enabled())
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.auto_target_enabled = false
	for actor in get_tree().get_nodes_in_group("enemies"):
		if actor is EnemyActor:
			actor.set_physics_process(false)
			actor.set_combat_position(game.player.global_position + Vector2(4000, 4000), &"slaying_fixture_clear")
	var origin_gu := Vector2(38.5, 13.5)
	var origin: Vector2 = game._canonical_ground_gu_to_screen_px(origin_gu)
	game._set_player_world_position(origin)
	var targets: Array[EnemyActor] = []
	for index in range(2):
		var enemy: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19), origin, false, -1.0, {"respawn_enabled": false})
		assert(enemy != null)
		enemy.set_physics_process(false)
		enemy.max_hp = 100000
		enemy.current_hp = enemy.max_hp
		targets.append(enemy)
	await get_tree().physics_frame
	for mode: String in ["normal", "thrust", "half_moon", "fire"]:
		var plain := _release(game, targets, origin_gu, mode, false)
		var proc := _release(game, targets, origin_gu, mode, true)
		assert(plain.size() == proc.size() and not proc.is_empty(), mode + ": missing real damage calls")
		for index in range(proc.size()):
			assert(plain[index].target == proc[index].target)
			assert(int(proc[index].damage) == int(plain[index].damage) + 8, mode + ": proc must be added once after body formula")
			assert(plain[index].accuracy == proc[index].accuracy, mode + ": proc must not duplicate passive accuracy")
		if mode in ["thrust", "half_moon"]:
			assert(proc.size() >= 2, mode + ": fixture must exercise shared multi-target proc")
	game.queue_free()
	await get_tree().process_frame
	print("WARRIOR_SLAYING_RELEASE_INTEGRATION_PASS")
	get_tree().quit(0)

func _release(game: Node, targets: Array[EnemyActor], origin_gu: Vector2, mode: String, proc: bool) -> Array[Dictionary]:
	var origin: Vector2 = game._canonical_ground_gu_to_screen_px(origin_gu)
	var offsets := [Vector2(1.1, 0), Vector2(2.1, 0) if mode == "thrust" else Vector2(0.8, 0.8)]
	for index in range(targets.size()):
		targets[index].current_hp = targets[index].max_hp
		targets[index].set_combat_position(game._canonical_ground_gu_to_screen_px(origin_gu + offsets[index]), &"slaying_release_fixture")
	game.player.current_mp = 1000
	game.player.fire_sword_enabled = mode == "fire"
	game.player.thrusting_enabled = mode == "thrust"
	game.player.half_moon_enabled = mode == "half_moon"
	game._set_canonical_fire_charge_expires_at(0)
	game.selected_seed = _seed_for(mode, proc)
	game.modifier_records.clear()
	game.damage_records.clear()
	game.locked_target = targets[0]
	game.magic_locked_target = targets[0]
	game._skill_cast_target = targets[0]
	var direction: Vector2 = (targets[0].global_position - origin).normalized()
	var geometry := ReleaseGeometry.resolve(origin, direction, targets[0].get_instance_id(), targets[0].global_position, true, true, ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION)
	game.player._pending_attack_context = {
		"mode": mode, "selected_body_mode": mode,
		"direct_toggle_release": mode == "fire", "release_geometry": geometry,
	}
	var hp_before := targets[0].current_hp
	game._on_player_attack(origin, direction, 100)
	assert(game.modifier_records.size() == 1, mode + ": expected one modifier decision per release")
	var decision: Dictionary = game.modifier_records[0]
	assert(str(decision.body_mode) == mode and bool(decision.slaying_proc) == proc, str(decision))
	assert(int(decision.slaying_proc_roll_count) == 1)
	assert(targets[0].current_hp < hp_before, mode + ": real actor must receive damage")
	return game.damage_records.duplicate(true)

func _seed_for(mode: String, proc: bool) -> int:
	for seed_value in range(1, 1000):
		var decision := Router.resolve_warrior_melee_modifiers({
			"body_mode": mode, "basic_sword_learned": true, "basic_sword_rank": 3,
			"slaying_learned": true, "slaying_rank": 3,
			"valid_melee_swing": true, "seed": seed_value,
		})
		if bool(decision.slaying_proc) == proc:
			return seed_value
	assert(false, "could not find deterministic proc control")
	return 1
