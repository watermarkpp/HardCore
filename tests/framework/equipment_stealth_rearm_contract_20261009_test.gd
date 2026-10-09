extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const WorldSkillFixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")

var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)
		push_error("B02 stealth contract: " + label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.level = 40
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	await WorldSkillFixture.wait_for_formal_world(self, game, "equipment_stealth_rearm_contract")
	game.set_process(false)
	game.set_physics_process(false)
	PlayerState.add_item("隐身戒指")
	var inventory_index := -1
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == "隐身戒指":
			inventory_index = index
			break
	check(inventory_index >= 0, "formal stealth ring item exists")
	check(inventory_index >= 0 and PlayerState.equip_inventory_index(inventory_index).begins_with("已装备"), "formal stealth ring equips")
	check(game.player.is_stealthed(), "peaceful equipped ring activates stealth")
	var enemy: EnemyActor = null
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if candidate is EnemyActor and not (candidate as EnemyActor)._dying and (candidate as EnemyActor).current_hp > 0:
			enemy = candidate as EnemyActor
			break
	check(enemy != null, "formal live enemy exists")
	if enemy == null:
		game.queue_free()
		await get_tree().process_frame
		_finish()
		return
	game.player.break_stealth()
	check(not game.player.is_stealthed(), "accepted combat submission breaks stealth")
	enemy.target = game.player
	check(PlayerState.unequip_slot("hc.slot.ring_left").begins_with("已卸下"), "live combat ring removal succeeds")
	PlayerState.add_item("隐身戒指")
	inventory_index = -1
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == "隐身戒指":
			inventory_index = index
			break
	check(inventory_index >= 0 and PlayerState.equip_inventory_index(inventory_index).begins_with("已装备"), "live combat ring re-equips")
	check(not game.player.is_stealthed(), "equipment refresh does not re-arm stealth during live combat")
	game._recover_equipment_stealth_if_out_of_combat()
	check(not game.player.is_stealthed(), "GameRoot combat gate blocks recovery while enemy targets player")
	enemy.target = null
	game._recover_equipment_stealth_if_out_of_combat()
	check(game.player.is_stealthed(), "GameRoot recovery re-arms stealth after target leaves")
	game.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	var receipt_ok := proof.write_receipt("equipment_stealth_rearm_contract_20261009_test", proof.records.size(), failures.size())
	print("EQUIPMENT_STEALTH_REARM_CONTRACT_%s" % ("PASS" if failures.is_empty() and receipt_ok else "FAIL"))
	get_tree().quit(0 if failures.is_empty() and receipt_ok else 1)
