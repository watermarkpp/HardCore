extends Node2D

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const TerrainPolicy := preload("res://scripts/monster_terrain_navigation_policy.gd")


class RevisionProvider:
    extends Node

    var blocked_world_px := Vector2.INF
    var revision := 1
    var sample_calls := 0

    func is_environment_point_blocked(world_px: Vector2) -> bool:
        sample_calls += 1
        return (
            blocked_world_px.is_finite()
            and world_px.distance_to(blocked_world_px) <= 2.0
        )

    func environment_collision_revision() -> int:
        return revision


class RevisionlessProvider:
    extends Node

    var blocked_world_px := Vector2.INF
    var sample_calls := 0

    func is_environment_point_blocked(world_px: Vector2) -> bool:
        sample_calls += 1
        return (
            blocked_world_px.is_finite()
            and world_px.distance_to(blocked_world_px) <= 2.0
        )


var _saved_settings := {}
var _provider: RevisionProvider


func _ready() -> void:
    _run.call_deferred()


func _run() -> void:
    PlayerState.test_mode = true
    PlayerState.reset_progress()
    _disable_performance_settings()
    assert(not RuntimeDiagnostics.performance_enabled())
    assert(RuntimeDiagnostics.timing_start() == 0)

    _provider = RevisionProvider.new()
    add_child(_provider)
    RuntimeDiagnostics.set_device_lab_performance_enabled(true)
    assert(RuntimeDiagnostics.performance_enabled())

    var player := _make_player(Vector2(1.0, 0.0))
    var attacker := await _make_attacker(64, player, _provider)
    RuntimeDiagnostics.reset_performance_window()
    await _assert_static_window_cache(attacker, player)
    await _assert_key_and_provider_changes(attacker, player)
    await _assert_immediate_delivery_reuse()
    await _assert_release_rechecks()

    attacker.queue_free()
    player.queue_free()
    await get_tree().process_frame
    _restore_performance_settings()
    print(
        "MONSTER_ATTACK_LOS_CACHE_PASS "
        + "static_10s=1 cache_hit_rate>95% "
        + "key_changes=target,source,target_endpoint,map,revision,provider "
        + "legacy_provider_bypass=1 immediate_reuse=melee,70,projectile,magic "
        + "release_recheck=melee,projectile,magic"
    )
    get_tree().quit(0)


func _disable_performance_settings() -> void:
    for setting: StringName in [
        RuntimeDiagnostics.SETTING_ENABLED,
        RuntimeDiagnostics.SETTING_PERFORMANCE,
        RuntimeDiagnostics.SETTING_DEVICE_LAB_PERFORMANCE,
    ]:
        _saved_settings[setting] = ProjectSettings.get_setting(setting, false)
        ProjectSettings.set_setting(setting, false)
    RuntimeDiagnostics.set_device_lab_performance_enabled(false)
    RuntimeDiagnostics.refresh_performance_gate()


func _restore_performance_settings() -> void:
    RuntimeDiagnostics.set_device_lab_performance_enabled(false)
    for setting: Variant in _saved_settings.keys():
        ProjectSettings.set_setting(setting, _saved_settings[setting])
    RuntimeDiagnostics.refresh_performance_gate()


