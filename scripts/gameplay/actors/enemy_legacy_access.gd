extends RefCounted

## Main-only receiver adapter. No synthetic IDs or shadow actor fields.
var _actor: WeakRef
const ALIASES := {"runtime_actor_id":"get_instance_id", "read_meta":"get_meta",
	"write_meta":"set_meta", "contains_meta":"has_meta", "parent_scope":"get_parent",
	"is_inside_world":"is_inside_tree", "is_queued_for_retirement":"is_queued_for_deletion",
	"physics_processing_enabled":"is_physics_processing"}

func _init(actor: Object = null) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	_actor = weakref(actor) if actor != null else null

func owner_thread_id() -> int:
	return OS.get_main_thread_id()

func self_view() -> Object:
	return _actor.get_ref()

func capture(value: Object) -> RefCounted:
	return weakref(value) if is_instance_valid(value) else null

func resolve(link: RefCounted) -> Object:
	if link == null: return null
	assert(link is WeakRef)
	return link.get_ref()

func resolve_runtime(runtime_id: int) -> Object:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return instance_from_id(runtime_id)

func is_present(value: Variant) -> bool:
	return is_instance_valid(value)

func supports(value: Object, method: StringName) -> bool:
	return value != null and value.has_method(ALIASES.get(method, method))

func is_kind(value: Variant, kind: StringName) -> bool:
	match kind:
		&"player": return value is PlayerCharacter
		&"summon": return value is SummonActor
		&"enemy": return value is EnemyActor
		&"spatial": return value is Node2D
		&"collision": return value is CollisionObject2D
		_: assert(false, "unknown actor kind"); return false

func is_exact_player(value: Object) -> bool:
	return value.get_script() == load("res://scripts/player.gd")

func scope_runtime_id(value: Object) -> int:
	return value.get_instance_id()

func invoke(value: Object, method: StringName, arguments: Array) -> Variant:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	assert(is_instance_valid(value))
	var original: StringName = ALIASES.get(method, method)
	assert(value.has_method(original), "missing original actor method: " + str(original))
	return value.callv(original, arguments)

func invoke_call(value: Object, arguments: Array) -> Variant:
	assert(not arguments.is_empty())
	return invoke(value, StringName(arguments[0]), arguments.slice(1))
