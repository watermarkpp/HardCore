extends Node

const MainScene := preload("res://scenes/main.tscn")
const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")
const MAX_WORLD_READY_FRAMES := 1800
const BICH_RUNTIME_MAP_ID := 910001


var _game: Node
var _formal_enemy: EnemyActor
var _fallback_enemy: EnemyActor
var _failed := false
var _failure_messages: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.set_synchronous_loading_for_tests(true)
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true)
	RuntimeDiagnosticsScript.reset_performance_window()
	_verify_redraw_gate_source()
	_game = MainScene.instantiate()
	add_child(_game)
	if not await _wait_for_world_ready():
		_expect(false, "GameRoot production bootstrap did not reach READY")
		_finish_test()
		return
	_game.set_process(false)
	_game.set_physics_process(false)
	await _freeze_existing_enemies()
	_formal_enemy = await _create_formal_enemy()
	_fallback_enemy = await _create_genuine_fallback_enemy()
	if is_instance_valid(_formal_enemy) and is_instance_valid(_fallback_enemy):
		_verify_runtime_redraw_ownership()
	await _cleanup_fixture()
	_finish_test()


func _wait_for_world_ready() -> bool:
	for _frame: int in range(MAX_WORLD_READY_FRAMES):
		if (
			not bool(_game._world_bootstrap_in_progress)
			and not bool(_game._map_transition_in_progress)
			and _game._world_bootstrap_coordinator.stage
			== WorldBootstrapCoordinator.Stage.READY
		):
			return true
		if _game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.FAILED:
			return false
		await get_tree().process_frame
	return false


func _freeze_existing_enemies() -> void:
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and is_instance_valid(value):
			(value as EnemyActor).set_physics_process(false)
			(value as EnemyActor).set_process(false)
	await get_tree().process_frame


func _create_formal_enemy() -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.name = "R3_4_FormalRedrawFixture"
	enemy.setup(GameData.get_monster_by_id(18), _game.player, false)
	enemy.configure_runtime_map_projection(
		BICH_RUNTIME_MAP_ID,
		Callable(_game, "_canonical_ground_gu_to_screen_px"),
		Callable(_game, "_canonical_screen_px_to_ground_gu"),
	)
	enemy.set_meta("spawn_serial", 97001)
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_combat_position(
		_game._canonical_ground_gu_to_screen_px(Vector2.ZERO),
		&"r3_4_redraw_fixture_spawn",
	)
	_game.add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().process_frame
	if enemy.visual != null and enemy.visual.active_resources.is_empty():
		enemy.visual._activate_resources()
	_expect(enemy.visual != null, "formal actor did not construct MonsterVisual")
	if enemy.visual != null:
		_expect(enemy.visual.has_authored_client_art(), "formal actor has no authored art mapping")
		_expect(enemy.visual.uses_final_art(), "formal actor did not acquire final textured art")
	return enemy


func _create_genuine_fallback_enemy() -> EnemyActor:
	# ID 999 is intentionally absent from the canonical appearance catalog. It
	# remains a live EnemyActor fixture, so the actual procedural fallback branch
	# is exercised without mutating any production resource or visual state.
	var enemy := EnemyActor.new()
	enemy.name = "R3_4_GenuineFallbackRedrawFixture"
	enemy.monster_id = 999
	enemy.monster_data = {"monster_id": 999}
	enemy.display_name = "fallback-fixture"
	enemy.max_hp = 1
	enemy.current_hp = 1
	enemy.global_position = Vector2(32.0, 32.0)
	enemy.set_meta("spawn_position", enemy.global_position)
	_game.add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().process_frame
	_expect(enemy.visual != null, "fallback actor did not construct MonsterVisual")
	if enemy.visual != null:
		_expect(not enemy.visual.has_authored_client_art())
		_expect(enemy.visual.should_draw_procedural_fallback(), "fallback actor unexpectedly has final art")
	return enemy


