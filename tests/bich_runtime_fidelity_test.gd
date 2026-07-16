extends Node

func _ready()->void:
	PlayerState.test_mode=true
	var game:Node=load("res://scenes/main.tscn").instantiate();add_child(game)
	await get_tree().process_frame;await get_tree().process_frame;await get_tree().process_frame
	var runtime:=MapEditorRuntimeBridge.load_bich();assert(not runtime.is_empty())
	assert(game.background._editor_runtime_visual.get("design_size",[])==[64.0,64.0] or game.background._editor_runtime_visual.get("design_size",[])==[64,64])
	var environment_sprites:=0
	for node:Node in game.background._environment_nodes:
		if node is Sprite2D:environment_sprites+=1
	assert(environment_sprites==8+runtime.instances.size())
	var expected_npcs:={}
	for entry:Dictionary in runtime.semantics.npc_points:expected_npcs[str(entry.display_name)]=MapEditorRuntimeBridge.tile_to_world(runtime,entry.tile)
	var actual_npcs:=0
	for node:Node in get_tree().get_nodes_in_group("interactable"):
		if node is NPCActor:
			actual_npcs+=1;assert(expected_npcs.has(node.npc_name));assert(node.global_position.is_equal_approx(expected_npcs[node.npc_name]))
	assert(actual_npcs==5)
	var expected_monsters:=[]
	for entry:Dictionary in runtime.semantics.monster_spawn:expected_monsters.append(int(str(entry.monster_id).trim_prefix("monster.")))
	var actual_monsters:=[]
	for node:Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:actual_monsters.append(int(node.monster_data.get("monsterId",-1)))
	expected_monsters.sort();actual_monsters.sort();assert(actual_monsters==expected_monsters)
	for node:Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			assert(node.visual.uses_final_art(), "比奇怪物仍在使用占位外观：%s" % node.display_name)
			node.visual.play_attack(0.62);node.visual._process(0.05)
			assert(node.visual.current_state=="attack", "怪物攻击动作未进入播放状态：%s" % node.display_name)
	assert(MapEditorRuntimeBridge.home_position().is_equal_approx(MapEditorRuntimeBridge.tile_to_world(runtime,[25,29])))
	var sample:EnemyActor=get_tree().get_nodes_in_group("enemies")[0];sample.facing=Vector2.RIGHT;sample.visual._process(0.01)
	var expected_row:=ArtSpec.mir2_client_direction_row(Vector2.RIGHT) if str(sample.visual.active_resources.get("direction_mode",""))=="mir2_north_first" else ArtSpec.direction_index(Vector2.RIGHT)
	assert(sample.visual.current_direction==expected_row)
	sample.visual.play_attack(0.62);sample.visual._process(0.05);assert(sample.visual.current_state=="attack" or sample.visual.is_fallback_attacking())
	print("BICH_RUNTIME_FIDELITY_PASS")
	get_tree().quit()
