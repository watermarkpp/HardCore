extends Node


const LOADOUT_PATH := "res://assets/data/equipment_test_loadouts.json"
const ACTIONS := ["idle", "walk", "attack", "cast", "hit", "death"]
const PROFESSIONS := ["战士", "法师", "道士"]
const RESOLVED_WEAPON_PROFESSIONS := {
	"罗刹": "战士",
	"嗜魂法杖": "法师",
	"鹤嘴锄": "战士",
}
const UNRESOLVED_WEAPONS := ["落魄神兵"]


func _ready() -> void:
	_run.call_deferred()


func _loadouts() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOADOUT_PATH))
	assert(parsed is Dictionary, "九人物装备配置不是有效 JSON")
	return parsed.get("loadouts", [])


func _equipment_from_profile(profile: Dictionary) -> Dictionary:
	var result := {
		"武器": {}, "衣服": {}, "头盔": {}, "项链": {},
		"左手镯": {}, "右手镯": {}, "左戒指": {}, "右戒指": {},
	}
	for slot: String in profile.get("equipment", {}):
		var source: Variant = profile.get("equipment", {})[slot]
		if source is Dictionary:
			result[slot] = {"name": str(source.get("itemName", ""))}
	return result


func _spawn_visual(profession: String, equipment: Dictionary, gender := "男") -> Array:
	PlayerState.profession = profession
	PlayerState.gender = gender
	PlayerState.equipment = equipment
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	return [player, player.visual]


