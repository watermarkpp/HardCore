extends RefCounted
## Capture actual Main callback qualification before its sole Source handoff.
## A scope's structural lifetime is not an actor's combat/life authority.
const Scope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")

static func capture_existing(node: Node) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion(): return {"success":false,"error":"actual_existing_Main_scope_required"}
	var tree: SceneTree=node.get_tree()
	if tree==null or node==tree.root: return {"success":false,"error":"actual_owned_nonroot_Node_required"}
	var source_path: Array[int]=[]
	var current: Node=node
	var root_child: Node=node
	var effective: int=Node.PROCESS_MODE_INHERIT
	while current!=null:
		if effective==Node.PROCESS_MODE_INHERIT and current.process_mode!=Node.PROCESS_MODE_INHERIT: effective=current.process_mode
		if current==tree.root: break
		root_child=current
		source_path.push_front(current.get_index(true))
		current=current.get_parent()
	if current!=tree.root or effective not in [1,2,3,4]: return {"success":false,"error":"actual_Main_ancestor_process_mode_required"}
	var nodes: Array[Node]=[]
	_preorder(tree.root,nodes)
	var ordinal: int=nodes.find(node)
	if ordinal<0: return {"success":false,"error":"actual_Main_scope_absent_from_tree"}
	var prototype: RefCounted=Scope.new()
	var structural_life: int=prototype.life_generation
	prototype=null
	var code: Script=node.get_script()
	var path: String=code.resource_path if code!=null else ""
	var scope: Dictionary={"runtime_present":true,"life_generation":structural_life,"inside_world":true,"queued_for_retirement":false,
		"parent_scope_id":node.get_parent().get_instance_id(),"can_process":node.can_process(),
		"process_processing_enabled":node.is_processing(),"physics_processing_enabled":node.is_physics_processing(),
		"ordinary_p_enabled":node.is_processing(),"raw_h_enabled":node.is_physics_processing(),
		"process_priority":node.process_priority,"physics_priority":node.process_physics_priority,
		"process_mode":node.process_mode,"effective_process_mode":effective,
		"source_path":source_path,"tree_ordinal":ordinal,"source_entry":path+":_process" if code!=null and node.has_method("_process") else ""}
	var value: Dictionary={"scope":scope,"node_id":node.get_instance_id(),"root_child_id":root_child.get_instance_id(),"source_path":source_path,"tree_ordinal":ordinal,
		"source_script":path,"source_sha256":code.get_source_code().sha256_text() if code!=null else "",
		"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames()}
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary=graph.capture(value,true,false)
	if captured.get("success")!=true: return {"success":false,"error":"actual_Main_scope_capture_not_plain"}
	var result: Dictionary=captured.value.duplicate(false)
	result.success=true
	return result

static func _preorder(node: Node, output: Array[Node]) -> void:
	output.append(node)
	for child: Node in node.get_children(true): _preorder(child,output)
