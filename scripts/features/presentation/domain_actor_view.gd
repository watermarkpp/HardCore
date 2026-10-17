extends RefCounted

## M presentation-only view of a frozen S ActorRef identity. The provider
## resolves its render proxy from ordered accepted snapshots/facts; it may not
## borrow a S Handle/model or create a gameplay authority.
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
var _identity: Dictionary
var _provider: WeakRef
func _init(provider: Object, identity: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	_provider = weakref(provider)
	_identity = Graph.capture(identity).value
func identity() -> Dictionary: return _identity
func resolve(require_alive := true) -> Node:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return _provider.get_ref().call("resolve_feature_cue_actor", _identity, require_alive) as Node
