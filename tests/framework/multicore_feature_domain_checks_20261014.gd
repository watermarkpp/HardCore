extends RefCounted

const Factory := preload("res://scripts/features/runtime/domain_factory.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
var _thread := OS.get_thread_caller_id()
var checks: Array[Dictionary] = []
var done := false
var _fixture: Dictionary
var _begun := false
var _replaced := false
var _fatal := false
var _accepted_at := 0
var _neighbor_hp := 0
var _root_ticket: RefCounted
var _original_fact: Dictionary
var _strong_damage := 0
var _weak_damage := 0
func _check(value: bool, label: String) -> void: checks.append({"pass":value,"label":label})
func _init(fixture: Dictionary) -> void:
	_fixture = fixture
	for name: String in ["core", "registry", "profile", "controller", "player", "enemy", "child_neighbor", "skill_id", "bindings", "resource_lease", "reentrant_pump_count", "reentrant_nonzero_count", "fact_observed_before_death_count"]:
		if not fixture.has(name):
			_check(false,"required actual feature production fixture:"+name)
			done = true
	if done: return
	_check(_thread != OS.get_main_thread_id(), "feature factory/Registry/models/budget/ticks are owned by genuine Host S")
	_check(not Factory.validate_required(null,fixture.registry,fixture.profile).success,
		"missing-domain witness rejects admission before any HP/resource/reservation write")
	_check(Factory.validate_required(fixture.core,fixture.registry,fixture.profile).success,
		"complete genuine S services pass strict domain admission")
	_check(fixture.controller._world.is_domain() and fixture.resource_lease.is_domain() and fixture.resource_lease._resources.is_empty(),
		"S uses actual canonical domain identities and retained numeric entitlement, never M Resource objects")
	for binding: Dictionary in fixture.bindings:
		if binding.definition.handler_id == "hc.ignite.v1":
			var fraction := float(binding.definition.config.fraction)
			_check(fraction > 0.0 and float(binding.definition.config.chance) == 1.0,"exact deterministic fixture preserves original compiled trigger probability/power formula")
			if fraction > 0.0:
				_weak_damage = ceili(1.0/fraction)
				_strong_damage = maxi(20,ceili(2.0/fraction))
	_check(_strong_damage > 0 and fixture.enemy.model.current_hp > _strong_damage+_weak_damage,
		"real formal fixture HP supports surviving direct and weaker replacement commits")

func _commit(amount: int, release_id: String) -> Dictionary:
	var controller: RefCounted = _fixture.controller
	var runtime: RefCounted = controller.runtime
	var ticket: RefCounted = runtime.reserve_action(_fixture.skill_id,_fixture.bindings,1,release_id,1)
	_check(ticket != null,"original reservation admits finite feature producer:"+release_id)
	if ticket == null: return {}
	var made := Batch.create(controller._world,release_id,_fixture.skill_id,_fixture.bindings,{"profile_id":_fixture.profile.active_profile_id},controller._clock.simulation_usec(),ticket,_fixture.resource_lease,ticket.chain_context(release_id))
	_check(made.success and made.batch.begin_base_scope(),"original bindings/lease/ticket/chain accept before base HP scope:"+release_id)
	if not made.success: return {}
	var model: Object = _fixture.enemy.model
	var before: int = model.current_hp
	model.take_damage(amount,_fixture.player.handle,{"feature_damage_batch":made.batch,"source_class":"direct","damage_channel":"magic_defense"})
	var facts: Array = made.batch.facts()
	_check(facts.size() == 1,"formal Enemy HP boundary produces exactly one immutable damage fact:"+release_id)
	var result: Dictionary = controller.finish_batch(made.batch)
	_check(result.success and result.outcome == "transferred","one-shot complete fact transfers through real EffectRuntime:"+release_id)
	if facts.size() == 1:
		_check(facts[0].hp_before == before and facts[0].actual_loss == facts[0].hp_before-facts[0].hp_after,
			"receipt/fact record exact committed HP before any reentrant presentation/heal/death observer:"+release_id)
		return facts[0]
	return {}

func after_phase(name: String, _frame: Dictionary, fixture: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == _thread)
	if done or name != "H_GROUP": return
	_fixture = fixture
	var controller: RefCounted = fixture.controller
	var runtime: RefCounted = controller.runtime
	var now: int = controller._clock.simulation_usec()
	if not _begun:
		_begun = true
		_accepted_at = now
		_original_fact = _commit(_strong_damage,"feature:s:root:1")
		_check(not _original_fact.is_empty() and _original_fact.target.runtime_id == fixture.enemy.handle.get_instance_id(),
			"base fact binds the canonical positive Handle ObjectID rather than RefCounted model ID")
		return
	var metrics: Dictionary = runtime.metrics()
	if not _replaced and runtime.active_count() > 0:
		_check(int(metrics.started) > 0 and runtime.heap_count() == runtime.active_count(),"real fact dispatch owns original indexed heap/status heads")
		var old_handle: String = runtime._states.keys()[0]
		var old_state: Dictionary = runtime._states[old_handle]
		_check(old_state.next_due == old_state.command.period_usec + (old_state.expires-old_state.command.duration_usec),
			"full duration and first period begin at actual S application, preserving original delayed-fact horizon")
		_commit(_weak_damage,"feature:s:root:2")
		_replaced = true
		return
	if _replaced and not _fatal and int(metrics.replaced) > 0 and int(metrics.tick_delivery_count) > 0:
		_check(runtime.active_count() == 1 and int(metrics.replaced) == 1,
			"weaker same-species command replaces one original head without growing parallel states/cues")
		_check(int(metrics.ticks) > 0 and int(metrics.actual_loss) > 0,
			"actual due tick uses original MAC draw and formal receipt/HP pipeline on S")
		_neighbor_hp = fixture.child_neighbor.model.current_hp
		var fatal := _commit(fixture.enemy.model.current_hp,"feature:s:root:fatal")
		_check(not fatal.is_empty() and fatal.hp_after == 0 and fatal.has("commit_ground_origin"),
			"lethal fact freezes actual native commit projection before original death callbacks")
		_fatal = true
		return
	if _fatal and int(metrics.child_actions) > 0:
		_check(fixture.child_neighbor.model.current_hp < _neighbor_hp,
			"original finite death child uses the same canonical planner and real ordered spatial targets to write neighbor HP")
		_check(runtime._pumping == false and runtime.reservation_snapshot().children == runtime.child_count(),
			"outer-only consumer closes budget scope and retains exact child/reservation ownership after reentry")
		_check(fixture.reentrant_pump_count > 0 and fixture.reentrant_nonzero_count == 0,
			"actual same-Core restoration observer reenters pump and every nested call is rejected by original outer-consumer guard")
		_check(fixture.fact_observed_before_death_count > 0,
			"actual Enemy death observer sees the complete frozen fact/receipt that was captured at the unique HP boundary")
		_check(_original_fact.actual_loss == _original_fact.hp_before-_original_fact.hp_after,
			"later periodic/healing/death writes never replace the historical frozen base HP fact")
		_check(controller.presentation.flush(),"original cue lifecycle facts enter actual reliable outbox with M lease pins")
		done = true
	if now - _accepted_at > 6000000:
		_check(false,"real feature direct/tick/replacement/death-child closure completes within six simulation seconds")
		done = true

func close() -> void:
	assert(OS.get_thread_caller_id() == _thread)
	_fixture.clear()
	_root_ticket = null
