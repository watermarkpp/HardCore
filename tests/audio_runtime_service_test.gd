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
	assert(int(prewarm.get("event_loaded", 0)) == 510, "精确事件样本未在初始化阶段全部预热")
	assert(int(prewarm.get("missing", 0)) == 0, "运行时音频存在缺失路径")
	assert(int(prewarm.get("failed", 0)) == 0, "运行时音频预热存在解码失败")
	assert(service.npc_voice_player != null, "NPC音频缺少唯一播放器")
	assert(service.npc_voice_player.bus == &"SFX", "NPC音频未路由到SFX总线")
	assert(AudioServer.get_bus_index(&"Music") < 0 or AudioServer.get_bus_index(&"Music") != AudioServer.get_bus_index(&"SFX"), "NPC与BGM不应共用同一总线")
	var snapshot: Dictionary = service.state_snapshot()
	assert(int(snapshot.get("event_count", 0)) == 509, "精确事件映射数量漂移")
	assert(int(snapshot.get("item_route_identity_count", 0)) == 727, "物品稳定身份路由数量漂移")
	assert(int(snapshot.get("event_pool_size", 0)) == 24, "事件服务必须使用固定并发池而非每事件一个播放器")
	var female_slaying: Dictionary = service.play_event("player.skill.slaying", {"gender": "女"})
	assert(female_slaying.get("status", "") == "played", "女战士攻杀剑术未播放")
	assert(int(female_slaying.get("variant_index", -1)) == 1, "女战士攻杀未选择精确131声部")
	assert(str(female_slaying.get("runtime_path", "")).begins_with("res://assets/audio/sfx/client/131__"), "女战士攻杀映射错位")
	var monster_attack: Dictionary = service.play_monster_event(21, "attack_start", {"source": "test"})
	assert(monster_attack.get("status", "") == "played", "怪物21攻击动作起点精确映射未播放")
	var display_monster_rejected: Dictionary = service.play_event("monster.鸡.attack_start")
	assert(display_monster_rejected.get("status", "") == "missing_mapping", "怪物显示名不应绕过精确monster_id")
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
	var wrong_ambient_frame: Dictionary = service.play_monster_ambient_if_due(21, 0, "test-owner")
	assert(wrong_ambient_frame.get("reason", "") == "not_ambient_frame", "怪物环境声只能在client frame 1抽样")
	service.set_event_rng_seed("monster_ambient:21:test-owner", 1001)
	var ambient_played := false
	for _attempt in 64:
		var ambient: Dictionary = service.play_monster_ambient_if_due(21, 1, "test-owner")
		if ambient.get("status", "") == "played":
			ambient_played = true
			break
	assert(ambient_played, "怪物1/8环境声未通过独立音频RNG触发")

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
	service.stop_npc_voice("test_exit")
	service.stop_all_events("test_exit")
	assert(not service.is_npc_voice_active(), "角色退出/会话结束未停止NPC声部")
	print("AUDIO_RUNTIME_SERVICE_PASS：NPC精确ID/14项预热、509精确事件/固定24声部池、727物品稳定身份路由、怪物独立RNG及BGM并播总线契约通过")
	get_tree().quit(0)
