extends Node

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)


func _ready() -> void:
	_test_circle_boundary_contact_and_projection()
	_test_target_footprint_exact_projection()
	_test_sector_arc_all_directions()
	_test_swept_capsule_path_boundary()
	print("MONSTER_ATTACK_FOOTPRINT_SNAPSHOT_PASS")
	get_tree().quit(0)


func _test_circle_boundary_contact_and_projection() -> void:
	const RADIUS_GU := 3.0
	for direction_index in range(8):
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 8.0)
		var release_id := "test:circle:%d" % direction_index
		var snapshot := SkillFootprintSnapshotScript.create_circle(
			"monster.test.circle",
			release_id,
			Vector2(5.0, -2.0),
			RADIUS_GU,
		)
		assert(snapshot.is_read_only(), "monster circle snapshot must be read-only")
		assert(SkillFootprintSnapshotScript.has_legacy_base_contract(snapshot))
		assert(str(snapshot.release_id) == release_id)
		for target_radius_gu: float in [0.25, 0.33, 0.50]:
			var edge_center: Vector2 = (
				Vector2(5.0, -2.0)
				+ direction_ground * (RADIUS_GU + target_radius_gu - 0.00005)
			)
			assert(
				SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
					snapshot,
					edge_center,
					target_radius_gu,
				),
				"circle boundary contact rejected in direction %d" % direction_index,
			)
			var outside_center: Vector2 = (
				Vector2(5.0, -2.0)
				+ direction_ground * (RADIUS_GU + target_radius_gu + 0.01)
			)
			assert(
				not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
					snapshot,
					outside_center,
					target_radius_gu,
				),
				"circle attack expanded beyond its formal GU radius",
			)
		var polygon_ground := SkillFootprintSnapshotScript.ground_polygon_gu(snapshot)
		var polygon_px := SkillFootprintSnapshotScript.projected_polygon_screen_offset_px(snapshot)
		assert(polygon_ground.size() == polygon_px.size())
		for point_index in range(polygon_ground.size()):
			var recovered_ground_delta := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
				polygon_px[point_index]
			)
			assert(
				recovered_ground_delta.distance_to(
					polygon_ground[point_index] - Vector2(5.0, -2.0)
				) <= 0.00001,
				"circle visual projection diverged from damage polygon",
			)


func _test_target_footprint_exact_projection() -> void:
	const TARGET_RADIUS_GU := 0.33
	const TARGET_CENTER_GROUND_GU := Vector2(1.5, 0.0)
	var snapshot := SkillFootprintSnapshotScript.create_target_footprint(
		"monster.test.target",
		"test:target:1",
		TARGET_CENTER_GROUND_GU,
		TARGET_RADIUS_GU,
		99,
	)
	assert(str(snapshot.shape_type) == SkillFootprintSnapshotScript.SHAPE_TARGET_FOOTPRINT)
	assert(int(snapshot.target_instance_id) == 99)
	assert(
		SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			snapshot,
			TARGET_CENTER_GROUND_GU,
			TARGET_RADIUS_GU,
		),
		"target-footprint snapshot does not cover the selected target footprint",
	)
	assert(
		not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			snapshot,
			TARGET_CENTER_GROUND_GU + Vector2(TARGET_RADIUS_GU * 2.0 + 0.01, 0.0),
			TARGET_RADIUS_GU,
		),
		"target-footprint snapshot expanded beyond the two actor radii",
	)


func _test_sector_arc_all_directions() -> void:
	const RADIUS_GU := 4.0
	const TARGET_RADIUS_GU := 0.25
	for direction_index in range(8):
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 8.0)
		var snapshot := SkillFootprintSnapshotScript.create_sector_arc(
			"monster.test.sector",
			"test:sector:%d" % direction_index,
			Vector2.ZERO,
			direction_ground,
			RADIUS_GU,
			0.68,
		)
		assert(SkillFootprintSnapshotScript.has_legacy_base_contract(snapshot))
		assert(
			SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
				snapshot,
				direction_ground * (RADIUS_GU + TARGET_RADIUS_GU - 0.01),
				TARGET_RADIUS_GU,
			),
			"sector axis boundary rejected in direction %d" % direction_index,
		)
		assert(
			not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
				snapshot,
				-direction_ground * 1.0,
				0.10,
			),
			"sector accepted a target behind the attacker",
		)


func _test_swept_capsule_path_boundary() -> void:
	const PROJECTILE_RADIUS_GU := 0.20
	const TARGET_RADIUS_GU := 0.30
	var snapshot := SkillFootprintSnapshotScript.create_swept_capsule_path(
		"monster.test.projectile",
		"test:projectile:1",
		Vector2(-2.0, 1.0),
		Vector2(3.0, 1.0),
		PROJECTILE_RADIUS_GU,
	)
	assert(str(snapshot.shape_type) == SkillFootprintSnapshotScript.SHAPE_SWEPT_CAPSULE_PATH)
	assert(
		SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			snapshot,
			Vector2(0.0, 1.0 + PROJECTILE_RADIUS_GU + TARGET_RADIUS_GU - 0.00005),
			TARGET_RADIUS_GU,
		),
		"swept projectile lost inclusive target-footprint contact",
	)
	assert(
		not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			snapshot,
			Vector2(0.0, 1.0 + PROJECTILE_RADIUS_GU + TARGET_RADIUS_GU + 0.01),
			TARGET_RADIUS_GU,
		),
		"swept projectile expanded beyond projectile plus target radii",
	)