func _verify_runtime_redraw_ownership() -> void:
	RuntimeDiagnosticsScript.reset_performance_window()
	for _tick: int in range(400):
		_formal_enemy._request_actor_redraw_if_dynamic()
	var formal_metrics := RuntimeDiagnosticsScript.performance_counters()
	_expect(
		int(formal_metrics.get("actor_redraw_requests", 0)) == 0,
		"formal textured actor hot-loop parent redraw was not gated",
	)
	for _tick: int in range(400):
		_fallback_enemy._request_actor_redraw_if_dynamic()
	var fallback_metrics := RuntimeDiagnosticsScript.performance_counters()
	_expect(
		int(fallback_metrics.get("actor_redraw_requests", 0)) >= 400,
		"genuine procedural fallback lost its parent redraw ownership",
	)
	var before_one_shot := int(fallback_metrics.get("actor_redraw_requests", 0))
	_formal_enemy._request_actor_redraw()
	_expect(
		RuntimeDiagnosticsScript.performance_counter(&"actor_redraw_requests")
		== before_one_shot + 1,
		"explicit one-shot parent redraw was suppressed",
	)
	var before_selected := RuntimeDiagnosticsScript.performance_counter(&"actor_redraw_requests")
	_formal_enemy.set_targeted(true)
	_expect(RuntimeDiagnosticsScript.performance_counter(&"actor_redraw_requests") > before_selected)
	var before_hit := RuntimeDiagnosticsScript.performance_counter(&"actor_redraw_requests")
	_formal_enemy.take_damage(1)
	_expect(RuntimeDiagnosticsScript.performance_counter(&"actor_redraw_requests") > before_hit)
	var before_status := RuntimeDiagnosticsScript.performance_counter(&"actor_redraw_requests")
	_formal_enemy.apply_control(0.2)
	_expect(RuntimeDiagnosticsScript.performance_counter(&"actor_redraw_requests") > before_status)
	# The visual owns its own animation process and redraw invalidation. A stable
	# formal actor must continue to process animation even though its parent gate
	# remains closed.
	_expect(_formal_enemy.visual.is_processing(), "formal MonsterVisual animation was disabled")
	var before_animation := RuntimeDiagnosticsScript.performance_counter(&"visual_animation_updates")
	_formal_enemy.visual._process(1.0 / 60.0)
	_expect(
		RuntimeDiagnosticsScript.performance_counter(&"visual_animation_updates") > before_animation,
		"MonsterVisual own animation path did not run",
	)
	# Boss warning and safe-zone return retain explicit parent redraw callers in
	# the source contract; the production object remains untouched by this gate.
	var source := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var warning_start := source.find("if _boss_warning > 0.0:")
	var warning_end := source.find("\n\telif", warning_start + 1)
	_expect(warning_start >= 0 and warning_end > warning_start)
	_expect("queue_redraw()" in source.substr(warning_start, warning_end - warning_start))


func _verify_redraw_gate_source() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var wrapper_start := source.find("func _request_actor_redraw_if_dynamic()")
	var wrapper_end := source.find("\nfunc ", wrapper_start + 1)
	_expect(wrapper_start >= 0 and wrapper_end > wrapper_start)
	_expect(
		"_request_actor_redraw_if_dynamic_internal()" in source.substr(
			wrapper_start, wrapper_end - wrapper_start
		),
		"timed redraw wrapper must delegate to the production gate"
	)
	var gate_start := source.find("func _request_actor_redraw_if_dynamic_internal()")
	var gate_end := source.find("\nfunc ", gate_start + 1)
	_expect(gate_start >= 0 and gate_end > gate_start)
	if gate_start < 0 or gate_end <= gate_start:
		return
	var gate_body := source.substr(gate_start, gate_end - gate_start)
	_expect("uses_final_art" in gate_body)
	_expect("should_draw_synthetic_ground_shadow" in gate_body)
	_expect("is_fallback_attacking" in gate_body)
	_expect("_request_actor_redraw()" in gate_body)
	var physics_wrapper_start := source.find("func _physics_process(delta: float)")
	var physics_wrapper_end := source.find("\nfunc ", physics_wrapper_start + 1)
	_expect(physics_wrapper_start >= 0 and physics_wrapper_end > physics_wrapper_start)
	_expect(
		"_physics_process_internal(delta)" in source.substr(
			physics_wrapper_start, physics_wrapper_end - physics_wrapper_start
		),
		"timed physics wrapper must delegate to the production body"
	)
	var physics_start := source.find("func _physics_process_internal(delta: float)")
	var physics_end := source.find("\nfunc ", physics_start + 1)
	_expect(physics_start >= 0 and physics_end > physics_start)
	if physics_start >= 0 and physics_end > physics_start:
		var physics_body := source.substr(physics_start, physics_end - physics_start)
		_expect("_request_actor_redraw_if_dynamic()" in physics_body)
		_expect("_request_actor_redraw()" not in physics_body)
	var safe_return_start := source.find("func _handle_safe_zone_target_return")
	var safe_return_end := source.find("\nfunc ", safe_return_start + 1)
	_expect(safe_return_start >= 0 and safe_return_end > safe_return_start)
	if safe_return_start >= 0 and safe_return_end > safe_return_start:
		var safe_return_body := source.substr(
			safe_return_start,
			safe_return_end - safe_return_start,
		)
		_expect("_request_actor_redraw()" in safe_return_body)
	var selected_start := source.find("func set_targeted")
	var selected_end := source.find("\nfunc ", selected_start + 1)
	_expect(selected_start >= 0 and selected_end > selected_start)
	if selected_start >= 0 and selected_end > selected_start:
		_expect("queue_redraw()" in source.substr(selected_start, selected_end - selected_start))
	var death_start := source.find("func _mark_death_pending")
	var death_end := source.find("\nfunc ", death_start + 1)
	_expect(death_start >= 0 and death_end > death_start)
	if death_start >= 0 and death_end > death_start:
		_expect("remove_from_group(\"enemies\")" in source.substr(death_start, death_end - death_start))


func _cleanup_fixture() -> void:
	for enemy: EnemyActor in [_formal_enemy, _fallback_enemy]:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
			enemy.queue_free()
	await get_tree().process_frame
	if is_instance_valid(_game):
		_game.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, message := "assertion failed") -> bool:
	if condition:
		return true
	_failed = true
	_failure_messages.append(message)
	return false


func _finish_test() -> void:
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(false)
	if _failed:
		push_error(
			"MONSTER_PARENT_REDRAW_GATE_FAIL: "
			+ "; ".join(_failure_messages)
		)
		get_tree().quit(1)
		return
	print("MONSTER_PARENT_REDRAW_GATE_PASS")
	get_tree().quit(0)
