extends Node

## R4 T2 double-generation scenario: a listener revives inside the FIRST
## killing hit's synchronous broadcast, and the revived player takes a SECOND
## lethal hit immediately. The first death's frozen token (and the revival's
## own boundary) must never let the stale tail bind to the second life; the
## second death is a real formal death and its single notification is legal.

var _death_notifications := 0
var _second_death_seen := false


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
	# First lethal hit: the listener revives synchronously inside the stats
	# broadcast (generation 1 -> 2 before the deferred tail resumes).
	player.take_damage(999999)
	var revived: bool = not player._dead and player.current_hp > 0
	# Second lethal hit on the revived life: this is a NEW formal death with
	# its own frozen token (generation 3). Its single notification is legal.
	if revived:
		player.take_damage(999999)
		_second_death_seen = player._dead
	await get_tree().create_timer(1.2).timeout
	# Exactly one notification may ever fire: the second death's own. The
	# first death's stale tail was voided by its frozen token.
	var valid := revived and _second_death_seen and _death_notifications == 1
	player.queue_free()
	if not valid:
		printerr(
			"R4_DOUBLE_GENERATION: revived=%s second_death=%s notifications=%d (expected exactly 1)"
			% [revived, _second_death_seen, _death_notifications]
		)
		get_tree().quit(1)
		return
	print("R4_DOUBLE_GENERATION_DEATH_TOKEN_PASS")
	get_tree().quit(0)


func _on_hp(hp: int, _maximum: int, player: PlayerCharacter) -> void:
	if hp != 0 or _revival_used or not player._dead:
		return
	_revival_used = true
	player.complete_death_revival()


var _revival_used := false
