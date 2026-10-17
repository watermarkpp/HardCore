extends RefCounted

## Original GameRoot containers share a single writable authority with
## WorldSkill. RuntimeMap identity and sealed content never enter this copier.
const LATE_OWNER_PATHS := {
	"_world_context":"res://scripts/layers/runtime/execution/world_context.gd",
	"_world_bootstrap_coordinator":"res://scripts/gameplay/world/world_map_loading_coordinator.gd",
	"_feature_target_bound":"res://scripts/features/adapters/world_target_bound.gd"}
const ConstructorValues := preload("res://scripts/gameplay/source/source_constructor_value_codec.gd")
const WorkingGraph := preload("res://scripts/gameplay/world/world_runtime_working_graph.gd")
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _skills: RefCounted
var _values: Dictionary = {}
var _link_fields: Dictionary = {}
var _unbound_owner_fields: Dictionary = {}

func configure_owner(world: RefCounted, skills: RefCounted, publication: Dictionary) -> bool:
	if _world != null or _owner == OS.get_main_thread_id() or publication.get("contract_id") != "world.source_fields.handoff.v1" or not publication.get("fields") is Dictionary: return false
	var late: Variant = publication.get("unbound_owner_fields", [])
	if not late is Array: return false
	for field: Variant in late:
		if not field is String or (field != "_rng" and not LATE_OWNER_PATHS.has(field)) or _unbound_owner_fields.has(field) or not publication.fields.has(field) or publication.fields[field] != null: return false
		_unbound_owner_fields[field] = true
	var restored: Dictionary = ConstructorValues.decode(publication)
	if not restored.ok: return false
	_world = weakref(world)
	_skills = skills
	_values = restored.value
	for name: String in ["locked_target", "magic_locked_target", "_skill_cast_target"]:
		if _values.has(name):
			if _values[name] != null: return false
			_link_fields[name] = true
			_values.erase(name)
	# Existing skill field names retain their own originally typed working
	# arrays and ActorLink containers; both readers route to that same instance.
	for field: String in _values.keys():
		if _skills._values.has(field):
			if field in ["_pending_main_pet_arrivals", "_fire_wall_field_registry"]:
				if not _values[field].is_empty(): return false
				_values.erase(field)
				continue
			_skills.write_field(field, _values[field])
			_values.erase(field)
	return true

func owner_thread_id() -> int: return _owner
func has_source_field(field: StringName) -> bool: return _link_fields.has(String(field)) or _skills._values.has(String(field)) or _values.has(String(field))
func read_source_field(field: StringName) -> Variant:
	assert(OS.get_thread_caller_id() == _owner and has_source_field(field), "missing original source field: " + String(field))
	if _unbound_owner_fields.has(String(field)):
		_world.get_ref().fault("original_Source_owner_field_not_bound", {"field":field})
		return null
	match field:
		&"locked_target": return _world.get_ref().skill_actors.locked_target()
		&"magic_locked_target": return _world.get_ref().skill_actors.magic_locked_target()
		&"_skill_cast_target": return _world.get_ref().skill_actors.cast_target()
	return _skills.read_field(String(field)) if _skills._values.has(String(field)) else _values[String(field)]
func write_source_field(field: StringName, value: Variant) -> void:
	assert(OS.get_thread_caller_id() == _owner and has_source_field(field), "unknown original source field write: " + String(field))
	match field:
		&"locked_target": _world.get_ref().skill_actors.set_locked_target(value); return
		&"magic_locked_target": _world.get_ref().skill_actors.set_magic_locked_target(value); return
		&"_skill_cast_target": _world.get_ref().skill_actors.set_cast_target(value); return
	if _skills._values.has(String(field)): _skills.write_field(String(field), value)
	else: _values[String(field)] = value
func read_field(field: String) -> Variant: return read_source_field(StringName(field))
func write_field(field: String, value: Variant) -> void: write_source_field(StringName(field), value)
func bind_owner_field(field: StringName, value: Variant) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	if not has_source_field(field): return false
	if _unbound_owner_fields.has(String(field)):
		if field == &"_rng":
			if not value is RandomNumberGenerator: return false
		elif not value is RefCounted or value is Resource or value.get_script() == null or value.get_script().resource_path != LATE_OWNER_PATHS[String(field)]: return false
		_unbound_owner_fields.erase(String(field))
	if _skills._values.has(String(field)): _skills.write_field(String(field), value)
	else: _values[String(field)] = value
	return true
