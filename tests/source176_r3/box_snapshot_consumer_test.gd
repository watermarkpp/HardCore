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
	for id: int in [64,89]:
		var source := Vector2(20.125,20.875)
		var victim := F.player(self,source+Vector2(.99,.99))
		var actor := F.enemy(self,id,source,victim)
		actor.set_combat_position(F.to_screen(source),&"r3_snapshot_fixture")
		var hp := victim.current_hp
		actor._deal_melee_hit(victim,20)
		var snapshot: Dictionary = actor._last_attack_footprint_snapshot
		check(victim.current_hp<hp,"inside corner actually damaged")
		check(str(snapshot.get("shape_type",""))=="directed_rectangle","ordinary exact snapshot is rectangle")
		check((snapshot.get("origin_ground_gu",Vector2.INF) as Vector2).distance_to(source)<.0001,"snapshot preserves release source origin")
		check(actor._snapshot_intersects_target(snapshot,victim),"same inside victim consumed")
		victim.global_position = F.to_screen(source+Vector2(1.01,0))
		check(not actor._snapshot_intersects_target(snapshot,victim),"target footprint cannot expand centre authority")
		victim.global_position = F.to_screen(source+Vector2(1.0,1.0))
		check(actor._snapshot_intersects_target(snapshot,victim),"exact square corner inclusive")
		victim.global_position = F.to_screen(source+Vector2(1.00005,0))
		check(actor._snapshot_intersects_target(snapshot,victim),"inside frozen EPS band")
		victim.global_position = F.to_screen(source+Vector2(1.0002,0))
		check(not actor._snapshot_intersects_target(snapshot,victim),"outside frozen EPS band")
		victim.global_position = F.to_screen(source+Vector2(1.25,0))
		hp = victim.current_hp
		actor._deal_melee_hit(victim,20,.25,true)
		check(victim.current_hp<hp,"separate impact boundary inclusive")
		snapshot = actor._last_attack_footprint_snapshot
		victim.global_position = F.to_screen(source+Vector2(1.251,0))
		check(not actor._snapshot_intersects_target(snapshot,victim),"outside impact boundary rejected by snapshot consumer")
		F.dispose(actor,victim)
	check(F.write_evidence("box_snapshot_consumer",{"checks":checks,"errors":errors}),"write snapshot evidence")
	print(("R3_BOX_SNAPSHOT_PASS" if errors.is_empty() else "R3_BOX_SNAPSHOT_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
