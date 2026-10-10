extends Node2D

const EffectScript := preload("res://scripts/monster_ranged_projectile_effect.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var physical_descriptors: Array[Dictionary] = []
var special_descriptors: Array[Dictionary] = []

func _ready() -> void:
	await _run()
	var failures := 0
	for row: Dictionary in proof.records:
		if not bool(row.passed): failures += 1
	var receipt_ok := proof.write_receipt("monster_projectile_real_enemy_150_194_test", proof.records.size(), failures)
	if not receipt_ok: failures += 1
	print("MONSTER_PROJECTILE_REAL_ENEMY_150_194_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: push_error(label)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	await _run_physical_150()
	await _run_guard_194()

func _new_player() -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.global_position = _ground_to_screen(Vector2(4.0, 0.0))
	player.set_meta("runtime_map_id", 1)
	player.set_meta("safe_zones", [])
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 0
	player.defense_max = 0
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 0
	player.defense_max = 0
	return player

func _new_enemy(id: int, player: PlayerCharacter) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.global_position = Vector2.ZERO
	enemy.setup(GameData.get_monster_by_id(id), player, false)
	enemy.configure_runtime_map_projection(1, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
	enemy.configure_terrain_navigation_context({"width": 32, "height": 32, "blocked": []})
	enemy.set_meta("safe_zones", [])
	enemy.target = player
	enemy.attack_min = 7
	enemy.attack_max = 7
	add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func _run_physical_150() -> void:
	physical_descriptors.clear()
	var player := _new_player()
	var enemy := _new_enemy(150, player)
	enemy.ranged_projectile_requested.connect(func(d: Dictionary): physical_descriptors.append(d))
	await get_tree().physics_frame
	enemy._attack_timer = 0.0
	enemy._physics_process(0.01)
	await _advance_release(enemy)
	_check(physical_descriptors.size() == 1, "ID150 accepted descriptor released")
	var effect := _latest_effect()
	_check(effect != null, "ID150 accepted flight created")
	var hp_before := player.current_hp
	if effect != null:
		effect.set_physics_process(false)
		_force_missing_visual(effect)
		_check(not effect.visible, "ID150 missing visual is hidden")
		effect.call("_physics_process", 0.1344)
		player.global_position = _ground_to_screen(Vector2(4.0, 3.0))
		await get_tree().physics_frame
		await get_tree().process_frame
		effect.call("_physics_process", 0.3)
		_check(player.current_hp == hp_before, "ID150 movement dodge prevents flight damage")
		player.global_position = _ground_to_screen(Vector2(4.0, 0.0))
	await get_tree().physics_frame
	enemy._attack_timer = 0.0
	enemy._physics_process(0.01)
	await _advance_release(enemy)
	effect = _latest_effect()
	if effect != null:
		effect.set_physics_process(false)
		_force_missing_visual(effect)
		player._rng.seed = 1
		effect.call("_physics_process", 0.3)
		_check(player.current_hp < hp_before, "ID150 flight settles one real HP transaction")
		var settled := player.current_hp
		effect.call("_physics_process", 0.3)
		_check(player.current_hp == settled, "ID150 flight cannot settle HP twice")
	enemy.queue_free(); player.queue_free()
	await get_tree().process_frame

func _run_guard_194() -> void:
	special_descriptors.clear()
	var player := _new_player()
	var enemy := _new_enemy(194, player)
	enemy.global_position = player.global_position + Vector2(-16.0, 0.0)
	enemy.monster_special_delivery_requested.connect(func(d: Dictionary): special_descriptors.append(d))
	await get_tree().physics_frame
	var hp_before := player.current_hp
	var parent_release: Variant = enemy.call("_observe_special_contact_admission", player, 7, 1)
	var dispatched := bool(enemy.call("_launch_monster_special_cell_delivery", player, 7, parent_release))
	_check(dispatched, "ID194 formal guard delivery dispatches")
	_check(special_descriptors.size() == 1, "ID194 accepted guard descriptor released")
	var effect := _latest_effect()
	if effect != null:
		effect.set_physics_process(false)
		_force_missing_visual(effect)
		_check(not effect.visible, "ID194 missing visual is hidden")
		enemy.call("_on_guard_projectile_contact", effect.release_descriptor.get("release_record", {}), player)
	_check(player.current_hp < hp_before, "ID194 guard flight settles real HP")
	var settled := player.current_hp
	if effect != null:
			effect.call("_physics_process", 1.0)
	_check(player.current_hp == settled, "ID194 presentation flight cannot double settle HP")
	enemy.queue_free(); player.queue_free()
	await get_tree().process_frame

func _force_missing_visual(effect: Node2D) -> void:
	# Preserve the real accepted descriptor, Enemy owner and live flight. Only
	# replace the presentation source with a precise missing frame input.
	if effect.get("_sprite") != null:
		var sprite: Node = effect.get("_sprite")
		if is_instance_valid(sprite): sprite.queue_free()
		effect.set("_sprite", null)
	effect.set("_exact_profile", {})
	effect.set("_source_frame_index", 999999)
	effect.call("_install_source_frame")

func _advance_release(enemy: EnemyActor) -> void:
	enemy.set_physics_process(true)
	for _step in range(180):
		await get_tree().physics_frame
		if enemy._pending_attack_release_record.is_empty():
			enemy.set_physics_process(false)
			return
	enemy.set_physics_process(false)
	_check(false, "attack release completes")

func _latest_effect() -> Node2D:
	for child: Node in get_children():
		if child.get_script() == EffectScript: return child as Node2D
	return null

func _ground_to_screen(ground: Vector2) -> Vector2:
	return Vector2((ground.x - ground.y) * 24.0, (ground.x + ground.y) * 16.0)

func _screen_to_ground(screen: Vector2) -> Vector2:
	return Vector2(screen.x / 48.0 + screen.y / 32.0, screen.y / 32.0 - screen.x / 48.0)
