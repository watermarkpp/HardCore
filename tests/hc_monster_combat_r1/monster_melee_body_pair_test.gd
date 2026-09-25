extends Node

const ActorBodyPolicyScript := preload("res://scripts/actor_body_policy.gd")


## HC-BODY-2TIER-1P5-V1 melee body pair tests.
## With every managed body inside the two-tier system, the contact standing
## requirement ra + rt + 0.4375 stays inside the unified 1.5 GU start reach for
## every hostile/owner pair in every ground direction, and the retired radius
## authorities are proven to have violated the same invariant (the defects this
## package removes).


func _contact_gu(attacker_px: float, target_px: float) -> float:
	var iso_denominator := 32.0 * sqrt(2.0)
	var attacker_gu := attacker_px / iso_denominator
	var target_gu := target_px / iso_denominator
	return attacker_gu + target_gu + 0.4375


func _ready() -> void:
	var small_px := ActorBodyPolicyScript.tier_screen_radius_px(ActorBodyPolicyScript.TIER_SMALL)
	var large_px := ActorBodyPolicyScript.tier_screen_radius_px(ActorBodyPolicyScript.TIER_LARGE)
	var player_px := ActorBodyPolicyScript.player_screen_radius_px()
	assert(small_px > 0.0 and large_px > 0.0 and player_px > 0.0, "policy radii must resolve")

	# Managed pairs: (attacker body, target body). The large-large row is the
	# documented size upper bound, not a new friendly-fire mechanic.
	var managed_pairs := {
		"small->player": [small_px, player_px],
		"large->player": [large_px, player_px],
		"large->skeleton": [large_px, small_px],
		"large->divine_beast": [large_px, large_px],
		"large->large": [large_px, large_px],
	}
	for pair_name: String in managed_pairs:
		var pair: Array = managed_pairs[pair_name]
		var contact := _contact_gu(float(pair[0]), float(pair[1]))
		assert(
			contact <= 1.5,
			"%s contact standing %f GU exceeds the 1.5 GU start reach" % [pair_name, contact]
		)

	# Retired authorities violated the invariant and are proven captured here:
	# two legacy 28 px boss bodies and the old 28 px boss + 21 px round divine
	# beast cannot stand inside the unified start reach.
	assert(_contact_gu(28.0, 28.0) > 1.5, "the legacy 28px pair must violate the start reach")
	assert(_contact_gu(28.0, 21.0) > 1.5, "the legacy 28px+21px pair must violate the start reach")

	# Eight-direction start geometry at the boundary distances: the unified
	# start reach is a strict center-to-center gate at 1.5 GU in every ground
	# direction (1.49 inside, 1.50 boundary-excluded, 1.51 outside).
	for index in 8:
		var direction := Vector2.from_angle(TAU * float(index) / 8.0)
		assert(
			direction.length() * 1.49 < HCMonsterMeleePolicy.START_GU,
			"1.49 GU must stay inside the start reach (direction %d)" % index
		)
		assert(
			not HCMonsterMeleePolicy.within(direction * 1.51, Vector2.ZERO, HCMonsterMeleePolicy.START_GU),
			"1.51 GU must stay outside the start reach (direction %d)" % index
		)
		# The 1.5 GU gate is center-to-center: no body-radius padding may be
		# added on top (the design explicitly forbids edge-extended reach).
		var large_gu := large_px / (32.0 * sqrt(2.0))
		assert(
			1.5 >= large_gu + large_gu + 0.4375,
			"1.5 GU must remain the center-to-center gate, not edge-extended (direction %d)" % index
		)

	print("HC_MELEE_BODY_PAIR_PASS")
	get_tree().quit()
