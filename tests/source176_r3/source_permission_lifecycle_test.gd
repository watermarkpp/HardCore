extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
var checks := 0
var errors: Array[String] = []

func _ready() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)

func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var victim := F.player(self,Vector2(25,20))
	var actor := F.enemy(self,64,Vector2(20,20),victim)
	actor._combat_action_time_s = 2.0
	actor._movement_cadence.reset(0)
	check(actor._source176_take_tick_decision(),"first deterministic owner decision granted")
	var serial := actor._source176_decision_serial
	var walk_tick: int = actor._movement_cadence.walk_tick_ms
	check(actor._source176_take_tick_decision(),"same life and tick share grant")
	check(actor._source176_decision_serial==serial and actor._movement_cadence.walk_tick_ms==walk_tick,"shared decision evaluates once")
	var previous_life := int(actor.get_meta("hc_combat_life_epoch",0))
	actor.setup(GameData.get_monster_by_id(64),victim,false)
	check(int(actor.get_meta("hc_combat_life_epoch",0))==previous_life+1,"formal setup creates new life")
	# A fresh reset leaves its first interval unpaid. The old life already
	# granted in this same generation/tick, and must not lend that ticket.
	actor._movement_cadence.reset(int(actor._combat_action_time_s*1000.0))
	check(not actor._source176_take_tick_decision(),"same-tick new life cannot borrow prior grant")
	F.dispose(actor,victim)
	check(F.write_evidence("source_permission_lifecycle",{"checks":checks,"errors":errors}),"write lifecycle evidence")
	print(("R3_PERMISSION_LIFE_PASS" if errors.is_empty() else "R3_PERMISSION_LIFE_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
