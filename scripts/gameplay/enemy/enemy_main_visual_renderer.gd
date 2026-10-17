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
	for method in [&"apply_original_coordinator_operation", &"dispatch_original_visual_callback", &"publish_visual_process_qualification"]:
		if not original_phase_bridge.has_method(method):
			push_error("Main visual phase bridge missing: " + str(method))
			return false
	actor = owner_actor
	canonical_service_id = service_id
	publication = main_publication
	phase_bridge = original_phase_bridge
	return true

func apply_event(event: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	var op: StringName = event.operation
	var args: Array = event.arguments
	if op == &"source_request_profile":
		SourceFrames.request_profile(args[0], args[1])
		return
	if op == &"projectile_prewarm":
		Projectile.prewarm_for_monster_id(args[0])
		return
	assert(int(event.service_id) == canonical_service_id)
	if str(op).begins_with("coordinator_"):
		# The bridge maps the canonical S service to this Main render Node,
		# applies each original operation once at its original phase boundary,
		# and captures actual reply values through main_publication.
		phase_bridge.apply_original_coordinator_operation(self, canonical_service_id, event)
		return
	match op:
		&"visual_configure_actor_y_sort": OriginalVisual.configure_actor_y_sort_item(self, args[0])
		&"visual_create_body_sprite":
			assert(sprite == null)
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
		&"sprite_texture": sprite.texture = null if args[0] == null else publication.texture_from_token(int(args[0]))
		&"sprite_region": sprite.region_rect = args[0]
		&"sprite_position": sprite.position = args[0]
		&"visual_process_enabled": phase_bridge.publish_visual_process_qualification(canonical_service_id, bool(args[0]))
		&"visual_redraw": queue_redraw()
		&"actor_redraw": actor.queue_redraw()
		&"attack_overlay_create":
			assert(not _overlays.has(args[0]))
			_overlays[args[0]] = Overlay.new()
		&"attack_overlay_setup":
			_overlays[args[0]].setup(args[1], args[2], args[3], args[4], args[5])
		&"attack_overlay_attach": add_child(_overlays[args[0]])
		&"attack_overlay_visible": _overlays[args[0]].visible = args[1]
		&"attack_overlay_queue_free":
			_overlays[args[0]].queue_free()
			_overlays.erase(args[0])
		_: push_error("unknown numeric Enemy rendering operation: " + str(op)); assert(false)

func publish_snapshot(snapshot: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id() and int(snapshot.service_id) == canonical_service_id)
	_snapshot = snapshot.duplicate(true)

func streaming_residency_poll(now_msec: int) -> void:
	phase_bridge.dispatch_original_visual_callback(canonical_service_id, &"streaming_residency_poll", [now_msec])

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
