extends RefCounted

## Single feature combat algorithm for BOTH domains. Main service delegates
## here through its legacy stats adapter; S supplies canonical records/models.
## HP remains owned by the original receiver methods in either domain.
const ActorRef := preload("res://scripts/features/contracts/actor_ref.gd")
const ActorLink := preload("res://scripts/gameplay/foundation/actor_link.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
var _thread := OS.get_thread_caller_id()
var _world: RefCounted
var _legacy := WeakRef.new()
func _init(world: RefCounted = null, legacy_service: Node = null) -> void:
	assert((world != null and world.is_domain() and legacy_service == null) or (world == null and legacy_service != null and OS.get_thread_caller_id() == OS.get_main_thread_id()))
	_world = world
	if legacy_service != null: _legacy = weakref(legacy_service)
func _owned() -> void: assert(OS.get_thread_caller_id() == _thread)

func apply_feature_source_restore(source_ref: RefCounted, recipient: Dictionary, amount: int) -> Dictionary:
	_owned()
	if source_ref == null or source_ref.get_script() != ActorRef or source_ref.identity() != recipient or amount <= 0:
		return {"success":false,"reason":"feature_restore_identity","actual_gain":0}
	var source: Object = _world.feature_actor_model(_world.resolve_feature_actor(source_ref)) if _world != null else source_ref.resolve()
	if source == null or not source.has_method("restore_health") or (source.has_method("combat_transition_is_active") and source.combat_transition_is_active()):
		return {"success":true,"reason":"source_unavailable","actual_gain":0}
	# Capture the model's committed gain BEFORE a reentrant observer, exactly as
	# the existing authority. Never infer it by rereading HP after callbacks.
	var actual_gain: int = source.restore_health(amount)
	return {"success":true,"reason":"","actual_gain":actual_gain}

func apply_feature_periodic_damage(target: Object, raw_damage: int, source_actor: Object, tick_rng: RandomNumberGenerator, historical_credit: Dictionary) -> Dictionary:
	return _apply_feature_magic_damage(target,raw_damage,source_actor,tick_rng,historical_credit,null,"periodic")
func apply_feature_periodic_chain_damage(target: Object, raw_damage: int, source_actor: Object, tick_rng: RandomNumberGenerator, historical_credit: Dictionary, batch: RefCounted) -> Dictionary:
	if batch == null: return {"success":false,"reason":"periodic_batch_contract","actual_loss":0}
	return _apply_feature_magic_damage(target,raw_damage,source_actor,tick_rng,historical_credit,batch,"periodic")
func apply_feature_child_damage(target: Object, raw_damage: int, source_actor: Object, child_rng: RandomNumberGenerator, historical_credit: Dictionary, batch: RefCounted) -> Dictionary:
	if batch == null: return {"success":false,"reason":"child_batch_contract","actual_loss":0}
	return _apply_feature_magic_damage(target,raw_damage,source_actor,child_rng,historical_credit,batch,"child")

func _apply_feature_magic_damage(target: Object, raw_damage: int, source_actor: Object, tick_rng: RandomNumberGenerator, historical_credit: Dictionary, batch: RefCounted, source_class: String) -> Dictionary:
	_owned()
	var method := "take_feature_periodic_damage" if source_class == "periodic" else "take_feature_child_damage"
	if source_class == "periodic" and batch != null: method = "take_feature_periodic_chain_damage"
	var model: Object = _world.feature_actor_model(target) if _world != null else target
	var rejected := true
	if is_instance_valid(model):
		rejected = not target.can_receive_damage() if _world != null else bool(_legacy.get_ref().call("_target_rejects_damage",target))
	if not is_instance_valid(model) or rejected or not model.has_method(method) or not model.has_method("has_actor_capability") or tick_rng == null:
		return {"success":false,"reason":source_class+"_target_contract","actual_loss":0}
	# Reentrant death/clear may retire registration during the synchronous HP
	# call. Storage remains borrowed until THIS call returns, as an executing
	# legacy Node's queue_free did. The link grants no new alive/world/life right.
	var target_storage: RefCounted = ActorLink.capture(_world.actor_registry(),target) if _world != null else null
	if _world != null and target_storage == null: return {"success":false,"reason":source_class+"_target_storage","actual_loss":0}
	if batch != null:
		if batch.get_script() != Batch or not batch.requires_commit_context():
			return {"success":false,"reason":source_class+"_batch_contract","actual_loss":0}
		var prepared: Dictionary = batch.prepare_commit_context(target,{"source_class":source_class,"damage_channel":"magic_defense"})
		if not bool(prepared.get("success",false)):
			return {"success":false,"reason":source_class+"_batch_context","actual_loss":0}
	if raw_damage <= 0 or (source_class == "periodic" and bool(model.call("has_actor_capability","hc.immune.periodic"))):
		return {"success":true,"reason":"zero_or_immune","actual_loss":0}
	var stats: Dictionary = {}
	# The formal Enemy model owns runtime buffs/stats. The retired metadata/
	# monster_data fallback is not a formal S reception family.
	var stats_ready := false
	if _world == null:
		stats_ready = bool(_legacy.get_ref().call("_target_stats_with_runtime_buffs_into",model,stats))
	elif model.has_method("direct_spell_runtime_stats_into"):
		var raw_stats_result: Variant = model.call("direct_spell_runtime_stats_into",stats)
		stats_ready = raw_stats_result is bool and raw_stats_result
	if not stats_ready:
		return {"success":false,"reason":source_class+"_target_stats","actual_loss":0}
	var low := int(stats.get("magic_defense_min",-1))
	var high := int(stats.get("magic_defense_max",-1))
	if low < 0 or high < low: return {"success":false,"reason":source_class+"_mac_bounds","actual_loss":0}
	var resolved := maxi(0,raw_damage-tick_rng.randi_range(low,high))
	var receipt := {"hp_before":0,"hp_after":0,"actual_loss":0}
	if resolved > 0:
		if batch == null: model.call(method,resolved,source_actor,historical_credit,receipt)
		else: model.call(method,resolved,source_actor,historical_credit,receipt,batch)
	return {"success":true,"reason":"","actual_loss":receipt.actual_loss,"resolved_damage":resolved}
