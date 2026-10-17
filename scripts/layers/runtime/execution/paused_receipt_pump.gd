extends Node

# Pausing simulation cannot discard an accepted durable writer's receipt.
# Normal unpaused ordering remains in PlayerState._process, before its timers.
var _owner := WeakRef.new()
# Actual Main callback depth; no new clock, writer or gameplay state.
var _original_main_callback_ledger: Dictionary = {}

func configure(owner: Node) -> void:
	_owner = weakref(owner)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	_original_main_callback_ledger["_process"] = int(_original_main_callback_ledger.get("_process",0)) + 1
	_original_source_paused_receipt_pump__process(_delta)
	_original_main_callback_ledger["_process"] -= 1

func _original_source_paused_receipt_pump__process(_delta: float) -> void:
	if not get_tree().paused:
		return
	var owner: Node = _owner.get_ref() as Node
	if is_instance_valid(owner) and not owner.is_queued_for_deletion():
		owner.call("_pump_persistence_receipts")
