extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
var errors: Array[String] = []
var rows: Array = []
var actor: EnemyActor
var last := Vector2.INF
var moved := false
var collecting := false
var loss := 0.0
var ticks := 0
func _ready() -> void:
	process_physics_priority = 10000
	run.call_deferred()
func _physics_process(delta: float) -> void:
	if not collecting:
		return
	var now := F.to_ground(actor.global_position)
	if last.is_finite():
		var distance := now.distance_to(last)
		if moved:
			var expected := actor.move_speed_gu_per_sec*delta
			loss += maxf(0.0,expected-distance)
			if distance>expected+.0002:
				errors.append("frame movement exceeds one speed budget")
			rows.append({"tick":Engine.get_physics_frames(),"distance":distance,"budget":expected,"remaining_leg":actor._movement_step_active})
			ticks += 1
		if distance>.0001:
			moved = true
	last = now
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var victim := F.player(self,Vector2(25.125,25.1))
	actor = F.enemy(self,64,Vector2(20.125,20.875),victim)
	collecting = true
	actor.set_physics_process(true)
	for n in range(900):
		await get_tree().physics_frame
		if ticks>=150 or not errors.is_empty():
			break
	collecting = false
	actor.set_physics_process(false)
	if ticks<150:
		errors.append("insufficient real moving frames")
	if loss>.001:
		errors.append("short legs discard residual frame distance: "+str(loss))
	F.dispose(actor,victim)
	F.write_evidence("movement_frame_budget",{"errors":errors,"ticks":ticks,"lost_distance_gu":loss,"rows":rows})
	print(("R3_MOVEMENT_BUDGET_PASS" if errors.is_empty() else "R3_MOVEMENT_BUDGET_FAIL")+" ticks="+str(ticks)+" lost_gu="+str(loss)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
