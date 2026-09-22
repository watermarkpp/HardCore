extends Node

const WarriorMeleeGeometryScript := preload(
	"res://scripts/skills/warrior_melee_geometry.gd"
)

## Runtime proof for the GameRoot thrust integration.  The pure formula test is
## intentionally not enough here: both paths must reach EnemyActor through the
## real canonical melee effect loop, with only the final thrust segment
## bypassing the target's AC scalar.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.learned_skills = {
		"warrior.thrusting": 3,
		"warrior.slaying_swordsmanship": 3,
	}
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var enemies: Array[EnemyActor] = []
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if candidate is EnemyActor and not candidate.is_queued_for_deletion():
			enemies.append(candidate as EnemyActor)
	assert(enemies.size() >= 2, "runtime fixture needs two canonical enemies")

	var primary := enemies[0]
	# The arrays below are release-resolved fixtures, but canonical planning still
	# requires a valid skill-domain lock target. Put both actors inside the
	# shared lock range so this test exercises damage settlement rather than
	# rejecting an input with no cast target.
	primary.global_position = game.player.global_position + Vector2(32.0, 0.0)
	_prepare_high_defence_target(primary)
	var primary_targets: Array[EnemyActor] = []
	primary_targets.append(primary)
	var empty_secondaries: Array[EnemyActor] = []
	game.locked_target = primary
	game.magic_locked_target = primary
	game._skill_cast_target = primary
	var primary_hp_before := primary.current_hp
	var primary_release_snapshot: Dictionary = game._create_melee_release_footprint_snapshot(
		game.player.global_position,
		Vector2.RIGHT,
		"thrust",
		{}
	)
	assert(not primary_release_snapshot.is_empty(), "primary thrust fixture needs a release snapshot")
	var primary_axis_plan: Dictionary = WarriorMeleeGeometryScript.thrust_damage_axis_plan_ground_gu(
		game._melee_direction_index(Vector2.RIGHT, {}),
		{},
		{}
	)
	var primary_result: Dictionary = game._execute_canonical_melee(
		"thrust",
		game.player.global_position,
		Vector2.RIGHT,
		50,
		0,
		0,
		false,
		{},
		primary_axis_plan,
		primary_release_snapshot,
		{},
		primary_targets,
		empty_secondaries,
		empty_secondaries,
		true,
	)
	assert(primary_result.accepted and primary_result.hit_any)
	assert(
		primary.current_hp == primary_hp_before - 10,
		"primary 0..1.5 GU thrust must consume high enemy AC"
	)

	var secondary := enemies[1]
	secondary.global_position = game.player.global_position + Vector2(64.0, 0.0)
	_prepare_high_defence_target(secondary)
	var secondary_targets: Array[EnemyActor] = []
	secondary_targets.append(secondary)
	game.locked_target = secondary
	game.magic_locked_target = secondary
	game._skill_cast_target = secondary
	var secondary_hp_before := secondary.current_hp
	var secondary_release_snapshot: Dictionary = game._create_melee_release_footprint_snapshot(
		game.player.global_position,
		Vector2.RIGHT,
		"thrust",
		{}
	)
	assert(not secondary_release_snapshot.is_empty(), "secondary thrust fixture needs a release snapshot")
	var secondary_axis_plan: Dictionary = WarriorMeleeGeometryScript.thrust_damage_axis_plan_ground_gu(
		game._melee_direction_index(Vector2.RIGHT, {}),
		{},
		{}
	)
	var secondary_result: Dictionary = game._execute_canonical_melee(
		"thrust",
		game.player.global_position,
		Vector2.RIGHT,
		50,
		0,
		0,
		false,
		{},
		secondary_axis_plan,
		secondary_release_snapshot,
		{},
		empty_secondaries,
		secondary_targets,
		empty_secondaries,
		true,
	)
	assert(secondary_result.accepted and secondary_result.hit_any)
	assert(
		secondary.current_hp == secondary_hp_before - 50,
		"secondary 1.5..3 GU thrust must bypass high enemy AC"
	)

	game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print(
		"WARRIOR_THRUST_DEFENSE_RUNTIME_PASS: canonical primary consumes AC, "
		+ "secondary bypasses AC"
	)
	get_tree().quit(0)


func _prepare_high_defence_target(target: EnemyActor) -> void:
	target.current_hp = 1000
	target.max_hp = 1000
	target.defense = 40
	target.agility = 1
	target.control_time = 0.0
