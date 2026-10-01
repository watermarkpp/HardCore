extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
var errors: Array[String] = []
var checks := 0
var rows: Array = []
func _ready() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)
func zero_mac(_id: String, _damage: int, _stats: Dictionary) -> int:
	return 0
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var service := Combat.new()
	add_child(service)
	for level: int in [49,50]:
		for kind: String in ["DIRECT","MINE","EVADED","MAC_ZERO"]:
			var victim := F.player(self,Vector2(25,20))
			var actor := F.enemy(self,64,Vector2(20,20),victim)
			actor.level = level
			actor.max_hp = 1000000
			actor.current_hp = actor.max_hp
			actor.direct_spell_anti_magic_points = 10 if kind=="EVADED" else 0
			actor._rng.seed = 9317
			var reference := RandomNumberGenerator.new()
			reference.seed = 9317
			var sample := reference.randi_range(0,999)
			var tick: int = actor._movement_cadence.walk_tick_ms
			var rng: int = actor._rng.state
			var skill := "wizard.fire_wall" if kind=="MINE" else "wizard.lightning"
			var result := service.apply_enemy_direct_spell_damage(actor,skill,20,null,null,Callable(self,"zero_mac") if kind=="MAC_ZERO" else Callable(),0,{},Combat.EnemyMagicDeliveryKind.AUTO)
			var delays := level==49 and kind in ["DIRECT","MAC_ZERO"]
			check(actor._movement_cadence.walk_tick_ms==tick+(800+sample if delays else 0),"exact level/defense/evasion source delay")
			if kind in ["EVADED","MAC_ZERO"]:
				check(actor.current_hp==actor.max_hp,"zero damage does not write HP")
				check(actor._rng.state==(reference.state if delays else rng),"only eligible reception consumes target walk roll")
			rows.append({"level":level,"kind":kind,"result":result,"tick_before":tick,"tick_after":actor._movement_cadence.walk_tick_ms})
			F.dispose(actor,victim)
	check(not bool(service.apply_enemy_direct_spell_damage(null,"wizard.lightning",20,null).get("success",true)),"invalid target rejected")
	F.write_evidence("direct_reception_edges",{"checks":checks,"errors":errors,"rows":rows})
	print(("R3_DIRECT_EDGES_PASS" if errors.is_empty() else "R3_DIRECT_EDGES_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
