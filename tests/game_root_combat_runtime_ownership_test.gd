extends Node

## M30-CLEANUP-001 ownership regression for GameRoot's CombatRuntimeService.
##
## The service instance is created by a GameRoot member initializer and must be
## owned by that GameRoot (real add_child in _init) so instances that never
## enter the SceneTree are still released together with their owner. This test
## never frees the service directly; the owner relationship does the cleanup.
##
## Contract under test:
## 1. A GameRoot freed while never added to the tree must not leave a live
##    CombatRuntimeService behind (same-signature orphan from M30-CLEANUP-001).
## 2. Repeated create/destroy cycles must not accumulate that orphan signature.
## 3. A full formal world teardown must invalidate the old service, and a
##    freshly entered world must own exactly one valid service.

const GameRootScript := preload("res://scripts/game_root.gd")
const CombatRuntimeServiceScript := preload(
	"res://scripts/layers/runtime/combat_runtime_service.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_assert_out_of_tree_owner_release()
	await _assert_world_reentry_single_service()
	print("GAME_ROOT_COMBAT_RUNTIME_OWNERSHIP_PASS")
	get_tree().quit(0)


func _assert_out_of_tree_owner_release() -> void:
	var game: Node = GameRootScript.new()
	var service: Node = game._combat_runtime
	var service_ref: WeakRef = weakref(service)
	assert(
		is_instance_valid(service_ref.get_ref()),
		"CombatRuntimeService 必须在 GameRoot 实例化时创建",
	)
	assert(
		service.get_parent() == game,
		"CombatRuntimeService 必须以 GameRoot 为父节点建立所有权",
	)
	assert(
		not service.is_inside_tree(),
		"GameRoot 未入树时服务同样不入树，保持既有调用形态",
	)
	# Free the owner without ever entering the SceneTree. The service must die
	# with its owner instead of leaking as an orphan Node / GDScript resource.
	game.free()
	assert(
		not is_instance_valid(service_ref.get_ref()),
		"GameRoot 释放后 CombatRuntimeService 必须随所有者一起失效（M30-CLEANUP-001）",
	)
	# Cycles 2..N: repeated create/destroy must not accumulate same-signature
	# orphans. Engine prewarm caches are untouched; each cycle's service is
	# tracked by its own owner through a dedicated WeakRef.
	for cycle in range(2, 7):
		var cycle_game: Node = GameRootScript.new()
		var cycle_ref: WeakRef = weakref(cycle_game._combat_runtime)
		cycle_game.free()
		assert(
			not is_instance_valid(cycle_ref.get_ref()),
			"第 %d 次创建/销毁后同签名服务孤儿必须失效" % cycle,
		)
	print("GAME_ROOT_COMBAT_RUNTIME_OWNERSHIP_OUT_OF_TREE_OK")


func _assert_world_reentry_single_service() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.recalculate_stats()

	var first_world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(first_world)
	await get_tree().process_frame
	await get_tree().process_frame
	var first_service_ref: WeakRef = weakref(first_world._combat_runtime)
	var first_service_instance_id := (first_service_ref.get_ref() as Node).get_instance_id()
	_assert_single_owned_service(first_world)
	first_world.queue_free()
	await _await_world_released(first_world)
	assert(
		not is_instance_valid(first_service_ref.get_ref()),
		"正式世界退出后旧 CombatRuntimeService 必须失效",
	)

	var second_world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(second_world)
	await get_tree().process_frame
	await get_tree().process_frame
	var second_service_ref: WeakRef = weakref(second_world._combat_runtime)
	_assert_single_owned_service(second_world)
	assert(
		is_instance_valid(second_service_ref.get_ref()),
		"再次进入后新世界必须持有有效 CombatRuntimeService",
	)
	assert(
		(second_service_ref.get_ref() as Node).get_instance_id() != first_service_instance_id,
		"新世界服务必须是全新实例，不得复用旧世界服务",
	)
	second_world.queue_free()
	await _await_world_released(second_world)
	assert(
		not is_instance_valid(second_service_ref.get_ref()),
		"第二次世界退出后服务同样必须失效",
	)
	print("GAME_ROOT_COMBAT_RUNTIME_OWNERSHIP_WORLD_REENTRY_OK")


func _await_world_released(world: Node) -> void:
	for _frame in range(16):
		await get_tree().process_frame
		if not is_instance_valid(world):
			return
	assert(false, "正式世界在等待窗口内未完成释放")


func _assert_single_owned_service(world: Node) -> void:
	var owned: Array = world.get_children().filter(
		func(child: Node) -> bool: return child.get_script() == CombatRuntimeServiceScript
	)
	assert(
		owned.size() == 1,
		"每个世界实例应恰好有一个 CombatRuntimeService 子节点，实际 %d 个" % owned.size(),
	)
