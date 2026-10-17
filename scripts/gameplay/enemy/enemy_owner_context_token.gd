extends RefCounted

## Same-source owner-local service. One instance per S owner, shared by actors.
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var deps: Dictionary
var actors: Object

func configure_owner(bindings: Dictionary, actor_access: Object) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread:
		push_error("Enemy shared service configured twice or from another owner")
		return false
	if actor_access == null or actor_access is Node or actor_access is Resource or not actor_access.has_method("owner_thread_id") or actor_access.owner_thread_id() != _owner_thread:
		push_error("Enemy shared service requires owner-local actor access")
		return false
	actors = actor_access
	deps = {}
	_configured = true
	return true

func owner_thread_id() -> int:
	return _owner_thread


## Identity registry: never hash/serialize a map Dictionary to find its token.
## Main-thread only. A bounded strong-reference window prevents ABA reuse;
## evicted identities receive a NEW monotonic token, producing safe cache misses.
const MAX_CONTEXTS := 64
var _contexts: Array[Dictionary] = []
var _tokens: Array[int] = []
var _next_token: int = 1

func token(context: Dictionary) -> int:
	for index: int in range(_contexts.size()):
		if is_same(_contexts[index], context):
			return _tokens[index]
	var result: int = _next_token
	_next_token += 1
	if _contexts.size() >= MAX_CONTEXTS:
		_contexts.pop_front()
		_tokens.pop_front()
	_contexts.append(context)
	_tokens.append(result)
	return result

func retained_count() -> int:
	return _contexts.size()
