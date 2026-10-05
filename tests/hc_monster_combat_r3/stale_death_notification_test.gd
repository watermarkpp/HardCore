extends Node

# NOT_RUN by the reviewer. Explicitly exercises a lifecycle boundary through
# the public revival completion API; does not claim normal death UI always
# revives this early. The old death notification must not cross revival.
var _notifications := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.defense_min = 0
	player.defense_max = 0
	player.defense_buff = 0
	player.current_hp = 5
	player.death_requested.connect(func() -> void: _notifications += 1)
	player.take_damage(999999)
	if not player._dead:
		printerr("R3_DEATH_NOTIFICATION_FIXTURE: expected formal death without revival ring")
		player.queue_free()
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.10).timeout
	player.complete_death_revival()
	if player._dead or player.current_hp <= 0:
		printerr("R3_DEATH_NOTIFICATION_FIXTURE: revival did not complete")
		player.queue_free()
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.90).timeout
	var late_notification := _notifications != 0
	player.queue_free()
	if late_notification:
		printerr("R3_DEATH_NOTIFICATION: prior-life death_requested fired after revival")
	else:
		print("HC_MCR3_STALE_DEATH_NOTIFICATION_PASS")
	get_tree().quit(1 if late_notification else 0)
