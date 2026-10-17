extends RefCounted
const Projectile:=preload("res://scripts/gameplay/presentation/main_enemy_projectile_preview.gd")
const TargetMagic:=preload("res://scripts/gameplay/presentation/main_enemy_target_magic_preview.gd")
const Warrior:=preload("res://scripts/warrior_melee_visual_effect.gd")
const OPERATIONS: Array=[&"enemy_create_effect",&"enemy_effect_tick",&"retire_enemy_effect",&"spawn_target_aligned_melee_visual"]
var _root: Node2D
var _world: Dictionary
var _prefix: WeakRef
var _rows: Dictionary
var _retired: Dictionary
var _melee: Array[Dictionary]
var _exit: Dictionary
func configure_main(root: Node2D, world: Dictionary, consumer: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _root!=null or not is_instance_valid(root) or not root.is_inside_tree() or world.get("world_runtime_id")!=root.get_instance_id() or consumer==null or consumer.get_script()!=preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd") or consumer.get("_host")==null or not consumer.get("_host").is_class("HardCoreSimulationHost"): return false
	_root=root;_world=world.duplicate(true);_prefix=weakref(consumer);return true
func _authenticated(event: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not _exit.is_empty() or not is_instance_valid(_root) or not _root.is_inside_tree() or _prefix==null or _prefix.get_ref()==null: return false
	var consumer: RefCounted=_prefix.get_ref()
	var prefix: Dictionary=consumer.actual_current_original_prefix()
	return consumer.actual_current_original_event()==event and not prefix.is_empty() and event.get("kind")=="original_world_presentation" and event.get("operation") in OPERATIONS and event.get("source_site",{}).get("world_context")==_world and event.get("ordinal") is int and event.ordinal>0 and prefix.get("through_ordinal",0)>=event.ordinal and prefix.get("bridge_generation",0)>0 and prefix.get("journal_generation",0)>0
func apply_original_event(event: Dictionary) -> Variant:
	if not _authenticated(event) or not event.get("arguments") is Array: return false
	var args: Array=event.arguments
	if event.operation==&"spawn_target_aligned_melee_visual": return _melee_create(args,event)
	if args.is_empty() or not args[0] is int or args[0]<=0 or _retired.has(args[0]): return false
	var id: int=args[0]
	if event.operation==&"enemy_create_effect":
		if args.size()!=4 or args[1] not in [&"physical_projectile",&"target_magic"] or not args[2] is Dictionary or not args[3] is Dictionary: return false
		if _rows.has(id):
			var old: Dictionary=_rows[id]
			if old.create_event!=event or old.get("ready")==true: return false
			if not old.view.actual_artwork_ready(): return {"status":"PENDING","error":"actual_original_effect_artwork_loading"}
			old.ready=true;return true
		var descriptor: Dictionary=args[2].duplicate(true)
		var node: Node2D
		if args[1]==&"physical_projectile":
			if descriptor.get("effect_id")!="monster.physical_arrow.v1" or descriptor.get("presentation_only")!=false: return false
			# Only the renderer's copy is preview-only. S's frozen damage record
			# and original first-contact algorithm are never changed.
			descriptor.presentation_only=true
			descriptor.source_instance_id=0;descriptor.target_instance_id=0
			node=Projectile.new();node.setup(descriptor)
		else:
			if descriptor.get("effect_id")!="monster.target_lightning.v1" or not args[3].get("source_world_px") is Vector2 or not args[3].source_world_px.is_finite() or not args[3].get("source_direction8") is int or args[3].source_direction8<0 or args[3].source_direction8>7: return false
			node=TargetMagic.new();node.actual_source_position=args[3].source_world_px;node.actual_source_direction=args[3].source_direction8
			node.setup(descriptor)
		if node.get("_finished")==true or not node.visible and not (args[1]==&"physical_projectile" and node.get("_body_only")==true): node.free();return false
		node.name="SourceEnemyEffect_%d" % id
		_root.add_child(node)
		if node.is_processing() or node.is_physics_processing() or node.is_queued_for_deletion(): node.free();return false
		_rows[id]={"view":node,"node_id":node.get_instance_id(),"node_ids":_node_ids(node),"world":_world.duplicate(true),"kind":args[1],"descriptor":args[2].duplicate(true),"create_event":event.duplicate(true),"ready":false,"last_elapsed":0.0}
		if not node.actual_artwork_ready(): return {"status":"PENDING","error":"actual_original_effect_artwork_loading"}
		_rows[id].ready=true;return true
	if not _rows.has(id): return false
	var row: Dictionary=_rows[id]
	if row.world!=_world or row.get("ready")!=true or not is_instance_valid(row.view) or row.view.get_parent()!=_root: return false
	if event.operation==&"retire_enemy_effect": return args.size()==1 and _retire(id,event.ordinal)
	if event.operation!=&"enemy_effect_tick" or args.size()!=2 or not args[1] is Dictionary: return false
	var state: Dictionary=args[1]
	if state.size()!=5 or not state.get("elapsed") is float or not is_finite(state.elapsed) or state.elapsed<row.last_elapsed or not state.get("duration") is float or not is_finite(state.duration) or state.duration<=0.0 or not state.get("position") is Vector2 or not state.position.is_finite() or not state.get("blocked") is bool or not state.get("finished") is bool: return false
	# Occlusion may shorten original TargetMagic duration below this tick's
	# elapsed; retain exact original numbers instead of clamping/replaying.
	if not row.view.apply_source_tick(state): return {"status":"PENDING","error":"actual_original_effect_frame_loading"}
	row.last_elapsed=state.elapsed
	return true
func _melee_create(args: Array, event: Dictionary) -> bool:
	if args.size()!=5 or not args[0] is Dictionary or not args[1] is String or not args[2] is bool or not args[3] is Vector2 or not args[3].is_finite() or not args[4] is Dictionary: return false
	var geometry: Dictionary=args[4]
	var plan: Dictionary=geometry.get("target_aligned_plan",{})
	if plan.is_empty() or plan.get("target_axis_eligible")!=true or not geometry.get("snapshot_validation_context") is Dictionary or geometry.snapshot_validation_context.is_empty(): return false
	for fact: Dictionary in _melee:
		if fact.get("event_identity")==[event.source_site,event.ordinal]: return false
	var context: Dictionary=preload("res://scripts/gameplay/presentation/original_melee_presentation_context.gd").restore_main(geometry.snapshot_validation_context,args[0],_world,event.source_site)
	if context.is_empty(): return false
	var node: Node2D=Warrior.create_visual(args[0],args[1],{"hit":args[2],"release_id":str(plan.get("release_id",""))},context,args[3])
	if not preload("res://scripts/gameplay/presentation/original_melee_presentation_context.gd").release_main(context):
		if node!=null: node.free()
		return false
	if node==null: return false
	_root.add_child(node);node.add_to_group("zone_content")
	_melee.append({"node_id":node.get_instance_id(),"node_ids":_node_ids(node),"event_identity":[event.source_site,event.ordinal],"release_id":plan.get("release_id"),"world":_world.duplicate(true),"view":weakref(node)})
	return true
func _retire(id: int, ordinal: int) -> bool:
	var row: Dictionary=_rows[id]
	# Observe the whole current tree as well as every ID born under this
	# owner. Reparented/missing historical children remain an absence debt.
	for actual_id: int in _node_ids(row.view):
		if actual_id not in row.node_ids: row.node_ids.append(actual_id)
	row.view.free()
	for actual_id: int in row.node_ids:
		if is_instance_id_valid(actual_id): return false
	_retired[id]={"node_id":row.node_id,"node_ids":row.node_ids.duplicate(),"world":row.world,"retire_ordinal":ordinal,"actual_node_absent":true};_rows.erase(id);return true
func actual_nodes_absent() -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not _rows.is_empty(): return false
	for fact: Dictionary in _retired.values():
		for actual_id: int in fact.node_ids:
			if is_instance_id_valid(actual_id): return false
	for fact: Dictionary in _melee:
		for actual_id: int in fact.node_ids:
			if is_instance_id_valid(actual_id): return false
	return true
func capture_actual_world_exit(world: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or world!=_world or not is_instance_valid(_root): return {"success":false,"status":"INVALID"}
	if not _exit.is_empty(): return _exit
	# A Main world observation is not a Source cast close receipt. Keep the
	# live physical leaves and all S authority debts until close_effect emits
	# the exact retire_enemy_effect at the original S exit checkpoint.
	if not _rows.is_empty(): return {"success":true,"status":"PENDING","error":"await_actual_Source_effect_retirement"}
	for fact: Dictionary in _melee:
		var node: Node2D=fact.view.get_ref()
		if is_instance_valid(node):
			for actual_id: int in _node_ids(node):
				if actual_id not in fact.node_ids: fact.node_ids.append(actual_id)
			node.free()
	if not actual_nodes_absent(): return {"success":true,"status":"PENDING"}
	_exit={"success":true,"status":"READY","world":world.duplicate(true),"actual_enemy_effect_nodes_absent":true,"actual_effect_facts":_retired.values().duplicate(true),"actual_melee_facts":_melee.duplicate(true)}
	# Receipts are plain values; the actual observation WeakRefs stay private.
	for fact: Dictionary in _exit.actual_melee_facts: fact.erase("view")
	return _exit
func can_commit_empty_world(before: Dictionary, after: Dictionary) -> bool:
	return OS.get_thread_caller_id()==OS.get_main_thread_id() and before==_world and _exit.is_empty() and actual_nodes_absent() and after.get("world_runtime_id")==before.get("world_runtime_id") and after.get("profile_id")==before.get("profile_id") and after.get("world_epoch",-1)>before.get("world_epoch",-1)
func commit_empty_world(before: Dictionary, after: Dictionary) -> bool:
	if not can_commit_empty_world(before,after): return false
	_world=after.duplicate(true);return true

var _map_melee_exits: Array[Dictionary]
func prepare_actual_map_melee_exit(transaction: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _prefix==null or _prefix.get_ref()==null or not _exit.is_empty(): return {"status":"INVALID"}
	var consumer: RefCounted=_prefix.get_ref()
	var event: Dictionary=consumer.actual_current_original_event()
	var prefix: Dictionary=consumer.actual_current_original_prefix()
	if prefix.is_empty() or event.get("kind")!="original_world_presentation" or event.get("operation")!=&"source_map_arrival" or event.get("arguments")!=[transaction] or not consumer.get("_host").verify_committed_original_map_arrival(transaction): return {"status":"INVALID"}
	for fact: Dictionary in _map_melee_exits:
		if fact.transaction==transaction: return fact # Same receipt, no new writes.
	if _world!=transaction.get("before_world") or not is_instance_valid(_root) or not _root.is_inside_tree() or not _rows.is_empty(): return {"status":"INVALID","error":"actual_Source_effect_retirements_must_precede_Map_arrival"}
	var ids: Array[int]=[]
	for fact: Dictionary in _melee:
		if fact.world!=_world: continue
		var node: Node2D=fact.view.get_ref()
		if is_instance_valid(node):
			if node.get_parent()!=_root: return {"status":"INVALID"}
			for actual_id: int in _node_ids(node):
				if actual_id not in fact.node_ids: fact.node_ids.append(actual_id)
			node.free()
		for actual_id: int in fact.node_ids:
			if is_instance_id_valid(actual_id): return {"status":"PENDING"}
		ids.append(fact.node_id)
	var receipt: Dictionary={"status":"READY","success":true,"transaction":transaction.duplicate(true),"world":_world.duplicate(true),"actual_melee_node_ids":ids,"actual_melee_nodes_absent":true,"actual_prefix":prefix.duplicate(true),"actual_host_id":consumer.get("_host").get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames()}
	_map_melee_exits.append(receipt)
	return receipt

static func _node_ids(node: Node) -> Array[int]:
	var ids: Array[int]=[node.get_instance_id()]
	for child: Node in node.get_children(): ids.append_array(_node_ids(child))
	return ids
