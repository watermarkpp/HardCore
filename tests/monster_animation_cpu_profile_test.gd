extends Node
## Opt-in CPU micro-profile of the actual public MonsterVisual path. There is
## no renderer/GPU timing here; loading and fixture state changes are excluded.
const Fixtures := preload("res://tests/helpers/monster_streaming_test_fixtures.gd")
const Ground := preload("res://scripts/ground_unit_space.gd")
const GROUPS := {
	"insects": [110, 112, 114, 116, 118, 120],
	"red_moon": [164, 166, 168, 170, 174, 176],
	"other": [18, 24, 50, 62, 128, 138],
}
const FRAMES := 600
var _coordinator
var _player: PlayerCharacter
var _profiles: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(GameData.ensure_loaded())
	_coordinator = Fixtures.make_coordinator()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(true)
	var results: Array[Dictionary] = []
	for group: String in GROUPS:
		for count: int in [30, 60]:
			results.append(await _measure(group, count))
	var report := {"status": "PASS", "frames_per_trial": FRAMES, "trials": 3,
		"measurement": "hot MonsterVisual._process only; headless CPU, not GPU or world FPS",
		"results": results, "profiles": _profiles,
		"visual_source_sha256": FileAccess.get_sha256("res://scripts/monster_visual.gd"),
		"test_sha256": FileAccess.get_sha256("res://tests/monster_animation_cpu_profile_test.gd")}
	DirAccess.make_dir_recursive_absolute("res://outputs/repair_v93")
	var file := FileAccess.open("res://outputs/repair_v93/monster_animation_cpu.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_player.free()
	_coordinator.reset_for_tests()
	MonsterVisual.set_streaming_coordinator(null)
	MonsterVisual.reset_client_resource_cache()
	print("MONSTER_ANIMATION_CPU_PROFILE_PASS groups=3 counts=30/60 trials=3")
	get_tree().quit(0)

func _measure(group: String, count: int) -> Dictionary:
	var enemies: Array[EnemyActor] = []
	var texture_ids: Dictionary = {}
	for serial in range(count):
		var mid: int = GROUPS[group][serial % GROUPS[group].size()]
		assert(not GameData.get_monster_by_id(mid).is_empty())
		var enemy := Fixtures.make_enemy(self, _player, mid, serial + 1)
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		Fixtures.drive_residency_activation(enemy.visual)
		assert(not enemy.visual.active_resources.is_empty())
		enemy.visual.visible = true
		enemy.visual._process(0.0)
		var changes := enemy.visual.render_state_update_count()
		enemy.visual._process(0.0)
		assert(enemy.visual.render_state_update_count() == changes,
			"an unchanged pose must not resubmit its render state")
		var actions: Dictionary = {}
		for action: String in ["idle", "walk", "attack", "hit", "death"]:
			var texture: Texture2D = enemy.visual.active_resources[action]
			texture_ids[texture.get_instance_id()] = true
			actions[action] = {"path": texture.resource_path, "width": texture.get_width(), "height": texture.get_height()}
		_profiles[str(mid)] = {"name": enemy.display_name, "frame_size": [enemy.visual.frame_size.x, enemy.visual.frame_size.y], "actions": actions}
		enemies.append(enemy)
	assert(texture_ids.size() <= GROUPS[group].size() * 5,
		"same-species actors must share action texture resources")
	var usec_trials: Array[int] = []
	var changes_trials: Array[int] = []
	for trial in range(3):
		var total_usec := 0
		var changes_before := 0
		for enemy: EnemyActor in enemies: changes_before += enemy.visual.render_state_update_count()
		for frame in range(FRAMES):
			# Stable 120-frame phases: idle, walk, attack/struck FIFO, walk, idle.
			# Prepare outside the timed loop; production owns timers/frame selection.
			if frame % 120 == 0:
				for enemy: EnemyActor in enemies:
					enemy.velocity = Vector2(80, 40) if frame in [120, 360] else Vector2.ZERO
					enemy.movement_facing = Vector2(80, 40).normalized()
			if frame == 240 or frame == 300:
				for enemy: EnemyActor in enemies:
					enemy.visual.play_attack(0.46)
					enemy.visual.queue_struck()
			var started := Time.get_ticks_usec()
			for enemy: EnemyActor in enemies: enemy.visual._process(1.0 / 60.0)
			total_usec += Time.get_ticks_usec() - started
		var changes_after := 0
		for enemy: EnemyActor in enemies:
			changes_after += enemy.visual.render_state_update_count()
			assert(enemy.visual._presentation_count == 0)
		assert(changes_after - changes_before > 0)
		assert(changes_after - changes_before < count * FRAMES / 2)
		usec_trials.append(total_usec)
		changes_trials.append(changes_after - changes_before)
	# A far-away actor releases its atlases and leaves per-frame animation work.
	for enemy: EnemyActor in enemies:
		enemy.global_position = Vector2(100000, 100000)
		enemy.visual._update_resource_residency()
		assert(enemy.visual.active_resources.is_empty() and not enemy.visual.is_processing())
		assert(enemy.visual.sprite.texture == null)
		enemy.free()
	await get_tree().process_frame
	_coordinator.reset_for_tests()
	print("ANIMATION_CPU group=%s count=%d usec=%s" % [group, count, usec_trials])
	return {"group": group, "actors": count, "total_process_calls_per_trial": count * FRAMES,
		"usec_trials": usec_trials, "render_changes_trials": changes_trials,
		"unique_action_textures": texture_ids.size(), "residency_release_checks": count}

func _ground_to_screen(value: Vector2) -> Vector2:
	return Ground.ground_delta_gu_to_screen_delta_px(value)
