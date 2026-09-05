extends Node

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const FIXTURE_MONSTER_ID := 19

var _projectile_created_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "道士"
	PlayerState.learned_skills = {"灵魂火符": 3}
	PlayerState.recalculate_stats()
	var definition := SkillDataLoaderScript.skill("taoist.soul_fire_talisman")
	var timing: Dictionary = definition.get("timing", {})
	assert(int(timing.get("body_cast_ms", 0)) == 600)
	assert(
		int(timing.get("effect_resolve_ms_from_cast_start", 0)) == 1200,
		"source effect timing must remain unchanged"
	)
	assert(str(definition.get("geometry", {}).get("shape", "")) == "projectile")
	assert(
		PlayerCharacter.SOUL_FIRE_TALISMAN_LAUNCH_TIMING_CONTRACT_ID
			== "skills.taoist.soul_fire_talisman.body_release_frame_launch.v1"
	)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.child_entered_tree.connect(func(node: Node) -> void:
		if node is SkillProjectile and (node as SkillProjectile).resolution_skill_id == "taoist.soul_fire_talisman":
			_projectile_created_count += 1
	)
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var caster: PlayerCharacter = game.player
	caster.current_mp = 999
	var target := _make_enemy(game, caster, caster.global_position + Vector2(180.0, 0.0))
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	await get_tree().process_frame

	var signal_releases: Array[String] = []
	caster.skill_requested.connect(func(skill_name: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
		if SkillDataLoaderScript.stable_skill_id(skill_name) == "taoist.soul_fire_talisman":
			signal_releases.append(skill_name)
	)
	assert(caster.request_skill("灵魂火符", target.get_instance_id()))
	await get_tree().create_timer(0.55).timeout
	assert(signal_releases.is_empty(), "projectile released before the 600 ms body release frame")
	assert(_projectile_created_count == 0)
	await get_tree().create_timer(0.10).timeout
	assert(signal_releases.size() == 1, "projectile was not released exactly once near 600 ms")
	assert(_projectile_created_count == 1, "GameRoot did not create exactly one SkillProjectile")
	await get_tree().create_timer(0.65).timeout
	assert(signal_releases.size() == 1, "1200 ms effect timing emitted a second skill release")
	assert(_projectile_created_count == 1, "1200 ms effect timing created a duplicate projectile")
	assert(caster._attack_timer > 0.0, "1500 ms total lock/cooldown ended too early")

	game.queue_free()
	await get_tree().process_frame
	print(
		"TAOIST_SOUL_FIRE_LAUNCH_TIMING_PASS: no early release; body-frame launch "
		+ "created exactly one production projectile; 1200 ms did not duplicate"
	)
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(not canonical_data.is_empty(), "canonical soul-fire target fixture is missing")
	enemy.setup(canonical_data, caster, false)
	assert(enemy.monster_id == FIXTURE_MONSTER_ID and not enemy.is_boss)
	enemy.max_hp = 9999
	enemy.current_hp = enemy.max_hp
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.can_receive_damage(),
		"canonical soul-fire target fixture is not damage-eligible"
	)
	return enemy
