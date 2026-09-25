extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const ArtSpecScript := preload("res://scripts/art_spec.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")


## HC-BODY-2TIER-1P5-V1 projection tests.
## The resolved body radius, the physical CollisionShape2D and the combat
## conversion must describe one consistent isometric footsole: 16 points,
## identity local transform, no per-frame mutation, and the small/large tiers
## actually own the instance radii.


func _verify_body(actor: Node2D, expected_px: float) -> void:
	var iso_denominator := 32.0 * sqrt(2.0)
	assert(
		is_equal_approx(float(actor.collision_radius_px), expected_px),
		"instance collision radius diverges from the policy tier"
	)
	assert(
		is_equal_approx(
			float(actor.combat_radius_gu),
			expected_px / iso_denominator,
		),
		"instance combat radius is not the isometric conversion of the px radius"
	)
	var shapes: Array[Node] = actor.find_children("CollisionShape2D", "CollisionShape2D", false, false)
	assert(shapes.size() == 1, "actor must own exactly one footsole shape")
	var collision := shapes[0] as CollisionShape2D
	assert(collision != null and collision.shape != null, "missing physical shape")
	assert(collision.shape is ConvexPolygonShape2D, "footsole must be the 16-point convex polygon, not a circle")
	var polygon := collision.shape as ConvexPolygonShape2D
	assert(polygon.points.size() == 16, "footsole template must keep 16 vertices")
	assert(collision.position == Vector2.ZERO, "footsole must keep a zero local offset")
	assert(collision.rotation == 0.0, "footsole must not rotate with facing")
	assert(collision.scale == Vector2.ONE, "footsole must not scale the template")
	# Inverse projection: every vertex must round-trip to the declared ground
	# radius through the shared conversion authority.
	var ground_radius := float(actor.combat_radius_gu)
	for point in polygon.points:
		var vertex_gu := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(point)
		assert(
			absf(vertex_gu.length() - ground_radius) <= 0.00001,
			"footsole vertex diverges from the declared ground radius"
		)


func _ready() -> void:
	# Small tier (ordinary monster 18) and large tier (named large elite 56).
	var small := EnemyActor.new()
	small.setup(GameData.get_monster_by_id(18).duplicate(true), null, true)
	add_child(small)
	var small_profile: Dictionary = MonsterIdentityScript.body_profile(18)
	assert(str(small_profile.get("tier", "")) == "small", "fixture: monster 18 must be small tier")
	_verify_body(small, float(small_profile["screen_radius_px"]))
	assert(
		not small.has_meta("body_policy_fallback"),
		"a managed monster must never fall back away from its baked profile"
	)

	var large := EnemyActor.new()
	large.setup(GameData.get_monster_by_id(56).duplicate(true), null, true)
	add_child(large)
	var large_profile: Dictionary = MonsterIdentityScript.body_profile(56)
	assert(str(large_profile.get("tier", "")) == "large", "fixture: monster 56 must be large tier")
	_verify_body(large, float(large_profile["screen_radius_px"]))
	# The retired 28 px boss constant must no longer own any instance body.
	assert(
		float(large.collision_radius_px) < 28.0,
		"the legacy 28 px boss body authority must be retired"
	)

	# Player-character body stays untouched at 18 px.
	assert(
		is_equal_approx(ArtSpecScript.PLAYER_COLLISION_RADIUS_PX, 18.0),
		"player collision authority must stay 18 px"
	)

	small.queue_free()
	large.queue_free()
	print("HC_BODY_PROJECTION_PASS")
	get_tree().quit()
