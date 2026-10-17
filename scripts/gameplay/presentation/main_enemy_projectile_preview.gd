extends Node2D
## Pure physical renderer owner. The actual original factory/setup/READY/frame
## helper is reused; its flight callbacks NEVER run on Main.
const Original:=preload("res://scripts/monster_ranged_projectile_effect.gd")
var _leaf: Node2D
var _finished: bool:
	get: return _leaf==null or _leaf.get("_finished")==true
var _body_only: bool:
	get: return _leaf!=null and _leaf.get("_body_only")==true
func setup(descriptor: Dictionary) -> void:
	assert(not is_inside_tree() and _leaf==null and descriptor.get("presentation_only")==true)
	_leaf=Original.create_visual(descriptor)
	position=_leaf.position;_leaf.position=Vector2.ZERO
	y_sort_enabled=true
	visible=_leaf.visible
func _ready() -> void:
	# Original READY only installs Sprite2D/art and qualifies processing. It
	# has no timers, ray, instance_from_id, contact or guard callback.
	add_child(_leaf)
	_leaf.set_process(false);_leaf.set_physics_process(false)
	set_process(false);set_physics_process(false)
func original_renderer() -> Node2D: return _leaf
func actual_artwork_ready() -> bool:
	if not is_instance_valid(_leaf) or _leaf.is_queued_for_deletion() or _finished: return false
	if not _leaf.get("_exact_profile").is_empty() and _leaf.get("_sprite")!=null: _leaf._update_exact_frame()
	return _body_only or _leaf.get("_sprite")!=null and _leaf.get("_sprite").texture!=null
func apply_source_tick(state: Dictionary) -> bool:
	_leaf.set("_elapsed_seconds",state.elapsed);_leaf.duration_seconds=state.duration
	global_position=state.position;_leaf.position=Vector2.ZERO;_leaf.set("_blocked_by_world",state.blocked);_leaf.set("_finished",state.finished)
	if state.blocked: _leaf.visible=false
	if not _leaf.get("_exact_profile").is_empty() and _leaf.get("_sprite")!=null: _leaf._update_exact_frame()
	return _body_only or _leaf.get("_sprite")!=null and _leaf.get("_sprite").texture!=null