func _assert_static_window_cache(
    attacker: EnemyActor,
    player: PlayerCharacter,
) -> void:
    _provider.blocked_world_px = Vector2.INF
    _provider.revision = 1
    var eval_before := _counter("attack_los_evaluations")
    var request_before := _counter("attack_los_requests")
    var hit_before := _counter("attack_los_cache_hits")
    var sample_before := _counter("attack_los_map_samples")
    var ray_before := _counter("attack_los_physics_rays")
    assert(attacker._attack_world_path_is_clear_for_target(player))
    assert(_counter("attack_los_evaluations") == eval_before + 1)
    assert(_counter("attack_los_map_samples") > sample_before)
    assert(_counter("attack_los_physics_rays") > ray_before)

    # 600 frames represent ten seconds at 60 Hz. With a static source,
    # endpoint and revision, only the first request may evaluate LOS.
    for _frame in range(599):
        assert(attacker._attack_world_path_is_clear_for_target(player))
    var evaluation_delta := _counter("attack_los_evaluations") - eval_before
    var request_delta := _counter("attack_los_requests") - request_before
    var hit_delta := _counter("attack_los_cache_hits") - hit_before
    assert(request_delta == 600, "static window did not retain request count")
    assert(evaluation_delta == 1, "static window re-evaluated LOS")
    assert(hit_delta == 599, "static window did not hit every repeated request")
    assert(
        float(hit_delta) / float(hit_delta + evaluation_delta) > 0.95,
        "static LOS cache hit rate did not exceed 95%",
    )


func _assert_key_and_provider_changes(
    attacker: EnemyActor,
    player: PlayerCharacter,
) -> void:
    var eval_before := _counter("attack_los_evaluations")

    attacker.global_position = _ground_to_screen(Vector2(0.25, 0.0))
    assert(attacker._attack_world_path_is_clear_for_target(player))
    assert(_counter("attack_los_evaluations") == eval_before + 1)

    attacker.global_position = Vector2.ZERO
    player.global_position = _ground_to_screen(Vector2(1.25, 0.0))
    assert(attacker._attack_world_path_is_clear_for_target(player))
    assert(_counter("attack_los_evaluations") == eval_before + 2)

    var replacement := _make_player(Vector2(1.25, 0.0))
    assert(attacker._attack_world_path_is_clear_for_target(replacement))
    assert(_counter("attack_los_evaluations") == eval_before + 3)

    attacker.configure_runtime_map_projection(
        2,
        Callable(self, "_ground_to_screen"),
        Callable(self, "_screen_to_ground"),
    )
    assert(attacker._attack_world_path_is_clear_for_target(replacement))
    assert(_counter("attack_los_evaluations") == eval_before + 4)

    attacker.configure_runtime_map_projection(
        1,
        Callable(self, "_ground_to_screen"),
        Callable(self, "_screen_to_ground"),
    )
    _provider.revision += 1
    assert(attacker._attack_world_path_is_clear_for_target(replacement))
    assert(_counter("attack_los_evaluations") == eval_before + 5)

    var replacement_provider := RevisionProvider.new()
    add_child(replacement_provider)
    replacement_provider.revision = _provider.revision
    attacker.environment_blocker = replacement_provider
    assert(attacker._attack_world_path_is_clear_for_target(replacement))
    assert(_counter("attack_los_evaluations") == eval_before + 6)

    # A legacy provider with no usable revision API must never cache: changing
    # a blocker in place is visible on the very next request.
    var legacy_provider := RevisionlessProvider.new()
    add_child(legacy_provider)
    attacker.environment_blocker = legacy_provider
    legacy_provider.blocked_world_px = _ground_to_screen(Vector2(0.5, 0.0))
    assert(not attacker._attack_world_path_is_clear_for_target(replacement))
    var legacy_eval := _counter("attack_los_evaluations")
    legacy_provider.blocked_world_px = Vector2.INF
    assert(attacker._attack_world_path_is_clear_for_target(replacement))
    assert(_counter("attack_los_evaluations") == legacy_eval + 1)
    assert(
        _counter("attack_los_cache_hits") == 599,
        "legacy provider unexpectedly populated the LOS cache",
    )

    attacker.environment_blocker = _provider
    player.global_position = _ground_to_screen(Vector2(1.0, 0.0))
    replacement.queue_free()
    replacement_provider.queue_free()
    legacy_provider.queue_free()
    await get_tree().process_frame