func _assert_formal_visual(visual: Node, profession: String) -> void:
	assert(visual.uses_final_art(), "%s 必须启用正式人物图集" % profession)
	assert(visual.visible, "%s 正式人物层不得隐藏" % profession)
	assert(visual._base_action_textures.size() == ACTIONS.size(), "%s 基础人物必须有六动作" % profession)
	for action: String in ACTIONS:
		assert(visual._base_action_textures.has(action), "%s 缺少基础动作 %s" % [profession, action])
		assert(int(visual._body_action_frame_counts.get(action, 0)) > 0, "%s/%s 帧数无效" % [profession, action])
	visual.current_state = "action"
	visual._action_name = "cast"
	assert(visual._visual_action_key() == "cast", "%s 施法不得退回 idle" % profession)
	assert(visual._frame_count_for_action("cast") == 6, "%s 施法必须是六帧" % profession)
	assert(not visual.weapon_accent.visible, "不得恢复几何武器占位")
	assert(not visual.armor_accent.visible, "不得恢复几何衣服占位")
	assert(not visual.helmet_accent.visible, "不得恢复几何头盔占位")
	for layer_name: String in ["BodySprite", "ClientWeaponLayer", "ClientHelmetLayer"]:
		var layer := visual.get_node(layer_name) as CanvasItem
		assert(layer != null and layer.z_index == 0, "%s 必须留在人物遮挡 Z=0 平面" % layer_name)


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)

	for profession: String in PROFESSIONS:
		for gender: String in ["男", "女"]:
			var spawned := await _spawn_visual(profession, _equipment_from_profile({}), gender)
			var player: PlayerCharacter = spawned[0]
			var visual: Node = spawned[1]
			_assert_formal_visual(visual, "%s%s" % [gender, profession])
			assert(visual._dress_action_textures.is_empty(), "%s%s 裸装应使用正式基础人物" % [gender, profession])
			player.queue_free()
			await get_tree().process_frame

	var loadouts := _loadouts()
	assert(loadouts.size() == 9, "验收矩阵必须是三职业×三套装")
	for value: Variant in loadouts:
		assert(value is Dictionary)
		var profile: Dictionary = value
		var profession := str(profile.get("profession", ""))
		var spawned := await _spawn_visual(profession, _equipment_from_profile(profile))
		var player: PlayerCharacter = spawned[0]
		var visual: Node = spawned[1]
		_assert_formal_visual(visual, profession)
		assert(visual._dress_action_textures.size() == ACTIONS.size(), "%s 衣服必须有六动作" % profile.get("loadoutId", ""))
		assert(visual._weapon_action_textures.size() == ACTIONS.size(), "%s 武器必须有六动作" % profile.get("loadoutId", ""))
		player.queue_free()
		await get_tree().process_frame

	var live_wizard_profile: Dictionary = {}
	for value: Variant in loadouts:
		if value is Dictionary and str(value.get("profession", "")) == "法师":
			live_wizard_profile = value
			break
	assert(not live_wizard_profile.is_empty())
	var live_spawned := await _spawn_visual("法师", _equipment_from_profile({}))
	var live_player: PlayerCharacter = live_spawned[0]
	var live_visual: Node = live_spawned[1]
	PlayerState.equipment = _equipment_from_profile(live_wizard_profile)
	PlayerState.equipment_changed.emit()
	await get_tree().process_frame
	assert(live_visual._dress_action_textures.size() == ACTIONS.size(), "存活法师换装后衣服六动作未刷新")
	assert(live_visual._weapon_action_textures.size() == ACTIONS.size(), "存活法师换装后武器六动作未刷新")
	PlayerState.gender = "女"
	live_visual.refresh_profession()
	await get_tree().process_frame
	assert(live_visual.uses_final_art(), "存活角色切换女性资源后必须保持正式人物")
	assert(live_visual._base_action_textures.size() == ACTIONS.size(), "女性法师基础人物六动作未刷新")
	assert(live_visual._dress_action_textures.size() == ACTIONS.size(), "女性法师衣服六动作未刷新")
	assert(live_visual._weapon_action_textures.size() == ACTIONS.size(), "女性法师武器六动作未刷新")
	live_player.queue_free()
	await get_tree().process_frame

	for resolved_name: String in RESOLVED_WEAPON_PROFESSIONS:
		var item := GameData.get_item(resolved_name)
		assert(not item.is_empty(), "缺少正式装备：%s" % resolved_name)
		var resolved := GameData.item_world_appearance(int(item.get("itemId", -1)), "男")
		assert(resolved.get("status", "") == "exact_client_animation", "%s 必须使用正式世界动画" % resolved_name)
		var appearance: Variant = resolved.get("appearance", {})
		assert(appearance is Dictionary and bool(appearance.get("visible", false)), "%s 必须保持世界外观可见" % resolved_name)
		var actions: Variant = appearance.get("actions", {})
		assert(actions is Dictionary and actions.size() == ACTIONS.size(), "%s 必须提供六动作世界外观" % resolved_name)
		for action: String in ACTIONS:
			assert(actions.has(action), "%s 缺少正式动作 %s" % [resolved_name, action])
		var equipment := _equipment_from_profile({})
		equipment["武器"] = {"name": resolved_name}
		var spawned := await _spawn_visual(str(RESOLVED_WEAPON_PROFESSIONS[resolved_name]), equipment)
		var player: PlayerCharacter = spawned[0]
		var visual: Node = spawned[1]
		assert(visual.uses_final_art(), "%s 必须保留正式人物底层" % resolved_name)
		assert(visual._weapon_action_textures.size() == ACTIONS.size(), "%s 必须加载六动作武器层" % resolved_name)
		player.queue_free()
		await get_tree().process_frame

	for unresolved_name: String in UNRESOLVED_WEAPONS:
		var item := GameData.get_item(unresolved_name)
		assert(not item.is_empty(), "缺少正式装备：%s" % unresolved_name)
		var resolved := GameData.item_world_appearance(int(item.get("itemId", -1)), "男")
		assert(resolved.get("status", "") == "unresolved_no_placeholder", "%s 必须明确记录缺源策略" % unresolved_name)
		var equipment := _equipment_from_profile({})
		equipment["武器"] = {"name": unresolved_name}
		var spawned := await _spawn_visual("战士", equipment)
		var player: PlayerCharacter = spawned[0]
		var visual: Node = spawned[1]
		assert(visual.uses_final_art(), "%s 缺武器层时仍必须保留正式人物底层" % unresolved_name)
		assert(visual._weapon_action_textures.is_empty(), "%s 不得制造武器占位" % unresolved_name)
		player.queue_free()
		await get_tree().process_frame

	var reload_profile: Dictionary = loadouts[4]
	var reload_spawned := await _spawn_visual(str(reload_profile.get("profession", "")), _equipment_from_profile(reload_profile))
	var reload_player: PlayerCharacter = reload_spawned[0]
	var reload_visual: Node = reload_spawned[1]
	assert(GameData.load_database(), "装备视觉目录重载失败")
	await get_tree().process_frame
	assert(reload_visual.uses_final_art(), "数据库重载后正式人物视觉必须自动刷新")
	assert(reload_visual._dress_action_textures.size() == ACTIONS.size())
	assert(reload_visual._weapon_action_textures.size() == ACTIONS.size())
	reload_player.queue_free()

	print("PLAYER_THREE_PROFESSION_VISUAL_CATALOG_PASS：三职业基础人物、九套装备、施法与缺源策略通过")
	get_tree().quit(0)
