extends Node

const MapTeleportRuntimePolicyScript := preload(
	"res://scripts/layers/runtime/map_teleport_runtime_policy.gd"
)

const DIRECT_CITY_NODE_TO_MAP_ID := {
	"world_bich_province": 910001,
	"world_mengzhong_province": 910003,
	"world_fengmo_valley": 910005,
	"world_white_day_gate": 910006,
	"world_cangyue_island": 910007,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(GameData.ensure_loaded(), GameData.load_error)
	_test_policy_contract()
	await _test_left_selection_is_sole_authority()
	await _test_game_root_loading_travel()
	print("MAP_TELEPORT_SYSTEM_PASS direct_cities=5 left_selection_authority=true")
	get_tree().quit(0)


func _test_policy_contract() -> void:
	for map_id: int in DIRECT_CITY_NODE_TO_MAP_ID.values():
		var rule := MapTeleportRuntimePolicyScript.rule_for_map(map_id)
		assert(bool(rule.get("enabled", false)), "开放主城没有激活：%d" % map_id)
		assert(int(rule.get("destination_map_id", -1)) == map_id)
		assert(not bool(rule.get("requires_map_scroll", true)))
		var request := {
			"contract_id": "ui.map.teleport.v1",
			"selected_map_id": map_id,
			"destination_map_id": map_id,
			"arrival_anchor_id": rule.get("arrival_anchor_id", ""),
			"rule_id": rule.get("rule_id", ""),
		}
		assert(MapTeleportRuntimePolicyScript.request_matches_rule(request, rule))
		var arrival := MapTeleportRuntimePolicyScript.resolve_arrival(
			map_id,
			str(rule.get("arrival_anchor_id", "")),
		)
		assert(bool(arrival.get("valid", false)), "主城没有可解析落点：%d" % map_id)
		assert(
			str(arrival.get("source", "")) == "respawn_point",
			"主城传送不得回退到安全区或地图中心：%d" % map_id,
		)
		assert((arrival.get("position_px", Vector2.ZERO) as Vector2).is_finite())

	for locked_map_id: int in [910002, 910004, 911001]:
		var rule := MapTeleportRuntimePolicyScript.rule_for_map(locked_map_id)
		assert(not bool(rule.get("enabled", true)))
		assert(bool(rule.get("requires_map_scroll", false)))
		assert(int(rule.get("required_item_id", 0)) == -1)
	assert(
		MapTeleportRuntimePolicyScript.scroll_requirement_for_map(911001).is_empty(),
		"未配置的地图卷轴接口必须 fail-closed",
	)


func _test_left_selection_is_sole_authority() -> void:
	var panel := MapPanel.new()
	panel.teleport_availability_requested.connect(
		func(map_ids: Array) -> void:
			panel.set_teleport_availability(
				MapTeleportRuntimePolicyScript.rules_for_maps(map_ids)
			)
	)
	add_child(panel)
	await get_tree().process_frame
	for node_id: String in DIRECT_CITY_NODE_TO_MAP_ID:
		var city_map_id := int(DIRECT_CITY_NODE_TO_MAP_ID[node_id])
		panel._select_world_node(node_id)
		assert(
			panel._selected_map_id == city_map_id,
			"中间主城切换后左侧默认首项不是主城：%s" % node_id,
		)
		assert(not panel.teleport_button.disabled, "默认主城没有立即激活传送")
		var other_index := -1
		for index in range(panel.map_entries.size()):
			if int(panel.map_entries[index].get("mapId", -1)) != city_map_id:
				other_index = index
				break
		assert(other_index >= 0, "主城分类没有可验证的其他左侧地图：%s" % node_id)
		panel._select_map(other_index)
		assert(panel.teleport_button.disabled, "左侧改选其他地图后传送没有锁定")
	panel.queue_free()
	await get_tree().process_frame


func _test_game_root_loading_travel() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await _await_map_transition(game)
	game.hud._toggle_map_panel()
	var panel: MapPanel = game.hud.map_panel
	panel._select_world_node("world_mengzhong_province")
	assert(panel._selected_map_id == 910003)
	assert(not panel.teleport_button.disabled)
	var expected_arrival := MapTeleportRuntimePolicyScript.resolve_arrival(
		910003,
		MapTeleportRuntimePolicyScript.DEFAULT_CITY_ARRIVAL_ANCHOR_ID,
	)
	panel._teleport_selected()
	await _await_map_transition(game)
	assert(game.current_map_id == 910003, "结构化传送没有进入盟重")
	assert(
		game.player.global_position.is_equal_approx(
			expected_arrival.get("position_px", Vector2.ZERO) as Vector2
		),
		"结构化传送没有落到主城复活点",
	)
	assert(not game.hud.loading_transition_overlay.visible, "完成后 loading 没有关闭")
	game.player.global_position += Vector2(96.0, 64.0)
	game.hud._toggle_map_panel()
	panel._select_world_node("world_mengzhong_province")
	assert(not panel.teleport_button.disabled, "当前所在主城也必须允许回到复活点")
	panel._teleport_selected()
	await _await_map_transition(game)
	assert(
		game.player.global_position.is_equal_approx(
			expected_arrival.get("position_px", Vector2.ZERO) as Vector2
		),
		"同地图传送没有回到正式复活点",
	)
	game.queue_free()
	await get_tree().process_frame


func _await_map_transition(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while (
		bool(game.get("_world_bootstrap_in_progress"))
		or bool(game.get("_map_transition_in_progress"))
	) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(not bool(game.get("_world_bootstrap_in_progress")))
	assert(not bool(game.get("_map_transition_in_progress")))
