extends RefCounted

const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Original := preload("res://scripts/caster_skill_visual_registry.gd")
const ROLE_PROJECTILE := Original.ROLE_PROJECTILE
const ROLE_TARGET_EFFECT := Original.ROLE_TARGET_EFFECT
const ROLE_SELF_EFFECT := Original.ROLE_SELF_EFFECT
const ROLE_SELF_AREA := Original.ROLE_SELF_AREA
const ROLE_AREA_EFFECT := Original.ROLE_AREA_EFFECT
const ROLE_LINE_EFFECT := Original.ROLE_LINE_EFFECT
const ROLE_GROUND_EFFECT := Original.ROLE_GROUND_EFFECT
const ROLE_SUMMON_ACTOR := Original.ROLE_SUMMON_ACTOR
var _owner := 0
var _lease: Dictionary
var _metadata: Dictionary
var _professions: RefCounted
var _timing: RefCounted

static func create_owner(snapshot: Dictionary, timing_publication: Dictionary, professions: RefCounted, timing: RefCounted) -> RefCounted:
	if professions == null or timing == null or snapshot.get("contract_id") != "world.skill.visual_metadata.v1": return null
	if not snapshot.get("catalog_lease") is Dictionary or not Gate.owns_reader(snapshot.catalog_lease): return null
	if snapshot.get("catalog_lease") != timing_publication.get("catalog_lease") \
		or snapshot.get("timing_profiles_sha256") != timing_publication.get("profiles_sha256"): return null
	if not snapshot.get("metadata") is Dictionary or not Graph.validate(snapshot).success \
		or Graph.fingerprint(snapshot.metadata) != snapshot.get("metadata_sha256"): return null
	if not snapshot.metadata.get("profiles") is Dictionary or not snapshot.metadata.get("visual_profiles") is Dictionary: return null
	var captured := Graph.capture(snapshot.metadata)
	if not captured.success: return null
	var result := new()
	result._owner = OS.get_thread_caller_id()
	result._lease = snapshot.catalog_lease
	result._metadata = captured.value
	result._professions = professions
	result._timing = timing
	return result

func _check_owner() -> void:
	assert(OS.get_thread_caller_id() == _owner and Gate.owns_reader(_lease))

func owner_thread_id() -> int: return _owner

func profile(skill_name_or_id: String) -> Dictionary:
	_check_owner()
	return _metadata.profiles.get(_professions.skill_id(skill_name_or_id), {}).duplicate(true)

func visual_profile(skill_name_or_id: String) -> Dictionary:
	_check_owner()
	return _metadata.visual_profiles.get(_professions.skill_id(skill_name_or_id), {}).duplicate(true)

func is_runtime_ready(skill_name_or_id: String) -> bool:
	_check_owner()
	return _timing.is_runtime_ready(skill_name_or_id)

func animation_duration(skill_name_or_id: String, phase_id := "") -> float:
	_check_owner()
	return _timing.animation_duration(skill_name_or_id, phase_id)

func render_policy(skill_name_or_id: String, phase_id := "") -> Dictionary:
	_check_owner()
	return _timing.render_policy(skill_name_or_id, phase_id)
