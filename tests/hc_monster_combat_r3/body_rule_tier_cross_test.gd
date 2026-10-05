extends Node

# R3 review counterexample. NOT_RUN by the remote reviewer: run in HardCore.
# The profile must bind id -> rule -> tier -> both radii, not just validate
# the claimed tier against its own radius. No production catalog is modified.
const Identity := preload("res://scripts/monster_identity.gd")
const Body := preload("res://scripts/actor_body_policy.gd")
var _failures: Array[String] = []

func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
		printerr("R3_BODY_RULE_TIER: ", message)

func _check_cross(monster_id: int, wrong_tier: StringName) -> void:
	var entry: Dictionary = Identity.catalog_entry(monster_id)
	var classification := str(entry.get("classification", ""))
	var original: Dictionary = Identity.body_profile(monster_id)
	_expect(not original.is_empty(), "missing positive-control body for %d" % monster_id)
	if original.is_empty():
		return
	_expect(not Body.resolve_monster_body(monster_id, classification, original).is_empty(),
		"original body must resolve for %d" % monster_id)
	var changed := original.duplicate(true)
	var wrong_px := Body.tier_screen_radius_px(wrong_tier)
	changed["tier"] = String(wrong_tier)
	changed["screen_radius_px"] = wrong_px
	changed["ground_radius_gu"] = WorldSpatialRules.actor_combat_radius_gu_from_screen_radius_px(wrong_px)
	# Preserve the correct assignment rule and policy hash. Only the assigned
	# tier and its mutually-consistent radii are wrong.
	_expect(Body.resolve_monster_body(monster_id, classification, changed).is_empty(),
		"identity %d accepted rule=%s with wrong tier=%s" % [monster_id, changed["assignment_rule"], wrong_tier])

func _ready() -> void:
	_check_cross(76, &"small")
	_check_cross(24, &"large")
	if _failures.is_empty():
		print("HC_MCR3_BODY_RULE_TIER_CROSS_PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)
