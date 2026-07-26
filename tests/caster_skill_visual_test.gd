extends Node

const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")


func _ready() -> void:
	var file := FileAccess.open("res://assets/data/caster_skill_visuals.json", FileAccess.READ)
	var manifest: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(manifest is Dictionary)
	assert(manifest.target_gender == "male_only")
	assert(manifest.primarySource.distribution_id == "client.classic_raw_complete")
	assert(manifest.primarySource.source_priority.tier == "primary" and manifest.primarySource.source_priority.weight == 100)
	assert(manifest.primary_missing_evidence.is_empty())
	assert(manifest.generated_candidates_retained.is_empty())
	assert(manifest.schemaVersion == 3)
	assert(manifest.animationContract == "caster_skill_animation.v1")
	assert(manifest.assets.size() == 26)
	assert(manifest.skillCoverage.size() == 27)
	assert(manifest.skillCoverage["taoist.spiritual_warfare"].status == "no_runtime_visual")
	var formal_skill_count := 0
	for skill_id: String in manifest.skillCoverage:
		var coverage: Dictionary = manifest.skillCoverage[skill_id]
		if coverage.status == "formal_primary_client_animation":
			formal_skill_count += 1
			assert(CasterSkillVisualRegistry.has_formal_visual(skill_id), "%s formal visual is unavailable" % skill_id)
	assert(formal_skill_count == 26)
	for asset_id: String in manifest.assets:
		var entry: Dictionary = manifest.assets[asset_id]
		assert(entry.distribution_id == "client.classic_raw_complete")
		assert(entry.source_priority.tier == "primary")
		assert(str(entry.original_path).begins_with("Data/"))
		assert(not str(entry.source_sha256).is_empty())
		assert(entry.animation.contract == "caster_skill_animation.v1")
		assert(int(entry.animation.frame_count) > 0 and int(entry.animation.direction_count) > 0)
		assert(entry.animation.sequences.size() == int(entry.animation.direction_count))
		var decoded_frames := 0
		for sequence: Dictionary in entry.animation.sequences:
			assert(sequence.frames.size() == int(entry.animation.frame_count))
			for frame: Dictionary in sequence.frames:
				decoded_frames += 1
				assert(int(frame.source_index) >= 0)
				assert(FileAccess.file_exists("res://%s" % frame.path))
		assert(decoded_frames == int(entry.animation.frame_count) * int(entry.animation.direction_count))
		var path := "res://%s" % entry.path
		assert(FileAccess.file_exists(path), "%s source PNG is missing" % path)
		var texture := CasterSkillVisualRegistry.load_texture_path(path)
		assert(texture != null)
		assert(not texture.get_image().is_empty())
		assert(entry.icon.derived_only_from_animation_frame)
		assert(str(entry.icon.selection_rule).contains("luminance_stddev"))
		assert(str(entry.icon.transform).contains("transparent_96x96_center"))
		assert(int(entry.icon.selection_metrics.opaque_pixels) > 0)
		assert(float(entry.icon.selection_metrics.endpoint_filter_ratio) == 0.45)
		var icon := CasterSkillVisualRegistry.load_texture_path("res://%s" % entry.icon.path)
		assert(icon != null and icon.get_width() == 96 and icon.get_height() == 96)

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession(ProfessionRules.profession_display_name("wizard"))
	for skill_id: String in SkillProjectile.VISUAL_PATHS:
		var projectile := SkillProjectile.new()
		projectile.setup(Vector2.ZERO, Vector2.RIGHT, 10, 100.0, Color.CYAN, "damage", 0, 0.0, skill_id)
		add_child(projectile)
		assert(projectile.skill_id == skill_id and projectile._sprite != null)
		assert(projectile._sprite.visual_loaded)
		projectile.queue_free()
	for skill_id: String in GroundSkillEffect.VISUAL_PATHS:
		var area := GroundSkillEffect.new()
		area.setup(Vector2.ZERO, 1, 72.0, 1.0, Color.CYAN, skill_id)
		add_child(area)
		assert(area.skill_id == skill_id and area._sprite != null)
		assert(area._sprite.visual_loaded)
		area.queue_free()
	for skill_id: String in CasterSkillVisualRegistry.active_skill_ids():
		var profile := CasterSkillVisualRegistry.profile(skill_id)
		if profile.role == "summon_actor_visual":
			continue
		var visual := CasterSkillVisualEffect.new()
		visual.setup(Vector2.ZERO, skill_id, 72.0, 1.0)
		add_child(visual)
		assert(visual.skill_id == skill_id and visual.visual_loaded, "%s generic runtime visual did not load" % skill_id)
		visual.queue_free()

	assert(CasterSkillVisualRegistry.direction_index(Vector2.UP) == 0)
	assert(CasterSkillVisualRegistry.direction_index(Vector2.RIGHT) == 4)
	assert(CasterSkillVisualRegistry.direction_index(Vector2.DOWN) == 8)
	assert(CasterSkillVisualRegistry.direction_index(Vector2.LEFT) == 12)
	var directional := AnimationPlayerScript.new()
	add_child(directional)
	assert(directional.configure("wizard.fireball", Vector2.LEFT, 34.0, true))
	assert(directional.direction_index == 12 and directional.visual_loaded)
	var original_texture: Texture2D = directional.texture
	directional._process(0.051)
	assert(directional.current_frame_index == 1 and directional.texture != original_texture)
	directional.queue_free()
	print("CASTER_SKILL_VISUAL_PASS: 26 exact primary-client animations/icons cover 26 active caster skills; one passive has no cast visual; zero fallbacks; male-only")
	get_tree().quit(0)
