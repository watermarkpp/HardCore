extends RefCounted
## Real Native Source/journal/picking component, not full SourceWorld.
const Session:=preload("res://scripts/gameplay/source/source_session.gd")
const Journal:=preload("res://scripts/gameplay/world/world_original_event_journal.gd")
const InputCapture:=preload("res://scripts/gameplay/presentation/main_original_pick_input.gd")
const Enemy:=preload("res://scripts/gameplay/actors/enemy_actor_model.gd")
var _host: Object
var _session: RefCounted
var _journal: RefCounted
var _world: Object
var _ids: Array[Object]
var _enemy: RefCounted
var _selected:=0
var _checks: Array[Dictionary]
var _done:=false
var _queried:=false
var _through:=0
var _boot: Dictionary
func project_ground(p: Vector2) -> Vector2: return Vector2(p.x*64.0,p.y*32.0)
func _check(ok: bool,label: String) -> void: _checks.append({"pass":ok,"label":label})
func _selected_enemy(value: Object) -> void:
	_check(value==_enemy,"original Source callback emits same actual Enemy model")
	_selected+=1
func _init(host: Object, boot: Dictionary) -> void:
	print("ENEMY_TRACE S_init_enter")
	_host=host;_boot=boot
	_check(host.bind_original_world_context(boot.world_identity),"actual Native Source world bind")
	print("ENEMY_TRACE S_before_Session")
	_session=Session.new();_session.set("_host",host)
	_journal=Journal.new(_session,int(boot.bridge_generation),1);_session.set("_journal",_journal)
	print("ENEMY_TRACE S_before_Enemy")
	_enemy=Enemy.new();_enemy.target_requested.connect(_selected_enemy)
	_enemy._input_event(null,InputCapture.source_event(boot.pointer),0)
	_enemy._input_event(null,InputCapture.source_event(boot.touch),0)
	var release_event:=InputEventScreenTouch.new();release_event.pressed=false;_enemy._input_event(null,release_event,0)
	_check(_selected==2,"exact original Source Enemy callback accepts two real press kinds and refuses release")
	print("ENEMY_TRACE S_before_World")
	_world=ClassDB.instantiate("HardCoreSimulationWorld2D");_check(_world.initialize(boot.area),"real Source singleton physics space initialized")
	var identity:=Object.new();_ids.append(identity)
	var body: RID=_world.create_static_body(identity.get_instance_id(),Transform2D(0,boot.pointer.canvas_position),[{"type":PhysicsServer2D.SHAPE_CIRCLE,"data":8.0}],1,1)
	_check(body.is_valid() and _world.set_body_pickable(body,true),"real Source-owned body pickable setter, no Main collision body")
	print("ENEMY_TRACE S_before_melee")
	var site: Dictionary={"world_context":boot.world_identity}
	var context: Dictionary=preload("res://scripts/skills/skill_footprint_snapshot.gd").make_absolute_runtime_context(1001,Vector2.ZERO,Vector2.ZERO,Callable(self,"project_ground"))
	context.expected_runtime_map_id=1001
	var release: Dictionary={"origin_ground_gu":Vector2.ZERO,"locked_target_ground_gu_at_release":Vector2(1.2,0.4),"locked_target_valid_at_release":true,"locked_target_instance_id":9001,"live_locked_target_direction_ground_gu":Vector2(1.2,0.4).normalized(),"direction_index":preload("res://scripts/skills/warrior_melee_geometry.gd").direction_index_for_ground_delta_gu(Vector2(1.2,0.4)),"release_id":"enemy_component_melee"}
	var plan: Dictionary=preload("res://scripts/skills/warrior_melee_geometry.gd").target_aligned_melee_release_plan_ground_gu(release,"warrior.thrusting",context)
	var captured: Dictionary=preload("res://scripts/gameplay/presentation/original_melee_presentation_context.gd").capture_source(context,plan.get("skill_footprint_snapshot",{}),boot.world_identity,site)
	_check(not captured.is_empty(),"real Source original converter/strict snapshot exports complete exact pure-value point domain")
	var melee_args: Array=[plan.get("skill_footprint_snapshot",{}),"warrior.thrusting",true,Vector2.ZERO,{"target_aligned_plan":plan,"snapshot_validation_context":captured}]
	print("ENEMY_TRACE S_before_journal")
	for example: Dictionary in boot.examples:
		var object:=Object.new();_ids.append(object);var id: int=object.get_instance_id()
		var descriptor: Dictionary=example.descriptor.duplicate(true);descriptor.source_instance_id=_ids[0].get_instance_id()
		_check(_journal.append({"kind":"original_world_presentation","operation":&"enemy_create_effect","arguments":[id,example.kind,descriptor,example.constructor],"source_site":site}),"S appends actual Source effect birth")
		for elapsed: float in [0.1,0.55]:
			_check(_journal.append({"kind":"original_world_presentation","operation":&"enemy_effect_tick","arguments":[id,{"elapsed":elapsed,"duration":1.0,"position":example.descriptor.target_world_px if example.kind==&"target_magic" else example.descriptor.origin_world_px.lerp(example.descriptor.target_world_px,elapsed),"blocked":false,"finished":false}],"source_site":site}),"S appends exact effect state")
		_check(_journal.append({"kind":"original_world_presentation","operation":&"retire_enemy_effect","arguments":[id],"source_site":site}),"S appends original cast retirement")
	_check(_journal.append({"kind":"original_world_presentation","operation":&"spawn_target_aligned_melee_visual","arguments":melee_args,"source_site":site}),"S appends strict original melee context without Main numeric fallback")
	print("ENEMY_TRACE S_before_freeze")
	var prefix: Dictionary=_journal.freeze_prefix();_through=prefix.through_ordinal
	_check(_journal.register_normal_publication(prefix) and host.register_published_original_main_prefix(prefix),"real journal and Native FIFO register exact effect prefix")
	print("ENEMY_TRACE S_init_complete")
func on_inputs(_domain: String,_packets: Array) -> bool: return true
func on_phase(phase: String,_frame: Dictionary) -> bool:
	if phase=="P_GROUP" and not _queried:
		var result: Dictionary=_world.intersect_original_pick_point(_boot.pointer.canvas_position,0)
		_check(result.get("ok")==true and result.get("limit")==64 and result.get("hits",[]).size()==1 and result.hits[0].collider_id==_ids[0].get_instance_id(),"actual same transformed Main press point reaches S Native real body query")
		_queried=true
	if phase=="P_GROUP" and not _done:
		var ack: Dictionary=_host.completed_original_main_prefix_receipt()
		if not ack.is_empty() and int(ack.get("through_ordinal",-1))>=_through:
			_check(_journal.consume_normal_receipt(ack) and not _journal.has_pending(),"Source consumes actual Native Main ACK and retires exact journal prefix")
			_done=true
	if phase!="PUBLISH": return true
	return _host.publish_snapshot({"done":_done,"checks":_checks},[])
func close_session() -> bool:
	if _journal.has_pending(): return false
	if _world!=null and not _world.close(): return false
	_world=null;_enemy=null
	for object: Object in _ids: object.free()
	_ids.clear();return true
