extends RefCounted

## HC-BODY-2TIER-1P5-V1: two-tier footsole body policy.
##
## Single validation/parse entry for the versioned body policy
## (assets/data/actor_body_policy_v1.json) and the per-monster body_profile
## baked into the canonical catalog by tools/build_canonical_monster_catalog.py
## (applied to the checked-in catalog by tools/apply_actor_body_policy_v1.py).
##
## This class owns:
## - strict validation of a body_profile (finite, positive, upper bound,
##   known tier, matching policy identity),
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


## The single isometric footsole shape entry for monsters and summons. The
## 16-point template lives in WorldSpatialRules; this wrapper exists so no
## combat code reaches into display or legacy radius authorities.
static func footsole_shape_px(screen_radius_px: float) -> ConvexPolygonShape2D:
	return WorldSpatialRules.actor_footprint_shape_px(screen_radius_px)
