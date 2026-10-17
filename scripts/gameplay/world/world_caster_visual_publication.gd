extends RefCounted

## Main captures the actual registry once while the catalog lease is held.
## Timing remains the existing WorldSkillActionTiming owner on S.
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Structure := preload("res://scripts/gameplay/world/world_caster_visual_structure.gd")

static func publish(catalog_lease: Dictionary, timing_publication: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not Gate.is_active(catalog_lease): return {}
	if timing_publication.get("contract_id") != "world.skill.numeric_timing.v1" \
		or timing_publication.get("catalog_lease") != catalog_lease \
		or not timing_publication.get("profiles") is Dictionary: return {}
	if Graph.fingerprint(timing_publication.profiles) != timing_publication.get("profiles_sha256"): return {}
	var profiles: Dictionary = {}
	var visual_profiles: Dictionary = {}
	# The original timing publication enumerates the complete registered catalog,
	# equipment skills and visual manifest; no boot workset filters this owner.
	for skill: String in timing_publication.profiles:
		var full := Registry.profile(skill)
		var numeric: Dictionary = {}
		for field: String in ["render", "animation", "animation_phases", "status", "derived_status"]:
			if full.has(field): numeric[field] = full[field]
		if numeric != timing_publication.profiles[skill]: return {}
		profiles[skill] = full
		visual_profiles[skill] = Registry.visual_profile(skill)
	var metadata := {"profiles":profiles, "visual_profiles":visual_profiles,"structure_contract_id":Structure.CONTRACT}
	var captured := Graph.capture({"contract_id":"world.skill.visual_metadata.v1", "metadata":metadata,
		"metadata_sha256":Graph.fingerprint(metadata), "timing_profiles_sha256":timing_publication.profiles_sha256,
		"catalog_lease":catalog_lease})
	return captured.value if captured.success else {}
