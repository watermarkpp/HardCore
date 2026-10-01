extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
var actor: EnemyActor
var checks := 0
var errors: Array[String] = []
var rows: Array = []
var collecting := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 10000
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)

func _physics_process(delta: float) -> void:
	if not collecting:
		return
	var row := {"tick":Engine.get_physics_frames(),"delta":delta,"game_s":actor._combat_action_time_s,
		"paused":get_tree().paused,"scale":Engine.time_scale}
	if not rows.is_empty():
		var previous: Dictionary = rows[-1]
		if bool(previous.paused)==bool(row.paused):
			var expected := 0.0 if get_tree().paused else delta
			check(absf(float(row.game_s)-float(previous.game_s)-expected)<.00001,"native owner clock exactly once or paused")
	rows.append(row)

func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var victim := F.player(self,Vector2(25,20))
	actor = F.enemy(self,64,Vector2(20,20),victim)
	actor.process_mode = Node.PROCESS_MODE_PAUSABLE
	actor.set_physics_process(true)
	collecting = true
	for scale: float in [.5,1.0,2.0]:
		Engine.time_scale = scale
		for n in range(24):
			await get_tree().physics_frame
	get_tree().paused = true
	var time_before := actor._combat_action_time_s
	var tick_before: int = actor._movement_cadence.walk_tick_ms
	for n in range(12):
		await get_tree().physics_frame
	check(actor._combat_action_time_s==time_before,"pause preserves game clock")
	check(actor._movement_cadence.walk_tick_ms==tick_before,"pause preserves source phase")
	get_tree().paused = false
	Engine.time_scale = 1.0
	for n in range(4):
		await get_tree().physics_frame
	collecting = false
	actor.set_physics_process(false)
	check(rows.size()>=80,"all native scale and pause frames observed")
	F.dispose(actor,victim)
	check(F.write_evidence("source_game_clock_trace",{"checks":checks,"errors":errors,"rows":rows}),"write clock evidence")
	print(("R3_GAME_CLOCK_PASS" if errors.is_empty() else "R3_GAME_CLOCK_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
