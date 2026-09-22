extends Node2D
const Visual := preload("res://scripts/caster_skill_animation_player.gd")
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const Fixtures := preload("res://tests/helpers/fire_wall_controller_test_fixtures.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
const Music := preload("res://scripts/town_music_controller.gd")
var rows: Dictionary = {}
var damage_calls := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var music := AudioStreamPlayer.new()
	add_child(music)
	var start := Time.get_ticks_usec()
	music.stream = load(Music.TOWN_MUSIC_PATH)
	rows.music_load_usec = Time.get_ticks_usec() - start
	music.volume_db = -80.0
	var plays: Array[int] = []
	for i in range(12):
		start = Time.get_ticks_usec()
		music.play()
		plays.append(Time.get_ticks_usec() - start)
		music.stop()
		await get_tree().process_frame
	rows.music_play_usec = plays
	var prepared := Music.PreparedMusicStream.new()
	prepared.source_stream = music.stream
	music.stream = prepared
	var prepared_plays: Array[int] = []
	for i in range(12):
		prepared.prepare()
		start = Time.get_ticks_usec()
		music.play()
		prepared_plays.append(Time.get_ticks_usec() - start)
		music.stop()
		await get_tree().process_frame
	rows.music_prepared_play_usec = prepared_plays
	music.queue_free()

	var visuals: Array[Visual] = []
	start = Time.get_ticks_usec()
	for i in range(54):
		var visual := Visual.new()
		add_child(visual)
		assert(visual.configure("wizard.fire_wall", Vector2.DOWN, 74.0, true))
		visual.set_process(false)
		visuals.append(visual)
	rows.fire_wall_54_cell_configure_usec = Time.get_ticks_usec() - start
	var first_texture: WeakRef = weakref(visuals[0].texture)
	var frame_work: Array[int] = []
	for frame in range(360):
		start = Time.get_ticks_usec()
		for visual in visuals:
			visual._process(0.1)
		frame_work.append(Time.get_ticks_usec() - start)
		if frame == 3:
			rows.fire_wall_first_texture_retained_after_advance = first_texture.get_ref() != null
	rows.fire_wall_54_cell_frame_work_usec = frame_work
	rows.texture_cache = Registry.frame_texture_cache_diagnostics()
	for visual in visuals:
		visual.queue_free()
	await get_tree().process_frame
	var index := Index.new()
	var enemies: Array[EnemyActor] = []
	for i in range(30):
		enemies.append(Fixtures.make_enemy(self, index, i + 1, 11012,
			Vector2((i % 6) * 0.3, (i / 6) * 0.3), 0.25, 100000))
	var caster := Node2D.new()
	add_child(caster)
	var controller := Fixtures.make_controller(self, index, 11012, Vector2.ZERO,
		{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
		"v82:probe", caster, _apply_damage)
	# Isolate repeatable exact-phase + real nonlethal damage work. Temporal
	# claims are covered by the separate production controller parity suite.
	controller.runtime_damage_enabled = false
	var ticks: Array[int] = []
	for i in range(120):
		start = Time.get_ticks_usec()
		controller._apply_field_tick()
		ticks.append(Time.get_ticks_usec() - start)
	rows.fire_wall_dense_30_tick_usec = ticks
	rows.damage_calls = damage_calls
	rows.controller = controller.fire_wall_controller_diagnostics()
	assert(damage_calls > 0)
	assert(controller.controller_exact_test_count == 3600)
	controller.queue_free()
	for enemy in enemies:
		enemy.queue_free()
	caster.queue_free()
	var label := OS.get_environment("HARDCORE_V82_LABEL")
	if label.is_empty():
		label = "probe"
	var folder := "res://outputs/performance_v82"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder + "/" + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print("PERFORMANCE_V82_COMPONENT_PROBE_PASS ", label)
	await get_tree().process_frame
	get_tree().quit(0)

func _apply_damage(enemy: EnemyActor, power: int) -> void:
	damage_calls += 1
	enemy.take_damage(power)

func _ground_to_screen(value: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(value)

func _screen_to_ground(value: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(value)
