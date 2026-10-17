extends RefCounted
## Closed original Feature facade calls. This describes transport admission;
## the single Source Coordinator still executes each original business body.
const ARITIES := {"prepare":2,"prepare_code_publication":8,"prepare_code_inputs":6,"request_code_script":3,"retire_resources":1,"cancel_all":0,"cancel_code_owner":2}
const VOID_CALLS := ["retire_resources","cancel_all","cancel_code_owner"]
static func accepts(method: String, arguments: Variant) -> bool:
	return arguments is Array and ARITIES.has(method) and arguments.size() == ARITIES[method]
