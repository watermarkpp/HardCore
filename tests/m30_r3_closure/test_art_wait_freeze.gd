extends Node

const Freeze := preload("res://tests/m30_r3_closure/art_wait_freeze.gd")
var failures: int = 0

class Art:
	extends Node
	var frames: int = 0
	func _process(_delta: float) -> void:
		frames += 1

class Actor:
	extends CharacterBody2D
	var physics_calls: int = 0
	var wakes: int = 0
	var timer: Timer
	var art: Node
	func _ready() -> void:
		art = Art.new()
		add_child(art)
		timer = Timer.new()
		timer.wait_time = 0.05
		timer.one_shot = true
		timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
		# Explicit ALWAYS also tests that a descendant cannot bypass the fence.
		timer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(timer)
		timer.timeout.connect(_wake)
		set_physics_process(false)
		timer.start()
	func _wake() -> void:
		wakes += 1
		set_physics_process(true)
	func _physics_process(_delta: float) -> void:
		physics_calls += 1

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("M30_CLOSURE_FREEZE " + label)

func wait_real_seconds(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _run() -> void:
	var legacy := Actor.new()
	add_child(legacy)
	legacy.set_physics_process(false)
	await wait_real_seconds(0.65)
	check(legacy.wakes == 1 and legacy.physics_calls > 0, "control: child timer reopens a false physics flag")
	legacy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var actor := Actor.new()
	add_child(actor)
	var old_mode: int = actor.process_mode
	var old_art_mode: int = actor.art.process_mode
	var old_timer_mode: int = actor.timer.process_mode
	var old_disable_mode: int = actor.disable_mode
	var old_timer_left: float = actor.timer.time_left
	var freeze := Freeze.new()
	check(freeze.begin(actor, actor.art), "guard begin")
	check(not freeze.begin(actor, actor.art), "reject double begin")
	await wait_real_seconds(0.65)
	check(freeze.intact(), "all nonvisual scheduling remains disabled")
	check(actor.wakes == 0 and actor.physics_calls == 0, "no timer or actor work during long art wait")
	check(int(actor.art.get("frames")) > 1, "art still processes")
	check(is_equal_approx(actor.timer.time_left, old_timer_left), "timer countdown is not consumed")
	check(actor.disable_mode == CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE, "body not removed by pause")
	check(freeze.restore(), "restore survives complete wait")
	check(actor.process_mode == old_mode and actor.art.process_mode == old_art_mode, "actor and art modes restored")
	check(actor.timer.process_mode == old_timer_mode and actor.disable_mode == old_disable_mode, "timer and body modes restored")
	check(not actor.is_physics_processing(), "guard does not force wake or reset state at release")
	await wait_real_seconds(0.65)
	check(actor.wakes == 1 and actor.physics_calls > 0, "production-like timer resumes its normal wake")
	check(not freeze.restore(), "double restore is rejected")
	actor.queue_free()
	freeze = null
	await get_tree().process_frame
	await get_tree().process_frame
	print("M30_CLOSURE_FREEZE_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

func _ready() -> void:
	_run.call_deferred()
