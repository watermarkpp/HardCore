extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const ActorBodyPolicyScript := preload("res://scripts/actor_body_policy.gd")


## HC-BODY-2TIER-1P5-V1 contract tests.
## Every runtime-managed monster carries a validated two-tier body profile,
## the tier radii satisfy the contact-reach invariant, and the player body is
## explicitly frozen outside the tier system.


func _ready() -> void:
	var policy_text := FileAccess.get_file_as_string(
		"res://assets/data/actor_body_policy_v1.json"
	)
	var policy: Dictionary = JSON.parse_string(policy_text)
	assert(policy.get("contract_id", "") == "hardcore.actor.body_policy.v1", "policy contract id mismatch")

	var catalog_text := FileAccess.get_file_as_string(
		"res://assets/data/runtime/canonical_monster_catalog.json"
	)
	var catalog: Dictionary = JSON.parse_string(catalog_text)
	var entries: Array = catalog.get("entries", [])
	assert(entries.size() >= 156, "catalog entry count unexpectedly small")

	var iso_denominator := 32.0 * sqrt(2.0)
	var large_ids := 0
	var small_ids := 0
	var seen_ids := {}
	for entry: Dictionary in entries:
		var monster_id := int(entry.get("monster_id", 0))
		assert(monster_id > 0, "catalog entry without monster_id")
		assert(not seen_ids.has(monster_id), "duplicate catalog monster_id %d" % monster_id)
		seen_ids[monster_id] = true
		var combat: Dictionary = entry.get("combat", {})
		var profile: Dictionary = combat.get("body_profile", {})
		assert(not profile.is_empty(), "monster %d has no body_profile" % monster_id)
		assert(
			str(profile.get("contract_id", "")) == "hardcore.actor.body_policy.v1",
			"monster %d body profile contract mismatch" % monster_id
		)
		var tier := str(profile.get("tier", ""))
		assert(tier == "small" or tier == "large", "monster %d invalid tier %s" % [monster_id, tier])
		var radius_px := float(profile.get("screen_radius_px", -1.0))
		var ground_gu := float(profile.get("ground_radius_gu", -1.0))
		assert(is_finite(radius_px) and radius_px > 0.0, "monster %d invalid px radius" % monster_id)
		assert(is_finite(ground_gu) and ground_gu > 0.0, "monster %d invalid GU radius" % monster_id)
		assert(
			absf(ground_gu - radius_px / iso_denominator) <= 0.000001,
			"monster %d radius conversion mismatch" % monster_id
		)
		assert(ground_gu <= 0.50625, "monster %d exceeds the body upper bound" % monster_id)
		assert(not str(profile.get("assignment_rule", "")).is_empty(), "monster %d has no assignment rule" % monster_id)
		if tier == "large":
			large_ids += 1
		else:
			small_ids += 1
		# The runtime identity entry must expose the same baked profile
		# (HC-MONSTER-COMBAT-R2 T2: exact float compare, not int truncation).
		var runtime_profile: Dictionary = MonsterIdentityScript.body_profile(monster_id)
		assert(
			is_equal_approx(
				float(runtime_profile.get("screen_radius_px", -1.0)), radius_px
			),
			"monster %d runtime body profile diverges from the catalog" % monster_id
		)
		# Identity-bound resolution: the baked profile must resolve for its own
		# monster_id and its own classification, under the current policy bytes.
		var classification := str(entry.get("classification", ""))
		assert(
			not ActorBodyPolicyScript.resolve_monster_body(
				monster_id, classification, profile
			).is_empty(),
			"monster %d baked profile must resolve for its own identity" % monster_id
		)
		# A boss identity must not accept a default_small-stamped profile and a
		# non-boss must not accept a boss_large_body stamp (ownership check).
		var foreign_profile: Dictionary = profile.duplicate(true)
		foreign_profile["assignment_rule"] = (
			"default_small" if classification == "boss" else "boss_large_body"
		)
		assert(
			ActorBodyPolicyScript.resolve_monster_body(
				monster_id, classification, foreign_profile
			).is_empty(),
			"monster %d must reject a foreign assignment rule" % monster_id
		)
		# Stale policy provenance must reject even a structurally valid profile.
		var stale_profile: Dictionary = profile.duplicate(true)
		stale_profile["policy_sha256"] = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
		assert(
			ActorBodyPolicyScript.resolve_monster_body(
				monster_id, classification, stale_profile
			).is_empty(),
			"monster %d must reject a stale policy hash" % monster_id
		)
		# A radius that does not exactly equal the policy tier radius must reject.
		var wrong_radius: Dictionary = profile.duplicate(true)
		wrong_radius["screen_radius_px"] = (
			15.5 if tier == "small" else 27.5
		)
		assert(
			ActorBodyPolicyScript.resolve_monster_body(
				monster_id, classification, wrong_radius
			).is_empty(),
			"monster %d must reject a non-policy tier radius" % monster_id
		)
	assert(large_ids == 27 and small_ids == 129, "tier assignment summary drifted: %d large / %d small" % [large_ids, small_ids])

	# Contact-reach invariant: even the largest managed pair plus the fixed
	# contact gap and the config margin stays inside the 1.5 GU start reach.
	var large_gu := 0.5
	assert(large_gu + large_gu + 0.4375 + 0.05 <= 1.5, "large-large pair violates the start-reach invariant")

	# The player body stays frozen outside the tier system.
	assert(
		ActorBodyPolicyScript.player_screen_radius_px() == 18.0,
		"player body radius must stay frozen at 18 px"
	)
	# Summon tiers.
	assert(ActorBodyPolicyScript.summon_tier("skeleton") == "small", "skeleton must join the small tier")
	assert(ActorBodyPolicyScript.summon_tier("divine_beast") == "large", "divine beast must join the large tier")

	# Unknown summon ids fail closed (no silent tier adoption).
	assert(ActorBodyPolicyScript.summon_tier("unknown_beast") == "", "unknown summon id must not resolve a tier")

	print("HC_BODY_POLICY_CONTRACT_PASS")
	get_tree().quit()
