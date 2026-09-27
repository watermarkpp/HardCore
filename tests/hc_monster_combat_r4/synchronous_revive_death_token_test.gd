extends Node

## REVIEW FIXTURE ONLY. Godot NOT_RUN here. Unlike R3's revive-after-return
## case, revival happens INSIDE the killing hit's synchronous notification.
var _revived := false
var _death_notifications := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 100
	player.current_hp = 100
	player.defense_min = 0
	player.defense_max = 0
	player.death_requested.connect(func() -> void: _death_notifications += 1)
	player.stats_changed.connect(_on_hp.bind(player))
	player.take_damage(999999)
	var revived_at_return := _revived and not player._dead and player.current_hp > 0
	await get_tree().create_timer(1.0).timeout
	var valid := revived_at_return and not player._dead and _death_notifications == 0
	player.queue_free()
	if not valid:
		printerr("R4_SYNC_REVIVE: revived_at_return=%s stale_death_notifications=%d" % [revived_at_return, _death_notifications])
		get_tree().quit(1)
		return
	print("R4_SYNCHRONOUS_REVIVE_DEATH_TOKEN_PASS")
	get_tree().quit(0)

func _on_hp(hp: int, _maximum: int, player: PlayerCharacter) -> void:
	if hp != 0 or _revived or not player._dead:
		return
	_revived = true # reserve BEFORE complete_death_revival emits again
	player.complete_death_revival()
