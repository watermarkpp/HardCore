class_name MapEditorSelection
extends RefCounted

var selected_ids: Array[String] = []


func clear() -> void:
	selected_ids.clear()


func set_single(instance_id: String) -> void:
	selected_ids = [instance_id] if not instance_id.is_empty() else []


func toggle(instance_id: String) -> void:
	if instance_id in selected_ids:
		selected_ids.erase(instance_id)
	elif not instance_id.is_empty():
		selected_ids.append(instance_id)


func contains(instance_id: String) -> bool:
	return instance_id in selected_ids
