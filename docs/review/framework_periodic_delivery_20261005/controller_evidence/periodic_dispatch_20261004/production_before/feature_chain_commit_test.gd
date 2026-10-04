extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Enemy := preload("res://scripts/enemy.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
var batch_type: Variant = Batch

class MovingObserverEnemy extends Enemy:

	var move_after_commit := false
	var heal_after_commit := false
	func _refresh_overhead_health() -> void:
		if move_after_commit: global_position = Vector2(777,888)
		if heal_after_commit: current_hp = max_hp
		super._refresh_overhead_health()

func _ready() -> void: _run.call_deferred()

func _check(value: bool,label: String) -> void:
	checks += 1; proof.record(value,label)
	if not value: errors.append(label)

func _ground_to_screen(value: Vector2) -> Vector2: return value*10.0-Vector2(50,25)
func _screen_to_ground(value: Vector2) -> Vector2: return (value+Vector2(50,25))/10.0

func _lineage(release: String,source_class: String) -> Dictionary:
	return {"contract_id":"hardcore.combat.chain_context.v1","root_release_id":"chain:root:1",
		"release_id":release,"parent_release_id":"chain:root:1" if source_class=="child" else "",
		"root_skill_id":"hc.skill.wizard.ice_storm","generation":1 if source_class=="child" else 0,
		"maximum_generation":2}

func _target() -> MovingObserverEnemy:
	var actor := MovingObserverEnemy.new()
	actor.setup(GameData.get_monster_by_id(19),null); add_child(actor)
	actor.set_physics_process(false)
	actor.configure_runtime_map_projection(current_map_id,_ground_to_screen,_screen_to_ground)
	actor.global_position = _ground_to_screen(Vector2(12.5,-3.0))
	actor.max_hp = 100; actor.current_hp = 30
	actor.direct_spell_anti_magic_points = 0
	actor.direct_spell_magic_defense_min = 0; actor.direct_spell_magic_defense_max = 0
	actor.direct_spell_stats_valid = true
	return actor

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var world := World.new(); world.configure(self,PlayerState)
	_check(Batch.new().has_method("chain_context"),"the real HP batch must own a frozen finite lineage before death children can be produced")
	if not Batch.new().has_method("chain_context"):
		_finish(); return
	var combat: Variant = Combat.new()
	add_child(combat)
	for source_class: String in ["direct","periodic","child"]:
		var release := "chain:child:1" if source_class=="child" else "chain:root:1"
		var lineage := _lineage(release,source_class)
		var credit := {"profile_id":PlayerState.active_profile_id}
		var created: Dictionary = batch_type.create(world,release,"hc.skill.wizard.ice_storm",[],credit,0,null,null,lineage,source_class)
		_check(created.success,"typed "+source_class+" lineage enters the existing batch")
		if not created.success: continue
		var batch: RefCounted = created.batch
		lineage.maximum_generation = 99; credit.profile_id = "later:owner"
		_check(batch.chain_context().is_read_only() and batch.chain_context().maximum_generation==2,
			"accepted "+source_class+" lineage cannot be enlarged by caller mutation")
		_check(batch.begin_base_scope(),source_class+" base HP scope opens")
		var actor := _target(); actor.move_after_commit=true; actor.heal_after_commit=true
		var cadence_before: Variant = actor.get("_attack_timer")
		var rng := RandomNumberGenerator.new(); rng.seed = 481516
		var source_rng_before: int = actor.get("_rng").state
		var rng_before: int = rng.state
		var wrong: Dictionary = (combat.apply_feature_periodic_chain_damage(actor,100,null,rng,{},batch)
			if source_class=="child" else combat.apply_feature_child_damage(actor,100,null,rng,{},batch))
		_check(not wrong.success and actor.current_hp==30 and rng.state==rng_before,
			source_class+" wrong callback rejects before HP and independent RNG")
		_check(batch.errors.is_empty() and batch.facts().is_empty(),
			source_class+" wrong callback must not steal or poison the original legal commit qualification")
		if source_class=="direct":
			actor.take_damage(100,null,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense",
				"commit_ground_origin":{"x":999.0,"y":999.0}})
		else:
			var delivered: Dictionary = (combat.apply_feature_child_damage(actor,100,null,rng,{"profile_id":PlayerState.active_profile_id},batch)
				if source_class=="child" else combat.apply_feature_periodic_chain_damage(actor,100,null,rng,{"profile_id":PlayerState.active_profile_id},batch))
			_check(delivered.success and delivered.actual_loss==30,source_class+" uses the real MAC and actor HP port with commit-time receipt")
			_check(actor.get("_attack_timer")==cadence_before and actor.get("_rng").state==source_rng_before,
				source_class+" does not request STRUCK or direct magic walk-delay RNG")
		var facts: Array = batch.facts()
		_check(actor.current_hp==100 and actor.global_position==Vector2(777,888),source_class+" post-commit callback really moves and heals the actor")
		_check(facts.size()==1,source_class+" commits exactly one fact")
		if facts.size()==1:
			var fact: Dictionary = facts[0]
			_check(fact.hp_before==30 and fact.hp_after==0 and fact.actual_loss==30 and not fact.target_survived_commit,
				source_class+" death is captured before a callback restores HP")
			_check(fact.source_class==source_class and fact.chain_context==batch.chain_context(),source_class+" retains exact damage classification and finite lineage")
			_check(fact.commit_ground_origin=={"x":12.5,"y":-3.0} and fact.commit_ground_origin.is_read_only(),
				source_class+" captures authoritative mapped Ground GU before callbacks and ignores caller geometry")
			_check(fact.historical_credit.profile_id==PlayerState.active_profile_id,
				source_class+" retains the original profile credit after caller mutation")
		_check(batch.errors.is_empty() and batch.finish_base_scope() and batch.consume().size()==1,
			source_class+" buffer finishes and transfers once without fake HP work")
		actor.queue_free(); await get_tree().process_frame
	var broken := _lineage("chain:root:1","direct")
	var cases: Array = [broken.merged({"generation":1},true),broken.merged({"maximum_generation":-1},true),
		broken.merged({"maximum_generation":true},true),broken.merged({"release_id":"foreign"},true),
		broken.merged({"root_skill_id":"hc.skill.warrior.fire_sword"},true),broken.merged({"unknown":true},true)]
	for candidate: Dictionary in cases:
		_check(not batch_type.create(world,"chain:root:1","hc.skill.wizard.ice_storm",[],{},0,null,null,candidate,"direct").success,
			"invalid root lineage rejected before HP: "+JSON.stringify(candidate))
	_check(not batch_type.create(world,"chain:root:1","hc.skill.wizard.ice_storm",[],{},0,null,null,{},"child").success,
		"unscoped child damage cannot impersonate a root direct batch")
	var periodic: Dictionary = batch_type.create(world,"chain:root:1","hc.skill.wizard.ice_storm",[],{},0,null,null,_lineage("chain:root:1","periodic"),"periodic")
	periodic.batch.begin_base_scope()
	var immune := _target(); immune.replace_actor_capability_source("fixture:periodic:immune",["hc.immune.periodic"])
	var independent := RandomNumberGenerator.new(); independent.seed=93827
	var initial_rng: int=independent.state
	var immune_result: Dictionary=combat.apply_feature_periodic_chain_damage(immune,100,null,independent,{},periodic.batch)
	_check(immune_result.success and immune_result.actual_loss==0 and immune.current_hp==30
		and independent.state==initial_rng and periodic.batch.facts().is_empty(),
		"real periodic immunity produces no fake committed death and consumes no random roll")
	immune.replace_actor_capability_source("fixture:periodic:immune",[])
	var zero_result: Dictionary=combat.apply_feature_periodic_chain_damage(immune,0,null,independent,{},periodic.batch)
	_check(zero_result.success and zero_result.actual_loss==0 and independent.state==initial_rng and immune.current_hp==30,
		"zero damage stays zero without consuming the original legal periodic qualification")
	var final_periodic: Dictionary=combat.apply_feature_periodic_chain_damage(immune,100,null,independent,{},periodic.batch)
	_check(final_periodic.success and final_periodic.actual_loss==30 and periodic.batch.facts().size()==1,
		"after immune and zero no-ops the same legal periodic batch delivers one actual first death")
	_check(immune.collision_layer==0 and immune.collision_mask==0 and not immune.is_in_group("enemies"),
		"periodic first death immediately removes collision and live targeting membership")
	periodic.batch.finish_base_scope(); immune.queue_free(); await get_tree().process_frame
	var child: Dictionary=batch_type.create(world,"chain:child:1","hc.skill.wizard.ice_storm",[],{},0,null,null,_lineage("chain:child:1","child"),"child")
	child.batch.begin_base_scope(); var dying:=_target()
	var old_life: int=int(dying.get_meta("hc_combat_life_epoch"))
	var lethal: Dictionary=combat.apply_feature_child_damage(dying,100,null,independent,{},child.batch)
	_check(lethal.success and lethal.actual_loss==30 and dying.current_hp==0 and child.batch.facts().size()==1,
		"child first death traverses the existing MAC and HP mutation authority")
	_check(dying.collision_layer==0 and dying.collision_mask==0 and not dying.is_in_group("enemies"),
		"child first death immediately removes collision before deferred death art and rewards")
	_check(child.batch.facts()[0].target.life_generation==old_life and int(dying.get_meta("hc_combat_life_epoch"))==old_life+1,
		"child fact owns the committed old life while the death authority retires that life exactly once")
	child.batch.finish_base_scope(); dying.queue_free(); await get_tree().process_frame
	var valid: Dictionary = batch_type.create(world,"chain:root:1","hc.skill.wizard.ice_storm",[],{},0,null,null,_lineage("chain:root:1","direct"),"direct")
	var invalid_actor := _target(); invalid_actor.configure_runtime_map_projection(current_map_id,Callable(),Callable())
	valid.batch.begin_base_scope(); var hp_before: int = invalid_actor.current_hp
	invalid_actor.take_damage(10,null,{"feature_damage_batch":valid.batch,"source_class":"direct","damage_channel":"magic_defense"})
	_check(invalid_actor.current_hp==hp_before and valid.batch.facts().is_empty(),"missing mapped geometry refuses the chain commit before HP with no identity fallback")
	invalid_actor.queue_free(); await get_tree().process_frame
	# Audited wrong-public-entry and Combat projection recovery boundaries.
	for source_class: String in ["periodic","child"]:
		var release := "chain:child:1" if source_class=="child" else "chain:root:1"
		var made: Dictionary=batch_type.create(world,release,"hc.skill.wizard.ice_storm",[],{},0,null,null,_lineage(release,source_class),source_class)
		_check(made.success,source_class+" wrong-entry probe owns a legal finite batch")
		if not made.success: continue
		var batch: RefCounted=made.batch; batch.begin_base_scope()
		var actor:=_target()
		var attack_before: float=float(actor.get("_attack_timer"))
		var actor_rng: int=actor.get("_rng").state
		actor.take_damage(10,null,{"feature_damage_batch":batch,"source_class":source_class,"damage_channel":"magic_defense"})
		_check(actor.current_hp==30 and float(actor.get("_attack_timer"))==attack_before and actor.get("_rng").state==actor_rng,
			"matching "+source_class+" caller label cannot turn the direct public entry into a chain HP or STRUCK entry")
		_check(batch.facts().is_empty() and batch.errors.is_empty(),source_class+" wrong public entry preserves the legal batch qualification")
		actor.configure_runtime_map_projection(current_map_id,Callable(),Callable())
		var rng:=RandomNumberGenerator.new(); rng.seed=54892
		var rng_before: int=rng.state
		var result: Dictionary=combat.apply_feature_child_damage(actor,100,null,rng,{},batch) if source_class=="child" \
			else combat.apply_feature_periodic_chain_damage(actor,100,null,rng,{},batch)
		_check(not result.success and rng.state==rng_before and actor.current_hp==30 \
			and batch.errors.is_empty() and batch.facts().is_empty(),
			"bad projection through Combat "+source_class+" refuses before RNG/HP and keeps qualification")
		actor.configure_runtime_map_projection(current_map_id,_ground_to_screen,_screen_to_ground)
		result=combat.apply_feature_child_damage(actor,100,null,rng,{},batch) if source_class=="child" \
			else combat.apply_feature_periodic_chain_damage(actor,100,null,rng,{},batch)
		_check(result.success and result.actual_loss==30 and batch.facts().size()==1 and batch.errors.is_empty(),
			"after wrong entry and bad projection the same "+source_class+" batch legally commits exactly once")
		_check(actor.collision_layer==0 and actor.collision_mask==0,source_class+" recovered death still removes collision immediately")
		batch.finish_base_scope(); batch.consume()
		actor.queue_free(); await get_tree().process_frame
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_chain_commit_test",checks,errors.size()): errors.append("receipt_write")
	print(("FRAMEWORK_CHAIN_COMMIT_PASS" if errors.is_empty() else "FRAMEWORK_CHAIN_COMMIT_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
