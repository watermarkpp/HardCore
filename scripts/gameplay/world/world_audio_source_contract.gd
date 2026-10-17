extends RefCounted
## S input only. This never represents a Main visibility/canvas observation.
const Actor := preload("res://scripts/gameplay/presentation/actor_visual_projection_contract.gd")
static func accepts(value: Dictionary) -> bool:
	if value.size() != 6 or not value.has_all(["actor_identity","monster_id","position_screen_px","source_present","source_inside_world","source_retiring"]): return false
	if not value.actor_identity is Dictionary or not Actor.valid_identity(value.actor_identity) or not value.monster_id is int or value.monster_id <= 0 or not value.position_screen_px is Vector2 or not value.position_screen_px.is_finite(): return false
	for field: String in ["source_present","source_inside_world","source_retiring"]:
		if not value[field] is bool: return false
	return true
