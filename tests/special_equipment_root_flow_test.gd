extends Node

## Single-root integration fixture for the equipment-granted skill boundary.
## This intentionally uses the production GameRoot release and physical-hit
## paths; it does not replace them with mocks or invoke a second executor.
const Icons := preload("res://scripts/hud_skill_icon_catalog.gd")
const WorldSkillFixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")

const TELEPORT_ID := "hc.skill.equipment.ring_teleport"
const HEALING_ID := "hc.skill.equipment.ring_healing"
const FIREBALL_ID := "hc.skill.equipment.ring_fireball"

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await WorldSkillFixture.wait_for_formal_world(self, _game, "special_equipment_root_flow")
	_game.set_process(false)
	_game.set_physics_process(false)

	_assert_hud_special_feature_removed()
	_assert_ring_release_effects()
	_assert_stealth_recovery_edge()
	await _assert_physical_paralysis_classification()
	_game.queue_free()
	await get_tree().process_frame
	print("SPECIAL_EQUIPMENT_ROOT_FLOW_PASS grants=3 effects=teleport/heal/fireball stealth_recovery=1 paralysis=ordinary5/elite2.5/boss2.5")
	get_tree().quit(0)


func _reset_and_wear(item_name: String) -> Dictionary:
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	PlayerState.add_item(item_name)
	var index: int = -1
	for candidate in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[candidate].get("name", "")) == item_name:
			index = candidate
	assert(index >= 0, "missing fixture item: %s" % item_name)
	assert(PlayerState.equip_inventory_index(index).begins_with("已装备"), "wear failed: %s" % item_name)
	return PlayerState.equipment["hc.slot.ring_left"]


func _assert_ring_release_effects() -> void:
	_reset_and_wear("传送戒指")
	assert(PlayerState.is_skill_available(TELEPORT_ID))
	# Reuse the formal outdoor fixture's known legal caster cell so teleport
	# tests the production collision path instead of a Home-wall rejection.
	var legal_ground := Vector2(38.5, 13.5)
	var legal_position: Vector2 = _game._canonical_ground_gu_to_screen_px(legal_ground)
	_game._set_player_world_position(legal_position)
	_game.player.facing = Vector2.DOWN
	var teleport_before: Vector2 = _game.player.global_position
	var teleport_mp_before: int = int(_game.player.current_mp)
	assert(_game._try_release_skill(TELEPORT_ID, false) == &"released")
	assert(_game.player.global_position != teleport_before, "teleport grant did not move player")
	assert(_game.player.current_mp == teleport_mp_before, "teleport grant must cost 0 MP")
	assert(Icons.texture_for(TELEPORT_ID) != null, "teleport grant icon missing")
	assert(PlayerState.unequip_slot("hc.slot.ring_left").begins_with("已卸下"))
	assert(_game._try_release_skill(TELEPORT_ID, false) == &"rejected", "unworn teleport remained usable")

	_reset_and_wear("防御戒指")
	_game.player.current_mp = 100
	_game.player.current_hp = maxi(1, _game.player.max_hp - 20)
	var healing_before: int = int(_game.player.current_hp)
	var healing_mp_before: int = int(_game.player.current_mp)
	assert(_game._try_release_skill(HEALING_ID, false) == &"released")
	assert(_game.player.current_hp > healing_before, "healing grant did not restore HP")
	assert(_game.player.current_mp == healing_mp_before - 5, "healing grant MP mismatch")

	_reset_and_wear("火焰戒指")
	_game.player.current_mp = 100
	var fireball_mp_before: int = int(_game.player.current_mp)
	assert(_game._try_release_skill(FIREBALL_ID, false) == &"released")
	assert(_game.player.current_mp == fireball_mp_before - 5, "fireball grant MP mismatch")
	var projectile: SkillProjectile = null
	for child: Node in _game.get_children():
		if child is SkillProjectile and (child as SkillProjectile).resolution_skill_id == "wizard.fireball":
			projectile = child as SkillProjectile
			break
	assert(projectile != null, "fireball grant did not create the canonical projectile")
	assert(projectile.get_parent() == _game and projectile.source_actor == _game.player)


