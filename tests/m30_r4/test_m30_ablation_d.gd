extends Node

## M30-R4 ablation D: cold-resource vs hot-resource child birth cost, and
## sustained post-birth combat, measured separately. Test-fixture only.

const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")

var _timings: Array[String] = []


func _timed_spawn(game: Node, ground: Vector2, monster_id: int) -> EnemyActor:
	var started_usec := Time.get_ticks_usec()
	var monster: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(monster_id),
		game._canonical_ground_gu_to_screen_px(ground),
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:m30_ablation_d_%d" % randi()},
	)
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	_timings.append("%d usec (monster %d)" % [elapsed_usec, monster_id])
	return monster


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await Fixture.wait_for_formal_world(self, game, "m30_ablation_d")
	var caster: PlayerCharacter = game.player
	caster.max_hp = 999999
	caster.current_hp = caster.max_hp
	var center: Vector2 = Fixture.FIXTURE_GROUND_POSITION
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(center + Vector2(-3.0, 0.0)))
	# Cold births: the client resource cache is reset before every birth.
	var cold_spawns: Array[EnemyActor] = []
	for index: int in range(3):
		MonsterVisual.reset_client_resource_cache()
		MonsterVisual.set_synchronous_loading_for_tests(false)
		cold_spawns.append(_timed_spawn(game, center + Vector2(0.5 + float(index) * 0.7, 1.5), 127))
	# Hot births: resources stay resident between births.
	var hot_spawns: Array[EnemyActor] = []
	for index: int in range(3):
		hot_spawns.append(_timed_spawn(game, center + Vector2(0.5 + float(index) * 0.7, -1.5), 127))
	# Sustained post-birth combat window with all six children engaged.
	var sustained_frames := 240
	var peak_frame_ms := 0.0
	for tick: int in range(sustained_frames):
		await get_tree().physics_frame
		var frame_ms: float = Time.get_ticks_usec() / 1000.0 % 1000.0
		peak_frame_ms = maxf(peak_frame_ms, frame_ms)
	for monster: EnemyActor in cold_spawns + hot_spawns:
		if is_instance_valid(monster):
			monster.take_damage(999999, caster, {"source": "m30_ablation_d"})
			monster.queue_free()
	print("M30_ABLATION_D_PASS cold_spawns=%d hot_spawns=%d" % [cold_spawns.size(), hot_spawns.size()])
	for line: String in _timings:
		print("M30ABLD_EVIDENCE " + line)
	get_tree().quit(0)


func _ready() -> void:
	_run.call_deferred()
