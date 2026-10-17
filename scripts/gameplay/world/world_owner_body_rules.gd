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

var _cached_policy: Dictionary = {}
var _cached_policy_sha := ""
var _cached_policy_failed := false


func _load_policy() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner and not _cached_policy.is_empty(), "body policy must be captured at the original Main boundary")
	return _cached_policy


func tier_screen_radius_px(tier: StringName) -> float:
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
func player_screen_radius_px() -> float:
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
func summon_tier(summon_id: String) -> String:
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
func validate_body_profile(profile: Variant) -> Dictionary:
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
func resolve_monster_body(monster_id: int, classification: String, profile: Variant) -> Dictionary:
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
	# HC-MONSTER-COMBAT-R3 W3 (R3-04): the assignment rule also PINS the tier.
	# A profile that keeps the correct rule but swaps the tier (a boss rule
	# carrying small radii, or default_small carrying large radii) contradicts
	# the versioned policy and is rejected; callers must fail closed.
	var rule_tier := _expected_rule_tier(expected_rule)
	if rule_tier == StringName() or tier != rule_tier:
		return {}
	var expected_px := tier_screen_radius_px(tier)
	if expected_px <= 0.0 or not is_equal_approx(float(data["screen_radius_px"]), expected_px):
		return {}
	return data


func _expected_rule_tier(rule_id: String) -> StringName:
	var policy := _load_policy()
	if policy.is_empty():
		return StringName()
	for rule: Variant in policy.get("assignment_rules", []):
		if not rule is Dictionary:
			continue
		var entry: Dictionary = rule
		if str(entry.get("rule_id", "")) != rule_id:
			continue
		var tier := StringName(str(entry.get("tier", "")))
		if tier == TIER_SMALL or tier == TIER_LARGE:
			return tier
		return StringName()
	return StringName()


func _expected_assignment_rule(monster_id: int, classification: String) -> String:
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


func _policy_sha256_lower() -> String:
	if _cached_policy_sha.is_empty() and not _cached_policy_failed:
		_load_policy()
	return _cached_policy_sha


## The single isometric footsole shape entry for monsters and summons. The
## 16-point template lives in WorldSpatialRules; this wrapper exists so no
## combat code reaches into display or legacy radius authorities.

var _owner := OS.get_thread_caller_id()
func owner_thread_id() -> int: return _owner
func configure_publication(body_templates: Dictionary) -> bool:
	if _owner == OS.get_main_thread_id() or not _cached_policy.is_empty() or not body_templates.get("policy") is Dictionary: return false
	var parsed: Variant = JSON.parse_string(body_templates.get("policy_raw_utf8", PackedByteArray()).get_string_from_utf8())
	if not parsed is Dictionary or parsed != body_templates.policy or not body_templates.get("policy_normalized_sha256") is String: return false
	var captured := preload("res://scripts/features/contracts/plain_graph.gd").capture(body_templates.policy)
	if not captured.success: return false
	_cached_policy = captured.value
	_cached_policy_sha = body_templates.policy_normalized_sha256
	_cached_policy_failed = false
	return true
