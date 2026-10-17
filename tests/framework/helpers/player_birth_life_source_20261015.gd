extends RefCounted
## Actual PlayerModel + original Registry/ActorRef/ActorLink + Native physical
## body on S. This checks constructor/transition identity, not full WorldCore.
const Player := preload("res://scripts/gameplay/actors/player_actor_model.gd")
const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const ActorRef := preload("res://scripts/features/contracts/actor_ref.gd")
const ActorLink := preload("res://scripts/gameplay/foundation/actor_link.gd")
const VisualPublication := preload("res://scripts/gameplay/presentation/source_actor_visual_publication.gd")
const VisualContract := preload("res://scripts/gameplay/presentation/actor_visual_projection_contract.gd")
var _world_context: Dictionary
var registry: RefCounted:
	get: return _registry
func owner_thread_id() -> int: return OS.get_thread_caller_id()
func current_world_identity() -> Dictionary: return _world_context
var _host: Object
var _native: Object
var _model: RefCounted
var _registry: RefCounted
var _record: Object
var _motion: Object
var _timer: Object
var _link: RefCounted
var _first_action: RefCounted
var _checks: Array[Dictionary] = []
var _done := false
var _closed := false
func _check(value: bool, label: String) -> void: _checks.append({"passed":value,"label":label})
func _init(host: Object, boot: Dictionary) -> void:
	_host = host
	_world_context = boot.world_identity
	_check(OS.get_thread_caller_id() != OS.get_main_thread_id(),"real S owns all player/registry/native state")
	_registry = Registry.new()
	_check(_registry.configure_world(boot.world_identity,""),"real original pre-map registry exists before combat life")
	_native = ClassDB.instantiate("HardCoreSimulationWorld2D")
	_check(_native.initialize(boot.area),"actual sole backend space created on S")
	_model = Player.new()
	_check(_model.current_life() == 0 and _model.combat_epoch == 0,"actual PlayerModel constructor retains original zero combat epoch")
	_check(_registry.register_actor(_model,1,&"player",0) == null,"positive Node scope cannot substitute for actual player combat life")
	_record = _registry.register_actor(_model,0,&"player",0)
	_check(_record != null,"initial player runtime can be registered without inventing positive combat life")
	if _record == null:
		_done = true
		return
	var id: int = _record.get_instance_id()
	_check(id > 0 and _model.bind_runtime_actor_id(id),"real positive Object Handle is the original runtime identity")
	_check(_model.current_life() == 0 and _record.identity().is_empty(),"runtime registration neither increments life nor produces ActorRef identity")
	_check(_registry.resolve_runtime_actor(id) == _record,"original object-link lookup sees the present precombat Player")
	_check(ActorRef.capture_domain(_registry,_record) == null and _registry.remaining_lease_count() == 0,"unaccepted combat lifetime cannot acquire ActorRef lease")
	var display: Dictionary = VisualPublication._actual_render_identity(self,_record,_model)
	_check(VisualContract.valid_premap_player_identity(display) and display.runtime_id == id and display.life_generation == 0,"real registered original life-zero Player supplies a separate bounded display descriptor")
	_check(not VisualContract.valid_identity(display) and _record.identity().is_empty() and _registry.remaining_lease_count() == 0,"display capture neither creates a combat identity nor takes an ActorRef lease")
	_check(_registry.register_actor(_model,0,&"player",1) == null,"same original player cannot be registered twice")
	var second := Player.new()
	_check(_registry.register_actor(second,0,&"player",1) == null,"another initial player cannot introduce parallel world authority")
	_check(_registry.register_actor(second,0,&"enemy",1) == null,"zero life exception is not extended to enemy setup")
	_check(_registry.register_actor(second,-1,&"player",1) == null,"negative combat life remains rejected")
	_link = ActorLink.capture(_registry,_record)
	_check(_link != null and _link.borrow_model() == _model,"persistent ActorLink retains the one existing runtime object without freezing life")
	_motion = _native.create_actor(id,boot.motion)
	_check(_motion != null and _motion.get_canonical_id() == id,"actual native body uses the same canonical ObjectID")
	if _motion == null: _done = true; return
	_check(is_equal_approx(_motion.safe_margin(),float(boot.motion.get("safe_margin",0.08))),"real S-owned motion reads its configured collision margin")
	_motion.set_safe_margin(0.125)
	_check(is_equal_approx(_motion.safe_margin(),0.125),"real S-owned motion margin getter still reads live body state")
	_timer = _host.create_timer(1.0)
	_check(_timer != null and is_equal_approx(_timer.time_left,1.0),"real S-owned timer getter reads its actual admitted timer")
	_timer.time_left = 0.75
	_check(is_equal_approx(_timer.time_left,0.75),"real S-owned timer getter observes its authoritative timer update")
	_model.motion = _motion # real Native stop_velocity; no fake motion service.
func on_inputs(_domain: String, _packets: Array) -> bool: return true
func on_phase(phase: String, _frame: Dictionary) -> bool:
	if phase == "H_GROUP" and not _done:
		var hp_before: int = _model.current_hp
		_check(_motion.set_velocity_screen_px_per_sec(Vector2(12,6)),"actual native velocity configured before original transition")
		_check(_model.begin_combat_transition("original-initial-map"),"original PlayerModel begin_combat_transition actually executes")
		_check(_model.combat_epoch == 1 and _record.identity().get("life_generation") == 1,"first original transition advances zero to one exactly once")
		var display: Dictionary = VisualPublication._actual_render_identity(self,_record,_model)
		_check(VisualContract.valid_premap_player_identity(display) and display.life_generation == 1 and not VisualContract.valid_identity(display),"real life transition before map arrival remains display-only while map is still -1")
		_check(_motion.velocity_screen_px_per_sec() == Vector2.ZERO,"original transition stopped the actual native body")
		_check(not _model.begin_combat_transition("reentry") and _model.combat_epoch == 1,"active original transition does not advance life twice")
		_check(_model.finish_combat_transition("original-initial-map"),"original transition completion executes")
		_first_action = ActorRef.capture_domain(_registry,_record)
		_check(_first_action != null and _first_action.resolve_record(false) == _record,"positive original life now permits canonical accepted action capture")
		_check(_model.begin_combat_transition("original-next-map"),"subsequent original transition uses the same PlayerModel")
		_check(_model.current_life() == 2 and _first_action.resolve_record(false) == null,"old accepted life fails after real second transition")
		_check(_link.borrow_model() == _model and _link.resolve_record() == _record,"persistent ActorLink survives original life change on same object")
		_check(_model.current_hp == hp_before,"identity admission and transitions do not create or mutate HP")
		_check(_model.finish_combat_transition("original-next-map"),"second original transition completes")
		_done = true
	if phase != "PUBLISH": return true
	return _host.publish_snapshot({"done":_done,"checks":_checks},[])
func close_session() -> bool:
	if _closed: return true
	if _first_action != null: _first_action.dispose_domain(); _first_action = null
	if _link != null: _link.dispose(); _link = null
	if _model != null: _model.motion = null
	_motion = null
	_timer = null
	if _native != null:
		if not _native.close(): return false
		_native = null
	if _registry != null:
		if not _registry.retire_world() or _registry.remaining_actor_count() != 0 or _registry.remaining_lease_count() != 0: return false
		_registry = null
	_record = null; _model = null; _closed = true
	return true
