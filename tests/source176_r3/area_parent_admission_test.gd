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
	for id: int in [124,180,195]:
		var victim := F.player(self,Vector2(24,20))
		var actor := F.enemy(self,id,Vector2(20,20),victim)
		actor._attack_timer = 0.0
		actor._area_attack_cooldown = 0.0
		actor._pending_attack_time = .5
		var rng: int = actor._rng.state
		var parent := actor._attack_logic_serial
		if id==124:
			actor._update_area_magic_delivery(0.0)
		else:
			actor._update_area_attack(0.0)
		check(actor._attack_logic_serial==parent and actor._rng.state==rng,"incompatible pending rejects area before parent and RNG: "+str(id))
		check(actor._area_magic_release_records.is_empty() and actor._area_attack_release_records.is_empty(),"rejection freezes no release: "+str(id))
		actor._pending_attack_time = -1.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		if id==124:
			actor._update_area_magic_delivery(0.0)
		else:
			actor._update_area_attack(0.0)
		var records: Array = actor._area_magic_release_records if id==124 else actor._area_attack_release_records
		check(actor._attack_logic_serial==parent+1 and not records.is_empty(),"one admitted area parent: "+str(id))
		for record: Dictionary in records:
			check(int(record.get("parent_action_id",-1))==actor._attack_logic_serial,"release binds already allocated parent")
			check(int(record.get("source_life",-1))==actor._hc_life(actor),"release binds source life")
		# Child survives its parent's presentation finishing, but not source
		# reuse in the same generation. No second admission/payment at settle.
		if not records.is_empty():
			var record: Dictionary = records[0]
			actor._attack_action_active = false
			check(actor._area_magic_release_target_is_valid(victim,record) if id==124 else actor._area_attack_release_target_is_valid(victim,record),"released child outlives pose")
			actor.set_meta("hc_combat_life_epoch",actor._hc_life(actor)+1)
			check(not (actor._area_magic_release_target_is_valid(victim,record) if id==124 else actor._area_attack_release_target_is_valid(victim,record)),"released child cannot cross source life")
		F.dispose(actor,victim)
	check(F.write_evidence("area_parent_admission",{"checks":checks,"errors":errors}),"write evidence")
	print(("R3_AREA_PARENT_PASS" if errors.is_empty() else "R3_AREA_PARENT_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
