extends Node

## Q2-D animation continuity: applying a resource mid-action must not reset
## action, direction, playing state, frame progress or death progress.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Reference := preload(
	"res://tests/helpers/monster_visual_legacy_streaming_reference.gd"
)

var _coordinator
var _player: PlayerCharacter
var _enemy: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = Fixtures.make_coordinator()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(true)
	_enemy = Fixtures.make_enemy(self, _player, Fixtures.catalog_ids()[0], 1)
	await get_tree().process_frame
	var visual: MonsterVisual = _enemy.visual
	Fixtures.drive_residency_activation(visual)
	assert(
		not visual.active_resources.is_empty(),
		"sync test profile must be active"
	)
	_enemy.facing = Vector2.RIGHT
	visual._attack_remaining = 0.5
	visual._elapsed = 0.0
	visual._process(0.016)
	assert(visual.current_state == "attack", "attack action must engage")
	var attack_direction := visual.current_direction
	var attack_frame := visual.current_frame
	# Force the frozen re-application path (residency release + activate).
	visual._release_resources()
	visual._activate_resources()
	visual._process(0.016)
	var expected := Reference.expected_animation_after_apply(
		"attack",
		attack_direction,
		true,
		0.0
	)
	assert(
		visual.current_state == str(expected.get("action", "")),
		"resource re-application must not cancel the attack action"
	)
	assert(
		visual.current_direction == int(expected.get("direction", 0)),
		"direction must be preserved"
	)
	assert(
		visual._attack_remaining > 0.0,
		"attack progress must be preserved"
	)
	# Death animation must never restart on re-application.
	visual._attack_remaining = 0.0
	visual._death_remaining = 1.0
	visual._elapsed = 0.0
	visual._process(0.016)
	assert(visual.current_state == "death", "death action must engage")
	var death_progress_before := visual._death_remaining
	visual._release_resources()
	visual._activate_resources()
	visual._process(0.016)
	assert(visual.current_state == "death", "death animation must not restart")
	assert(
		is_equal_approx(visual._death_remaining, death_progress_before - 0.016),
		"death progress must continue (not restart)"
	)
	# Hit action: preserved the same way.
	visual._death_remaining = 0.0
	visual._hit_remaining = 0.4
	visual._elapsed = 0.0
	visual._process(0.016)
	assert(visual.current_state == "hit", "hit action must engage")
	visual._release_resources()
	visual._activate_resources()
	visual._process(0.016)
	assert(visual.current_state == "hit", "hit action must be preserved")
	_cleanup()
	await get_tree().process_frame
	print("MONSTER_STREAMING_ANIMATION_CONTINUITY_PASS")
	get_tree().quit(0)


func _cleanup() -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
