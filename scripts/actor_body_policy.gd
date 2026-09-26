extends RefCounted

## HC-BODY-2TIER-1P5-V1: two-tier footsole body policy.
##
## Single validation/parse entry for the versioned body policy
## (assets/data/actor_body_policy_v1.json) and the per-monster body_profile
## baked into the canonical catalog by tools/build_canonical_monster_catalog.py
## (the formal generator is the only production writer; the R1 standalone
## injector was retired in HC-MONSTER-COMBAT-R2 T2).
##
## This class owns:
## - strict validation of a body_profile (finite, positive, upper bound,
##   known tier, matching policy identity),
## - identity-bound body resolution (policy hash, exact tier radius and
##   assignment-rule ownership per monster_id),
## - the two authoritative tier radii and the frozen player radius,
## - the unified isometric footsole shape entry for monsters and summons.
##
## It must never gain _process/_physics_process or per-frame polling: body
## data resolves once at instance initialization, before spawn checks, shape
## creation and spatial-index registration.

const BODY_POLICY_CONTRACT_ID := "hardcore.actor.body_policy.v1"
const BODY_POLICY_PATH := "res://assets/data/actor_body_policy_v1.json"

## Radius upper bound from the policy invariants: every managed body pair must
## satisfy ra + rt + 0.4375 + 0.05 <= 1.5 (contact start reach), so a single
## body may never exceed 0.50625 GU.
const MAX_BODY_GROUND_RADIUS_GU := 0.50625

const TIER_SMALL := &"small"
const TIER_LARGE := &"large"

static var _cached_policy: Dictionary = {}
static var _cached_policy_sha := ""
static var _cached_policy_failed := false


static func _load_policy() -> Dictionary:
	if _cached_policy_failed:
		return {}
	if not _cached_policy.is_empty():
		return _cached_policy
	var text := FileAccess.get_file_as_string(BODY_POLICY_PATH)
	if text.is_empty():
		_cached_policy_failed = true
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_cached_policy_failed = true
		return {}
	var policy: Dictionary = parsed
	if str(policy.get("policy_id", "")) != "actor_body_policy_v1":
		_cached_policy_failed = true
		return {}
	if str(policy.get("contract_id", "")) != BODY_POLICY_CONTRACT_ID:
		_cached_policy_failed = true
		return {}
	_cached_policy = policy
	# Provenance hash with the generator's lf_text normalization, so the
	# baked body_profile.policy_sha256 is comparable byte-for-byte regardless
	# of the checkout's line endings.
	_cached_policy_sha = text.replace("\r\n", "\n").replace("\r", "\n").sha256_text()
	return _cached_policy


## Authoritative screen radius (px) of a tier. The isometric ground radius is
## always derived through WorldSpatialRules, never duplicated here.
static func tier_screen_radius_px(tier: StringName) -> float:
	var policy := _load_policy()
	if policy.is_empty():
		return -1.0
	var tiers: Dictionary = policy.get("tier_radii", {})
	var tier_entry: Variant = tiers.get(String(tier), null)
	if not tier_entry is Dictionary:
		return -1.0
	var radius: Variant = (tier_entry as Dictionary).get("screen_radius_px", null)
	if radius is float or radius is int:
		return float(radius)
	return -1.0


## Frozen player body radius (px). The player is explicitly not tier-managed.
static func player_screen_radius_px() -> float:
	var policy := _load_policy()
	if policy.is_empty():
		return -1.0
	var player: Variant = policy.get("player", null)
	if not player is Dictionary:
		return -1.0
	var radius: Variant = (player as Dictionary).get("screen_radius_px", null)
	if radius is float or radius is int:
		return float(radius)
	return -1.0


## Summon body tier ("skeleton"/"divine_beast" -> "small"/"large").
static func summon_tier(summon_id: String) -> String:
	var policy := _load_policy()
	if policy.is_empty():
		return ""
	var summons: Variant = policy.get("summon_tiers", null)
	if not summons is Dictionary:
		return ""
	var tier: Variant = (summons as Dictionary).get(summon_id, null)
	return String(tier) if tier is String else ""


