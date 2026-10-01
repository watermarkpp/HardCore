extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
var checks := 0
var errors: Array[String] = []
var rows: Array = []

func _ready() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)

func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for pending: String in ["_pending_attack_time","_boss_warning","_area_attack_warning","_area_magic_warning","_summon_warning"]:
		var victim := F.player(self,Vector2(20.9,20))
		var actor := F.enemy(self,64,Vector2(20,20),victim)
		actor.set_combat_position(F.to_screen(Vector2(20,20)),&"r3_body_fixture")
		actor._attack_timer = 0.0
		actor.set(pending,.25)
		var rng: int = actor._rng.state
		var parent := actor._attack_logic_serial
		var hp := victim.current_hp
		# Structural window test: no special identity is enabled or copied
		# into production data. The central owner must recognize its pending
		# logical windows regardless of which independent entry asks next.
		check(not actor._hc_try_start(victim),"pending window blocks independent parent "+pending)
		check(actor._rng.state==rng and actor._attack_logic_serial==parent,"rejection precedes RNG and parent "+pending)
		check(actor._attack_timer==0.0 and victim.current_hp==hp,"rejection precedes cooldown and damage "+pending)
		rows.append({"pending_field":pending,"kind":"structural window","parent_before":parent,"parent_after":actor._attack_logic_serial})
		F.dispose(actor,victim)
	var victim := F.player(self,Vector2(25,20))
	var actor := F.enemy(self,64,Vector2(20,20),victim)
	check(actor._try_reserve_source_body_action(false),"first same-tick body admission")
	check(not actor._try_reserve_source_body_action(false),"same-tick second admission rejected")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(actor._try_reserve_source_body_action(false),"clear next tick admits without arbitrary animation lock")
	F.dispose(actor,victim)
	check(F.write_evidence("body_action_owner_matrix",{"checks":checks,"errors":errors,"rows":rows}),"write body windows evidence")
	print(("R3_BODY_OWNER_PASS" if errors.is_empty() else "R3_BODY_OWNER_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
