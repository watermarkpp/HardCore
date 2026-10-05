extends RefCounted

# Code-owned admission permit, never deserialized from player/content JSON.
# The overlay methods are defined by the accompanying candidate patch.
var _overlay: WeakRef
var _consumer: WeakRef
var _receipt: Dictionary = {}
var _generation := -1
var _cancelled := false

static func issue(overlay: Control, consumer: Node, generation: int) -> RefCounted:
	if not is_instance_valid(overlay) or not is_instance_valid(consumer) or generation < 0:
		return null
	if not overlay.has_method("code_preparation_cover_receipt"):
		return null
	var overlay_script: Script = overlay.get_script() as Script
	if overlay_script == null or not _provider_path_current(overlay_script.resource_path, consumer) or not is_same(overlay.get_parent(), consumer):
		return null
	if not consumer.has_method("is_code_preparation_generation_current"):
		return null
	if not consumer.has_method("is_code_preparation_loading_phase_current") or not bool(consumer.is_code_preparation_loading_phase_current(generation)):
		return null
	if not bool(consumer.is_code_preparation_generation_current(generation)):
		return null
	var receipt: Dictionary = overlay.code_preparation_cover_receipt()
	if receipt.is_empty() or not consumer.is_inside_tree() or consumer.is_queued_for_deletion():
		return null
	var result := new()
	result._overlay = weakref(overlay)
	result._consumer = weakref(consumer)
	result._receipt = receipt.duplicate(true)
	result._receipt.make_read_only()
	result._generation = generation
	return result

func valid_for(consumer: Node, generation: int) -> bool:
	if _cancelled or generation != _generation or _overlay == null or _consumer == null:
		return false
	var current_consumer: Node = _consumer.get_ref()
	var current_overlay: Control = _overlay.get_ref()
	if not is_instance_valid(current_consumer) or not is_same(current_consumer, consumer):
		return false
	if not current_consumer.is_inside_tree() or current_consumer.is_queued_for_deletion():
		return false
	if not current_consumer.has_method("is_code_preparation_generation_current") or not bool(current_consumer.is_code_preparation_generation_current(generation)):
		return false
	if not current_consumer.has_method("is_code_preparation_loading_phase_current") or not bool(current_consumer.is_code_preparation_loading_phase_current(generation)):
		return false
	if not is_instance_valid(current_overlay) or current_overlay.is_queued_for_deletion():
		return false
	var overlay_script: Script = current_overlay.get_script() as Script
	if overlay_script == null or not _provider_path_current(overlay_script.resource_path, current_consumer) or not is_same(current_overlay.get_parent(), consumer):
		return false
	return current_overlay.code_preparation_cover_current(_receipt)

func cancel() -> void:
	_cancelled = true

func observation() -> Dictionary:
	return {"generation": _generation, "cancelled": _cancelled, "cover": _receipt.duplicate(true)}


static func _provider_path_current(path: String, consumer: Node) -> bool:
	if path == "res://scripts/loading_transition_overlay.gd":
		return true
	var consumer_script: Script = consumer.get_script() as Script
	return path == "res://scripts/brand_intro.gd" and consumer_script != null and consumer_script.resource_path == "res://scripts/startup_loading.gd"
