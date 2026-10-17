extends Node2D
## Actual original factory renderer, with a detached plain presentation copy.
## No Source ObjectID is ever given to its ObjectDB fallback branches.
const Original:=preload("res://scripts/monster_target_magic_effect.gd")
var actual_source_position: Vector2
var actual_source_direction: int
var _leaf: Node2D
var _finished: bool:
	get: return _leaf==null or _leaf.get("_finished")==true
func setup(descriptor: Dictionary) -> void:
	assert(not is_inside_tree() and _leaf==null and actual_source_position.is_finite() and actual_source_direction in range(8))
	var preview: Dictionary=descriptor.duplicate(true)
	preview.source_instance_id=0 # No Main ObjectDB lookup of a Source identity.
	preview.source_world_px=actual_source_position # Early-return before fallback.
	_leaf=Original.create_visual(preview)
	_leaf.source_direction8=actual_source_direction # Actual S visual row, before READY.
	position=_leaf.position;_leaf.position=Vector2.ZERO
	y_sort_enabled=true
	visible=_leaf.visible
func _ready() -> void:
	# Original READY is Sprite/RenderOrder only; priest ray is exclusively in
	# original _process, which is disabled before returning this same stack.
	add_child(_leaf)
	_leaf.set_process(false);_leaf.set_physics_process(false)
	set_process(false);set_physics_process(false)
func original_renderer() -> Node2D: return _leaf
func actual_artwork_ready() -> bool:
	if not is_instance_valid(_leaf) or _leaf.is_queued_for_deletion() or not _leaf.visible: return false
	_leaf._update_presentation()
	return _leaf.get("_target_sprite")!=null and (_leaf.source_monster_id!=Original.COW_KING_ID or _leaf.get("_elapsed_seconds")<Original.CLIENT_MAGIC_RELEASE_SECONDS or _leaf.get("_target_sprite").texture!=null)
func apply_source_tick(state: Dictionary) -> bool:
	_leaf.set("_elapsed_seconds",state.elapsed);_leaf.set("_duration_seconds",state.duration)
	global_position=state.position;_leaf.position=Vector2.ZERO;_leaf.set("_fly_blocked_by_world",state.blocked);_leaf.set("_finished",state.finished)
	_leaf._update_presentation()
	return actual_artwork_ready()
