extends Node

## Q2-D: 100 visuals requesting one shared resource must produce one threaded
## request, 100 subscriptions and 100 applications (no per-visual duplicate
## loads, no apply only to the first visual).

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const VISUAL_COUNT := 100

var _coordinator
var _player: PlayerCharacter
var _enemies: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = Fixtures.make_coordinator()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(false)
	var shared_monster_id := Fixtures.catalog_ids()[0]
	for i: int in range(VISUAL_COUNT):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_player,
				shared_monster_id,
				i + 1
			)
		)
	await get_tree().process_frame
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		int(diag.get("request_enqueue_count", 0)) == VISUAL_COUNT,
		"every visual must enqueue its resource need"
	)
	assert(
		int(diag.get("unique_request_count", 0)) == 1,
		"100 same-resource visuals must share one unique request"
	)
	assert(
		int(diag.get("duplicate_request_count", 0)) == VISUAL_COUNT - 1,
		"99 visuals must be deduplicated onto the existing request"
	)
	assert(
		int(diag.get("registered_visual_count", 0)) == VISUAL_COUNT,
		"all 100 visuals must be registered"
	)
	var waiting_count = _coordinator.waiting_visual_count_for_resource(
		_coordinator.request_order()[0]
	)
	assert(
		waiting_count == VISUAL_COUNT,
		"waiting visual count must be 100"
	)
	# Threaded loads: one profile = five action atlases.
	var deadline := Time.get_ticks_msec() + 20000
	while (
		_coordinator.pending_request_count() > 0
		and Time.get_ticks_msec() < deadline
	):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	var completed := 0
	for enemy: EnemyActor in _enemies:
		if not is_instance_valid(enemy):
			continue
		Fixtures.drive_residency_activation(enemy.visual)
		if not enemy.visual.active_resources.is_empty():
			completed += 1
	assert(
		completed == VISUAL_COUNT,
		"all 100 visuals must apply the shared resource (got %d)" % completed
	)
	var final_diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		int(final_diag.get("resource_apply_count", 0)) == VISUAL_COUNT,
		"per-visual resource application count must be 100"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"MONSTER_STREAMING_REQUEST_DEDUP_PASS visuals=%d unique=1 threaded_actions=5 applied=%d"
		% [VISUAL_COUNT, completed]
	)
	get_tree().quit(0)


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
