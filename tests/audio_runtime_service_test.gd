extends Node

const AudioServiceScript := preload("res://scripts/audio_runtime_service.gd")
const TownMusicScript := preload("res://scripts/town_music_controller.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var service = AudioServiceScript.new()
	add_child(service)
	await get_tree().process_frame
	var prewarm := service.prewarm_runtime_streams()
	assert(int(prewarm.get("npc_loaded", 0)) == 14, "NPC 14个WAV未在初始化阶段全部预热")
	assert(int(prewarm.get("event_loaded", 0)) == 525, "精确事件样本未在初始化阶段全部预热")
	assert(int(prewarm.get("missing", 0)) == 0, "运行时音频存在缺失路径")
	assert(int(prewarm.get("failed", 0)) == 0, "运行时音频预热存在解码失败")
	assert(service.npc_voice_player != null, "NPC音频缺少唯一播放器")
	assert(service.npc_voice_player.bus == &"SFX", "NPC音频未路由到SFX总线")
	assert(AudioServer.get_bus_index(&"Music") < 0 or AudioServer.get_bus_index(&"Music") != AudioServer.get_bus_index(&"SFX"), "NPC与BGM不应共用同一总线")
	var snapshot: Dictionary = service.state_snapshot()
	assert(int(snapshot.get("event_count", 0)) == 522, "精确事件映射数量漂移")
	assert(int(snapshot.get("item_route_identity_count", 0)) == 727, "物品稳定身份路由数量漂移")
	assert(int(snapshot.get("event_pool_size", 0)) == 24, "事件服务必须使用固定并发池而非每事件一个播放器")
	var female_slaying: Dictionary = service.play_event("player.skill.slaying", {"gender": "女"})
	assert(female_slaying.get("status", "") == "played", "女战士攻杀剑术未播放")
	assert(int(female_slaying.get("variant_index", -1)) == 1, "女战士攻杀未选择精确131声部")
	assert(str(female_slaying.get("runtime_path", "")).begins_with("res://assets/audio/sfx/client/131__"), "女战士攻杀映射错位")
	var female_hurt: Dictionary = service.play_event("player.hurt.voice", {"gender": "女"})
	assert(str(female_hurt.get("runtime_path", "")).ends_with("139__139.wav"), "女性受击未映射sound 139")
	var male_death: Dictionary = service.play_event("player.death.voice", {"gender": "男"})
	assert(str(male_death.get("runtime_path", "")).ends_with("144__144.wav"), "男性死亡未映射sound 144")
	var shape_six_contact: Dictionary = service.play_player_physical_contact(6, {"source": "test"})
	assert(int(shape_six_contact.get("played_layer_count", 0)) == 2, "shape 6命中必须播放双层接触声")
	var shape_six_paths: Array[String] = []
	for layer: Dictionary in shape_six_contact.get("layers", []):
		shape_six_paths.append(str(layer.get("runtime_path", "")))
	assert(
		shape_six_paths.any(func(path: String) -> bool: return path.ends_with("64__64.wav"))
		and shape_six_paths.any(func(path: String) -> bool: return path.ends_with("70__70.wav")),
		"shape 6必须保持源二次div的64层并叠加body sword 70",
	)
	var fist_contact: Dictionary = service.play_player_physical_contact(0, {"source": "test"})
	assert(int(fist_contact.get("played_layer_count", 0)) == 1, "徒手命中源规则只有body fist一层")
	assert(
		str((fist_contact.get("layers", [])[0] as Dictionary).get("runtime_path", "")).ends_with("73__73.wav"),
		"徒手命中未映射sound 73",
	)
	var monster_attack: Dictionary = service.play_monster_event(21, "attack_start", {"source": "test"})
	assert(monster_attack.get("status", "") == "played", "怪物21攻击动作起点精确映射未播放")
	var display_monster_rejected: Dictionary = service.play_event("monster.鸡.attack_start")
	assert(display_monster_rejected.get("status", "") == "missing_mapping", "怪物显示名不应绕过精确monster_id")
	service.stop_all_events("w4_contract")
	service.set_clock_for_test(0)
	service.reset_metrics_for_test(true)
	var combat_prompt := service.play_monster_combat_prompt(
		21,
		"test-owner",
		{"source": "test", "session_id": "combat:1"},
	)
	assert(combat_prompt.get("status", "") == "played", "真正进入战斗时必须播放一次怪物提示")
	assert(combat_prompt.get("semantic_event", "") == "combat_prompt", "怪物提示必须标记为combat_prompt")
	assert(combat_prompt.get("source_semantic_event", "") == "ambient", "无专属提示样本时只能复用同ID ambient样本")
	var duplicate_prompt := service.play_monster_combat_prompt(
		21,
		"test-owner",
		{"source": "target_refresh", "session_id": "combat:target_refresh"},
	)
	assert(duplicate_prompt.get("status", "") == "combat_session_duplicate", "目标刷新不得重复打开战斗提示会话")
	var transient_los := service.notify_monster_los_interrupted("test-owner")
	assert(transient_los.get("reason", "") == "transient_los", "短暂LOS中断不得结束音频会话")
	var duplicate_after_los := service.play_monster_combat_prompt(21, "test-owner", {"session_id": "combat:los_refresh"})
	assert(duplicate_after_los.get("status", "") == "combat_session_duplicate", "短暂LOS中断后不得重播战斗提示")
	var ended := service.end_monster_combat_session("test-owner", "explicit_disengage")
	assert(ended.get("status", "") == "ended", "真正脱离战斗必须关闭音频会话")
	var rearm_pending := service.play_monster_combat_prompt(21, "test-owner", {"session_id": "combat:2"})
	assert(rearm_pending.get("status", "") == "combat_session_rearm_pending", "真实脱战后必须经过短暂重入防抖")
	service.set_clock_for_test(751)
	var reentered := service.play_monster_combat_prompt(21, "test-owner", {"session_id": "combat:2"})
	assert(reentered.get("status", "") == "played", "真实脱战后允许重新进入战斗并播放提示")
	service.stop_all_events("w4_contract")
	var direct_ambient := service.play_monster_event(21, "ambient", {"source": "walk_frame"})
	assert(direct_ambient.get("status", "") == "monster_event_not_allowed", "追击/转向环境声不得进入生产事件白名单")
	var direct_hurt := service.play_monster_event(21, "hurt", {"source": "damage"})
	assert(direct_hurt.get("status", "") == "monster_event_not_allowed", "怪物受击声不得进入生产事件白名单")
	var direct_death := service.play_monster_event(21, "death", {"source": "death"})
	assert(direct_death.get("status", "") == "monster_event_not_allowed", "怪物死亡声不得进入生产事件白名单")
	var weapon_equip: Dictionary = service.play_item_event("item:80", "equip_success")
	assert(weapon_equip.get("status", "") == "played", "武器成功装备未走精确类型声")
	assert(str(weapon_equip.get("runtime_path", "")).ends_with("111__111.wav"), "武器装备声未映射到sound 111")
	var potion_use: Dictionary = service.play_item_event("service:658", "use_success")
	assert(potion_use.get("status", "") == "played", "药品成功使用未走精确类型声")
	assert(str(potion_use.get("runtime_path", "")).ends_with("108__108.wav"), "药品使用声未映射到sound 108")
	var scroll_silent: Dictionary = service.play_item_event("service:717", "use_success")
	assert(scroll_silent.get("status", "") == "silent_or_unmapped_item_event", "主源无成功声的卷轴不应借用药品声")
	var gold_loot: Dictionary = service.play_item_event("currency:gold", "loot_success")
	assert(gold_loot.get("status", "") == "played", "金币入账成功未走精确声")
	assert(str(gold_loot.get("runtime_path", "")).ends_with("106__106.wav"), "金币声未映射到sound 106")
	var display_item_rejected: Dictionary = service.play_item_event("乌木剑", "equip_success")
	assert(display_item_rejected.get("status", "") == "missing_item_route", "物品显示名不应绕过稳定item_id")
	var ambient_compatibility_call: Dictionary = service.play_monster_ambient_if_due(21, 1, "test-owner")
	assert(ambient_compatibility_call.get("reason", "") == "ambient_disabled", "旧环境声入口必须保持静音兼容而不再抽样播放")
	service.stop_all_events("w4_contract")
	var dedup_first := service.play_monster_event(
		21,
		"attack_start",
		{"audio_owner_key": "attack-owner", "release_id": "attack:1"},
	)
	assert(dedup_first.get("status", "") == "played", "已确认攻击动作必须播放攻击起点")
	var dedup_second := service.play_monster_event(
		21,
		"attack_start",
		{"audio_owner_key": "attack-owner", "release_id": "attack:1"},
	)
	assert(dedup_second.get("status", "") == "duplicate_owner_release", "同一owner/release不能重复占用声部")
	service.set_clock_for_test(2000)
	assert(service.set_user_sfx_gain_linear(1.0), "用户SFX增益设置失败")
	var expected_sfx_db := linear_to_db(0.5)
	assert(absf(service.npc_voice_player.volume_db - expected_sfx_db) < 0.001, "SFX必须应用线性0.5工程缩放")
	service.set_user_sfx_gain_linear(1.0)
	assert(absf(service.npc_voice_player.volume_db - expected_sfx_db) < 0.001, "重复设置SFX增益不得再次折半")
	service.set_sfx_enabled(false)
	var disabled_result := service.play_event("player.skill.slaying", {"source": "sfx_off"})
	assert(disabled_result.get("status", "") == "sfx_disabled", "SFX开关关闭时必须在取资源前拒绝")
	service.set_sfx_enabled(true)

	service.set_rng_seed("npc.service.warehouse.v1", 1001)
	var warehouse := service.play_npc_interaction_success("npc.service.warehouse.v1", {"source": "test"})
	assert(warehouse.get("status", "") == "played", "仓库成功交互未播放")
	assert(str(warehouse.get("runtime_path", "")).begins_with("res://assets/audio/npc/warehouse/"), "仓库音频跨目录映射")
	var veteran := service.play_npc_interaction_success("npc.service.veteran.v1")
	assert(veteran.get("status", "") == "played", "老兵成功交互未播放")
	assert(service.active_npc_id() == "npc.service.veteran.v1", "快速切换NPC后旧声部未被替换")
	assert(service.npc_voice_player.stream != null, "切换NPC后唯一播放器没有新流")
	service._stream_cache.clear()
	var unavailable := service.play_npc_interaction_success("npc.service.veteran.v1")
	assert(unavailable.get("status", "") == "load_failed", "未预热资源未按失败关闭")
	assert(not service.is_npc_voice_active(), "替换资源未就绪时不能继续播放旧NPC声音")

	var display_name_rejected := service.play_npc_interaction_success("仓库管理员")
	assert(display_name_rejected.get("status", "") == "missing_mapping", "显示名不应绕过精确NPC ID")
	var town := TownMusicScript.new()
	add_child(town)
	await get_tree().process_frame
	assert(town.music_player.bus == &"Music", "主城BGM未路由到Music总线")
	assert(town.music_player.bus != service.npc_voice_player.bus, "NPC声部与BGM总线冲突")
	var music_volume_before_sfx_change := town.music_player.volume_db
	service.set_user_sfx_gain_linear(0.25)
	assert(absf(town.music_player.volume_db - music_volume_before_sfx_change) < 0.001, "SFX增益调整不得改变BGM音量")
	service.set_user_sfx_gain_linear(1.0)
	service.stop_npc_voice("test_exit")
	service.stop_all_events("test_exit")
	assert(not service.is_npc_voice_active(), "角色退出/会话结束未停止NPC声部")
	print("AUDIO_RUNTIME_SERVICE_PASS：精确映射/固定24声部池、W4怪物白名单/会话/预算前置/owner-release去重、SFX线性0.5幂等、BGM独立、玩家物品路由通过")
	get_tree().quit(0)
