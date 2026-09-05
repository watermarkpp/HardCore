extends Node

## Q3-B: one successful release generates exactly one release id; the spawned
## projectile and the canonical snapshot share that exact release id.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const FIXTURE_MONSTER_ID := 19


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"火球术": 3}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var caster: PlayerCharacter = game.player
	caster.current_mp = 500
	var target := _make_enemy(game, caster, caster.global_position + Vector2(40, 0))
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	await get_tree().process_frame

	Plan.reset_sentinels_for_tests()
	var result: Dictionary = game._execute_canonical_skill(
		"火球术",
		caster.global_position,
		Vector2.RIGHT,
		12
	)
	assert(bool(result.get("accepted", false)), "fireball formal release rejected")
	assert(
		Plan.sentinel_diagnostics().release_id_generation_count == 1,
		"exactly one release id must be generated"
	)
	var plan: Dictionary = result.get("canonical_plan", {})
	var release_id := str(plan.get("release_id", ""))
	assert(not release_id.is_empty(), "plan release id missing")
	var projectile: SkillProjectile = null
	for child: Node in game.get_children():
		if child is SkillProjectile:
			projectile = child
			break
	assert(projectile != null, "projectile node missing")
	assert(
		str(projectile.release_id) == release_id,
		"projectile must share the canonical release id"
	)
	var execution_result: Dictionary = result.get("execution_result", {})
	assert(
		str(execution_result.get("release_id", "")) == release_id,
		"execution result must carry the canonical release id"
	)
	assert(
		str(plan.get("snapshot_id", "")).begins_with(str(plan.get("skill_id", ""))),
		"snapshot id must derive from the same release"
	)
	await get_tree().process_frame
	print("SKILL_PRODUCTION_SINGLE_RELEASE_ID_PASS release=%s" % release_id)
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"single-release fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	enemy.setup(canonical_data, caster, false)
	assert(
		enemy.monster_id == FIXTURE_MONSTER_ID and not enemy.is_boss,
		"single-release fixture must remain an ordinary exact-ID target"
	)
	enemy.max_hp = 9999
	enemy.current_hp = enemy.max_hp
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.can_receive_damage(),
		"single-release fixture target must survive exact-ID admission"
	)
	return enemy
