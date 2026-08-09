extends Node

const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const CombatUnitLegacyAdapter := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_talisman_from_hand_along_direction()
	_test_wizard_projectile_policy_unchanged()
	print(
		"TAOIST_SUMMON_PROJECTILE_ORIGIN_ANCHOR_PASS: soul fire talisman keeps "
		+ "canonical gameplay origin, drops the 24px/top-left muzzle combo and "
		+ "anchors from the directional hand draw offset; wizard policy unchanged"
	)
	get_tree().quit(0)


func _test_talisman_from_hand_along_direction() -> void:
	var origin := Vector2(320.0, 240.0)
	var direction_screen := Vector2.RIGHT
	var projectile := SkillProjectile.new()
	projectile.setup_ground_unit_projectile(
		origin,
		GroundUnitSpace.screen_delta_px_to_ground_delta_gu(direction_screen),
		9.0,
		24,
		CombatUnitLegacyAdapter.PROJECTILE_SPEED_GU_PER_SEC,
		CombatUnitLegacyAdapter.PROJECTILE_RADIUS_GU,
		direction_screen * 24.0,
		Color.YELLOW,
		"damage",
		0,
		0.0,
		"taoist.soul_fire_talisman"
	)
	add_child(projectile)
	assert(
		projectile.global_position == origin,
		"canonical gameplay release origin must stay at the player foot"
	)
	assert(
		projectile.visual_muzzle_offset_px == Vector2(24.0, 0.0),
		"muzzle offset field contract must stay untouched"
	)
	assert(
		projectile._sprite != null and projectile._sprite.visual_loaded,
		"talisman visual must load"
	)
	assert(
		projectile._sprite.position == Vector2.ZERO,
		"the 24px muzzle offset must not shift the talisman visual"
	)
	assert(
		projectile._sprite._anchor_policy == "source_draw_offset_from_actor_foot",
		"talisman must anchor at the actor foot/hand draw offset, not top-left"
	)
	var expected_center := _expected_frame_center(
		"taoist.soul_fire_talisman",
		projectile._sprite.direction_index
	)
	assert(
		projectile._sprite.offset.is_equal_approx(expected_center),
		"talisman sprite offset must come from the directional source_draw_offset"
	)
	assert(
		projectile._sprite.offset.y < 0.0 and projectile._sprite.offset.x > 0.0,
		"talisman must start at hand height in front of the body"
	)
	assert(
		projectile.direction_ground_gu.is_equal_approx(
			GroundUnitSpace.screen_delta_px_to_ground_delta_gu(
				direction_screen
			).normalized()
		),
		"talisman ground direction must stay unchanged"
	)
	assert(projectile.max_travel_distance_gu == 9.0)
	assert(projectile.damage == 24)
	projectile.queue_free()


func _test_wizard_projectile_policy_unchanged() -> void:
	var projectile := SkillProjectile.new()
	projectile.setup_ground_unit_projectile(
		Vector2(100.0, 200.0),
		GroundUnitSpace.screen_delta_px_to_ground_delta_gu(Vector2.RIGHT),
		9.0,
		24,
		CombatUnitLegacyAdapter.PROJECTILE_SPEED_GU_PER_SEC,
		CombatUnitLegacyAdapter.PROJECTILE_RADIUS_GU,
		Vector2.RIGHT * 24.0,
		Color.CYAN,
		"damage",
		0,
		0.0,
		"wizard.fireball"
	)
	add_child(projectile)
	assert(
		projectile._sprite != null and projectile._sprite.visual_loaded,
		"wizard fireball visual must still load"
	)
	assert(
		projectile._sprite._anchor_policy == "top_left_from_world_anchor",
		"wizard projectile presentation policy must remain unchanged"
	)
	assert(
		projectile._sprite.position == Vector2.RIGHT * 24.0,
		"wizard projectile keeps its existing muzzle presentation offset"
	)
	projectile.queue_free()


func _expected_frame_center(skill_id: String, direction_index: int) -> Vector2:
	var file := FileAccess.open(
		"res://assets/data/caster_skill_visuals.json",
		FileAccess.READ
	)
	assert(file != null, "caster skill visual manifest must exist")
	var manifest: Variant = JSON.parse_string(file.get_as_text())
	assert(manifest is Dictionary)
	var coverage: Dictionary = manifest.skillCoverage[skill_id]
	var asset_id := str(coverage.get("asset_id", ""))
	var asset: Dictionary = manifest.assets[asset_id]
	var sequences: Array = asset.animation.sequences
	for sequence: Dictionary in sequences:
		if int(sequence.get("direction_index", -1)) != direction_index:
			continue
		var frames: Array = sequence.get("frames", [])
		assert(not frames.is_empty())
		var first: Dictionary = frames[0]
		var source_draw_offset: Array = first.get("source_draw_offset", [0, 0])
		var pixel_size: Array = first.get("pixel_size", [0, 0])
		return Vector2(
			float(source_draw_offset[0]) + float(pixel_size[0]) * 0.5,
			float(source_draw_offset[1]) + float(pixel_size[1]) * 0.5
		)
	assert(false, "missing direction sequence for %s" % skill_id)
	return Vector2.ZERO
