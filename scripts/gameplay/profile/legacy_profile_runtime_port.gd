extends RefCounted

var _facade: WeakRef
var world_owners: Dictionary = {}

func _init(facade: Node) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	_facade = weakref(facade)

func global_randi() -> int:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return randi()

func global_randi_range(low: int, high: int) -> int:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return randi_range(low, high)

func next_service() -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	await (_facade.get_ref() as Node).get_tree().process_frame

func register_world(owner: Node) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	# Even an unsaved profile's live world owns accepted callbacks and package
	# lifecycle. An empty persistence identity must not bypass that boundary.
	if is_instance_valid(owner) and owner.is_inside_tree():
		world_owners[owner.get_instance_id()] = weakref(owner)

func unregister_world(owner: Node) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if is_instance_valid(owner):
		world_owners.erase(owner.get_instance_id())

func feature_publication_context(active_profile_id: String) -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	# Delegate readiness to the same registered worlds that own profile
	# replacement. No second world clock, identity or lifecycle coordinator.
	var active := false
	var ready := not (_facade.get_ref() as Node).get_tree().paused
	var scopes := {}
	var scope_ready := true
	for runtime_id: int in world_owners.keys():
		var owner: Node = (world_owners[runtime_id] as WeakRef).get_ref() as Node
		if not is_instance_valid(owner) or not owner.is_inside_tree():
			world_owners.erase(runtime_id)
			continue
		active = true
		if owner.has_method("feature_publication_scope"):
			scopes[runtime_id] = owner.call("feature_publication_scope")
		else:
			scope_ready = false
		if owner.is_queued_for_deletion() or not owner.has_method("gameplay_input_is_enabled") \
			or not bool(owner.call("gameplay_input_is_enabled")):
			ready = false
			continue
		var actor: Variant = owner.get("player")
		if not is_instance_valid(actor) or not actor.has_method("combat_action_snapshot") \
			or not actor.has_method("has_pending_combat_release") \
			or bool(actor.call("has_pending_combat_release")) \
			or bool(actor.call("combat_action_snapshot").get("active", true)):
			ready = false
	return {"world_active":active, "world_ready":ready, "scope_ready":scope_ready,
		"scope":{"profile_id":active_profile_id, "owners":scopes}}

func profile_is_owned_by_gameplay() -> bool:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	# CharacterSelect may replace profile state only after the old world has
	# finished its logout barrier and left the tree. A queued deletion still
	# owns deferred deaths and persistence completions until _exit_tree ends.
	for runtime_id: int in world_owners.keys():
		var owner: Node = (world_owners[runtime_id] as WeakRef).get_ref() as Node
		if is_instance_valid(owner) and owner.is_inside_tree():
			return true
		world_owners.erase(runtime_id)
	return false

