extends RefCounted

## Original helper with its actor-null appearance already captured on Main.
static func mapping_for_profile(profile: Dictionary) -> Dictionary:
	if profile.is_empty() or str(profile.get("status", "")) != "formal":
		return {}
	var atlas: Dictionary = profile.get("atlas", {}) if profile.get("atlas", {}) is Dictionary else {}
	var frame_size: Array = atlas.get("frame_size", [160, 160])
	var foot_anchor: Array = atlas.get("foot_anchor", [80, 138])
	if frame_size.size() < 2 or foot_anchor.size() < 2:
		return {}
	var actions: Variant = profile.get("actions", {})
	if not actions is Dictionary:
		return {}
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Variant = actions.get(action_name, {})
		if not action is Dictionary or str(action.get("path", "")).is_empty() or str(action.get("path_sha256", "")).is_empty():
			return {}
	return {
		"appearance_profile_id": str(profile.get("appearance_profile_id", "")),
		"frameSize": frame_size,
		"footAnchor": foot_anchor,
		"healthBarTopByDirection": [],
		"directionPolicy": "mir2_directional",
		"actions": actions,
	}
