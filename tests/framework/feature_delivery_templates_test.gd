extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Authority := preload("res://scripts/features/adapters/feature_authority.gd")
const TEMPLATE_REGISTRY := "res://assets/data/features/templates/template_registry.json"
const MODULE_IDS := ["hc.template.numeric_skills","hc.template.direct_ignite","hc.template.finite_chain"]
const EVENT := "damage_committed:hc.skill.wizard.ice_storm"
var proof:=Proof.new()
var errors: Array[String]=[]

func _ready() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: errors.append(label)

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	var loaded: bool=ContentLayers.reload_feature_catalog(TEMPLATE_REGISTRY)
	check(loaded,"reusable module templates load through the original production catalog publisher")
	if not loaded: _finish(); return
	var configuration: Dictionary=ContentLayers.feature_configuration()
	check(configuration.catalog.modules.size()==3 and configuration.enabled_modules.is_empty(),
		"three registered templates remain default-off and do not install new gameplay")
	check(PlayerState.feature_bundle().sources.is_empty() and PlayerState.feature_bundle().event_index.is_empty(),
		"unselected templates contribute no source or hit subscription")
	var modules: Array=[]
	for id: String in MODULE_IDS:
		var module: Dictionary=configuration.catalog.modules[id]
		check(module.default_enabled==false and module.core_api_version==1 and not module.tests.is_empty(),
			"template declares its activation, core version and verification: "+id)
		modules.append(module)
		check(ContentLayers.set_feature_module_enabled(id,true),"formal activation compiles the template: "+id)
	var bundle: Dictionary=PlayerState.feature_bundle()
	check(bundle.sources.size()==5 and bundle.stat_operations.size()==1 and bundle.skill_operations.size()==1,
		"five stable sources populate exactly the declared numeric, skill and trigger indices")
	check(bundle.event_index.get(EVENT,[]).size()==3 and int(bundle.cost.states_per_target)==3,
		"two independent status definitions and one finite death binding retain the compiler's conservative declared cost")
	check(bundle.is_read_only() and bundle.sources.is_read_only() and bundle.event_index[EVENT].is_read_only(),
		"template consumers receive the original deeply frozen compiled graph")
	var contributions: Array=[]
	for source: Dictionary in bundle.sources.values():
		contributions.append({"source":source,"mechanic_id":source.mechanic_id})
	var compiled:=Compiler.compile(modules,contributions,Authority.build())
	check(compiled.success and compiled.bundle.sources.size()==5,
		"the same template payloads and exact production sources compile through the single compiler")
	var duplicate:=modules.duplicate(false); duplicate.append(modules[0])
	check(not Compiler.compile_catalog(duplicate,Authority.build()).success,"duplicate template module identity is explicitly rejected")
	var repeated:=contributions.duplicate(false); repeated.append(contributions[0])
	check(not Compiler.compile_loadout(configuration.catalog,repeated,Authority.build()).success,
		"duplicate stable contribution identity is rejected before publication")
	var unknown: Array=contributions.duplicate(true); unknown[0].mechanic_id="hc.template.unknown"
	unknown[0].source.mechanic_id="hc.template.unknown"
	check(not Compiler.compile_loadout(configuration.catalog,unknown,Authority.build()).success,
		"unknown template mechanism does not fall back to a display name")
	check(ContentLayers.set_feature_module_enabled("hc.template.finite_chain",false),"withdraw finite-chain template through the original publisher")
	var withdrawn: Dictionary=PlayerState.feature_bundle()
	check(withdrawn.event_index.get(EVENT,[]).size()==1 and withdrawn.sources.size()==3
		and withdrawn.skill_operations.size()==1,"withdrawal removes only its two sources and preserves independent numeric and direct status grants")
	check(bundle.event_index[EVENT].size()==3 and bundle.sources.size()==5,
		"an already captured compiled graph remains unchanged after a later publication")
	check(ContentLayers.set_feature_module_enabled("hc.template.finite_chain",true)
		and PlayerState.feature_bundle().sources==bundle.sources,"re-activation restores the same exact stable source handles")
	for id: String in MODULE_IDS:
		check(ContentLayers.set_feature_module_enabled(id,false),"template safely withdraws at its declared boundary: "+id)
	check(PlayerState.feature_bundle().sources.is_empty() and PlayerState.feature_bundle().event_index.is_empty()
		and PlayerState.feature_bundle().stat_operations.is_empty() and PlayerState.feature_bundle().skill_operations.is_empty(),
		"all templates off restores the existing empty extension indices")
	_check_combinations(configuration.catalog.modules,bundle)
	check(ContentLayers.reload_feature_catalog(),"test restores the formal default registry")
	_finish()

func _check_combinations(modules: Dictionary, captured: Dictionary) -> void:
	for mask in range(8):
		var expected_mechanics: Dictionary={}
		for index in range(MODULE_IDS.size()):
			var id: String=MODULE_IDS[index]
			var selected: bool=(mask & (1 << index))!=0
			var already: bool=ContentLayers.feature_configuration().enabled_modules.has(id)
			var previous: String=PlayerState.feature_bundle().revision
			var changed: bool=ContentLayers.set_feature_module_enabled(id,selected)
			check(changed==(already!=selected) and (already!=selected or PlayerState.feature_bundle().revision==previous),
				"combination changes selection or preserves a no-op revision through the production boundary: "+str(mask)+"/"+id)
			if selected:
				for mechanic: Dictionary in modules[id].mechanics:
					expected_mechanics[mechanic.mechanic_id]=true
		var active: Dictionary=PlayerState.feature_bundle()
		var expected_sources: Dictionary={}
		for handle: String in captured.sources:
			var source: Dictionary=captured.sources[handle]
			if expected_mechanics.has(source.mechanic_id): expected_sources[handle]=source
		var numeric: int=1 if (mask & 1)!=0 else 0
		var direct: int=1 if (mask & 2)!=0 else 0
		var chain: int=1 if (mask & 4)!=0 else 0
		check(active.sources==expected_sources and active.stat_operations.size()==numeric
			and active.skill_operations.size()==numeric and active.event_index.get(EVENT,[]).size()==direct+2*chain
			and int(active.cost.states_per_target)==direct+2*chain,
			"all eight combinations preserve exact stable sources and independent subscriptions: "+str(mask))

func _finish() -> void:
	var written:=proof.write_receipt("feature_delivery_templates_test",proof.records.size(),errors.size())
	print("FEATURE_DELIVERY_TEMPLATES_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
