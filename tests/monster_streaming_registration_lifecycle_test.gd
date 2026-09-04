extends Node

## Q2-D registration lifecycle: register/unregister/queue_free/death/map-clear,
## load-destroyed, double-register and double-unregister leave no strong-ref
## leaks, no duplicate applications and zero active subscriptions.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

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
	MonsterVisual.set_synchronous_loading_for_tests(true)
	var catalog: Array[int] = []
	for monster_id: int in Fixtures.catalog_ids():
		if MonsterIdentity.is_runtime_allowed(monster_id):
			catalog.append(monster_id)
		if catalog.size() == 10:
			break
	assert(catalog.size() == 10, "fixture needs 10 runtime-allowed monsters")
	for i: int in range(10):
		_enemies.append(
			Fixtures.make_enemy(self, _player, catalog[i], i + 1)
		)
	await get_tree().process_frame
	assert(
		_coordinator.registered_visual_count() == 10,
		"all 10 visuals must register"
	)
	# Double registration is a no-op.
	var first_visual: MonsterVisual = _enemies[0].visual
	var first_mapping = first_visual._client_mapping_for(
		_enemies[0].monster_data
	)
	_coordinator.register_visual(
		first_visual,
		_enemies[0].monster_id,
		1,
		0,
		first_visual._client_resource_cache_key(first_mapping),
		first_visual._client_resource_paths(first_mapping),
		1
	)
	assert(
		_coordinator.registered_visual_count() == 10,
		"double registration must be deduplicated"
	)
	# Double unregister is safe.
	var first_id := first_visual.get_instance_id()
	_coordinator.unregister_visual(first_id)
	_coordinator.unregister_visual(first_id)
	assert(
		_coordinator.registered_visual_count() == 9,
		"unregister must remove exactly one subscription"
	)
	# queue_free -> cleanup on the next poll.
	_enemies[1].queue_free()
	_enemies[1] = null
	await get_tree().process_frame
	_coordinator.poll_once(Engine.get_process_frames())
	assert(
		_coordinator.registered_visual_count() == 8,
		"queue_free must clean the subscription"
	)
	# Death animation completion frees the enemy -> visual unregisters.
	_enemies[2].take_damage(99999, null)
	var death_deadline := Time.get_ticks_msec() + 10000
	while (
		_coordinator.registered_visual_count() > 7
		and Time.get_ticks_msec() < death_deadline
	):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	assert(
		_coordinator.registered_visual_count() == 7,
		"death teardown must clean the subscription"
	)
	# Map-clear / generation teardown: free every remaining enemy.
	for enemy: EnemyActor in _enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_coordinator.poll_once(Engine.get_process_frames())
	assert(
		_coordinator.registered_visual_count() == 0,
		"map clear must leave zero active subscriptions"
	)
	# Load-destroyed: request a threaded profile, destroy the subscriber, then
	# poll - no invalid access, no permanent LOADING subscriber.
	MonsterVisual.set_synchronous_loading_for_tests(false)
	var enemy := Fixtures.make_enemy(self, _player, catalog[0], 100)
	await get_tree().process_frame
	assert(_coordinator.registered_visual_count() == 1)
	enemy.queue_free()
	await get_tree().process_frame
	for _frame: int in range(20):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	assert(
		_coordinator.registered_visual_count() == 0,
		"load-destroyed subscriber must be cleaned"
	)
	# A leaked caller that cannot run MonsterVisual._exit_tree is still reclaimed,
	# but cleanup work is fixed per poll rather than one full subscription walk.
	var stale_count: int = (
		int(_coordinator.MAX_SUBSCRIBER_CLEANUP_VISITS_PER_POLL) * 3
	)
	for index in range(stale_count):
		var stale_visual := Node.new()
		add_child(stale_visual)
		_coordinator.register_visual(
			stale_visual,
			1000 + index,
			1,
			_coordinator.current_world_generation(),
			"",
			{},
			1000 + index,
		)
		stale_visual.queue_free()
	await get_tree().process_frame
	var cleanup_polls := 0
	while _coordinator.registered_visual_count() > 0 and cleanup_polls < 6:
		_coordinator.poll_once(Engine.get_process_frames())
		cleanup_polls += 1
		await get_tree().process_frame
	var cleanup_diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		_coordinator.registered_visual_count() == 0,
		"bounded cleanup leaked invalid subscriptions: %s" % cleanup_diag,
	)
	assert(
		int(cleanup_diag.subscriber_cleanup_max_visits_per_poll)
			<= _coordinator.MAX_SUBSCRIBER_CLEANUP_VISITS_PER_POLL,
		"cleanup exceeded its per-poll visit ceiling: %s" % cleanup_diag,
	)
	_cleanup()
	await get_tree().process_frame
	print("MONSTER_STREAMING_REGISTRATION_LIFECYCLE_PASS")
	get_tree().quit(0)


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
