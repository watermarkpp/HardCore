extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Death := preload("res://scripts/features/handlers/death_burst_handler.gd")
const Child := preload("res://scripts/features/contracts/child_action_lease.gd")
var _zone_generation := 1
var current_map_id := 910002
var proof := Proof.new()
var errors: Array[String] = []
var world: RefCounted
var runtime: RefCounted
var bindings: Array = []

func _ready() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	proof.record(value,label)
	if not value: errors.append(label)

func _unexpected_child(_request: Dictionary, _ticket: RefCounted, _bindings: Array,
	_source: Node2D, _resources: RefCounted) -> Dictionary:
	check(false,"identity-only protocol test never executes a child")
	return {"success":false,"reason":"identity_test_has_no_child_execution"}

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/state_loan_lifetime_registry.json")
		and ContentLayers.set_feature_module_enabled("hc.validation.state_loan_lifetime",true),
		"formal existing default-off direct/child module supplies real compiled bindings")
	bindings=PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size()==2,"formal producer includes both persistent and death subscriptions")
	if bindings.size()!=2: _finish(); return
	world=World.new(); world.configure(self,PlayerState)
	var clock:=Clock.new(); clock.configure(self)
	var combat:=Combat.new(); add_child(combat)
	runtime=Runtime.new()
	check(runtime.configure(world,clock,combat) and runtime.configure_child_executor(_unexpected_child),
		"actual runtime owns the pre-HP producer capability")
	for mode in range(3): _reject_without_stealing(mode)
	# Pure schema/handler unit. It does not claim a production periodic ticket,
	# enable unsupported periodic bindings or submit HP/child work.
	var root := "identity:periodic:root"
	var lineage := {"contract_id":"hardcore.combat.chain_context.v1","root_release_id":root,
		"release_id":root+":tick:1000000","parent_release_id":root,
		"root_skill_id":"hc.skill.wizard.ice_storm","generation":0,"maximum_generation":1}
	check(Batch._lineage_valid(lineage,lineage.release_id,"hc.skill.wizard.ice_storm","periodic"),
		"generation-zero periodic work has its own release identity while preserving the root")
	check(not Batch._lineage_valid(lineage,lineage.release_id,"hc.skill.wizard.ice_storm","direct"),
		"a unique periodic label cannot masquerade as the root direct producer")
	var bad:=lineage.duplicate(true); bad.parent_release_id=""
	check(not Batch._lineage_valid(bad,bad.release_id,"hc.skill.wizard.ice_storm","periodic"),
		"periodic work must identify the status-producing parent")
	var alias:=lineage.duplicate(true); alias.release_id=root; alias.parent_release_id=""
	check(not Batch._lineage_valid(alias,root,"hc.skill.wizard.ice_storm","periodic"),
		"a periodic tick cannot reuse the root direct release identity")
	var binding: Dictionary={}
	for candidate: Dictionary in bindings:
		if candidate.definition.handler_id==Death.ID: binding=candidate.duplicate(true)
	check(not binding.is_empty(),"pure handler unit uses the formal registered death definition")
	if not binding.is_empty():
		binding.definition.source_classes=["direct","periodic","child"]
		var fact := {"contract_id":"hardcore.combat.damage_fact.v1","fact_id":lineage.release_id+":hp:0",
			"release_id":lineage.release_id,"skill_id":"hc.skill.wizard.ice_storm","source_class":"periodic",
			"damage_channel":"magic_defense","target_survived_commit":false,
			"hp_before":5,"hp_after":0,"actual_loss":5,"requested_damage":10,
			"historical_credit":{"profile_id":"identity-credit"},
			"target":{"world":world.capture_world(),"runtime_id":1,"life_generation":1},
			"commit_ground_origin":{"x":1.0,"y":2.0},"chain_context":lineage}
		var commands: Array=Death.commands(fact,binding)
		check(commands.size()==1 and commands[0].parent_release_id==lineage.release_id
			and commands[0].generation==1 and commands[0].root_release_id==root,
			"fatal periodic fact preserves its unique parent and advances child generation once")
		if commands.size()==1:
			var command: Dictionary=commands[0]
			check(command.get("parent_source_class")=="periodic",
				"a periodic child explicitly names its parent producer variant")
			var made: Dictionary=Child.create(command,world,root+":child:after_tick")
			check(made.success,"a typed generation-one periodic parent enters the existing child request owner")
			if made.success:
				check(made.request.child_action_lease.chain_context().parent_release_id==lineage.release_id,
					"the child request preserves the exact tick parent rather than rewriting it to the root")
			var missing: Dictionary=command.duplicate(true); missing.erase("parent_source_class")
			check(not Child.create(missing,world,root+":child:missing_type").success,
				"an untyped generation-one non-root parent cannot impersonate the old direct variant")
			var wrong: Dictionary=command.duplicate(true); wrong.parent_source_class="direct"
			check(not Child.create(wrong,world,root+":child:wrong_type").success,
				"a wrong explicit parent type cannot broaden child request identity")
			var aliased: Dictionary=command.duplicate(true); aliased.parent_release_id=root
			aliased.parent_fact_id=root+":hp:0"
			check(not Child.create(aliased,world,root+":child:aliased").success,
				"an explicit periodic parent may never reuse the root direct identity")
		fact.target_survived_commit=true; fact.hp_before=10; fact.hp_after=5
		check(Death.commands(fact,binding).is_empty(),"a nonfatal periodic fact produces no death child")
		fact.target_survived_commit=false; fact.hp_before=5; fact.hp_after=0
		fact.chain_context=alias; fact.release_id=root
		check(Death.commands(fact,binding).is_empty(),"pure death handler also rejects an aliased periodic root identity")
	check(not runtime.has_work() and runtime.errors.is_empty(),"all identity probes retire without HP or hidden runtime work")
	check(ContentLayers.reload_feature_catalog(),"identity-only owner restores the formal registry")
	_finish()

