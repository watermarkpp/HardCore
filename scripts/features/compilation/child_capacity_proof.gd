extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const MAX_EXACT_INTEGER := 9007199254740991

# A conservative derived cost only. The caller still owns trusted handler
# contracts, legal world bounds, per-target slots and the actual reservation.
# No actor, target list, mutation port, clock or gameplay limiter is created.
static func compile(request: Variant, limits: Variant) -> Dictionary:
	if not request is Dictionary or not _keys(request,["maximum_receivers","child_bindings",
		"maximum_generation","binding_count","persistent_bindings"]):
		return _failure("invalid_child_capacity_request")
	for key: String in request:
		if not _integer(request[key]): return _failure("invalid_child_capacity_request")
	var n := int(request.maximum_receivers)
	var b := int(request.child_bindings)
	var g := int(request.maximum_generation)
	var l := int(request.binding_count)
	var s := int(request.persistent_bindings)
	if l <= 0 or b > l or s > l: return _failure("invalid_child_capacity_request")
	if not limits is Dictionary or not _keys(limits,["pending_facts","active_states","receipts"]):
		return _failure("invalid_child_capacity_limits")
	for key: String in limits:
		if not _integer(limits[key]): return _failure("invalid_child_capacity_limits")
	# One beyond the greatest capacity is sufficient to prove rejection; never
	# build an enormous integer or walk G individual generations to discover it.
	var ceiling := maxi(int(limits.pending_facts),maxi(int(limits.active_states),int(limits.receipts)))+1
	var factor := _multiply(n,b,ceiling)
	var generations := _power_sum(factor,g+1,ceiling)
	var facts := _multiply(n,int(generations.sum),ceiling)
	var states := _multiply(facts,s,ceiling)
	var receipts := _multiply(facts,l,ceiling)
	if facts > int(limits.pending_facts): return _failure("child_fact_capacity")
	if states > int(limits.active_states): return _failure("child_state_capacity")
	if receipts > int(limits.receipts): return _failure("child_receipt_capacity")
	var parents := _power_sum(factor,g,ceiling)
	var children := _multiply(_multiply(n,b,ceiling),int(parents.sum),ceiling)
	var captured := Graph.capture({"facts":facts,"states":states,"receipts":receipts,
		"child_actions":children,"maximum_generation":g},16,2)
	return {"success":true,"reason":"","cost":captured.value}

static func _power_sum(factor: int, terms: int, ceiling: int) -> Dictionary:
	# Compose geometric-series blocks in O(log terms):
	# S(a+b)=S(a)+P(a)*S(b), P(a+b)=P(a)*P(b).
	var power := 1
	var sum := 0
	var block_power := mini(factor,ceiling)
	var block_sum := 1
	while terms > 0:
		if (terms & 1) != 0:
			sum=_add(sum,_multiply(power,block_sum,ceiling),ceiling)
			power=_multiply(power,block_power,ceiling)
		terms >>= 1
		if terms == 0: break
		block_sum=_add(block_sum,_multiply(block_power,block_sum,ceiling),ceiling)
		block_power=_multiply(block_power,block_power,ceiling)
	return {"power":power,"sum":sum}

# The serial runtime consumes all current facts before starting another child
# and retires each closed branch's dedup receipts. Total work is still bounded
# by the original geometric proof; it is not all resident at the same time.
# States and the complete breadth-first command frontier remain conservatively
# reserved. No receiver set or gameplay depth is truncated by this distinction.
static func compile_serial_residency(request: Variant, limits: Variant) -> Dictionary:
	var total:=compile(request,{"pending_facts":MAX_EXACT_INTEGER-1,
		"active_states":MAX_EXACT_INTEGER-1,"receipts":MAX_EXACT_INTEGER-1})
	if not total.success: return total
	if not limits is Dictionary or not _keys(limits,["pending_facts","active_states","receipts"]):
		return _failure("invalid_child_capacity_limits")
	for key: String in limits:
		if not _integer(limits[key]): return _failure("invalid_child_capacity_limits")
	var n:=int(request.maximum_receivers)
	var resident_facts:=n*2 if int(request.child_bindings)>0 and int(request.maximum_generation)>0 else n
	var resident_receipts:=_multiply(resident_facts,int(request.binding_count),MAX_EXACT_INTEGER)
	if resident_facts>int(limits.pending_facts) or int(total.cost.child_actions)>int(limits.pending_facts):
		return _failure("child_fact_capacity")
	if int(total.cost.states)>int(limits.active_states): return _failure("child_state_capacity")
	if resident_receipts>int(limits.receipts): return _failure("child_receipt_capacity")
	var cost:=Graph.capture({"facts":resident_facts,"states":int(total.cost.states),"receipts":resident_receipts,
		"child_actions":int(total.cost.child_actions),"maximum_generation":int(total.cost.maximum_generation),
		"total_facts":int(total.cost.facts),"total_receipts":int(total.cost.receipts)},24,2)
	return {"success":true,"reason":"","cost":cost.value}

# Only the runtime's returned-origin-loan protocol can use this resident cost.
# Every root holds N*S loans throughout its remaining production lifetime;
# dead/retired receiver states return their origin loan before a new life uses
# it. Refresh roots retain their own full pool and all shared state owners.
# Cumulative creations/work and the complete command frontier are unchanged.
static func compile_state_loan_residency(request: Variant, limits: Variant) -> Dictionary:
	var total:=compile_serial_residency(request,{"pending_facts":MAX_EXACT_INTEGER-1,
		"active_states":MAX_EXACT_INTEGER-1,"receipts":MAX_EXACT_INTEGER-1})
	if not total.success: return total
	if not limits is Dictionary or not _keys(limits,["pending_facts","active_states","receipts"]):
		return _failure("invalid_child_capacity_limits")
	for key: String in limits:
		if not _integer(limits[key]): return _failure("invalid_child_capacity_limits")
	var resident_states:=_multiply(int(request.maximum_receivers),int(request.persistent_bindings),MAX_EXACT_INTEGER)
	if int(total.cost.facts)>int(limits.pending_facts) or int(total.cost.child_actions)>int(limits.pending_facts):
		return _failure("child_fact_capacity")
	if resident_states>int(limits.active_states): return _failure("child_state_capacity")
	if int(total.cost.receipts)>int(limits.receipts): return _failure("child_receipt_capacity")
	var cost:=Graph.capture({"facts":int(total.cost.facts),"states":resident_states,"receipts":int(total.cost.receipts),
		"child_actions":int(total.cost.child_actions),"maximum_generation":int(total.cost.maximum_generation),
		"total_facts":int(total.cost.total_facts),"total_receipts":int(total.cost.total_receipts),
		"total_state_creations":int(total.cost.states),"state_residency":"returned_origin_loans"},32,2)
	return {"success":true,"reason":"","cost":cost.value}

static func _multiply(a: int, b: int, ceiling: int) -> int:
	if a == 0 or b == 0: return 0
	@warning_ignore("integer_division")
	if a > ceiling/b: return ceiling
	return mini(a*b,ceiling)

static func _add(a: int, b: int, ceiling: int) -> int:
	return ceiling if a >= ceiling-b else a+b

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value)>=0 and float(value)<=MAX_EXACT_INTEGER and float(value)==floor(float(value))

static func _keys(value: Dictionary, required: Array) -> bool:
	if value.size()!=required.size(): return false
	for key: String in required:
		if not value.has(key): return false
	return true

static func _failure(reason: String) -> Dictionary:
	return {"success":false,"reason":reason,"cost":{}}
