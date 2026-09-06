extends Node

var _events: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _capture_event(request: Dictionary) -> void:
	_events.append(request.duplicate(true))


func _count_event(event_id: String) -> int:
	var count := 0
	for event: Dictionary in _events:
		if str(event.get("event_id", "")) == event_id:
			count += 1
	return count


func _has_contact_event() -> bool:
	for event: Dictionary in _events:
		if str(event.get("event_id", "")).begins_with("player.contact."):
			return true
	return false


func _event_path(event_id: String) -> String:
	for event: Dictionary in _events:
		if str(event.get("event_id", "")) == event_id:
			return str(event.get("runtime_path", ""))
	return ""


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	var previous_gender := PlayerState.gender
	var previous_equipment := PlayerState.equipment.duplicate(true)
	PlayerState.reset_progress(false)
	PlayerState.test_mode = false
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var service: Node = game._audio_runtime_service
	assert(service != null, "shared audio service missing")
	service.event_started.connect(_capture_event)
	_events.clear()

	# Public PlayerVisual action starts are the current SM_STRUCK/SM_NOWDEATH
	# equivalents. Repeating the same active action must not replay it.
	game.player.visual._action_remaining = 0.0
	game.player.visual.play_hit(0.24)
	game.player.visual.play_hit(0.24)
	assert(_count_event("player.hurt.pve.body") == 1, "hit action must emit PvE body sound once")
	assert(_count_event("player.hurt.voice") == 1, "hit action must emit male voice once")
	assert(_event_path("player.hurt.pve.body").ends_with("72__72.wav"), "PvE body sound must be 72")
	assert(_event_path("player.hurt.voice").ends_with("138__138.wav"), "male hurt sound must be 138")
	game.player.visual._action_remaining = 0.0
	_events.clear()
	game.player.visual.play_death(0.8)
	game.player.visual.play_death(0.8)
	assert(_count_event("player.death.voice") == 1, "active male death action must emit once")
	assert(_event_path("player.death.voice").ends_with("144__144.wav"), "male death sound must be 144")

	game.player.visual._action_remaining = 0.0
	PlayerState.gender = "女"
	_events.clear()
	game.player.visual.play_hit(0.24)
	assert(_event_path("player.hurt.voice").ends_with("139__139.wav"), "female hurt sound must be 139")
	game.player.visual._action_remaining = 0.0
	_events.clear()
	game.player.visual.play_death(0.8)
	game.player.visual.play_death(0.8)
	assert(_count_event("player.death.voice") == 1, "active female death action must emit once")
	assert(_event_path("player.death.voice").ends_with("145__145.wav"), "female death sound must be 145")

	# A noncanonical/unknown equipped record is not empty-handed. It must stay
	# fail-closed instead of borrowing fist contact or a neighboring shape.
	PlayerState.equipment["武器"] = {"item_id": 999999, "name": "unknown-audio-fixture"}
	assert(game.player.visual.audio_classic_weapon_shape() == -1, "unknown equipped shape did not fail closed")
	_events.clear()
	var rejected_contact: Dictionary = service.play_player_physical_contact(-1, {"source": "test"})
	assert(str(rejected_contact.get("status", "")) == "invalid_event", "unknown shape contact was not rejected")
	assert(not _has_contact_event(), "unknown shape borrowed a contact event")

	# Item 81 is the exact formal classic shape 6. The source's struck-weapon
	# second division resolves it to 64, while the body layer resolves to 70.
	PlayerState.gender = "男"
	PlayerState.equipment["武器"] = {"item_id": 81, "name": "匕首"}
	game.player.visual._refresh_equipment_visuals()
	assert(game.player.visual.audio_classic_weapon_shape() == 6, "fixture weapon shape drift")
	var target: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(38),
		game.player.global_position + Vector2(32.0, 0.0),
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_group_id": "player_core_audio_target"},
	)
	assert(target != null, "audio target spawn failed")
	await get_tree().process_frame
	target.control_time = 60.0
	target.max_hp = 1000
	target.current_hp = 1000
	target.agility = 1
	PlayerState.computed_stats["accuracy"] = 1
	_events.clear()
	assert(game._apply_physical_hit(target, 10), "guaranteed player physical hit failed")
	assert(_count_event("player.contact.weapon.axe") == 1, "shape 6 weapon contact 64 missing")
	assert(_count_event("player.contact.body.sword") == 1, "shape 6 body contact 70 missing")
	assert(_event_path("player.contact.weapon.axe").ends_with("64__64.wav"))
	assert(_event_path("player.contact.body.sword").ends_with("70__70.wav"))

	# Accuracy zero against agility one deterministically misses (roll 0 < 0 is
	# false). A miss submits no damage and therefore no contact layer.
	PlayerState.computed_stats["accuracy"] = 0
	var hp_before_miss := target.current_hp
	_events.clear()
	assert(not game._apply_physical_hit(target, 10), "deterministic miss unexpectedly hit")
	assert(target.current_hp == hp_before_miss, "miss changed HP")
	assert(not _has_contact_event(), "miss emitted physical contact")

	# Direct spell damage carries the same PlayerCharacter source actor but is
	# not physical. Attacker identity alone must never manufacture contact.
	target.current_hp = 1000
	_events.clear()
	var magic_result: Dictionary = game._combat_runtime.apply_enemy_direct_spell_damage(
		target,
		"wizard.fireball",
		100,
		game.player,
		null,
		Callable(),
		0,
	)
	assert(bool(magic_result.get("success", false)), "magic fixture did not commit damage")
	assert(not _has_contact_event(), "magic damage inferred physical contact from player source")

	# Current runtime does not enter hit presentation on lethal damage; match the
	# authorized boundary and do not synthesize a struck action or contact sound.
	target.current_hp = 1
	PlayerState.computed_stats["accuracy"] = 1
	_events.clear()
	assert(game._apply_physical_hit(target, 10), "lethal physical commit failed")
	assert(not _has_contact_event(), "lethal damage without hit action emitted contact")

	service.event_started.disconnect(_capture_event)
	game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	PlayerState.gender = previous_gender
	PlayerState.equipment = previous_equipment
	print("PLAYER_CORE_AUDIO_HOOK_PASS：受击/死亡动作一次、性别映射、物理命中双层、miss/魔法/致死无伪contact")
	get_tree().quit(0)
