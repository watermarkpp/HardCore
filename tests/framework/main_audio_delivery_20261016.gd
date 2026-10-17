extends "res://tests/framework/main_visual_qualification_bridge_20261016.gd"
## Actual claimed Native prefix + actual Main header/Node pose/canvas read.
## Does not assert full Caster ticket/playback/World startup acceptance.
func _init() -> void:
	source_script = preload("res://tests/framework/helpers/main_audio_delivery_source_20261016.gd")
func apply_original_main_journal_event(event: Dictionary) -> bool:
	if event.get("operation") != &"caster_presentation": return super.apply_original_main_journal_event(event)
	var command: Dictionary = event.arguments[0]
	var source: Dictionary = command.payload.source_pose
	var view: Node2D = _registry.get("_actors")[source.actor_identity.runtime_id].view
	var which: int = command.payload.fixture_case
	view.visible = which != 2
	var observed: Dictionary = _registry.capture_actual_original_audio_delivery(event)
	if which == 3:
		check(observed.get("status") == "REJECTED_STALE_OWNER" and observed.get("actual_identity",{}).get("life_generation") == 1,"old actual header cannot impersonate the requested new life")
		return observed.get("status") == "REJECTED_STALE_OWNER"
	check(observed.get("status") == "OBSERVED","actual Main delivery reads real header-only root without full snapshot or sprite")
	if observed.get("status") != "OBSERVED": return false
	check(view.global_position == source.position_screen_px and observed.position_screen_px == view.global_position and observed.global_transform_with_canvas == view.get_global_transform_with_canvas(),"real Main pose application precedes its actual canvas read")
	check(observed.visible == view.visible and observed.visible_in_tree == view.is_visible_in_tree() and observed.visible_rect == view.get_viewport().get_visible_rect(),"visibility and viewport belong to the actual Main root")
	var audible: bool = observed.visible and observed.visible_in_tree and observed.viewport_available and observed.visible_rect.has_point(observed.global_transform_with_canvas.origin)
	check(audible == (which == 0),"visible/offscreen/hidden cases use real canvas gate:"+str(which))
	var projected: Dictionary = _registry.actual_original_audio_projection(source.actor_identity)
	check(projected.get("present") == true and projected.get("monster_id") == 1234 and view.visual.sprite == null,"delivery permits audio identity only and never manufactures complete visual binding")
	var forged: Dictionary = event.duplicate(true)
	forged.arguments[0].payload.source_pose.position_screen_px += Vector2.ONE
	check(_registry.capture_actual_original_audio_delivery(forged).get("status") == "INVALID","a modified event cannot borrow the genuine current prefix")
	return true
func _finish() -> void:
	var written: bool = proof.write_receipt("main_audio_delivery_20261016",proof.records.size(),failed)
	print("MAIN_AUDIO_DELIVERY_20261016_","PASS" if written and failed == 0 else "FAIL")
	get_tree().quit(0 if written and failed == 0 else 1)
