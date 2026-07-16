extends Node

func _ready()->void:
	var runtime:=MapEditorRuntimeBridge.load_bich()
	assert(not runtime.is_empty())
	assert(runtime.design.design_size==[64.0,64.0] or runtime.design.design_size==[64,64])
	assert(runtime.instances.size()==28)
	assert(runtime.semantics.monster_spawn.size()==33)
	assert(runtime.semantics.npc_points.size()==5)
	assert(runtime.semantics.door_points.size()==4)
	assert(int(runtime.collision.blocked_count)==398)
	var content:=MapEditorRuntimeBridge.game_content()
	assert(content.spawns.size()==33)
	assert(content.npcs.size()==5)
	assert(content.portals.is_empty())
	print("BICH_USER_RUNTIME_IMPORT_PASS")
	get_tree().quit()