## Strict validation of a baked body_profile. Returns an empty dictionary on
## rejection; callers must fail closed with a diagnostic, never clamp radii.
static func validate_body_profile(profile: Variant) -> Dictionary:
	if not profile is Dictionary:
		return {}
	var data: Dictionary = profile
	if str(data.get("contract_id", "")) != BODY_POLICY_CONTRACT_ID:
		return {}
	if str(data.get("policy_id", "")) != "actor_body_policy_v1":
		return {}
	var tier := StringName(str(data.get("tier", "")))
	if tier != TIER_SMALL and tier != TIER_LARGE:
		return {}
	var radius_px: Variant = data.get("screen_radius_px", null)
	if not (radius_px is float or radius_px is int):
		return {}
	var radius := float(radius_px)
	if not is_finite(radius) or radius <= 0.0:
		return {}
	var ground_gu: Variant = data.get("ground_radius_gu", null)
	if not (ground_gu is float or ground_gu is int):
		return {}
	var ground := float(ground_gu)
	if not is_finite(ground) or ground <= 0.0 or ground > MAX_BODY_GROUND_RADIUS_GU:
		return {}
	var authoritative_gu := WorldSpatialRules.actor_combat_radius_gu_from_screen_radius_px(
		radius
	)
	if absf(authoritative_gu - ground) > 0.000001:
		return {}
	if str(data.get("assignment_rule", "")).is_empty():
		return {}
	return data


## HC-MONSTER-COMBAT-R2 T2: identity-bound body resolution. In addition to the
## structural validation above, a production body must match the CURRENT
## policy byte-for-byte in provenance and assignment: the recorded policy hash
## (case-insensitive), the exact tier radius of the claimed tier, and the
## assignment rule that this specific monster_id owns under the policy.
## Any mismatch rejects the profile; production callers must refuse combat
## instead of falling back to the small tier.
static func resolve_monster_body(monster_id: int, classification: String, profile: Variant) -> Dictionary:
	var data := validate_body_profile(profile)
	if data.is_empty():
		return {}
	if String(data.get("policy_sha256", "")).to_lower() != _policy_sha256_lower():
		return {}
	var tier := StringName(str(data.get("tier", "")))
	var expected_rule := _expected_assignment_rule(monster_id, classification)
	if expected_rule.is_empty():
		return {}
	if StringName(str(data.get("assignment_rule", ""))) != StringName(expected_rule):
		return {}
	var expected_px := tier_screen_radius_px(tier)
	if expected_px <= 0.0 or not is_equal_approx(float(data["screen_radius_px"]), expected_px):
		return {}
	return data


static func _expected_assignment_rule(monster_id: int, classification: String) -> String:
	var policy := _load_policy()
	if policy.is_empty():
		return ""
	if classification == "boss":
		return "boss_large_body"
	for rule: Variant in policy.get("assignment_rules", []):
		if not rule is Dictionary:
			continue
		var entry: Dictionary = rule
		if str(entry.get("rule_id", "")) != "named_large_elite_family":
			continue
		for item: Variant in entry.get("monster_ids", []):
			if item is int or item is float:
				if int(item) == monster_id:
					return "named_large_elite_family"
	return "default_small"


static func _policy_sha256_lower() -> String:
	if _cached_policy_sha.is_empty() and not _cached_policy_failed:
		_load_policy()
	return _cached_policy_sha


## The single isometric footsole shape entry for monsters and summons. The
## 16-point template lives in WorldSpatialRules; this wrapper exists so no
## combat code reaches into display or legacy radius authorities.
static func footsole_shape_px(screen_radius_px: float) -> ConvexPolygonShape2D:
	return WorldSpatialRules.actor_footprint_shape_px(screen_radius_px)
