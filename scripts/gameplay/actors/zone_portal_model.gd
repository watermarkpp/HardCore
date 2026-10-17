extends "interactable_actor_model.gd"
var target_zone := "比奇城"
var target_map_id := -1
var display_name := "前往比奇城"
var portal_role := "travel"
var portal_data: Dictionary = {}


func setup(zone: String, label_text: String) -> void:
	target_zone = zone
	target_map_id = -1
	display_name = label_text
	portal_role = "return" if "返回" in label_text else "travel"
	portal_data.clear()

func setup_map(
	map_id: int,
	label_text: String,
	runtime_portal_data: Dictionary = {}
) -> void:
	target_map_id = map_id
	target_zone = ""
	display_name = label_text
	portal_role = "return" if "返回" in label_text else ("deeper" if "进入" in label_text or "前往" in label_text else "travel")
	portal_data = runtime_portal_data.duplicate(true)

func _has_linked_portal_visual() -> bool:
	return not str(portal_data.get("linked_visual_asset_id", "")).is_empty()


## The authored portal label rides above the placeholder circle by default.
## When a linked portal-gate visual exists, the label moves above that
## visual's top vertex so the artwork and the caption never overlap.

func _label_offset_y() -> float:
	var top_offset := float(portal_data.get("visual_top_offset_px", 0.0))
	if _has_linked_portal_visual() and top_offset > 0.0:
		return -(top_offset + 32.0)
	return -78.0

func _role_color() -> Color:
	match portal_role:
		"return": return Color(0.42, 0.92, 0.56)
		"deeper": return Color(1.0, 0.66, 0.20)
	return Color(0.42, 0.83, 1.0)

func interaction_text() -> String:
	return display_name

func initialize_gameplay() -> void:
	if _ready_complete: _ports.fail("portal_ready_twice"); return
	add_to_group("interactable")
	add_to_group("zone_content")
	if not _ports.create_portal_visual(self): _ports.fail("portal_original_visual_admission_failed"); return
	_ready_complete = true

func interact(game: Object) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if target_map_id >= 0:
		if not portal_data.is_empty() and game.has_method("travel_via_portal"):
			game.travel_via_portal(self, true)
		else:
			game.travel_to_map(target_map_id)
	else:
		game.change_zone(target_zone)

