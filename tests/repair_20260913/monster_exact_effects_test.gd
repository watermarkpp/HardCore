extends Node
const Frames := preload("res://scripts/monster_source_frames.gd")
const Projectile := preload("res://scripts/monster_ranged_projectile_effect.gd")
const Magic := preload("res://scripts/monster_target_magic_effect.gd")
const Overlay := preload("res://scripts/monster_attack_source_overlay.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	for profile: Dictionary in Frames.data().profiles.values():
		await _wait_records(profile.frames)
	for id: int in [42, 50, 145, 174]: Projectile.prewarm_for_monster_id(id)
	var count := 0
	for id: int in [42,50,145,174]:
		for direction in range(16):
			var profile: Dictionary = Projectile._exact_sources.profiles["thorn" if id == 174 else "axe"]
			await _wait_records(profile.frames.slice(direction * 3, direction * 3 + 3))
			var effect := Projectile.create_visual({"effect_id":Projectile.EFFECT_ID,"source_monster_id":id,"origin_world_px":Vector2.ZERO,"target_world_px":Vector2.RIGHT * 100})
			effect._direction16 = direction
			add_child(effect)
			effect.set_process(false)
			for frame in range(3):
				effect._elapsed_seconds = frame * 0.05 + 0.001
				effect._update_exact_frame()
				assert(effect._sprite.texture != null)
				assert(effect._source_frame_index == (2967 if id == 174 else 447) + direction * 10 + frame)
				assert(effect.z_index == 0)
				count += 1
			effect.free()
	var body_only := Projectile.create_visual({"effect_id":Projectile.EFFECT_ID,"source_monster_id":62})
	assert(not body_only.visible)
	body_only.free()
	for id: int in [150,151,152,186,194,206,207]:
		var arrow := Projectile.create_visual({"effect_id":Projectile.EFFECT_ID,"source_monster_id":id,"target_world_px":Vector2.RIGHT * 100})
		add_child(arrow)
		assert(arrow._exact_profile.is_empty() and arrow._sprite.texture != null)
		arrow.free()
	for key: String in Frames.data().profile_by_monster_id:
		var id := int(key)
		var actor := EnemyActor.new()
		actor.setup(GameData.get_monster_by_id(id), null, false)
		add_child(actor)
		actor.set_physics_process(false)
		actor.visual.play_attack(0.6)
		var overlay: Node2D
		for child: Node in actor.visual.get_children():
			if child.get_script() == Overlay: overlay = child
		assert(overlay != null, "real monster attack creates exact overlay ID=%d" % id)
		overlay.set_process(false)
		await _wait_records(overlay.profile.frames.slice(overlay.direction * int(overlay.profile.frame_count), (overlay.direction + 1) * int(overlay.profile.frame_count)))
		for frame in range(int(overlay.profile.frame_count)):
			overlay.elapsed = overlay.start_delay + frame * overlay.frame_seconds + 0.001
			overlay._process(0)
			assert(overlay.sprite.texture != null)
			assert(overlay.sprite.material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD)
			count += 1
		overlay.free()
		actor.free()
	var king := Magic.create_visual({"effect_id":Magic.EFFECT_ID,"source_monster_id":224,"source_world_px":Vector2.ZERO,"target_world_px":Vector2(100,100)})
	add_child(king)
	king.set_process(false)
	await _wait_records(king._king_frames)
	for frame in range(20):
		king._elapsed_seconds = Magic.CLIENT_MAGIC_RELEASE_SECONDS + frame * 0.02 + 0.001
		king._update_presentation()
		assert(king._target_sprite.texture != null and king._target_sprite.visible)
		assert(king.z_index == 0 and king.y_sort_enabled)
		count += 1
	king.free()
	print("MONSTER_EXACT_EFFECTS_PASS frames=%d real_attack_overlays=13 king_mt13=20 physical_damage_untouched=true" % count)
	get_tree().quit()

func _wait_records(records: Array) -> void:
	for record: Dictionary in records: Frames.request(str(record.path))
	var limit := Time.get_ticks_msec() + 10000
	var ready := false
	while not ready and Time.get_ticks_msec() < limit:
		ready = true
		for record: Dictionary in records:
			if Frames.texture(str(record.path)) == null: ready = false
		assert(Frames._requested.size() <= Frames.MAX_IN_FLIGHT)
		assert(Frames._resident_bytes <= Frames.CACHE_BUDGET)
		await get_tree().process_frame
	assert(ready, "bounded background source-frame decoding")