func _assert_immediate_delivery_reuse() -> void:
    _provider.blocked_world_px = Vector2.INF
    _provider.revision += 1

    var melee_player := _make_player(Vector2(1.0, 0.0))
    var melee := await _make_attacker(64, melee_player, _provider)
    RuntimeDiagnostics.reset_performance_window()
    assert(
        melee._attack_engagement_ready(
            melee_player,
            Vector2(1.0, 0.0),
            1.0,
            melee._contact_distance_gu_to_target(melee_player),
            melee.attack_range_gu,
        )
    )
    var eval_after_engagement := _counter("attack_los_evaluations")
    var hp_before := melee_player.current_hp
    melee._deal_melee_hit(melee_player, 7)
    assert(melee_player.current_hp < hp_before)
    assert(_counter("attack_los_evaluations") == eval_after_engagement)
    assert(_counter("attack_los_cache_hits") >= 1)
    melee.queue_free()
    melee_player.queue_free()

    var special_player := _make_player(Vector2(1.0, 0.0))
    var special := await _make_attacker(70, special_player, _provider)
    RuntimeDiagnostics.reset_performance_window()
    assert(
        special._attack_engagement_ready(
            special_player,
            Vector2(1.0, 0.0),
            1.0,
            special._contact_distance_gu_to_target(special_player),
            special.attack_range_gu,
        )
    )
    var special_eval := _counter("attack_los_evaluations")
    var special_hp := special_player.current_hp
    special._deal_special_magic_melee_hit(special_player, 7)
    assert(special_player.current_hp < special_hp)
    assert(_counter("attack_los_evaluations") == special_eval)
    assert(_counter("attack_los_cache_hits") >= 1)
    special.queue_free()
    special_player.queue_free()

    var projectile_player := _make_player(Vector2(4.0, 0.0))
    var projectile := await _make_attacker(150, projectile_player, _provider)
    RuntimeDiagnostics.reset_performance_window()
    assert(
        projectile._attack_engagement_ready(
            projectile_player,
            Vector2(4.0, 0.0),
            4.0,
            projectile._contact_distance_gu_to_target(projectile_player),
            projectile.attack_range_gu,
        )
    )
    var projectile_eval := _counter("attack_los_evaluations")
    assert(projectile._launch_physical_projectile(projectile_player, 7))
    assert(_counter("attack_los_evaluations") == projectile_eval)
    assert(_counter("attack_los_cache_hits") >= 1)
    projectile.queue_free()
    projectile_player.queue_free()

    var magic_player := _make_player(Vector2(2.0, 0.0))
    var magic := await _make_attacker(220, magic_player, _provider)
    RuntimeDiagnostics.reset_performance_window()
    assert(
        magic._attack_engagement_ready(
            magic_player,
            Vector2(2.0, 0.0),
            2.0,
            magic._contact_distance_gu_to_target(magic_player),
            magic.attack_range_gu,
        )
    )
    var magic_eval := _counter("attack_los_evaluations")
    assert(magic._launch_target_magic(magic_player, 7))
    assert(_counter("attack_los_evaluations") == magic_eval)
    assert(_counter("attack_los_cache_hits") >= 1)
    magic.queue_free()
    magic_player.queue_free()
    await get_tree().process_frame


