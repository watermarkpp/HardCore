extends Node

const Controller := preload("res://scripts/town_music_controller.gd")

func _ready() -> void:
	_run.call_deferred()

func _enter(controller: Node, transition: String) -> void:
	controller.begin_map_transition(910001, transition)
	assert(controller.set_map_context(910001,
		[{"shape": "circle", "center_ground_gu": Vector2.ZERO, "radius_gu": 9.0}], Vector2.ZERO, transition))
	assert(controller.on_loading_transition_finished({
		"contract_id": "ui.loading.transition.v1", "transition_id": transition}))

func _run() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/town/main_city_bgm.playback.json"))
	assert(FileAccess.get_sha256(record.source_path) == record.source_sha256)
	var controller := Controller.new()
	add_child(controller)
	controller.delay_seconds = 0.02
	var starts: Array[Dictionary] = []
	controller.music_started.connect(func(event: Dictionary): starts.append(event))
	var stream := controller.music_player.stream as AudioStreamWAV
	assert(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS,
		"town playback must be native uncompressed PCM without runtime Vorbis setup")
	assert(stream.stereo and stream.mix_rate == record.sample_rate_hz)
	assert(stream.data.size() == int(record.sample_frames) * 4)
	assert(absf(stream.get_length() - float(record.duration_seconds)) < 1.0 / 44100.0)
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
	controller.cancel("world_exit")
	assert(not controller.is_music_active() and not controller.is_delay_pending())
	controller.queue_free()
	print("TOWN_MUSIC_PCM_LIFECYCLE_PASS frames=%d natural_end/reentry/no_overlap/explicit_exit" % int(record.sample_frames))
	get_tree().quit(0)
