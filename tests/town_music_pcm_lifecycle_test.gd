extends Node

const Controller := preload("res://scripts/town_music_controller.gd")

class MeasuringController extends Controller:
	var play_measurements: Array[Dictionary] = []
	var latest_real_process_interval_ms := -1.0
	var max_real_process_interval_ms := -1.0

	func _on_delay_timeout(expected_entry_serial: int) -> void:
		var before_usec := Time.get_ticks_usec()
		var frame_before := Engine.get_process_frames()
		super(expected_entry_serial)
		var after_usec := Time.get_ticks_usec()
		var frame_after := Engine.get_process_frames()
		play_measurements.append({
			"ordinal": play_measurements.size() + 1,
			"phase": "cold" if play_measurements.is_empty() else "warm",
			"native_cost_usec": after_usec - before_usec,
			"process_frame_before": frame_before,
			"process_frame_after": frame_after,
			"real_process_frame_interval_ms": latest_real_process_interval_ms,
			"max_real_process_frame_interval_ms": max_real_process_interval_ms,
		})

func _ready() -> void:
	_run.call_deferred()

func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	if not has_meta("pcm_measurement_last_process_usec"):
		set_meta("pcm_measurement_last_process_usec", now_usec)
		return
	var previous_usec := int(get_meta("pcm_measurement_last_process_usec"))
	var interval_ms := float(now_usec - previous_usec) / 1000.0
	set_meta("pcm_measurement_last_process_usec", now_usec)
	var controller := get_meta("pcm_measurement_controller", null) as MeasuringController
	if controller == null:
		return
	controller.latest_real_process_interval_ms = interval_ms
	controller.max_real_process_interval_ms = maxf(
		controller.max_real_process_interval_ms,
		interval_ms,
	)

func _enter(controller: Node, transition: String) -> void:
	controller.begin_map_transition(910001, transition)
	assert(controller.set_map_context(910001,
		[{"shape": "circle", "center_ground_gu": Vector2.ZERO, "radius_gu": 9.0}], Vector2.ZERO, transition))
	assert(controller.on_loading_transition_finished({
		"contract_id": "ui.loading.transition.v1", "transition_id": transition}))

func _run() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/town/main_city_bgm.playback.json"))
	assert(FileAccess.get_sha256(record.source_path) == record.source_sha256)
	var music_bus_before_index := AudioServer.get_bus_index(&"Music")
	var music_bus_existed := music_bus_before_index >= 0
	var music_bus_muted_before := false
	var music_bus_volume_before := 0.0
	if music_bus_existed:
		music_bus_muted_before = AudioServer.is_bus_mute(music_bus_before_index)
		music_bus_volume_before = AudioServer.get_bus_volume_db(music_bus_before_index)
	var controller := MeasuringController.new()
	add_child(controller)
	set_meta("pcm_measurement_controller", controller)
	controller.delay_seconds = 0.02
	var starts: Array[Dictionary] = []
	controller.music_started.connect(func(event: Dictionary): starts.append(event))
	var stream := controller.music_player.stream as AudioStreamWAV
	assert(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS,
		"town playback must be native uncompressed PCM without runtime Vorbis setup")
	assert(stream.stereo and stream.mix_rate == record.sample_rate_hz)
	assert(stream.data.size() == int(record.sample_frames) * 4)
	assert(absf(stream.get_length() - float(record.duration_seconds)) < 1.0 / 44100.0)
	var warmup_player := controller.get("warmup_player") as AudioStreamPlayer
	assert(warmup_player != null, "PCM warmup player must exist during controller startup")
	assert(warmup_player.stream == stream, "PCM warmup must reuse the already loaded native WAV")
	assert(warmup_player.bus == &"Music", "PCM warmup must use the Music bus")
	assert(warmup_player.volume_db <= -80.0, "PCM warmup must be fully silent")
	assert(controller.get("warmup_start_count") == 1, "PCM warmup must start exactly once")
	assert(starts.is_empty() and not controller.is_music_active(),
		"PCM warmup must not emit formal music_started or activate audible music")
	if music_bus_existed:
		var music_bus_after_index := AudioServer.get_bus_index(&"Music")
		assert(music_bus_after_index == music_bus_before_index)
		assert(AudioServer.is_bus_mute(music_bus_after_index) == music_bus_muted_before)
		assert(is_equal_approx(AudioServer.get_bus_volume_db(music_bus_after_index), music_bus_volume_before),
			"PCM warmup must not change the Music bus user setting")
	for _frame in range(60):
		if controller.get("warmup_completed") == true:
			break
		await get_tree().process_frame
	assert(controller.get("warmup_completed") == true,
		"PCM warmup must complete only after playback consumes its first sample")
	assert(controller.get("warmup_playback_position_observed") == true,
		"PCM warmup must observe non-zero playback position before cleanup")
	assert(starts.is_empty() and not controller.is_music_active(),
		"completed PCM warmup must remain outside formal music lifecycle")
	_enter(controller, "pcm:one")
	await get_tree().create_timer(0.08).timeout
	assert(starts.size() == 1 and controller.is_music_active())
	controller.set_town_presence(false)
	_enter(controller, "pcm:two")
	assert(controller.is_music_active() and controller.state_snapshot().waiting_for_track_finish)
	# The real native finished signal, rather than a direct call to its handler,
	# must rearm the next entry. Seeking only avoids a 48-second test wait.
	controller.music_player.seek(stream.get_length() - 0.12)
	await get_tree().create_timer(0.45).timeout
	assert(starts.size() == 2 and controller.is_music_active(), "native finish must rearm exactly one subsequent entry")
	controller.music_player.seek(stream.get_length() - 0.12)
	await get_tree().create_timer(0.4).timeout
	assert(starts.size() == 2 and not controller.is_music_active(), "native completion must not loop or replay the same entry")
	controller.set_town_presence(false)
	controller.set_town_presence(true)
	await get_tree().create_timer(0.08).timeout
	assert(starts.size() == 3 and controller.is_music_active())
	var measurement_path := "user://outputs/test_logs/town_music_pcm_start_measurements.json"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://outputs/test_logs")
	)
	var measurement_file := FileAccess.open(measurement_path, FileAccess.WRITE)
	if measurement_file != null:
		measurement_file.store_string(JSON.stringify({
			"schema": "town_music_pcm_start_measurement.v1",
			"source": "tests/town_music_pcm_lifecycle_test.gd",
			"driver_name": AudioServer.get_driver_name(),
			"output_device": AudioServer.get_output_device() if AudioServer.has_method("get_output_device") else "",
			"mix_rate": AudioServer.get_mix_rate(),
			"speaker_mode": AudioServer.get_speaker_mode(),
			"stream_class": stream.get_class(),
			"stream_format": stream.format,
			"measurements": controller.play_measurements,
		}, "\t") + "\n")
		measurement_file.close()
	print("TOWN_MUSIC_PCM_START_MEASUREMENTS ", JSON.stringify(controller.play_measurements))
	controller.cancel("world_exit")
	assert(not controller.is_music_active() and not controller.is_delay_pending())
	controller.queue_free()
	print("TOWN_MUSIC_PCM_LIFECYCLE_PASS frames=%d natural_end/reentry/no_overlap/explicit_exit" % int(record.sample_frames))
	get_tree().quit(0)
