extends Node

## Q3-B: one spatial release builds exactly ONE release-level Snapshot V2 in
## the canonical plan; the spawned projectile consumes that same snapshot id
## and its segment snapshots inherit it as parent_snapshot_id.

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
		Plan.sentinel_diagnostics().snapshot_build_count == 1,
		"exactly one release snapshot must be built"
	)
	var plan: Dictionary = result.get("canonical_plan", {})
	var snapshot_id := str(plan.get("snapshot_id", ""))
	assert(not snapshot_id.is_empty(), "plan snapshot id missing")
	var projectile: SkillProjectile = null
	for child: Node in game.get_children():
		if child is SkillProjectile:
			projectile = child
			break
	assert(projectile != null, "projectile node missing")
	assert(
		str(projectile.skill_footprint_snapshot.get("snapshot_id", ""))
			== snapshot_id,
		(
			"projectile must consume canonical snapshot expected=%s actual=%s "
			+ "rejection=%s snapshot_skill=%s projectile_skill=%s "
			+ "snapshot_release=%s projectile_release=%s snapshot_map=%s "
			+ "projectile_map=%s"
		)
		% [
			snapshot_id,
			str(projectile.skill_footprint_snapshot.get("snapshot_id", "")),
			str(projectile.projection_rejection_reason),
			str(plan.get("canonical_snapshot", {}).get("skill_id", "")),
			projectile.skill_id,
			str(plan.get("canonical_snapshot", {}).get("release_id", "")),
			projectile.release_id,
			str(plan.get("canonical_snapshot", {}).get("runtime_map_id", "")),
			str(projectile.runtime_map_id),
		]
	)
	assert(
		projectile.skill_footprint_snapshot
		== plan.get("canonical_snapshot", {}),
		"projectile must retain the exact canonical release snapshot"
	)
	var projectile_diag := projectile.projectile_broadphase_diagnostics()
	assert(bool(projectile_diag.canonical_release_snapshot_bound))
	assert(
		int(projectile_diag.release_snapshot_build_count) == 0,
		"canonical projectile setup/projection must not rebuild release snapshot"
	)
	for frame in range(3):
		await get_tree().physics_frame
	var segment_snapshot: Dictionary = projectile.last_segment_footprint_snapshot
	assert(
		str(segment_snapshot.get("parent_snapshot_id", "")) == snapshot_id,
		"projectile segment snapshot must inherit the canonical snapshot id"
	)
	await get_tree().process_frame
	print("SKILL_PRODUCTION_SINGLE_SNAPSHOT_PASS snapshot=%s" % snapshot_id)
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"single-snapshot fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	enemy.setup(canonical_data, caster, false)
	assert(
		enemy.monster_id == FIXTURE_MONSTER_ID and not enemy.is_boss,
		"single-snapshot fixture must remain an ordinary exact-ID target"
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
		"single-snapshot fixture target must survive exact-ID admission"
	)
	return enemy
