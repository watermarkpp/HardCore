extends Node

const Plan := preload("res://scripts/skills/skill_execution_plan_contract.gd")
const Rules := preload("res://scripts/world_spatial_rules.gd")
var releases: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.learned_skills = {"雷电术": 3}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for frame in range(1200):
		await get_tree().process_frame
		if not game._world_bootstrap_in_progress and not game._map_transition_in_progress:
			break
	assert(game.gameplay_input_is_enabled(), "formal world must reach READY")
	game.set_physics_process(false)
	game.auto_target_enabled = false
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			node.set_physics_process(false)
	var caster: PlayerCharacter = game.player
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5)))
	var victim: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19),
		game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5)), false, -1.0,
		{"respawn_enabled": false})
	assert(victim != null)
	victim.set_physics_process(false)
	victim.current_hp = 10000
	victim.max_hp = 10000
	caster.current_mp = 100
	caster.skill_requested.connect(func(_name: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
		releases.append(caster.consume_skill_context().duplicate(true)))
	await get_tree().physics_frame
	assert(game._hc_lightning_clear(victim, caster.global_position), "positive fixture requires actual WORLD-clear geometry")
	var wall := _wall(game, (caster.global_position + victim.global_position) * 0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(not game._is_magic_target_in_range(victim) and not game._is_attack_target_in_range(victim))
	game._on_enemy_target_requested(victim)
	assert(game.magic_locked_target != victim and game.locked_target != victim)
	assert(not game._spell_lock_candidates().has(victim))
	var mp := caster.current_mp
	var action := caster._combat_action_sequence
	var commits := Plan.resource_commit_count
	assert(not caster.request_skill("雷电术", victim.get_instance_id()))
	assert(caster.current_mp == mp and caster._combat_action_sequence == action)
	assert(caster.skill_cooldown_remaining_ms("wizard.lightning") == 0 and releases.is_empty())
	assert(Plan.resource_commit_count == commits and victim.current_hp == 10000)
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(game._hc_lightning_clear(victim, caster.global_position))
	game._set_magic_locked_target(victim, true)
	game._skill_cast_target = victim
	var plans := Plan.canonical_plan_build_count
	assert(caster.request_skill("雷电术", victim.get_instance_id()))
	await get_tree().create_timer(0.75).timeout
	assert(caster.current_mp == mp - 15, "public request must commit rank-3 MP exactly once")
	assert(Plan.resource_commit_count == commits + 1 and Plan.canonical_plan_build_count == plans + 1)
	assert(victim.current_hp < 10000 and releases.size() == 1)
	assert(caster.skill_cooldown_remaining_ms("wizard.lightning") > 0)
	var hp_after := victim.current_hp
	await get_tree().create_timer(0.75).timeout
	assert(victim.current_hp == hp_after and Plan.resource_commit_count == commits + 1)
	# A new WORLD wall during the next real windup must reject its release.
	while not caster.can_request_skill("雷电术"):
		await get_tree().physics_frame
	game._set_magic_locked_target(victim, true)
	game._skill_cast_target = victim
	mp = caster.current_mp
	assert(caster.request_skill("雷电术", victim.get_instance_id()))
	wall = _wall(game, (caster.global_position + victim.global_position) * 0.5)
	await get_tree().create_timer(0.75).timeout
	assert(caster.current_mp == mp and victim.current_hp == hp_after)
	assert(Plan.resource_commit_count == commits + 1)
	wall.queue_free()
	# Production primary-stat owner consumes the existing luck formula.
	PlayerState.computed_stats["magic_min"] = 1
	PlayerState.computed_stats["magic_max"] = 20
	PlayerState.computed_stats["tao_min"] = 2
	PlayerState.computed_stats["tao_max"] = 19
	PlayerState.computed_stats["luck"] = 9
	for sample in range(8):
		assert(game._canonical_primary_stat_roll("wizard") == 20)
		assert(game._canonical_primary_stat_roll("taoist") == 19)
	game.queue_free()
	await get_tree().process_frame
	print("COMBAT_ENVIRONMENT_REQUEST_INTEGRATION_PASS")
	get_tree().quit(0)

func _wall(game: Node, position_px: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = Rules.WORLD_LAYER
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20, 64)
	collider.shape = shape
	body.add_child(collider)
	game.add_child(body)
	body.global_position = position_px
	return body
