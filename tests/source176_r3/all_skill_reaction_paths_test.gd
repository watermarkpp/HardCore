extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Registry := preload("res://scripts/monster_source176/skill_reaction_registry.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const Fixtures := preload("res://tests/helpers/skill_execution_plan_test_fixtures.gd")
var errors: Array[String] = []
var checks := 0
func _ready() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)
func _ground_to_screen(p: Vector2) -> Vector2:
	return F.to_screen(p)
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var service := Combat.new()
	add_child(service)
	var ids := Loader.skill_ids()
	check(ids.size()==33 and Registry.validate_ids(ids).is_empty(),"exact current SOT and registry set")
	var rows: Array = []
	for id: String in ids:
		var definition := Loader.skill(id)
		var family := Registry.family(id)
		var context := Fixtures.default_target_context(true)
		context.merge({"target_is_monster":true,"target_is_undead":true,"target_level":1,
			"target_is_friendly":true,"target_hp":1,"target_max_hp":100,"target_can_tame":true})
		var resources := {"mana":10000,"materials":{"amulet":100,"grey_powder":100,"yellow_powder":100},"selected_material":"grey_powder"}
		var release := "r3:skills:"+id
		var plan := Fixtures.build_canonical_plan(id,3,50,Vector2i.ZERO,Vector2i.RIGHT,context,resources,42,1,release,Fixtures.circle_snapshot(self,id,release,1,Vector2.ZERO,3))
		check(str(plan.get("skill_id",""))==id,"formal planner returns exact skill identity "+id)
		var victim := F.player(self,Vector2(25,20))
		var actor := F.enemy(self,64,Vector2(20,20),victim)
		actor.level = 49
		actor.max_hp = 100000
		actor.current_hp = actor.max_hp
		var before: int = actor._movement_cadence.walk_tick_ms
		var rng_before: int = actor._rng.state
		var result := service.apply_enemy_direct_spell_damage(actor,id,50,null,null,Callable(),9,{},Combat.EnemyMagicDeliveryKind.AUTO)
		if family==&"DIRECT":
			check(bool(result.get("success",false)),"DIRECT actual sink damage "+id)
			check(actor._movement_cadence.walk_tick_ms>=before+800 and actor._movement_cadence.walk_tick_ms<=before+1799,"DIRECT source delay "+id)
		elif family==&"MINE":
			check(bool(result.get("success",false)) and actor._movement_cadence.walk_tick_ms==before,"MINE damage without DIRECT delay")
		else:
			check(str(result.get("failure_reason",""))=="source176_delivery_kind_rejected","dedicated family cannot use direct sink "+id)
			check(actor.current_hp==actor.max_hp and actor._rng.state==rng_before,"wrong sink rejection has no side effects "+id)
		rows.append({"skill_id":id,"family":str(family),"producer":"scripts/skills/skill_runtime_router.gd::build_canonical_plan",
			"operation":plan.get("gameplay_actions",[]),"plan_rejection":plan.get("rejection",{}),
			"sink":"CombatRuntimeService.apply_enemy_direct_spell_damage" if family in [&"DIRECT",&"MINE"] else "dedicated production operation; direct sink rejected",
			"reception_evidence":result,"walk_tick_before":before,"walk_tick_after":actor._movement_cadence.walk_tick_ms,
			"required_semantic_tests":definition.get("required_tests",[]),"evidence_status":"PASS",
			"evidence_scope":"planner and reception; dedicated sinks require critical semantic regressions"})
		F.dispose(actor,victim)
	check(F.write_evidence("SKILL_EXECUTION_MATRIX",{"checks":checks,"errors":errors,"rows":rows}),"write skill matrix")
	print(("R3_SKILL_PATHS_PASS" if errors.is_empty() else "R3_SKILL_PATHS_FAIL")+" count="+str(rows.size())+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
