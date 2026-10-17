extends RefCounted
## Physical loot artwork only. S owns the item, collection, filter and lifetime.
const Display := preload("res://scripts/gameplay/presentation/main_loot_display.gd")
const Layout := preload("res://scripts/loot_name_layout.gd")
const OPERATIONS := [&"create_loot_view",&"loot_filter",&"loot_visual_tick",&"place_loot_name",&"retire_loot_view"]
var _root: Node2D
var _world: Dictionary
var _prefix: WeakRef
var _rows: Dictionary
var _retired: Dictionary
var _exit: Dictionary

func configure_main(root: Node2D, world: Dictionary, prefix: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _root!=null or not is_instance_valid(root) or not root.is_inside_tree() or world.get("contract_id")!="hardcore.execution.world_context.v1" or world.get("world_runtime_id")!=root.get_instance_id() or prefix==null or prefix.get_script()!=preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd"): return false
	var host: Object=prefix.get("_host")
	if host==null or not host.is_class("HardCoreSimulationHost"): return false
	_root=root;_world=world.duplicate(true);_prefix=weakref(prefix)
	return true

func _authenticated(event: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not is_instance_valid(_root) or not _root.is_inside_tree() or _prefix==null or _prefix.get_ref()==null or not _exit.is_empty(): return false
	var consumer: RefCounted=_prefix.get_ref()
	var prefix: Dictionary=consumer.actual_current_original_prefix()
	return consumer.actual_current_original_event()==event and not prefix.is_empty() and event.get("kind")=="original_world_presentation" and event.get("operation") in OPERATIONS and event.get("source_site",{}).get("world_context")==_world and event.get("ordinal") is int and event.ordinal>0 and prefix.get("through_ordinal",0)>=event.ordinal and prefix.get("bridge_generation",0)>0 and prefix.get("journal_generation",0)>0

func apply_original_event(event: Dictionary) -> bool:
	if not _authenticated(event): return false
	var args: Variant=event.get("arguments")
	if not args is Array or args.is_empty() or not args[0] is int or args[0]<=0: return false
	var id: int=args[0]
	if event.operation==&"create_loot_view":
		if args.size()!=8 or _rows.has(id) or _retired.has(id) or not args[1] is String or not args[2] is Dictionary or not args[3] is int or args[3]<0 or not args[4] is Vector2 or not args[4].is_finite() or not args[5] is Dictionary or not args[6] is Dictionary or not args[7] is bool: return false
		var descriptor: Dictionary=args[5]
		if descriptor.is_empty() or not descriptor.get("path") is String or not descriptor.get("kind") is String or not descriptor.get("label_color") is Color or not descriptor.get("fallback_draw_color") is Color or not descriptor.get("display_size") is Vector2: return false
		var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
		var captured: Dictionary=graph.capture(args,true,false)
		if captured.get("success")!=true: return false
		args=captured.value
		var node: Node2D=Display.new()
		if not node.configure_main(args[1],args[2],args[3],args[4],args[5],args[6],args[7]): node.free();return false
		node.name="SourceLoot_%d" % id
		_root.add_child(node)
		if not is_instance_valid(node.name_label) or node.item_record!=args[2] or node.global_position!=args[4]: node.free();return false
		_rows[id]={"view":node,"node_id":node.get_instance_id(),"runtime_id":id,"world":_world.duplicate(true),"create_ordinal":event.ordinal,"item_record":args[2],"gold_amount":args[3]}
		return true
	if not _rows.has(id) or _retired.has(id): return false
	var row: Dictionary=_rows[id]
	if row.world!=_world or not is_instance_valid(row.view) or not row.view.is_inside_tree(): return false
	match event.operation:
		&"loot_filter":
			return args.size()==2 and args[1] is bool and row.view.apply_source_filter(args[1])
		&"loot_visual_tick":
			if args.size()!=2 or not (args[1] is float or args[1] is int) or not is_finite(float(args[1])) or args[1]<0: return false
			row.view.manager_visual_tick(args[1]);return true
		&"place_loot_name":
			if args.size()!=1: return false
			Layout.place_at_home(row.view);return row.view.name_label.position==row.view.name_label_home_position() and row.view.name_label_display_offset==Vector2.ZERO
		&"retire_loot_view":
			if args.size()!=1: return false
			return _retire_row(id,event.ordinal,"actual_Source_cast_exit")
	return false

func _retire_row(id: int, ordinal: int, reason: String) -> bool:
	var row: Dictionary=_rows[id]
	# This pure Node has no physics owner or gameplay callbacks. Retire now so
	# the following exact Map arrival can prove absence in this same prefix.
	row.view.free()
	if is_instance_id_valid(row.node_id): return false
	_retired[id]={"runtime_id":id,"world":row.world,"actual_node_id":row.node_id,"actual_node_absent":true,"retire_ordinal":ordinal,"reason":reason,"actual_Main_process_frame":Engine.get_process_frames()}
	_rows.erase(id)
	return true

func actual_nodes_absent() -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _root==null or not _rows.is_empty(): return false
	for fact: Dictionary in _retired.values():
		if is_instance_id_valid(fact.actual_node_id): return false
	return true

func capture_actual_world_exit(world: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or world!=_world or not is_instance_valid(_root) or not _root.is_inside_tree(): return {"success":false,"status":"INVALID"}
	if not _exit.is_empty(): return _exit
	for id: int in _rows.keys():
		if not _retire_row(id,0,"actual_Main_world_exit_barrier"): return {"success":false,"status":"INVALID"}
	if not actual_nodes_absent(): return {"success":true,"status":"PENDING"}
	_exit={"success":true,"status":"READY","world":_world.duplicate(true),"actual_loot_nodes_absent":true,"actual_loot_facts":_retired.values().duplicate(true),"actual_registry_id":get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames()}
	return _exit

func can_commit_empty_world(before: Dictionary, after: Dictionary) -> bool:
	return OS.get_thread_caller_id()==OS.get_main_thread_id() and is_instance_valid(_root) and _root.is_inside_tree() and before==_world and _exit.is_empty() and actual_nodes_absent() and after.get("contract_id")=="hardcore.execution.world_context.v1" and after.size()==5 and after.get("world_runtime_id")==_root.get_instance_id() and after.get("profile_id")==_world.get("profile_id") and after.get("world_epoch") is int and after.world_epoch>_world.get("world_epoch",-1) and after.get("runtime_map_id") is int and after.runtime_map_id>=0

func commit_empty_world(before: Dictionary, after: Dictionary) -> bool:
	if not can_commit_empty_world(before,after): return false
	_world=after.duplicate(true)
	return true
