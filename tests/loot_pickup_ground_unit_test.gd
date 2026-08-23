extends Node

const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

var _rejection_count := 0


func _on_rejected(_item_name: String, _message: String) -> void:
	_rejection_count += 1


func _confirm_collected(_item_name: String, pickup: LootPickup) -> void:
	pickup.confirm_collect()


func _ready() -> void:
	var retry_a := LootPickupScript.new()
	var retry_b := LootPickupScript.new()
	add_child(retry_a)
	add_child(retry_b)
	retry_a._arm_collection_retry_cooldown()
	assert(is_equal_approx(retry_a.retry_cooldown_remaining(), 5.0), "拾取失败冷却必须为5秒")
	retry_a._process(4.99)
	assert(retry_a.retry_cooldown_remaining() > 0.0, "5秒内不应再次重试同一地物")
	assert(is_zero_approx(retry_b.retry_cooldown_remaining()), "不同地物不应共享拾取冷却")
	retry_a._process(0.01)
	assert(is_zero_approx(retry_a.retry_cooldown_remaining()), "5秒后应解除同一地物冷却")
	retry_a._collection_pending = true
	assert(retry_a.collection_pending(), "拾取两阶段确认未登记pending")
	retry_a.confirm_collect()
	assert(not retry_a.collection_pending(), "确认成功后pending未清除")

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 1
	PlayerState.inventory = [{"name": "强效太阳水", "count": 99}]
	PlayerState.recalculate_stats()
	var target := PlayerCharacter.new()
	var overweight_pickup := LootPickupScript.new()
	add_child(overweight_pickup)
	overweight_pickup.setup("强效太阳水", target)
	overweight_pickup.collection_rejected.connect(_on_rejected)
	overweight_pickup.global_position = Vector2.ZERO
	target.global_position = Vector2.ZERO
	overweight_pickup._process(0.0)
	assert(overweight_pickup.collection_authority_check_count() == 1 and _rejection_count == 1, "首次超重拾取未执行一次权威检查")
	assert(not overweight_pickup.is_queued_for_deletion(), "超重拒绝错误删除地物")
	overweight_pickup._process(4.99)
	assert(overweight_pickup.collection_authority_check_count() == 1 and _rejection_count == 1, "5秒内重复检查/提示同一地物")
	overweight_pickup._process(0.01)
	assert(overweight_pickup.collection_authority_check_count() == 2 and _rejection_count == 2, "5秒后未重新检查同一地物")
	target.global_position = Vector2(1000, 1000)
	overweight_pickup._process(0.01)
	assert(is_zero_approx(overweight_pickup.retry_cooldown_remaining()), "离开拾取范围未立即解除冷却")
	assert(not overweight_pickup.is_queued_for_deletion(), "失败拾取地物被错误删除")

	var accepted := LootPickupScript.new()
	add_child(accepted)
	accepted.setup("金币", target)
	target.global_position = accepted.global_position
	accepted.collected.connect(_confirm_collected)
	accepted._process(0.0)
	assert(accepted.is_queued_for_deletion(), "只有权威接收成功才应删除地物")
	for node: Node in [retry_a, retry_b, overweight_pickup, accepted]:
		if is_instance_valid(node):
			node.free()
	if is_instance_valid(target):
		target.free()
	var pickup_screen_position_px := Vector2(137.0, -91.0)
	for direction_index: int in range(32):
		var direction_ground_gu := Vector2.from_angle(
			TAU * float(direction_index) / 32.0
		)
		var inside_screen_position_px := (
			pickup_screen_position_px
			+ GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu
				* (LootPickupScript.COLLECTION_RADIUS_GU - 0.0001)
			)
		)
		var outside_screen_position_px := (
			pickup_screen_position_px
			+ GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu
				* (LootPickupScript.COLLECTION_RADIUS_GU + 0.0001)
			)
		)
		assert(LootPickupScript.target_is_within_collection_range_screen_px(
			pickup_screen_position_px,
			inside_screen_position_px
		))
		assert(not LootPickupScript.target_is_within_collection_range_screen_px(
			pickup_screen_position_px,
			outside_screen_position_px
		))
	print("LOOT_PICKUP_GROUND_UNIT_PASS: 32 directions use one 0.75 GU radius")
	get_tree().quit(0)