func _assert_release_rechecks() -> void:
    _provider.blocked_world_px = Vector2.INF
    _provider.revision += 1

    var melee_player := _make_player(Vector2(1.0, 0.0))
    var melee := await _make_attacker(64, melee_player, _provider)
    RuntimeDiagnostics.reset_performance_window()
    assert(melee._attack_world_path_is_clear_for_target(melee_player))
    var melee_eval := _counter("attack_los_evaluations")
    _provider.blocked_world_px = _ground_to_screen(Vector2(0.5, 0.0))
    var melee_hp := melee_player.current_hp
    melee._pending_attack_time = 0.1
    melee._pending_attack_target = melee_player
    melee._pending_attack_damage = 7
    melee._pending_attack_release_record = {}
    melee._update_pending_attack(0.1)
    assert(melee_player.current_hp == melee_hp)
    assert(_counter("attack_los_evaluations") == melee_eval + 1)
    melee.queue_free()
    melee_player.queue_free()

    _provider.blocked_world_px = Vector2.INF
    _provider.revision += 1
    var projectile_player := _make_player(Vector2(4.0, 0.0))
    var projectile := await _make_attacker(150, projectile_player, _provider)
    RuntimeDiagnostics.reset_performance_window()
    assert(projectile._attack_world_path_is_clear_for_target(projectile_player))
    var projectile_eval := _counter("attack_los_evaluations")
    assert(projectile._launch_physical_projectile(projectile_player, 7))
    _provider.blocked_world_px = _ground_to_screen(Vector2(2.0, 0.0))
    var projectile_hp := projectile_player.current_hp
    projectile._update_pending_attack(2.0)
    assert(projectile_player.current_hp == projectile_hp)
    assert(_counter("attack_los_evaluations") == projectile_eval + 1)
    projectile.queue_free()
    projectile_player.queue_free()

    _provider.blocked_world_px = Vector2.INF
    _provider.revision += 1
    var magic_player := _make_player(Vector2(2.0, 0.0))
    var magic := await _make_attacker(220, magic_player, _provider)
    RuntimeDiagnostics.reset_performance_window()
    assert(magic._attack_world_path_is_clear_for_target(magic_player))
    var magic_eval := _counter("attack_los_evaluations")
    assert(magic._launch_target_magic(magic_player, 7))
    _provider.blocked_world_px = _ground_to_screen(Vector2(1.0, 0.0))
    var magic_hp := magic_player.current_hp
    magic._update_pending_attack(1.0)
    assert(magic_player.current_hp == magic_hp)
    assert(_counter("attack_los_evaluations") == magic_eval + 1)
    magic.queue_free()
    magic_player.queue_free()
    await get_tree().process_frame


func _make_player(ground_gu: Vector2) -> PlayerCharacter:
    var player := PlayerCharacter.new()
    player.global_position = _ground_to_screen(ground_gu)
    player.process_mode = Node.PROCESS_MODE_DISABLED
    player.set_physics_process(false)
    player.set_meta("runtime_map_id", 1)
    add_child(player)
    player.max_hp = 1000
    player.current_hp = 1000
    player.defense_min = 0
    player.defense_max = 0
    return player


func _make_attacker(
    monster_id: int,
    player: PlayerCharacter,
    provider: Node,
) -> EnemyActor:
    var attacker := EnemyActor.new()
    attacker.global_position = Vector2.ZERO
    attacker.setup(GameData.get_monster_by_id(monster_id), player, false)
    attacker.configure_runtime_map_projection(
        1,
        Callable(self, "_ground_to_screen"),
        Callable(self, "_screen_to_ground"),
    )
    attacker.configure_terrain_navigation_context(_empty_terrain_context())
    attacker.environment_blocker = provider
    attacker.process_mode = Node.PROCESS_MODE_DISABLED
    attacker.set_physics_process(false)
    add_child(attacker)
    await get_tree().process_frame
    attacker.global_position = Vector2.ZERO
    attacker._attack_timer = 999.0
    attacker._pending_attack_time = -1.0
    attacker._pending_attack_target = null
    attacker._pending_attack_damage = 0
    attacker._pending_attack_release_record = {}
    return attacker


func _counter(field: String) -> int:
    return RuntimeDiagnostics.performance_counter(StringName(field))


func _ground_to_screen(value: Vector2) -> Vector2:
    return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
    return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)


func _empty_terrain_context() -> Dictionary:
    return TerrainPolicy.build_context(
        1,
        {
            "build_sha256": "1".repeat(64),
            "source": {"runtime_map_id": 1},
            "design": {"design_size": [32, 32]},
            "collision": {"blocked_tiles": []},
        },
        TerrainPolicy.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
    )
