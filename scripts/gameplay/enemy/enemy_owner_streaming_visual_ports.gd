extends "res://scripts/gameplay/enemy/enemy_owner_visual_ports.gd"

## Reuses the original numeric catalog, viewport and pure presentation journal.
## Only gameplay-relevant binding mutations use actual Main continuations.
var _resource_primitives: RefCounted
var _numeric_coordinator: RefCounted

func configure_streaming_bindings(primitives: RefCounted, coordinator: RefCounted) -> bool:
	if not _require(_configured and _resource_primitives == null and OS.get_thread_caller_id() == _owner, "streaming visual ports configuration order"): return false
	for provider in [primitives, coordinator]:
		if not _require(provider != null and provider.owner_thread_id() == _owner, "binding dependency owner mismatch"): return false
	for method in ["apply_binding_event", "observe_binding", "binding_fact", "has_binding_fact", "is_configured"]:
		if not _require(primitives.has_method(method), "missing binding primitive " + method): return false
	if not _require(primitives.is_configured() and coordinator.is_healthy() and coordinator.has_method("complete_synchronous_profile"), "binding coordinator not installed"): return false
	_resource_primitives = primitives
	_numeric_coordinator = coordinator
	return true

func emit_visual(service_id: int, operation: StringName, arguments: Array) -> void:
	if not _require(_resource_primitives != null and _resource_primitives.is_configured() and OS.get_thread_caller_id() == _owner and service_id > 0 and _plain(arguments), "binding event outside configured owner"): return
	if str(operation).begins_with("coordinator_"):
		_require(false, "second Main coordinator execution is forbidden")
		return
	if operation not in [&"visual_visible", &"visual_create_body_sprite", &"sprite_texture"]:
		super.emit_visual(service_id, operation, arguments)
		return
	# There is no pending invalidation: prior dependent mutations returned only
	# after actual execution. Journal-only events below preserve every operand
	# of visible && sprite_exists && texture_nonnull and held profile metadata.
	if _resource_primitives.has_binding_fact(service_id):
		var fact: Dictionary = _resource_primitives.binding_fact(service_id)
		if operation == &"visual_visible" and arguments.size() == 1 and arguments[0] == fact.actual_visible:
			super.emit_visual(service_id, operation, arguments)
			return
		if operation == &"sprite_texture" and arguments.size() == 1 and arguments[0] != null and fact.sprite_exists and fact.texture_nonnull:
			var same_profile := false
			var confirmed_texture_in_profile := false
			for action: String in ["idle", "walk", "attack", "hit", "death"]:
				if fact.active_resources.get(action) == arguments[0]: same_profile = true
				if fact.active_resources.get(action) == fact.actual_texture_token: confirmed_texture_in_profile = true
			if same_profile and confirmed_texture_in_profile:
				super.emit_visual(service_id, operation, arguments)
				return
	# Host applies the earlier Main journal prefix first. This mutation itself
	# is NOT added to that journal and therefore cannot execute a second time.
	if _resource_primitives.live_resource_phase():
		if operation == &"visual_create_body_sprite":
			# Creation is structural: its original journal position must precede
			# the region/position writes emitted next by the same Source ready.
			# Queuing a later creation primitive freezes those dependent writes
			# into its prerequisite prefix and executes them without a Sprite.
			super.emit_visual(service_id, operation, arguments)
			_require(_numeric_coordinator.enqueue_live_binding_observation(service_id), "actual initial Sprite observation was not retained")
		else:
			_numeric_coordinator.enqueue_live_binding_event(service_id, operation, arguments)
		return
	_require(_resource_primitives.apply_binding_event(service_id, operation, arguments), "actual binding mutation did not complete")

func confirmed_uses_final_art(service_id: int, active_resources: Dictionary) -> bool:
	if not _require(_resource_primitives != null and _resource_primitives.is_configured() and OS.get_thread_caller_id() == _owner, "final-art read outside configured owner"): return false
	if _resource_primitives.live_resource_phase():
		# Actual Loading/birth binding is a required gameplay closure.
		if not _resource_primitives.has_binding_fact(service_id):
			var pending: Array = _numeric_coordinator.get("_live_bindings")
			var own: Array = []
			for row: Dictionary in pending:
				if row.get("service_id") == service_id: own.append({"op":str(row.get("op")),"cleanup":row.get("cleanup"),"await_initial_binding":row.get("await_initial_binding",false)})
			_require(false, "LIVE final-art read without actual initial binding closure: "+JSON.stringify({"service_id":service_id,"queue_size":pending.size(),"head":{} if pending.is_empty() else {"service_id":pending.front().get("service_id"),"op":str(pending.front().get("op"))},"own_rows":own}))
			return false
	if not _resource_primitives.has_binding_fact(service_id):
		if not _require(_resource_primitives.observe_binding(service_id), "initial actual binding observation missing"): return false
	var fact: Dictionary = _resource_primitives.binding_fact(service_id)
	if not _require((fact.active_resources == active_resources or _resource_primitives.live_resource_phase() and _numeric_coordinator.live_binding_transaction_pending(service_id)), "profile decision precedes its actual binding receipt"): return false
	return bool(fact.actual_visible) and bool(fact.sprite_exists) and bool(fact.texture_nonnull)

func complete_synchronous_profile(service_id: int, mapping: Dictionary) -> Dictionary:
	if not _require(_numeric_coordinator != null, "test synchronous coordinator unavailable"): return {}
	return _numeric_coordinator.complete_synchronous_profile(service_id, mapping)

func request_visual_resources(_visual: RefCounted, _mapping: Dictionary, _monster: int, _request_async: bool) -> Variant:
	_require(false, "inject the single numeric coordinator; no presentation replay")
	return null

func visual_subscription_is_current(_service_id: int, _key: String) -> bool:
	_require(false, "inject the single numeric coordinator; no presentation reply snapshot")
	return false
