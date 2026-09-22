extends Node2D
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const Visual := preload("res://scripts/caster_skill_animation_player.gd")
const Prepared := preload("res://scripts/prepared_music_stream.gd")
const Music := preload("res://scripts/town_music_controller.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Registry.clear_frame_texture_cache()
	var visual := Visual.new()
	add_child(visual)
	assert(visual.configure("wizard.fire_wall", Vector2.DOWN, 0.0, true))
	visual.set_process(false)
	var frames: Array = Registry.animation_profile("wizard.fire_wall").sequences[0].frames
	var first_id := visual.texture.get_instance_id()
	var frame_ids: Array[int] = []
	var emitted: Array[int] = []
	visual.skill_frame_changed.connect(func(index: int) -> void: emitted.append(index))
	for cycle in range(3):
		for index in range(frames.size()):
			assert(visual._apply_frame(index))
			var expected_path := "res://" + str(frames[index].path)
			var reference := load(expected_path) as Texture2D
			assert(reference != null and visual.texture == reference, "Exact source texture must be drawn")
			if cycle == 0:
				frame_ids.append(visual.texture.get_instance_id())
			else:
				assert(frame_ids[index] == visual.texture.get_instance_id(), "Repeated loop must reuse each exact frame")
	assert(frame_ids[0] == first_id)
	assert(emitted.size() == frames.size() * 3, "Do not drop frame events to optimize animation")
	var diag := Registry.frame_texture_cache_diagnostics()
	assert(diag.loads == frames.size(), "Load each source frame once across loops")
	# Eviction must only remove cache ownership, never a sprite's live texture.
	var visible_texture := visual.texture
	var filler := ImageTexture.create_from_image(Image.create(1024, 1024, false, Image.FORMAT_RGBA8))
	for i in range(12):
		Registry._frame_texture_serial += 1
		Registry._retain_frame_texture("probe:budget:%d" % i, filler)
	assert(Registry.frame_texture_cache_diagnostics().resident_bytes <= Registry.TEXTURE_CACHE_BYTES)
	assert(visual.texture == visible_texture)
	Registry.clear_frame_texture_cache()
	var tiny := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for i in range(520):
		Registry._frame_texture_serial += 1
		Registry._retain_frame_texture("probe:entry:%d" % i, tiny)
	assert(Registry.frame_texture_cache_diagnostics().entries == Registry.TEXTURE_CACHE_ENTRIES)
	Registry.clear_frame_texture_cache()
	assert(Registry.load_texture_path("") == null)
	assert(Registry.load_texture_path("res://outputs/performance_v82/missing.png") == null)
	visual.queue_free()

	var original := load(Music.TOWN_MUSIC_PATH) as AudioStreamOggVorbis
	assert(original != null and not original.loop)
	var prepared := Prepared.new()
	prepared.source_stream = original
	prepared.prepare()
	var dormant: AudioStreamPlayback = prepared._prepared
	assert(dormant != null and not dormant.is_playing())
	prepared.prepare()
	assert(prepared._prepared == dormant, "Repeated preparation must not allocate/advance another decoder")
	var actual := prepared.instantiate_playback()
	assert(actual == dormant and prepared._prepared == null, "One prepared decoder is consumed once")
	assert(actual.get_class() == "AudioStreamPlaybackOggVorbis", "Mixing remains in the native decoder")
	assert(is_equal_approx(prepared.get_length(), original.get_length()))
	var reference := original.instantiate_playback()
	actual.start()
	reference.start()
	var audible := false
	for i in range(120):
		var a := actual.mix_audio(1.0, 4096)
		var b := reference.mix_audio(1.0, 4096)
		assert(a == b, "Prepared playback must match every original PCM sample")
		for value in a:
			if value.length_squared() > 0.000001:
				audible = true
	assert(audible, "PCM comparison must contain actual music, not only silence")
	actual.seek(original.get_length() - 0.1)
	reference.seek(original.get_length() - 0.1)
	for i in range(4):
		assert(actual.mix_audio(1.0, 4096) == reference.mix_audio(1.0, 4096))
	assert(not actual.is_playing() and not reference.is_playing(), "Native one-shot completion must be preserved")
	prepared.prepare()
	var replay := prepared.instantiate_playback()
	assert(replay != actual and not replay.is_playing(), "Each city entry gets a fresh decoder starting at zero")
	replay.start()
	var fresh := original.instantiate_playback()
	fresh.start()
	assert(replay.mix_audio(1.0, 4096) == fresh.mix_audio(1.0, 4096))
	replay.stop()
	fresh.stop()
	await get_tree().process_frame
	print("PERFORMANCE_V82_RESOURCE_REUSE_PASS")
	get_tree().quit(0)
