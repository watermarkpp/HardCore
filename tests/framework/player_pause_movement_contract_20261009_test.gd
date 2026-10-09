extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const WorldSpatialRules := preload("res://scripts/world_spatial_rules.gd")

var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)
		push_error("player B02 contract: " + label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.set_profession_identity("hc.profession.wizard")
	PlayerState.level = 40
	PlayerState.learned_skills = {"hc.skill.wizard.ice_storm": 3}
	PlayerState.recalculate_stats(false)
	var game := Root.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while (game.player == null or not game.gameplay_input_is_enabled()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.player != null and game.gameplay_input_is_enabled(), "formal GameRoot creates an input-ready Player")
	if game.player == null:
		_finish()
		return
	var player: PlayerCharacter = game.player
	player.attack_hit_windup = 0.12
	player.attack_animation_duration = 0.25
	var release_counts := {"attack": 0}
	player.attack_requested.connect(func(_origin: Vector2, _direction: Vector2, _damage: int) -> void:
		release_counts["attack"] = int(release_counts.get("attack", 0)) + 1
	)
	check(player.request_attack(false), "formal Player accepts an ordinary attack")
	game._show_system_menu()
	check(get_tree().paused, "formal GameRoot menu owns the pause")
	await get_tree().create_timer(0.24, true).timeout
	check(int(release_counts.get("attack", 0)) == 0, "paused tree does not advance accepted attack windup")
	game._hide_system_menu()
	check(not get_tree().paused, "formal GameRoot menu releases the pause")
	await get_tree().create_timer(0.24, true).timeout
	check(int(release_counts.get("attack", 0)) == 1, "resume releases accepted attack exactly once")
	await _test_skill_windup_pause(game)
	await _collision_recovery_probe(game.player)
	game.queue_free()
	await get_tree().process_frame
	_finish()

func _test_skill_windup_pause(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while game.player._attack_timer > 0.0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var target := await Fixture.prepare_target(self, game, game.player, 19, "player_pause_skill")
	check(target != null, "formal skill receiver exists")
	if target == null:
		game.queue_free()
		return
	target.max_hp = 10000
	target.current_hp = target.max_hp
	target.control_time = 0.0
	target.direct_spell_anti_magic_points = 0
	target.direct_spell_magic_defense_min = 0
	target.direct_spell_magic_defense_max = 0
	target.direct_spell_stats_valid = true
	game._skill_cast_target = target
	game._set_magic_locked_target(target, true)
	var lease: RefCounted = game._capture_action_configuration("hc.skill.wizard.ice_storm")
	var release_counts := {"skill": 0}
	game.player.skill_requested.connect(func(_name: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
		release_counts["skill"] = int(release_counts.get("skill", 0)) + 1
	)
	var hp_before := target.current_hp
	check(game.player.request_skill("hc.skill.wizard.ice_storm", target.get_instance_id(), lease), "formal Player accepts a legal skill")
	game._show_system_menu()
	await get_tree().create_timer(0.35, true).timeout
	check(target.current_hp == hp_before and int(release_counts.get("skill", 0)) == 0, "paused tree retains accepted skill windup and HP")
	game._hide_system_menu()
	deadline = Time.get_ticks_msec() + 3000
	while int(release_counts.get("skill", 0)) == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(int(release_counts.get("skill", 0)) == 1 and target.current_hp < hp_before, "resume releases legal skill once with real HP mutation")

func _collision_recovery_probe(player: PlayerCharacter) -> void:
	player.set_touch_vector(Vector2.ZERO)
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(320.0, 240.0)
	var recovery_body := StaticBody2D.new()
	recovery_body.collision_layer = WorldSpatialRules.ENEMY_LAYER
	recovery_body.collision_mask = 0
	recovery_body.global_position = player.global_position
	var shape := CollisionShape2D.new()
	shape.shape = WorldSpatialRules.actor_footprint_shape_px(18.0)
	recovery_body.add_child(shape)
	add_child(recovery_body)
	var movement_events := {"count": 0}
	var event_snapshot := {"position": Vector2.INF, "ground_motion": Vector2.ZERO}
	player.movement_performed.connect(func(_position: Vector2, _facing: Vector2) -> void:
		movement_events["count"] = int(movement_events.get("count", 0)) + 1
		event_snapshot.position = _position
		event_snapshot.ground_motion = player.actual_ground_motion_gu
	)
	var before := player.global_position
	await get_tree().physics_frame
	await get_tree().process_frame
	var after := player.global_position
	check((event_snapshot.position as Vector2).is_finite() and (event_snapshot.position - before).length_squared() > 0.0001, "zero-input collision recovery produces real displacement")
	check((event_snapshot.ground_motion as Vector2).length_squared() > 0.000001, "recovery displacement is retained in actual ground motion")
	check(after == event_snapshot.position, "published recovery position is the final position for the physics step")
	check(int(movement_events.get("count", 0)) == 1, "recovery displacement publishes one movement event")
	recovery_body.queue_free()

func _finish() -> void:
	var receipt_ok := proof.write_receipt("player_pause_movement_contract_20261009_test", proof.records.size(), failures.size())
	print("PLAYER_PAUSE_MOVEMENT_CONTRACT_%s" % ("PASS" if failures.is_empty() and receipt_ok else "FAIL"))
	get_tree().quit(0 if failures.is_empty() and receipt_ok else 1)
