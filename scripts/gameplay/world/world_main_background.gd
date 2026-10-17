extends "res://scripts/world_background.gd"
## Main display projection uses the original map descriptors, textures, wall
## bridge and city layout. Collision objects belong exclusively to Source.
const ActualCoordinator := preload("res://scripts/world_bootstrap_coordinator.gd")
const ActualGothic := preload("res://scripts/layers/presentation/gothic_bich_camp_builder.gd")
var _original_visual_configured := false
var _original_visual_entered := false
var _original_visual_failure := ""
func configure_original_Main_visual_only() -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _original_visual_configured or is_inside_tree() or get_child_count(true) != 0 or not _environment_nodes.is_empty() or not _source_collision_nodes.is_empty() or _source_collision_shape_count != 0: return false
	if not defer_initial_legacy_build_to_coordinator(): return false
	_original_visual_configured = true
	return true
func _ready() -> void:
	if not _original_visual_configured:
		_original_visual_failure = "Main_visual_role_not_configured_before_entry"
		return
	super._ready() # Genuine original z/filter setup; first build is coordinator-owned.
	_original_visual_entered = true
	if not original_visual_environment_is_physics_free(): _original_visual_failure = "Main_visual_entry_contains_physics"
func _physics_free_subtree(node: Node) -> bool:
	if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D: return false
	for child: Node in node.get_children(true):
		if not _physics_free_subtree(child): return false
	return true
func original_visual_environment_is_physics_free() -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not _original_visual_configured or not _original_visual_failure.is_empty() or not _source_collision_nodes.is_empty() or not _source_mask_markers.is_empty() or _source_collision_shape_count != 0 or not _physics_free_subtree(self): return false
	# Original actor-sort props can be siblings of Background. The real owner
	# ledger includes those Nodes, so checking only children would miss them.
	for node: Node in _environment_nodes:
		if is_instance_valid(node) and not _physics_free_subtree(node): return false
	return true
func actual_original_visual_build_state() -> Dictionary:
	return {"ok":_original_visual_entered and original_visual_environment_is_physics_free(),"error":_original_visual_failure,"map_id":_staged_build_map_id,"generation":_staged_generation,"visual_nodes":environment_node_count()}
func prepare_original_visual_map_build(map_id: int, coordinator: WorldBootstrapCoordinator, map_data: Dictionary) -> Dictionary:
	if not _original_visual_entered or not original_visual_environment_is_physics_free() or map_id < 0 or coordinator == null or coordinator.get_script() != ActualCoordinator: return {"ok":false,"error":"actual_Main_visual_map_owner_required"}
	# Both descriptor sets remain complete. Source consumes the original
	# collision definitions from its adopted environment, never Main bodies.
	var prepared: Dictionary = super.prepare_map_build(map_id,coordinator,map_data)
	if prepared.get("ok") != true or not original_visual_environment_is_physics_free():
		_original_visual_failure = "actual_Main_visual_prepare_failed"
		return {"ok":false,"error":_original_visual_failure}
	return prepared
func build_original_visual_map_item(descriptor: Dictionary) -> Node:
	if not _original_visual_entered or not original_visual_environment_is_physics_free(): return null
	if str(descriptor.get("kind","")) not in ["chunk_draw","guard_band","full_ground","instance_sprite","wall_atlas_sprite","wall_chunk_sprite","prop_sprite","light_glow","gothic_camp"]:
		_original_visual_failure = "nonvisual_descriptor_in_Main_display"
		return null
	var node: Node = super.build_one_map_item(descriptor)
	if not original_visual_environment_is_physics_free():
		_original_visual_failure = "actual_Main_visual_build_created_physics"
		return null
	return node
func finish_original_visual_map_build() -> bool:
	if not _original_visual_entered or not original_visual_environment_is_physics_free(): return false
	super.finish_map_build() # Same authored wall sprites/overlays and revision point.
	if not original_visual_environment_is_physics_free():
		_original_visual_failure = "actual_Main_visual_finish_created_physics"
		return false
	return true
func _build_gothic_camp_node(payload: Dictionary) -> Node:
	if not _generation_is_current() or not original_visual_environment_is_physics_free(): return null
	var built: Dictionary = ActualGothic.build(self,payload.get("home",Vector2.ZERO),false)
	_gothic_camp_built = built
	_gothic_camp_layout = built.get("layout",{})
	_environment_nodes.append_array(built.get("nodes",[]))
	var nodes: Array = built.get("nodes",[])
	return nodes.front() as Node if not nodes.is_empty() else null
func build_one_collision(_descriptor: Dictionary) -> CollisionObject2D:
	_original_visual_failure = "legacy_collision_call_on_Main_display"
	return null
func _rebuild_environment() -> void:
	# Legacy implicit zone/focus rebuilding is not a map-owner receipt. Reject
	# it rather than silently running its collision half on the Main backend.
	_original_visual_failure = "legacy_synchronous_rebuild_on_Main_display"
func set_focus_position(world_position: Vector2) -> void:
	if not original_visual_environment_is_physics_free(): return
	_focus_position = world_position
	queue_redraw()
