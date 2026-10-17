extends RefCounted

const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")

static func publish(catalog_lease: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not Gate.is_active(catalog_lease): return {}
	var profiles: Dictionary = {}
	var ids: Array = ProfessionRules.SKILL_CATALOG.keys()
	ids.append_array(ProfessionRules.EQUIPMENT_GRANTED_SKILLS.keys())
	ids.append_array(Registry._manifest().get("skillCoverage", {}).keys())
	var visual_document: Variant = JSON.parse_string(FileAccess.get_file_as_string(Registry.VISUAL_PROFILE_PATH))
	if visual_document is Dictionary:
		ids.append_array(visual_document.get("skill_profiles", {}).keys())
	for row: Dictionary in GameData.skills:
		ids.append(str(row.get("skill_id", "")))
	for skill: String in ids:
		if profiles.has(skill) or skill.is_empty(): continue
		var source := Registry.profile(skill)
		var numeric: Dictionary = {}
		for field: String in ["render", "animation", "animation_phases", "status", "derived_status"]:
			if source.has(field): numeric[field] = source[field]
		profiles[skill] = numeric
	var captured := Graph.capture({"contract_id":"world.skill.numeric_timing.v1", "profiles":profiles,
		"profiles_sha256":Graph.fingerprint(profiles), "catalog_lease":catalog_lease,
		"profession_growth_source_path":GameData.profession_growth_source_path,
		"manifest_sha256":FileAccess.get_sha256(Registry.MANIFEST_PATH),
		"visual_profile_sha256":FileAccess.get_sha256(Registry.VISUAL_PROFILE_PATH)})
	return captured.value if captured.success else {}
