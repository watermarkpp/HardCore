extends RefCounted

## Pure original metadata/sequence decisions shared by Source and Main.
## No texture, residency, lease, Node, loading window or gameplay authority.
const CONTRACT := "world.caster.visual_structure.v1"
const Direction := preload("res://scripts/gameplay/world/world_caster_direction_numeric.gd")

static func direction_index(direction: Vector2) -> int:
	return Direction.direction_index(direction)

static func sequence_index(direction_16: int, sequences_or_count: Variant) -> int:
	var normalized := posmod(direction_16,16)
	if sequences_or_count is int:
		var count := int(sequences_or_count)
		if count <= 1: return 0
		return posmod(int(floor(float(normalized)*float(count)/16.0+0.5)),count)
	if not sequences_or_count is Array or sequences_or_count.is_empty(): return 0
	var sequences: Array = sequences_or_count
	var best_index := 0
	var best_distance := 17
	var best_clockwise_delta := 17
	for index: int in range(sequences.size()):
		var candidate := posmod(int(sequences[index].get("direction_index",0)),16)
		var clockwise_delta := posmod(candidate-normalized,16)
		var counterclockwise_delta := posmod(normalized-candidate,16)
		var distance := mini(clockwise_delta,counterclockwise_delta)
		if distance < best_distance or (distance == best_distance and clockwise_delta < best_clockwise_delta):
			best_index = index; best_distance = distance; best_clockwise_delta = clockwise_delta
	return best_index

static func select_sequence(animation: Dictionary, direction_16: int) -> Dictionary:
	if animation.get("contract","") != "caster_skill_animation.v1": return {"accepted":false}
	var sequences: Array = animation.get("sequences",[])
	if sequences.is_empty(): return {"accepted":false}
	var direction := posmod(direction_16,16) if int(animation.get("direction_count",1)) > 1 else 0
	var selected: Dictionary = sequences[sequence_index(direction,sequences)]
	var frames: Array = selected.get("frames",[])
	return {"accepted":not frames.is_empty(),"direction_index":direction,"sequence":selected,"frames":frames}

static func runtime_ready(profile: Dictionary) -> bool:
	return profile.get("status","") == "formal_primary_client_animation" and profile.get("animation",{}).get("contract","") == "caster_skill_animation.v1" and str(profile.get("derived_status","ready")) == "ready"

static func readiness_reason(profile: Dictionary) -> String:
	if profile.is_empty(): return "missing_visual_profile"
	if profile.get("status","") != "formal_primary_client_animation": return str(profile.get("reason","not_formal_primary_client_animation"))
	if profile.get("animation",{}).get("contract","") != "caster_skill_animation.v1": return "missing_animation_contract"
	var status := str(profile.get("derived_status","ready"))
	return "" if status == "ready" else status

static func animation_profile(profile: Dictionary, phase_id := "") -> Dictionary:
	return profile.get("animation",{}) if phase_id.is_empty() else profile.get("animation_phases",{}).get(phase_id,{})

static func binding(metadata: Dictionary, skill: String) -> Dictionary:
	if not metadata.get("profiles") is Dictionary or not metadata.get("visual_profiles") is Dictionary: return {}
	if not skill.is_empty() and not metadata.profiles.has(skill): return {}
	var original: Dictionary = metadata.profiles.get(skill,{})
	var visual: Dictionary = metadata.visual_profiles.get(skill,{})
	var merged: Dictionary = original.duplicate(true)
	for key: String in visual:
		if not merged.has(key) and key != "animation": merged[key] = visual[key]
	return {"original_profile":original,"factory_profile":merged,"role":str(original.get("role",""))}

static func projectile_structure(profile: Dictionary, direction: Vector2) -> Dictionary:
	if str(profile.get("role","")) != "projectile":
		return {"role_valid":false,"rejection_reason":"non_projectile_visual:%s" % str(profile.get("role","missing")),"animation_accepted":false}
	if not runtime_ready(profile): return {"role_valid":true,"rejection_reason":readiness_reason(profile),"animation_accepted":false}
	var selected := select_sequence(animation_profile(profile),direction_index(direction))
	return {"role_valid":true,"rejection_reason":"" if selected.accepted else "projectile_animation_failed","animation_accepted":selected.accepted}
