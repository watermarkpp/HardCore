extends RefCounted
## Captures actual Main SceneTree preorder at the legal original checkpoint.
## No actor profile/HP reads, Node reparenting, fake SceneTree-root ID or priority.
var _tree: SceneTree
var _checkpoint: RefCounted
var _generation := 0
func configure_main(tree: SceneTree, checkpoint: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _tree != null or tree == null or checkpoint == null or not checkpoint.has_method("verify_original_profile_ui_receiver_closure"): return false
	_tree = tree; _checkpoint = checkpoint
	return true
func capture_original_world_root(root: Node, world: Dictionary, checkpoint: Dictionary) -> Dictionary:
	if _tree == null or not is_instance_valid(root) or root.get_tree() != _tree or not root.is_inside_tree() or root.is_queued_for_deletion(): return {"success":false,"errors":["actual_registered_root_required"]}
	var proof: Dictionary = _checkpoint.verify_original_profile_ui_receiver_closure(checkpoint)
	if proof.get("success") != true or checkpoint.get("world_context") != world: return {"success":false,"errors":["actual_source_tree_checkpoint_required"]}
	var ledger: Array[Dictionary] = []
	_capture_preorder(_tree.root,-1,ledger)
	var root_ordinal := -1
	for record: Dictionary in ledger:
		if record.runtime_id == root.get_instance_id(): root_ordinal = record.ordinal
	if root_ordinal < 0: return {"success":false,"errors":["actual_root_not_in_preorder"]}
	_generation += 1
	var publication := {"contract_id":"hardcore.source_tree.root_preorder.v1","generation":_generation,"producer_runtime_id":get_instance_id(),"producer_script_sha256":get_script().get_source_code().sha256_text(),"scene_tree_root_id":_tree.root.get_instance_id(),"world_context":world.duplicate(true),"world_root_id":root.get_instance_id(),"world_root_ordinal":root_ordinal,"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"checkpoint":checkpoint.duplicate(true),"ledger":ledger}
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary = graph.capture(publication,true,false)
	if captured.get("success") != true: return {"success":false,"errors":["actual_runtime_publication_capture_failed"],"details":captured}
	return {"success":true,"publication":captured.value}
func _capture_preorder(node: Node, parent: int, ledger: Array[Dictionary]) -> void:
	var ordinal := ledger.size()
	ledger.append({"ordinal":ordinal,"runtime_id":node.get_instance_id(),"parent_ordinal":parent,"name":str(node.name),"scene_file_path":node.scene_file_path,"script_path":node.get_script().resource_path if node.get_script()!=null else "","process_priority":node.process_priority,"physics_priority":node.process_physics_priority,"internal_process":node.is_processing_internal(),"internal_physics":node.is_physics_processing_internal(),"process":node.is_processing(),"physics":node.is_physics_processing()})
	for child: Node in node.get_children(true): _capture_preorder(child,ordinal,ledger)