func _reject_without_stealing(mode: int) -> void:
	var root: String="identity:root:"+str(mode)
	var ticket: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",bindings,1,root,1)
	check(ticket!=null,"identity probe has an actual accepted reservation: "+str(mode))
	if ticket==null: return
	var canonical: Dictionary=ticket.chain_context(root)
	check(canonical.is_read_only(),"published lineage cannot mutate the runtime-owned producer authority: "+str(mode))
	var supplied: Dictionary=canonical.duplicate(true)
	var source_class := "direct"
	if mode==0: supplied.maximum_generation=2
	elif mode==1: supplied={}
	else: source_class="periodic"
	var before: Dictionary=runtime.reservation_snapshot()
	var wrong: Dictionary=Batch.create(world,root,"hc.skill.wizard.ice_storm",bindings,{},0,ticket,null,supplied,source_class)
	check(not wrong.success,"wrong lineage/source is rejected before producer claim: "+str(mode))
	check(ticket.can_begin_release(root) and runtime.reservation_snapshot()==before,
		"rejected caller preserves the legitimate unique qualification and all promises: "+str(mode))
	var valid: Dictionary=Batch.create(world,root,"hc.skill.wizard.ice_storm",bindings,{},0,ticket,null,canonical)
	check(valid.success and valid.batch.requires_commit_context(),"the original legitimate producer still succeeds exactly once: "+str(mode))
	if valid.success:
		var duplicate: Dictionary=Batch.create(world,root,"hc.skill.wizard.ice_storm",bindings,{},0,ticket,null,canonical)
		check(not duplicate.success,"a consumed producer cannot be claimed twice: "+str(mode))
		valid.batch.finish_production()
	if wrong.success: wrong.batch.finish_production()
	ticket.close()
	check(runtime.reservation_snapshot().actions==0,"identity probe has no newly retained writer, batch or root: "+str(mode))

func _finish() -> void:
	var written:=proof.write_receipt("periodic_producer_identity_test",proof.records.size(),errors.size())
	print("PERIODIC_PRODUCER_IDENTITY_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