func _assert_hud_special_feature_removed() -> void:
	var hud: Node = _game.hud
	assert(is_instance_valid(hud), "formal GameRoot HUD was not initialized")
	assert(hud.get_node_or_null("SpecialActionButton") == null)
	assert(not hud.has_signal("special_action_pressed"))


func _assert_stealth_recovery_edge() -> void:
	_reset_and_wear("隐身戒指")
	assert(_game.player.is_stealthed(), "stealth ring did not activate")
	_game.player.break_stealth()
	assert(not _game.player.is_stealthed())
	var enemy: EnemyActor = null
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if (
			candidate is EnemyActor
			and not (candidate as EnemyActor)._dying
			and not (candidate as EnemyActor)._death_pending
			and (candidate as EnemyActor).current_hp > 0
		):
			(candidate as EnemyActor).target = null
			if enemy == null: enemy = candidate as EnemyActor
	assert(enemy != null, "formal world has no enemy for stealth target edge")
	enemy.target = _game.player
	_game._recover_equipment_stealth_if_out_of_combat()
	assert(not _game.player.is_stealthed(), "stealth recovered while enemy target remained")
	enemy.target = null
	_game._recover_equipment_stealth_if_out_of_combat()
	assert(_game.player.is_stealthed(), "stealth did not recover after combat target cleared/death")


func _assert_physical_paralysis_classification() -> void:
	_reset_and_wear("麻痹戒指")
	var classifications: Dictionary = {"ordinary": 5.0, "elite": 2.5, "boss": 2.5}
	var descriptors: Array[Dictionary] = []
	for classification: String in classifications:
		var catalog := _catalog_for_classification(classification)
		assert(not catalog.is_empty(), "missing canonical catalog class: %s" % classification)
		descriptors.append({
			"id": int(catalog.get("monsterId", catalog.get("monster_id", -1))),
			"position": _game.player.global_position + Vector2(80.0 + descriptors.size() * 40.0, 0.0),
			"respawn": -1.0,
			"context": {
				"respawn_enabled": false,
				"spawn_slot_id": "test:special_equipment:%s" % classification,
			},
		})
	var published: Array[EnemyActor] = await WorldSkillFixture.publish_targets(
		self,
		_game,
		descriptors,
		"special equipment paralysis classification",
	)
	assert(published.size() == classifications.size())
	_game._rng.seed = 0x5EED
	var class_index := 0
	for classification: String in classifications:
		var enemy: EnemyActor = published[class_index]
		class_index += 1
		_assert_published_paralysis_target(enemy, classification)
		var succeeded: bool = false
		for attempt in range(32):
			enemy.control_time = 0.0
			var hp_before: int = int(enemy.current_hp)
			if _game._apply_physical_hit(enemy, 10):
				assert(enemy.current_hp < hp_before, "physical hit did not commit HP damage")
				if enemy.control_time >= float(classifications[classification]) - 0.01:
					succeeded = true
					break
		assert(succeeded, "paralysis classification did not apply: %s" % classification)


func _catalog_for_classification(classification: String) -> Dictionary:
	for raw: Variant in GameData.monsters:
		if not raw is Dictionary: continue
		var data: Dictionary = GameData.get_monster_by_id(int(raw.get("monsterId", raw.get("monster_id", -1))))
		if str(data.get("classification", "")) != classification: continue
		if int(data.get("combat", {}).get("stats", {}).get("hp", 0)) < 400: continue
		return data
	return {}


func _assert_published_paralysis_target(enemy: EnemyActor, classification: String) -> void:
	assert(enemy != null and is_instance_valid(enemy))
	assert(str(enemy.monster_data.get("classification", "")) == classification)
	assert(enemy.current_hp > 0 and enemy.max_hp >= enemy.current_hp)
	assert(not enemy._dying and not enemy._death_pending)
