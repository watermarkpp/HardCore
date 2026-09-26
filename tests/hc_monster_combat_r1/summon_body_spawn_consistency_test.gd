extends Node

const ActorBodyPolicyScript := preload("res://scripts/actor_body_policy.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")


## HC-BODY-2TIER-1P5-V1 summon body consistency tests.
## Skeleton and divine beast resolve their bodies from the same two-tier
## policy as monsters, own the shared 16-point isometric footsole (no legacy
## screen circle), and keep the spawn footprint snapshot consistent with the
## physical shape across respawn/re-spawn.


func _configure_summon_map(summon: SummonActor) -> void:
	summon.configure_runtime_map_projection(
		9001,
		Callable(self, "_test_ground_to_screen"),
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu
	)


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _ready() -> void:
	var owner := PlayerCharacter.new()
	owner.current_hp = 100
	add_child(owner)

	var skeleton := SummonActor.new()
	skeleton.setup(owner, "变异骷髅", 30, 3, "taoist.summon_skeleton", 26)
	add_child(skeleton)
	_configure_summon_map(skeleton)
	await get_tree().process_frame

	var beast := SummonActor.new()
	beast.setup(owner, "神兽", 30, 3, "taoist.summon_divine_beast", 40)
	add_child(beast)
	_configure_summon_map(beast)
	await get_tree().process_frame

	var small_px := ActorBodyPolicyScript.tier_screen_radius_px(ActorBodyPolicyScript.TIER_SMALL)
	var large_px := ActorBodyPolicyScript.tier_screen_radius_px(ActorBodyPolicyScript.TIER_LARGE)
	var iso_denominator := 32.0 * sqrt(2.0)

	# Body tier ownership and single consistent convention.
	assert(is_equal_approx(float(skeleton.collision_radius_px), small_px), "skeleton must own the small tier radius")
	assert(
		is_equal_approx(float(skeleton.combat_radius_gu), small_px / iso_denominator),
		"skeleton combat radius must use the isometric conversion"
	)
	assert(is_equal_approx(float(beast.collision_radius_px), large_px), "divine beast must own the large tier radius")
	assert(
		is_equal_approx(float(beast.combat_radius_gu), large_px / iso_denominator),
		"divine beast combat radius must use the isometric conversion"
	)

	for summon: SummonActor in [skeleton, beast]:
		var shapes: Array[Node] = summon.find_children("CollisionShape2D", "CollisionShape2D", false, false)
		assert(shapes.size() == 1, "summon must own exactly one footsole shape")
		var collision := shapes[0] as CollisionShape2D
		assert(collision.shape is ConvexPolygonShape2D, "the legacy screen circle must be replaced by the isometric polygon")
		var polygon := collision.shape as ConvexPolygonShape2D
		assert(polygon.points.size() == 16, "summon footsole must keep 16 vertices")
		assert(collision.position == Vector2.ZERO and collision.scale == Vector2.ONE, "summon footsole must keep identity transform")
		var ground_radius := float(summon.combat_radius_gu)
		for point in polygon.points:
			var vertex_gu := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(point)
			assert(
				absf(vertex_gu.length() - ground_radius) <= 0.00001,
				"summon footsole vertex diverges from the declared ground radius"
			)

	# Spawn footprint consistency: the snapshot taken at spawn uses the same
	# resolved combat radius as the physical body. HC-MONSTER-COMBAT-R2 T6:
	# the old "or snapshot.is_empty()" exemption is gone - a mapped summon
	# must produce a REAL non-empty spawn snapshot.
	for summon: SummonActor in [skeleton, beast]:
		summon.configure_spawn_release_footprint(
			"%s:release:census" % summon.skill_id
		)
		var snapshot: Dictionary = summon.summon_spawn_footprint_snapshot
		assert(
			not snapshot.is_empty(),
			"a mapped summon must produce a real spawn footprint snapshot"
		)
		assert(
			is_equal_approx(
				float(snapshot.get("target_combat_radius_gu", -1.0)),
				float(summon.combat_radius_gu),
			),
			"summon spawn footprint radius must match the physical body"
		)
		assert(
			not str(snapshot.get("release_id", "")).is_empty(),
			"the spawn snapshot must own its release id"
		)

	# Re-spawn consistency: re-entering the tree re-resolves the same body
	# and a fresh real spawn snapshot.
	var beast_radius_before := float(beast.collision_radius_px)
	beast.queue_free()
	var beast2 := SummonActor.new()
	beast2.setup(owner, "神兽", 30, 3, "taoist.summon_divine_beast", 40)
	add_child(beast2)
	_configure_summon_map(beast2)
	await get_tree().process_frame
	assert(
		is_equal_approx(float(beast2.collision_radius_px), beast_radius_before),
		"a re-summoned divine beast must resolve the identical body"
	)
	beast2.configure_spawn_release_footprint("taoist.summon_divine_beast:release:census2")
	assert(
		not beast2.summon_spawn_footprint_snapshot.is_empty()
		and is_equal_approx(
			float(beast2.summon_spawn_footprint_snapshot.get("target_combat_radius_gu", -1.0)),
			float(beast2.combat_radius_gu),
		),
		"a re-summoned divine beast must snapshot a real matching footprint"
	)

	skeleton.queue_free()
	beast2.queue_free()
	owner.queue_free()
	print("HC_SUMMON_BODY_SPAWN_CONSISTENCY_PASS")
	get_tree().quit()
