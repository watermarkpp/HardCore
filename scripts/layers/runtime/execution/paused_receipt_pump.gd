extends Node

# Pausing simulation cannot discard an accepted durable writer's receipt.
# Normal unpaused ordering remains in PlayerState._process, before its timers.
var _owner := WeakRef.new()

func configure(owner: Node) -> void:
	_owner = weakref(owner)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not get_tree().paused:
		return
	var owner: Node = _owner.get_ref() as Node
	if is_instance_valid(owner) and not owner.is_queued_for_deletion():
		owner.call("_pump_persistence_receipts")
