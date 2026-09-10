extends RefCounted

## Test fixture only. Freeze scheduled actor/Timer work without stopping art.
## Never clears target, cooldown, attack count, position, or pending impact.
## Saved nodes are weak references: this guard cannot keep a dead actor alive.
var _saved: Array[Dictionary] = []
var _actor_ref: WeakRef
var _active: bool = false
var _entered_msec: int = -1

func begin(actor: Node, visual: Node) -> bool:
	if _active or not is_instance_valid(actor) or not is_instance_valid(visual):
		return false
	if not actor.is_inside_tree() or not actor.is_ancestor_of(visual):
		return false
	_actor_ref = weakref(actor)
	_entered_msec = Time.get_ticks_msec()
	var nodes: Array[Node] = [actor]
	var cursor: int = 0
	while cursor < nodes.size():
		var node: Node = nodes[cursor]
		cursor += 1
		if node == visual:
			_saved.append({"ref": weakref(node), "mode": node.process_mode, "art": true})
			# Art's own residency timer and frame updates may continue.
			node.process_mode = Node.PROCESS_MODE_ALWAYS
			continue
		var record: Dictionary = {"ref": weakref(node), "mode": node.process_mode, "art": false}
		if node is CollisionObject2D:
			var body := node as CollisionObject2D
			record["disable_mode"] = body.disable_mode
			# Prevent the freeze itself from removing a body's existing collision.
			body.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		_saved.append(record)
		node.process_mode = Node.PROCESS_MODE_DISABLED
		for child: Node in node.get_children(true):
			nodes.append(child)
	_active = true
	return true

func intact() -> bool:
	if not _active:
		return false
	for record: Dictionary in _saved:
		var node: Node = (record["ref"] as WeakRef).get_ref() as Node
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			return false
		if bool(record["art"]):
			if node.process_mode != Node.PROCESS_MODE_ALWAYS:
				return false
		else:
			if node.process_mode != Node.PROCESS_MODE_DISABLED or node.can_process():
				return false
	return true

func elapsed_msec() -> int:
	return maxi(0, Time.get_ticks_msec() - _entered_msec) if _entered_msec >= 0 else 0

func restore() -> bool:
	if not _active:
		return false
	var complete: bool = true
	# Children first, parent last; no frame is yielded in this restoration.
	for index: int in range(_saved.size() - 1, -1, -1):
		var record: Dictionary = _saved[index]
		var node: Node = (record["ref"] as WeakRef).get_ref() as Node
		if not is_instance_valid(node):
			complete = false
			continue
		node.process_mode = int(record["mode"])
		if node is CollisionObject2D and record.has("disable_mode"):
			(node as CollisionObject2D).disable_mode = int(record["disable_mode"])
	_saved.clear()
	_actor_ref = null
	_active = false
	return complete
