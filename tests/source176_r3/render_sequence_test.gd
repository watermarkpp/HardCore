extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
var errors: Array[String] = []
var rows: Array = []
var renders := 0
var actor: EnemyActor
var collecting := false
var frames := 0
var last_parent := 0
var sequence: Array = []
var presentation_gap := false
func _ready() -> void:
	process_physics_priority = 10000
	run.call_deferred()
func _physics_process(_delta: float) -> void:
	if not collecting:
		return
	frames += 1
	if presentation_gap and frames>=60 and frames<=180:
		actor.visual.set_process(false)
	elif presentation_gap:
		actor.visual.set_process(true)
	if actor._attack_logic_serial!=last_parent:
		sequence.append({"parent":actor._attack_logic_serial,"time":actor._combat_action_time_s,"rng":str(actor._rng.state)})
		last_parent = actor._attack_logic_serial
func _process(_delta: float) -> void:
	if collecting:
		renders += 1
func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var original_fps := Engine.max_fps
	var reference: Dictionary = {}
	for fps: int in [60,30,20,15,60]:
		var gap := rows.size()==4
		Engine.max_fps = fps
		var victim := F.player(self,Vector2(20.98,20))
		actor = F.enemy(self,64,Vector2(20,20),victim)
		actor.set_combat_position(F.to_screen(Vector2(20,20)),&"r3_render_fixture")
		actor._rng.seed = 29341
		actor.visual.visible = true
		actor.set_physics_process(true)
		frames = 0
		last_parent = 0
		sequence = []
		presentation_gap = gap
		renders = 0
		collecting = true
		while frames<240:
			await get_tree().physics_frame
		collecting = false
		actor.set_physics_process(false)
		var row := {"render_cap":fps,"long_visual_gap":gap,"physics_frames":frames,"observed_render_frames":renders,
			"sequence":sequence,"hp_delta":victim.max_hp-victim.current_hp,"starts":actor._hc_starts,
			"rng":str(actor._rng.state),"timer":actor._attack_timer,"clock":actor._combat_action_time_s}
		if rows.is_empty():
			reference = row
		elif sequence!=reference.sequence or row.hp_delta!=reference.hp_delta or row.rng!=reference.rng or absf(row.timer-reference.timer)>.000001:
			errors.append("render scheduling changed logical sequence at cap="+str(fps)+" gap="+str(gap))
		if row.starts<2 or row.hp_delta<=0 or absf(row.clock-4.0)>.00001:
			errors.append("missing natural actions or physics60 clock")
		rows.append(row)
		F.dispose(actor,victim)
	Engine.max_fps = original_fps
	F.write_evidence("render_sequence",{"errors":errors,"rows":rows,"scope":"native physics60; actual render caps and a 120-physics-frame presentation gap"})
	print(("R3_RENDER_SEQUENCE_PASS" if errors.is_empty() else "R3_RENDER_SEQUENCE_FAIL")+" cases="+str(rows.size())+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
