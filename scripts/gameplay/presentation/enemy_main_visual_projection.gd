extends Node2D

## Main renderer only: no timeline, combat clock, damage or locomotion writer.
const OriginalVisual := preload("res://scripts/monster_visual.gd")
const Overlay := preload("res://scripts/monster_attack_source_overlay.gd")
const SourceFrames := preload("res://scripts/monster_source_frames.gd")
const Projectile := preload("res://scripts/monster_ranged_projectile_effect.gd")
var canonical_service_id: int
var actor: Node2D
var sprite: Sprite2D
var publication: RefCounted
var phase_bridge: Object
var _overlays: Dictionary = {}
var _snapshot: Dictionary = {}

func configure_main(owner_actor: Node2D, service_id: int, main_publication: RefCounted, original_phase_bridge: Object) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or actor != null or owner_actor == null or service_id <= 0 or original_phase_bridge == null:
		push_error("numeric Enemy renderer requires Main and its canonical service mapping")
		return false
	for method in [&"publish_visual_process_qualification"]:
		if not original_phase_bridge.has_method(method):
			push_error("Main visual phase bridge missing: " + str(method))
			return false
	actor = owner_actor
	canonical_service_id = service_id
	publication = main_publication
	phase_bridge = original_phase_bridge
	return true

func apply_event(event: Dictionary) -> bool:
	return apply_event_checked(event)

func apply_event_checked(event: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not _validate_event(event): return false
	var op: StringName = event.operation
	var args: Array = event.arguments
	match op:
		&"visual_configure_actor_y_sort": OriginalVisual.configure_actor_y_sort_item(self, args[0])
		&"visual_create_body_sprite":
			if sprite != null: return false
			sprite = Sprite2D.new()
			sprite.name = "BodySprite"
			OriginalVisual.configure_actor_y_sort_item(sprite, "body_sprite")
			sprite.region_enabled = true
			sprite.region_filter_clip_enabled = true
			sprite.centered = false
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(sprite)
		&"visual_position": position = args[0]
		&"visual_visible": visible = args[0]
		&"sprite_texture":
			var texture: Texture2D = null if args[0] == null else publication.texture_from_token(int(args[0]))
			if args[0] != null and texture == null: return false
			sprite.texture = texture
		&"sprite_region": sprite.region_rect = args[0]
		&"sprite_position": sprite.position = args[0]
		&"visual_process_enabled":
			if not phase_bridge.publish_visual_process_qualification(canonical_service_id, bool(args[0])): return false
		&"visual_redraw": queue_redraw()
		&"actor_redraw": actor.queue_redraw()
		&"attack_overlay_create":
			if _overlays.has(args[0]): return false
			_overlays[args[0]] = Overlay.new()
		&"attack_overlay_setup":
			_overlays[args[0]].setup(args[1], args[2], args[3], args[4], args[5])
		&"attack_overlay_attach": add_child(_overlays[args[0]])
		&"attack_overlay_visible": _overlays[args[0]].visible = args[1]
		&"attack_overlay_queue_free":
			_overlays[args[0]].queue_free()
			_overlays.erase(args[0])
		_: return false
	return true

func publish_snapshot_checked(snapshot: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or snapshot.get("service_id") != canonical_service_id: return false
	for key: String in ["present","uses_final_art","burrowed","dying","targeted","contact_center","ring_radii","foot_radii","ring_center","airborne"]:
		if not snapshot.has(key): return false
	_snapshot = snapshot.duplicate(true)
	queue_redraw()
	return true

func streaming_residency_poll(_now_msec: int) -> bool:
	# The actual Source visual owns this callback; Main cannot run or park it.
	return false

func _draw() -> void:
	if _snapshot.is_empty() or not _snapshot.present or not _snapshot.uses_final_art or _snapshot.burrowed:
		return
	var center: Vector2 = _snapshot.contact_center
	var radii: Vector2 = _snapshot.ring_radii
	_draw_contact_core(center, _snapshot.foot_radii)
	if _snapshot.dying or not _snapshot.targeted:
		return
	center = _snapshot.ring_center
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_polyline(points, Color(1.0, 0.78, 0.18, 0.78), 2.0, true)

func _draw_contact_core(center: Vector2, radii: Vector2) -> void:
	var scale := OriginalVisual.CONTACT_CORE_RADIUS_SCALE
	var points := PackedVector2Array()
	for index in range(25):
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x * scale, sin(angle) * radii.y * scale))
	var alpha: float = OriginalVisual.CONTACT_CORE_ALPHA_AIRBORNE if _snapshot.airborne else OriginalVisual.CONTACT_CORE_ALPHA_GROUNDED
	draw_colored_polygon(points, Color(0.05, 0.04, 0.03, alpha))


const ARG_COUNTS := {"visual_configure_actor_y_sort":1,"visual_create_body_sprite":0,"visual_position":1,
	"visual_visible":1,"sprite_texture":1,"sprite_region":1,"sprite_position":1,"visual_process_enabled":1,
	"visual_redraw":0,"actor_redraw":0,"attack_overlay_create":1,"attack_overlay_setup":6,
	"attack_overlay_attach":1,"attack_overlay_visible":2,"attack_overlay_queue_free":1}
func _validate_event(event: Dictionary) -> bool:
	if event.get("service_id") != canonical_service_id or not event.get("operation") is StringName or not event.get("arguments") is Array: return false
	var op: String = str(event.operation); var args: Array = event.arguments
	if not ARG_COUNTS.has(op) or args.size() != ARG_COUNTS[op]: return false
	if op.begins_with("sprite_") and sprite == null: return false
	if op in ["visual_position","sprite_position"] and not args[0] is Vector2: return false
	if op == "sprite_region" and not args[0] is Rect2: return false
	if op in ["visual_visible","visual_process_enabled"] and not args[0] is bool: return false
	if op == "sprite_texture" and args[0] != null and (not args[0] is int or args[0] == 0): return false
	if op.begins_with("attack_overlay_") and op != "attack_overlay_create" and not _overlays.has(args[0]): return false
	return true

func uses_final_art() -> bool:
	return not _snapshot.is_empty() and bool(_snapshot.uses_final_art)
