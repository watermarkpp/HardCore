class_name HCM30ContextToken
extends RefCounted

## Identity registry: never hash/serialize a map Dictionary to find its token.
## Main-thread only. A bounded strong-reference window prevents ABA reuse;
## evicted identities receive a NEW monotonic token, producing safe cache misses.
const MAX_CONTEXTS := 64
static var _contexts: Array[Dictionary] = []
static var _tokens: Array[int] = []
static var _next_token: int = 1

static func token(context: Dictionary) -> int:
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

static func retained_count() -> int:
	return _contexts.size()
