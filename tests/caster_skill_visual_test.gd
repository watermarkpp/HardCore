extends Node

const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const CombatUnitLegacyAdapter := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)


class ShieldOwner:
	extends Node2D
	var shield_active := true

	func magic_shield_snapshot() -> Dictionary:
		return {"active": shield_active}


func _ready() -> void:
	var file := FileAccess.open("res://assets/data/caster_skill_visuals.json", FileAccess.READ)
	var manifest: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(manifest is Dictionary)
	assert(manifest.target_gender == "male_only")
	assert(manifest.primarySource.distribution_id == "client.classic_raw_complete")
	assert(manifest.primarySource.source_priority.tier == "primary" and manifest.primarySource.source_priority.weight == 100)
	assert(manifest.primary_missing_evidence.is_empty())
	assert(manifest.generated_candidates_retained.is_empty())
	assert(manifest.schemaVersion == 4)
	assert(manifest.animationContract == "caster_skill_animation.v1")
	assert(manifest.renderContract == "caster_skill_render.v2")
	assert(manifest.fallbacks_used.is_empty())
	assert(manifest.primarySource.custom_library_layout == false)
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
		assert(entry.render.contract == "caster_skill_render.v2")
		assert(int(entry.animation.frame_count) > 0 and int(entry.animation.direction_count) > 0)
		assert(entry.animation.sequences.size() == int(entry.animation.direction_count))
		var decoded_frames := 0
		for sequence: Dictionary in entry.animation.sequences:
			assert(sequence.frames.size() == int(entry.animation.frame_count))
			for frame: Dictionary in sequence.frames:
				decoded_frames += 1
				assert(int(frame.source_index) >= 0)
				assert(FileAccess.file_exists("res://%s" % frame.path))
				assert(not str(frame.png_sha256).is_empty())
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
		projectile.setup_ground_unit_projectile(
			Vector2.ZERO,
			GroundUnitSpace.screen_delta_px_to_ground_delta_gu(Vector2.RIGHT),
			3.125,
			10,
			CombatUnitLegacyAdapter.PROJECTILE_SPEED_GU_PER_SEC,
			CombatUnitLegacyAdapter.PROJECTILE_RADIUS_GU,
			Vector2.ZERO,
			Color.CYAN,
			"damage",
			0,
			0.0,
			skill_id
		)
		add_child(projectile)
		assert(projectile.skill_id == skill_id and projectile._sprite != null)
		assert(projectile._sprite.visual_loaded)
		projectile.queue_free()
	for skill_id: String in GroundSkillEffect.VISUAL_PATHS:
		var area := GroundSkillEffect.new()
		area.setup_ground_unit_effect(
			Vector2.ZERO, 1, 0.5, 1.0, Color.CYAN, skill_id, 0.8, 72.0
		)
		add_child(area)
		assert(area.skill_id == skill_id and area._sprite != null)
		assert(area._sprite.visual_loaded)
		area.queue_free()
	for skill_id: String in CasterSkillVisualRegistry.active_skill_ids():
		var profile := CasterSkillVisualRegistry.profile(skill_id)
		if profile.role in ["summon_actor_visual", "projectile", "ground_effect"]:
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
	assert(CasterSkillVisualRegistry.direction_index(Vector2(4.0, -1.0)) == 4)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(4.0, -1.01)) == 3)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(1.0, -4.01)) == 0)
	var directional := AnimationPlayerScript.new()
	add_child(directional)
	assert(directional.configure("wizard.fireball", Vector2.LEFT, 34.0, true))
	assert(directional.direction_index == 12 and directional.visual_loaded)
	var original_texture: Texture2D = directional.texture
	directional._process(0.051)
	assert(directional.current_frame_index == 1 and directional.texture != original_texture)
	directional.queue_free()
	var teleport_arrival := AnimationPlayerScript.new()
	add_child(teleport_arrival)
	assert(teleport_arrival.configure("wizard.teleport", Vector2.DOWN, 0.0, null, "arrival"))
	assert(teleport_arrival.frame_count() == 10)
	assert(teleport_arrival.texture.get_width() > 0)
	teleport_arrival.queue_free()
	var shield_owner := ShieldOwner.new()
	add_child(shield_owner)
	shield_owner.global_position = Vector2(123.4, 77.6)
	var shield_visual := CasterSkillVisualEffect.new()
	shield_visual.setup(
		Vector2.ZERO,
		"wizard.magic_shield",
		72.0,
		1.0,
		Vector2.DOWN,
		shield_owner
	)
	add_child(shield_visual)
	assert(is_equal_approx(shield_visual.global_position.x, 123.4))
	assert(is_equal_approx(shield_visual.global_position.y, 77.6 - 0.001))
	assert(shield_visual.is_persistent_magic_shield_visual())
	assert(shield_visual.get_meta(
		"magic_shield_visual_contract", ""
	) == "skills.wizard.magic_shield.primary_actor_footpoint_centered_behind_body.v1")
	var shield_sprite: CasterSkillAnimationPlayer = shield_visual._sprites[0]
	var shield_render := CasterSkillVisualRegistry.render_policy(
		"wizard.magic_shield"
	)
	assert(shield_render.anchor_policy == "top_left_from_world_anchor")
	assert(shield_render.anchor_rebase_pixels == [7.5, 0.0])
	assert(shield_render.attachment_draw_order == "behind_attached_actor_same_footpoint")
	assert(shield_sprite.fitted_visual_bounds().position == Vector2(-34.5, -80.0))
	# Both sides of a half-pixel boundary must keep exactly the same ordering.
	# The old rounded shield key sorted behind at .4 and in front at .6, which
	# made the actor disappear while stationary and flicker while moving.
	for owner_position: Vector2 in [
		Vector2(123.4, 77.4),
		Vector2(123.4, 77.6),
		Vector2(123.4, 78.1),
	]:
		shield_owner.global_position = owner_position
		shield_visual._process(0.0)
		assert(is_equal_approx(shield_visual.global_position.x, owner_position.x))
		assert(is_equal_approx(
			shield_visual.global_position.y,
			owner_position.y - 0.001
		))
		assert(shield_visual.global_position.y < shield_owner.global_position.y)
	shield_sprite._process(shield_sprite.animation_duration() + 0.01)
	shield_visual._process(0.1)
	assert(shield_sprite.playback_complete)
	assert(shield_sprite.current_frame_index == shield_sprite.frame_count() - 1)
	assert(not shield_visual.is_queued_for_deletion())
	shield_owner.shield_active = false
	shield_visual._process(0.01)
	assert(shield_visual.is_queued_for_deletion())
	shield_owner.queue_free()
	print("CASTER_SKILL_VISUAL_PASS: 26 exact primary-client animations/icons cover 26 active caster skills; one passive has no cast visual; zero fallbacks; male-only")
	get_tree().quit(0)
