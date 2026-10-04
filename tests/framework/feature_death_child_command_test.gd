extends Node

const Handlers := preload("res://scripts/features/handlers/handler_registry.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Authority := preload("res://scripts/features/adapters/feature_authority.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _binding() -> Dictionary:
	return {"handle":"death:source:1","source":{"instance_id":"death:item:1","slot":"hc.slot.weapon","mechanic_id":"hc.death_burst.fixture"},
		"definition":{"mechanic_id":"hc.death_burst.fixture","kind":"trigger","event":"damage_committed",
		"skill_id":"hc.skill.wizard.ice_storm","handler_id":"hc.death_burst.v1","tags":[],
		"source_classes":["direct","periodic","child"],"dedup":"per_target_life_per_root_death",
		"lifecycle":"child_chain","config":{"fraction":0.5,"radius_gu":2.0,"maximum_generation":1}}}

func _fact() -> Dictionary:
	return {"contract_id":"hardcore.combat.damage_fact.v1","fact_id":"player:1:action:2:hp:0",
		"release_id":"player:1:action:2","skill_id":"hc.skill.wizard.ice_storm",
		"source_class":"direct","damage_channel":"magic_defense","requested_damage":15,
		"hp_before":10,"hp_after":0,"actual_loss":10,"target_survived_commit":false,
		"target":{"world":{"epoch":1},"runtime_id":20,"life_generation":3},"source":{},
		"historical_credit":{"profile_id":"fixture-owner"},"commit_ground_origin":{"x":2.0,"y":3.0},
		"chain_context":{"contract_id":"hardcore.combat.chain_context.v1",
		"root_release_id":"player:1:action:2","release_id":"player:1:action:2","parent_release_id":"",
		"root_skill_id":"hc.skill.wizard.ice_storm","generation":0,"maximum_generation":1}}

func _check(value: bool, label: String) -> void:
	checks+=1; proof.record(value,label)
	if not value: errors.append(label)

func _run() -> void:
	var fact := _fact(); var binding := _binding()
	var commands: Array = Handlers.commands(fact,binding)
	_check(commands.size()==1,"a committed first death with an explicit finite chain produces one closed child request")
	if commands.size()!=1:
		_finish(); return
	var command: Dictionary=commands[0]
	_check(command.op=="RequestChildAction" and command.action_id=="hc.child.death_burst.v1"
		and command.raw_damage==5 and command.radius_gu==2.0 and command.source_class=="child",
		"child describes the authored actual-loss damage and radius, without submitting HP itself")
	_check(command.root_release_id=="player:1:action:2" and command.parent_release_id=="player:1:action:2"
		and command.parent_fact_id=="player:1:action:2:hp:0" and command.generation==1 and command.maximum_generation==1,
		"root, parent fact and next generation stay separate and explicit")
	_check(command.origin=={"x":2.0,"y":3.0} and command.historical_credit=={"profile_id":"fixture-owner"}
		and command.parent_target==fact.target and command.source_handle=="death:source:1",
		"death location, historical credit, old life identity and exact contribution remain owned values")
	fact.commit_ground_origin.x=99.0; fact.historical_credit.profile_id="later-profile"
	binding.definition.config.fraction=1.0
	_check(command.is_read_only() and command.origin.is_read_only() and command.parent_target.is_read_only()
		and command.origin.x==2.0 and command.historical_credit.profile_id=="fixture-owner" and command.raw_damage==5,
		"later position, profile or configuration mutations cannot rewrite a queued child")
	var periodic:=_fact(); periodic.source_class="periodic"
	periodic.release_id+="\u003atick:1000000"; periodic.fact_id=periodic.release_id+":hp:0"
	periodic.chain_context.release_id=periodic.release_id
	periodic.chain_context.parent_release_id=periodic.chain_context.root_release_id
	_check(Handlers.commands(periodic,_binding()).size()==1,"a real periodic lethal fact remains eligible without posing as direct damage")
	var last:=_fact(); last.source_class="child"; last.chain_context.generation=1
	last.release_id="child:1"; last.chain_context.release_id="child:1"; last.chain_context.parent_release_id="player:1:action:2"
	_check(Handlers.commands(last,_binding()).is_empty(),"authored terminal generation emits no further child; it is not a hidden queue truncation")
	var unsafe:=_binding(); unsafe.definition.config.erase("maximum_generation")
	_check(Handlers.commands(_fact(),unsafe).is_empty(),"undeclared or infinite recurrence has no executable request")
	unsafe=_binding(); unsafe.definition.config.maximum_generation=2
	_check(Handlers.commands(_fact(),unsafe).is_empty(),"a live definition cannot enlarge the already accepted finite chain")
	for field: String in ["actual_loss","hp_before","requested_damage"]:
		var broken:=_fact(); broken[field]=0
		_check(Handlers.commands(broken,_binding()).is_empty(),"nonlethal or invalid committed loss is rejected: "+field)
	var survived:=_fact(); survived.hp_after=1; survived.actual_loss=9; survived.target_survived_commit=true
	_check(Handlers.commands(survived,_binding()).is_empty(),"a surviving target is not a death trigger")
	for field: String in ["chain_context","commit_ground_origin","historical_credit"]:
		var missing:=_fact(); missing.erase(field)
		_check(Handlers.commands(missing,_binding()).is_empty(),"missing frozen ownership field is rejected: "+field)
	var wrong:=_fact(); wrong.chain_context.release_id="wrong-action"
	_check(Handlers.commands(wrong,_binding()).is_empty(),"a foreign current release cannot reuse this lineage")
	wrong=_fact(); wrong.chain_context.root_skill_id="hc.skill.warrior.fire_sword"
	_check(Handlers.commands(wrong,_binding()).is_empty(),"root skill scope cannot be inferred from a display name or another source")
	wrong=_fact(); wrong.skill_id="hc.skill.warrior.fire_sword"
	_check(Handlers.commands(wrong,_binding()).is_empty(),"a generation-zero direct fact cannot contradict its accepted root skill identity")
	wrong=_fact(); wrong.erase("skill_id")
	_check(Handlers.commands(wrong,_binding()).is_empty(),"a missing actual root skill cannot be manufactured from the binding or lineage")
	var descendant:=_fact(); descendant.skill_id="hc.child.death_burst.v1"; descendant.source_class="child"
	descendant.release_id="child:identity:1"; descendant.chain_context.release_id=descendant.release_id
	descendant.chain_context.parent_release_id=descendant.chain_context.root_release_id
	descendant.chain_context.generation=1; descendant.chain_context.maximum_generation=2
	var descendant_binding:=_binding(); descendant_binding.definition.config.maximum_generation=2
	_check(Handlers.commands(descendant,descendant_binding).size()==1,
		"an explicitly classified descendant action identity may differ from its accepted root skill")
	wrong=_fact(); wrong.chain_context.parent_release_id="unexpected-parent"
	_check(Handlers.commands(wrong,_binding()).is_empty(),"a root generation cannot claim an undeclared parent")
	wrong=_fact(); wrong.source_class="ambient"
	_check(Handlers.commands(wrong,_binding()).is_empty(),"unknown damage classification never defaults to direct")
	wrong=_fact(); wrong.commit_ground_origin.x=INF
	_check(Handlers.commands(wrong,_binding()).is_empty(),"nonfinite death geometry is rejected before any planner call")
	wrong=_fact(); wrong.commit_ground_origin.x=1.0e300
	_check(Handlers.commands(wrong,_binding()).is_empty(),"JSON-finite origin must also fit the actual engine geometry representation")
	unsafe=_binding(); unsafe.definition.config.radius_gu=1.0e300
	_check(Handlers.commands(_fact(),unsafe).is_empty(),"JSON-finite radius cannot overflow the actual engine geometry")
	wrong=_fact(); wrong.damage_channel="unclassified"
	_check(Handlers.commands(wrong,_binding()).is_empty(),"unknown committed damage channel cannot authorize a magic child")
	unsafe=_binding(); unsafe.definition.config.execute="arbitrary"
	_check(Handlers.commands(_fact(),unsafe).is_empty(),"unknown config execution fields are rejected")
	unsafe=_binding(); unsafe.definition.config.fraction=0.01
	_check(Handlers.commands(_fact(),unsafe).is_empty(),"rounded zero child damage remains zero rather than inventing a minimum hit")
	seed(72143); var expected:=randi(); seed(72143)
	Handlers.commands(_fact(),_binding()); var observed:=randi()
	_check(expected==observed,"pure child preparation leaves the existing global RNG stream unchanged")
	var incomplete: Dictionary=_binding().definition; incomplete.config.erase("maximum_generation")
	var module: Dictionary={"schema_version":1,"module_id":"hc.death_burst.fixture","module_version":1,"core_api_version":1,
		"requires":[],"conflicts":[],"capabilities":["combat.post_hit","combat.child"],"handlers":["hc.death_burst.v1"],
		"resource_dependencies":[],"cost":{"commands_per_event":1,"states_per_target":0},"mechanics":[incomplete],
		"tests":["tests/framework/feature_death_child_command_test.tscn"]}
	_check(not Compiler.compile_catalog([module],Authority.build()).success,
		"a module lacking a finite contract and complete production port cannot be published by the pure command probe")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_death_child_command_test",checks,errors.size()): errors.append("receipt_write")
	print(("FRAMEWORK_DEATH_CHILD_COMMAND_PASS" if errors.is_empty() else "FRAMEWORK_DEATH_CHILD_COMMAND_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
