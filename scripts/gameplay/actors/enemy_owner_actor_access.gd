extends RefCounted

## S-only access to the existing registry. Views are never accepted identities.
## All persistent actor references use ActorLink; HP/life remain in the model.
const Link := preload("res://scripts/gameplay/foundation/actor_link.gd")
var _owner := OS.get_thread_caller_id()
var _registry: RefCounted
var _self_handle: Object
var _world: Object
var _views: Dictionary = {}
var _scopes: Dictionary = {}

class ActorView:
	extends RefCounted
	var access: RefCounted
	var link: RefCounted
	func record() -> Object:
		return link.resolve_record()
	func _get(key: StringName) -> Variant:
		return access.read_property(self, key)
	func _set(key: StringName, value: Variant) -> bool:
		access.write_property(self, key, value)
		return true
	func _get_property_list() -> Array[Dictionary]:
		var actor: Object = record()
		if actor == null: return []
		return actor.model().get_property_list()

class ParentScope:
	extends RefCounted
	var scope_id: int

func _init(registry: RefCounted, self_handle: Object, world: Object,
		owner_shared_views: Dictionary, owner_shared_scopes: Dictionary) -> void:
	assert(OS.get_thread_caller_id() != OS.get_main_thread_id())
	assert(registry != null and self_handle != null and world != null)
	assert(registry.resolve_runtime_actor(self_handle.get_instance_id()) == self_handle)
	_registry = registry
	_self_handle = self_handle
	_world = world
	# Every Enemy access object in one owner uses these same dictionaries.
	# This preserves original Node reference equality across actor callbacks.
	_views = owner_shared_views
	_scopes = owner_shared_scopes

func owner_thread_id() -> int:
	return _owner

func _owned() -> void:
	assert(OS.get_thread_caller_id() == _owner, "Enemy actor access left S")

func canonical(value: Object) -> Object:
	_owned()
	if value == null: return null
	if value is ActorView: return value.record()
	assert(not value is Node and not value is Resource)
	assert(_registry.resolve_runtime_actor(value.get_instance_id()) == value,
		"noncanonical actor/model supplied where a Handle is required")
	return value

func self_view() -> Object:
	return view(_self_handle)

func view(record: Object) -> Object:
	_owned()
	if record == null: return null
	var runtime_id := record.get_instance_id()
	assert(_registry.resolve_runtime_actor(runtime_id) == record)
	if _views.has(runtime_id):
		var cached: Object = _views[runtime_id].get_ref()
		if cached != null: return cached
	var result := ActorView.new()
	result.access = self
	result.link = Link.capture(_registry, record)
	assert(result.link != null)
	_views[runtime_id] = weakref(result)
	return result

func capture(value: Object) -> RefCounted:
	_owned()
	return Link.capture(_registry, canonical(value)) if value != null else null

func resolve(link: RefCounted) -> Object:
	_owned()
	if link == null: return null
	assert(link.get_script() == Link, "Enemy persistent target must use ActorLink")
	return view(link.resolve_record())

func resolve_runtime(runtime_id: int) -> Object:
	_owned()
	return view(_registry.resolve_runtime_actor(runtime_id))

func is_present(value: Variant) -> bool:
	_owned()
	if value == null: return false
	assert(not value is Node and not value is Resource)
	if value is ActorView:
		var actor: Object = value.record()
		return actor != null and actor.runtime_object_is_present()
	return is_instance_valid(value)

func is_kind(value: Variant, kind: StringName) -> bool:
	_owned()
	if value == null or not value is Object: return false
	if not value is ActorView: return false
	var actor: Object = value.record()
	if actor == null: return false
	if kind == &"spatial" or kind == &"collision":
		return actor.kind() in [&"player", &"summon", &"enemy"]
	return actor.kind() == kind

func is_exact_player(value: Object) -> bool:
	var actor := canonical(value)
	# This retains the source's exact-script distinction for compatibility
	# actors: the Main-published actor contract must identify the exact class.
	return actor.kind() == &"player" and _world.actor_has_exact_legacy_player_contract(actor)

func supports(value: Object, method: StringName) -> bool:
	_owned()
	if value is ActorView:
		var actor: Object = value.record()
		return actor != null and _world.actor_supports_original_method(actor, method)
	return value != null and value.has_method(method)

func read_property(value: Object, key: StringName) -> Variant:
	var actor := canonical(value)
	assert(actor != null)
	# WorldCore maps original property names to the sole domain authority;
	# especially position, owner_player, target, state and numerical timeline.
	return _world.read_original_actor_property(actor, key, self)

func write_property(value: Object, key: StringName, replacement: Variant) -> void:
	var actor := canonical(value)
	assert(actor != null)
	_world.write_original_actor_property(actor, key, replacement, self)

func parent_scope(actor: Object) -> Object:
	var scope_id: int = actor.parent_scope_id()
	if scope_id <= 0: return null
	if not _scopes.has(scope_id):
		var scope := ParentScope.new()
		scope.scope_id = scope_id
		_scopes[scope_id] = scope
	return _scopes[scope_id]

func scope_runtime_id(value: Object) -> int:
	_owned()
	assert(value is ParentScope)
	return value.scope_id

func invoke(value: Object, method: StringName, arguments: Array) -> Variant:
	_owned()
	if value is ParentScope:
		assert(method == &"runtime_actor_id" and arguments.is_empty())
		return value.scope_id
	if not value is ActorView:
		assert(not value is Node and not value is Resource)
		assert(value.has_method(method), "missing owner-local service method: " + str(method))
		return value.callv(method, arguments)
	var actor: Object = value.record()
	assert(actor != null, "Enemy attempted to invoke a retired actor")
	match method:
		&"runtime_actor_id": return actor.get_instance_id()
		&"parent_scope": return parent_scope(actor)
		&"is_inside_world": return actor.is_inside_world()
		&"is_queued_for_retirement": return actor.is_queued_for_retirement()
		&"can_process": return actor.can_process()
		&"physics_processing_enabled": return actor.is_physics_processing_enabled()
		&"is_in_group": return _world.actor_is_in_group(actor, arguments[0])
		&"read_meta": return _world.actor_metadata_read(actor, arguments[0], arguments[1] if arguments.size() > 1 else null)
		&"write_meta": _world.actor_metadata_write(actor, arguments[0], arguments[1]); return null
		&"contains_meta": return _world.actor_metadata_contains(actor, arguments[0])
	# Synchronous call: no command queue, no replacement HP or delayed death.
	# WorldCore maps Player/Summon original method ABI to their existing models.
	return _world.invoke_original_actor_method(actor, method, arguments, self)

func invoke_call(value: Object, arguments: Array) -> Variant:
	assert(not arguments.is_empty())
	return invoke(value, StringName(arguments[0]), arguments.slice(1))
