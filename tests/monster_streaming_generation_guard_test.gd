extends Node

## Q2-D generation guard: an old-generation completion is never applied to the
## new world; stale completions are counted; valid current subscribers complete
## normally.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

var _coordinator
var _player: PlayerCharacter
var _enemy_a: EnemyActor
var _enemy_b: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = Fixtures.make_coordinator()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(false)
	_coordinator.set_generation_for_tests(1)
	var shared_id := Fixtures.catalog_ids()[0]
	var mapping_probe := Fixtures.make_enemy(
		self,
		_player,
		shared_id,
		0
	)
	var probe_mapping = mapping_probe.visual._client_mapping_for(
		mapping_probe.monster_data
	)
	var key_probe := mapping_probe.visual._client_resource_cache_key(
		probe_mapping
	)
	mapping_probe.queue_free()
	mapping_probe = null
	await get_tree().process_frame
	# Explicit generation-1 request (prefetch-style) for the shared key.
	_coordinator.request_client_profile(probe_mapping, shared_id, 1)
	_enemy_a = Fixtures.make_enemy(self, _player, shared_id, 1)
	await get_tree().process_frame
	var mapping_a = _enemy_a.visual._client_mapping_for(
		_enemy_a.monster_data
	)
	var key_a := _enemy_a.visual._client_resource_cache_key(mapping_a)
	assert(key_a == key_probe, "shared resource key must match the prefetch key")
	# Map switch: generation 2, old map visual freed, new map visual registers.
	_coordinator.set_generation_for_tests(2)
	_enemy_a.queue_free()
	_enemy_a = null
	_enemy_b = Fixtures.make_enemy(self, _player, shared_id, 2)
	await get_tree().process_frame
	assert(
		_enemy_b.visual._client_resource_cache_key(
			_enemy_b.visual._client_mapping_for(_enemy_b.monster_data)
		) == key_a,
		"map B registers the same shared resource key"
	)
	# Complete the generation-1 request during generation 2.
	var deadline := Time.get_ticks_msec() + 20000
	while (
		_coordinator.pending_request_count() > 0
		and Time.get_ticks_msec() < deadline
	):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		int(diag.get("stale_completion_count", 0)) == 1,
		"the generation-1 completion must be counted stale"
	)
	assert(
		_coordinator.registered_visual_count() == 1,
		"only the new-generation visual remains subscribed"
	)
	Fixtures.drive_residency_activation(_enemy_b.visual)
	assert(
		not _enemy_b.visual.active_resources.is_empty(),
		"the valid current subscriber must apply the shared resource"
	)
	assert(
		_enemy_a == null,
		"the old-generation visual is destroyed and must never apply"
	)
	_cleanup()
	await get_tree().process_frame
	print("MONSTER_STREAMING_GENERATION_GUARD_PASS stale=1")
	get_tree().quit(0)


func _cleanup() -> void:
	if _enemy_a != null and is_instance_valid(_enemy_a):
		_enemy_a.queue_free()
	if _enemy_b != null and is_instance_valid(_enemy_b):
		_enemy_b.queue_free()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
