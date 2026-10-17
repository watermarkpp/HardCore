extends RefCounted

const Timing := preload("res://scripts/gameplay/world/world_skill_action_timing.gd")
const Profiles := preload("res://scripts/gameplay/world/world_skill_timing_profiles.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")

static func create_owner(snapshot: Dictionary, professions: RefCounted) -> RefCounted:
	if snapshot.get("contract_id") != "world.skill.numeric_timing.v1" \
		or not snapshot.get("profiles") is Dictionary or not snapshot.get("catalog_lease") is Dictionary \
		or professions == null or not Gate.owns_reader(snapshot.catalog_lease): return null
	if not Graph.validate(snapshot).success or Graph.fingerprint(snapshot.profiles) != snapshot.get("profiles_sha256"):
		return null
	# Keep an independent immutable provider even for a caller's mutable envelope.
	var captured := Graph.capture(snapshot.profiles)
	if not captured.success: return null
	return Timing.new(Profiles.new(captured.value, professions))
