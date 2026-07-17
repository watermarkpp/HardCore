extends Node


func _ready() -> void:
	var file := FileAccess.open("res://assets/data/caster_skill_visuals.json", FileAccess.READ)
	var manifest: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(manifest is Dictionary)
	assert(manifest.target_gender == "male_only")
	assert(manifest.primarySource.distribution_id == "client.classic_raw_complete")
	assert(manifest.primarySource.source_priority.tier == "primary" and manifest.primarySource.source_priority.weight == 100)
	assert(manifest.primary_missing_evidence.is_empty())
	assert(manifest.generated_candidates_retained.is_empty())
	assert(manifest.assets.size() == 25)
	assert(manifest.skillCoverage.size() == 27)
	assert(manifest.skillCoverage["taoist.spiritual_warfare"].status == "no_runtime_visual")
	var formal_skill_count := 0
	for skill_id: String in manifest.skillCoverage:
		var coverage: Dictionary = manifest.skillCoverage[skill_id]
		if coverage.status == "formal_primary_client_pixel":
			formal_skill_count += 1
			assert(CasterSkillVisualRegistry.has_formal_visual(skill_id), "%s formal visual is unavailable" % skill_id)
	assert(formal_skill_count == 26)
	for asset_id: String in manifest.assets:
		var entry: Dictionary = manifest.assets[asset_id]
		assert(entry.distribution_id == "client.classic_raw_complete")
		assert(entry.source_priority.tier == "primary")
		assert(str(entry.original_path).begins_with("Data/"))
		assert(int(entry.source_index) >= 0 and not str(entry.source_sha256).is_empty())
		var path := "res://%s" % entry.path
		assert(ResourceLoader.exists(path), "%s was not imported" % path)
		var texture := load(path) as Texture2D
		assert(texture != null and texture.get_width() == int(entry.pixel_size[0]) and texture.get_height() == int(entry.pixel_size[1]))
		assert(not texture.get_image().is_empty())

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession(ProfessionRules.profession_display_name("wizard"))
	for skill_id: String in SkillProjectile.VISUAL_PATHS:
		var projectile := SkillProjectile.new()
		projectile.setup(Vector2.ZERO, Vector2.RIGHT, 10, 100.0, Color.CYAN, "damage", 0, 0.0, skill_id)
		add_child(projectile)
		assert(projectile.skill_id == skill_id and projectile._sprite != null)
		projectile.queue_free()
	for skill_id: String in GroundSkillEffect.VISUAL_PATHS:
		var area := GroundSkillEffect.new()
		area.setup(Vector2.ZERO, 1, 72.0, 1.0, Color.CYAN, skill_id)
		add_child(area)
		assert(area.skill_id == skill_id and area._sprite != null)
		area.queue_free()
	for skill_id: String in CasterSkillVisualRegistry.active_skill_ids():
		var visual := CasterSkillVisualEffect.new()
		visual.setup(Vector2.ZERO, skill_id, 72.0, 1.0)
		add_child(visual)
		assert(visual.skill_id == skill_id and visual.visual_loaded, "%s generic runtime visual did not load" % skill_id)
		visual.queue_free()
	print("CASTER_SKILL_VISUAL_PASS: 25 exact primary-client assets cover 26 active caster skills; one passive has no cast visual; zero generated fallbacks; male-only")
	get_tree().quit(0)
