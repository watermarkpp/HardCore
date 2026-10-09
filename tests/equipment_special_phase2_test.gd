extends Node

const FormalWorldSkillFixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Icons := preload("res://scripts/hud_skill_icon_catalog.gd")
const TELEPORT_ID := "hc.skill.equipment.ring_teleport"
const FIREBALL_ID := "hc.skill.equipment.ring_fireball"
const HEALING_ID := "hc.skill.equipment.ring_healing"

var _game: Node

func _ready() -> void:
	_run.call_deferred()

func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1

func _reset_level_50() -> void:
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.gold = 1000
	PlayerState.recalculate_stats()

func _equip(item_name: String) -> void:
	PlayerState.add_item(item_name)
	var index := _inventory_index(item_name)
	assert(index >= 0, "%s missing from inventory" % item_name)
	assert(PlayerState.equip_inventory_index(index).begins_with("已装备"), "%s cannot be equipped" % item_name)

func _move_to_legal_ground() -> void:
	var ground := Vector2(38.5, 13.5)
	_game._set_player_world_position(_game._canonical_ground_gu_to_screen_px(ground))
	_game.player.facing = Vector2.DOWN

func _run() -> void:
	PlayerState.test_mode = true
	_reset_level_50()
	var base_hp := int(PlayerState.computed_stats.get("max_hp", 0))
	var base_mp := int(PlayerState.computed_stats.get("max_mp", 0))
	for item_name: String in ["魔血项链", "魔血手镯", "魔血戒指"]:
		_equip(item_name)
	var expected_magic_power := mini(125, maxi(0, base_mp - 1))
	assert(PlayerState.has_special_effect("magic_blood"))
	assert(int(PlayerState.computed_stats.get("max_hp", 0)) == base_hp + expected_magic_power)
	assert(int(PlayerState.computed_stats.get("max_mp", 0)) == base_mp - expected_magic_power)
	var magic_necklace: Dictionary = PlayerState.equipment["hc.slot.necklace"]
	PlayerState.damage_equipment_durability("hc.slot.necklace", int(magic_necklace.get("max_durability", 1)))
	assert(int(PlayerState.computed_stats.get("max_hp", 0)) == base_hp + 50)

	_reset_level_50()
	var base_accuracy := int(PlayerState.computed_stats.get("accuracy", 0))
	for item_name: String in ["虹魔项链", "虹魔手镯", "虹魔戒指"]:
		_equip(item_name)
	assert(int(PlayerState.computed_stats.get("life_steal_percent", 0)) == 9)
	assert(int(PlayerState.computed_stats.get("accuracy", 0)) == base_accuracy + 2)

	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await FormalWorldSkillFixture.wait_for_formal_world(self, _game, "equipment_special_phase2")
	_move_to_legal_ground()
	_assert_legacy_special_button_removed()

	var enemy: EnemyActor = _first_live_enemy()
	assert(enemy != null, "formal world has no live enemy")
	_game.player.current_hp = _game.player.max_hp - 30
	var hp_before: int = int(_game.player.current_hp)
	var enemy_hp_before: int = enemy.current_hp
	_game._rng.seed = 0x5EED
	assert(_game._apply_physical_hit(enemy, 100))
	assert(enemy.current_hp < enemy_hp_before, "formal melee hit did not reduce target HP")
	assert(_game.player.current_hp == hp_before + 9, "虹魔近战吸血没有按9%恢复")
	var rainbow_necklace: Dictionary = PlayerState.equipment["hc.slot.necklace"]
	PlayerState.damage_equipment_durability("hc.slot.necklace", int(rainbow_necklace.get("max_durability", 1)))
	assert(int(PlayerState.computed_stats.get("life_steal_percent", 0)) == 5)
	assert(int(PlayerState.computed_stats.get("accuracy", 0)) == base_accuracy)

	_reset_level_50()
	_equip("传送戒指")
	var grants := PlayerState.equipment_granted_skill_ids()
	assert(grants.has(TELEPORT_ID), "teleport grant source missing")
	assert(Icons.texture_for(TELEPORT_ID) != null)
	_move_to_legal_ground()
	var teleport_before: Vector2 = _game.player.global_position
	var teleport_mp_before: int = int(_game.player.current_mp)
	assert(_game._try_release_skill(TELEPORT_ID, false) == &"released")
	assert(_game.player.global_position != teleport_before)
	assert(_game.player.current_mp == teleport_mp_before)
	assert(PlayerState.unequip_slot("hc.slot.ring_left").begins_with("已卸下"))
	assert(not PlayerState.equipment_granted_skill_ids().has(TELEPORT_ID))
	assert(_game._try_release_skill(TELEPORT_ID, false) == &"rejected")

	_reset_level_50()
	_equip("火焰戒指")
	_move_to_legal_ground()
	_game.player.current_mp = 10
	var fireball_children_before := _game.get_child_count()
	assert(_game._try_release_skill(FIREBALL_ID, false) == &"released")
	assert(_game.player.current_mp == 5)
	assert(_game.get_child_count() == fireball_children_before + 1)
	var fireball_projectile: SkillProjectile = null
	for child: Node in _game.get_children():
		if child is SkillProjectile and (child as SkillProjectile).resolution_skill_id == "wizard.fireball":
			fireball_projectile = child as SkillProjectile
			break
	assert(fireball_projectile != null and fireball_projectile.source_actor == _game.player)

	_reset_level_50()
	_equip("防御戒指")
	_game.player.current_hp = _game.player.max_hp - 40
	_game.player.current_mp = 10
	var healing_before: int = int(_game.player.current_hp)
	assert(_game._try_release_skill(HEALING_ID, false) == &"released")
	assert(_game.player.current_hp > healing_before and _game.player.current_mp == 5)
	var recovery_ring: Dictionary = PlayerState.equipment["hc.slot.ring_left"]
	PlayerState.damage_equipment_durability("hc.slot.ring_left", int(recovery_ring.get("max_durability", 1)))
	assert(not PlayerState.equipment_granted_skill_ids().has(HEALING_ID))
	assert(_game._try_release_skill(HEALING_ID, false) == &"rejected")
	assert(not PlayerState.has_special_effect("memory") and not PlayerState.has_special_effect("prayer"))

	_game.queue_free()
	await get_tree().process_frame
	print("EQUIPMENT_SPECIAL_PHASE2_PASS: formal grants, set stats, MP costs, projectile, zero durability")
	get_tree().quit(0)

func _first_live_enemy() -> EnemyActor:
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if candidate is EnemyActor:
			var enemy := candidate as EnemyActor
			if not enemy._dying and not enemy._death_pending and enemy.current_hp > 0:
				return enemy
	return null

func _assert_legacy_special_button_removed() -> void:
	assert(is_instance_valid(_game.hud))
	assert(_game.hud.get_node_or_null("SpecialActionButton") == null)
	assert(not _game.hud.has_signal("special_action_pressed"))
