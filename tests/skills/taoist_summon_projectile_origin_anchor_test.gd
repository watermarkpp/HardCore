extends Node

const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const CombatUnitLegacyAdapter := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_talisman_from_hand_in_all_sixteen_directions()
	_test_wizard_projectile_policy_unchanged()
	print(
		"TAOIST_SUMMON_PROJECTILE_ORIGIN_ANCHOR_PASS: soul fire talisman keeps "
		+ "canonical gameplay origin and uses a close torso/hand presentation "
		+ "anchor in all 16 directions; wizard policy unchanged"
	)
	get_tree().quit(0)


func _test_talisman_from_hand_in_all_sixteen_directions() -> void:
	var origin := Vector2(320.0, 240.0)
	var observed_direction_indices: Array[int] = []
	for sample_index: int in range(16):
		var direction_screen := Vector2.UP.rotated(
			TAU * float(sample_index) / 16.0
		)
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
			projectile.visual_muzzle_offset_px.is_equal_approx(
				direction_screen.normalized() * 24.0
			),
			"muzzle offset field contract must stay untouched"
		)
		assert(
			projectile._sprite != null and projectile._sprite.visual_loaded,
			"talisman visual must load"
		)
		observed_direction_indices.append(projectile._sprite.direction_index)
		assert(
			projectile._sprite._anchor_policy
				== "center_sequence_bounds_on_geometry_origin",
			"raw Magic.wil draw coordinates must not masquerade as a hand socket"
		)
		assert(
			projectile._sprite.visual_bounds_center().is_zero_approx(),
			"primary-client pixels must be centred on the presentation node"
		)
		var expected_anchor := (
			SkillProjectile
			.soul_fire_talisman_presentation_launch_anchor_px(
				projectile.direction_screen_px
			)
		)
		assert(projectile._sprite.position == expected_anchor)
		assert(
			absf(expected_anchor.x) <= 12.0
			and expected_anchor.y >= -40.0
			and expected_anchor.y <= -28.0,
			"talisman presentation must stay close to the torso/hand, not the head"
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
	observed_direction_indices.sort()
	assert(observed_direction_indices == range(16), "all 16 source directions required")


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
