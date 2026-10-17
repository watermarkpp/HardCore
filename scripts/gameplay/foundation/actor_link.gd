extends RefCounted

## Owner-local equivalent of a persistent Node reference. This lease protects
## storage only. Original world, alive, queued and accepted-action checks stay
## at their respective consumers; ActorRef remains the release identity.
var _owner_thread := OS.get_thread_caller_id()
var _registry: RefCounted
var _runtime_id := 0
var _lease := 0

static func capture(registry: RefCounted, actor: Object) -> RefCounted:
	if registry == null or not is_instance_valid(actor):
		return null
	var runtime_id: int = actor.get_instance_id()
	if registry.resolve_runtime_actor(runtime_id) != actor:
		return null
	var lease: int = registry.retain_runtime_actor(runtime_id)
	if lease <= 0:
		return null
	var result := new()
	result._registry = registry
	result._runtime_id = runtime_id
	result._lease = lease
	return result

func runtime_id() -> int:
	return _runtime_id if OS.get_thread_caller_id() == _owner_thread else 0

func resolve_record() -> Object:
	if OS.get_thread_caller_id() != _owner_thread or _registry == null or _lease <= 0:
		return null
	return _registry.resolve_runtime_actor(_runtime_id)

func borrow_model() -> Object:
	var actor := resolve_record()
	return actor.model() if actor != null else null

func dispose() -> void:
	if OS.get_thread_caller_id() != _owner_thread or _registry == null or _lease <= 0:
		return
	if _registry.release_actor(_lease):
		_lease = 0
		_registry = null

func _notification(what: int) -> void:
	# Do not call a method on self at PREDELETE. A live domain reference is
	# confined to S; Main and W only receive numeric identities/plain values.
	if what == NOTIFICATION_PREDELETE and _registry != null and _lease > 0:
		assert(OS.get_thread_caller_id() == _owner_thread, "persistent actor lease destroyed outside its owner")
		if OS.get_thread_caller_id() == _owner_thread:
			var released: bool = _registry.release_actor(_lease)
			assert(released, "persistent actor lease could not release retired storage")
			_lease = 0
			_registry = null
