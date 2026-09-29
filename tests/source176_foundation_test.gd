extends SceneTree
const Geometry := preload("res://scripts/monster_source176/source_melee_geometry.gd")
const Steps := preload("res://scripts/monster_source176/source_step_plan.gd")
const Reaction := preload("res://scripts/monster_source176/reaction_policy.gd")
const Registry := preload("res://scripts/monster_source176/skill_reaction_registry.gd")
const Actions := preload("res://scripts/monster_source176/action_boundary.gd")
const Frames := preload("res://scripts/monster_source176/frame_cursor.gd")
const Budget := preload("res://scripts/monster_source176/step_budget.gd")
const Cadence := preload("res://tests/helpers/source_cadence_reference.gd")
var failures: int = 0
var assertions: int = 0

func check(value: bool, label: String) -> void:
    assertions += 1
    if not value:
        failures += 1
        printerr("FAIL: " + label)

func _initialize() -> void:
    for x: int in range(-2, 3):
        for y: int in range(-2, 3):
            var expected: bool = (x != 0 or y != 0) and absi(x) <= 1 and absi(y) <= 1
            check(Geometry.source_adjacent(Vector2i.ZERO, Vector2i(x, y)) == expected, "source integer adjacency")
    check(not Geometry.continuous_adjacent(Vector2(1.4, 0.0)), "reject excess axial circle reach")
    check(Geometry.continuous_adjacent(Vector2(1.0, 1.0)), "diagonal source neighbor")
    check(not Geometry.continuous_adjacent(Vector2.INF), "reject invalid coordinates")
    var point := Vector2.ZERO
    var goal := Vector2(12.0, 5.0)
    var total: float = 0.0
    var turns: int = 0
    var last_direction := Vector2.ZERO
    var count: int = 0
    while point.distance_to(goal) > 0.00001 and count < 64:
        var endpoint: Vector2 = Steps.next_leg(point, goal)
        var d: Vector2 = endpoint - point
        check(Steps.is_eight_way(d), "actual movement remains eight-way")
        var direction: Vector2 = d.normalized()
        if last_direction != Vector2.ZERO and direction.distance_to(last_direction) > 0.00001:
            turns += 1
        last_direction = direction
        total += d.length()
        point = endpoint
        count += 1
    check(count == 12 and turns == 1, "source direction structure, not micro-zigzag")
    check(absf(total - (7.0 + 5.0 * sqrt(2.0))) < 0.0001, "octile path length")
    check(Registry.FAMILIES.size() == 33, "complete 33 skill map")
    check(Registry.family("wizard.fire_wall") == &"MINE", "fire wall mine receipt")
    check(Registry.family("wizard.ice_storm") == &"DIRECT", "aoe not automatically mine")
    check(Registry.family("future.unknown") == &"UNKNOWN", "no direct default")
    check(Reaction.walk_delta_ms(&"DIRECT", 25, true, false, true, 0) == 800, "min walk delta")
    check(Reaction.walk_delta_ms(&"DIRECT", 40, true, false, true, 999) == 1799, "max walk delta")
    check(Reaction.walk_delta_ms(&"DIRECT", 50, true, false, true, 500) == 0, "level exemption")
    check(Reaction.walk_delta_ms(&"MINE", 25, true, false, true, 500) == 0, "mine no direct wait")
    check(Reaction.ordinary_struck_attack_delta_ms(&"DIRECT", 40, 0) == 0, "MAC zero has no ordinary STRUCK")
    check(Reaction.ordinary_struck_attack_delta_ms(&"MINE", 25, 1) == 50, "mine positive struck")
    check(Reaction.pushed_walk_delta_ms(2, true) == 1600, "successful push steps only")
    var cadence := Cadence.new()
    check(cadence.configure(1500, 1, 0), "cadence configure")
    check(cadence.postpone(1350), "preserve stored deadline")
    check(not cadence.evaluate(2850), "strict greater at deadline")
    check(cadence.evaluate(2851), "grant immediately after deadline")
    check(not cadence.evaluate(2851), "one grant per source timestamp")
    check(Actions.choose(true, false, false, true, true) == &"CADENCE_WAIT", "shared source decision gate")
    check(Actions.choose(true, false, true, true, true) == &"ATTACK", "decisive legal attack")
    check(Actions.choose(true, false, true, true, false) == &"COOLDOWN_HOLD", "in range no further chase")
    check(Actions.choose(true, false, true, false, true) == &"PURSUE", "out of range pursue")
    check(not Actions.can_reserve_body_action(100, 100, false, false), "no second same-tick body action")
    check(Frames.frame_at(10.01, 10.0, 0.72, 6) == 0, "new action survives long render delta")
    check(Frames.frame_at(10.72, 10.0, 0.72, 6) == -1, "no expired action replay")
    var motion: Vector2 = Budget.desired_motion(Vector2.ZERO, Vector2(0.01, 0), 2.0, 1.0 / 60.0)
    var remaining: float = Budget.after_arrival(1.0 / 60.0, motion.length(), 2.0)
    var motion2: Vector2 = Budget.desired_motion(motion, Vector2(1.0, 0), 2.0, remaining)
    check(motion.length() + motion2.length() <= 2.0 / 60.0 + 0.000001, "same frame budget never increases")
    print("SOURCE176_FOUNDATION assertions=%d failures=%d" % [assertions, failures])
    quit(0 if failures == 0 else 1)
