extends Node

func _ready()->void:
	var runtime:=MapEditorRuntimeBridge.load_bich();assert(not runtime.is_empty())
	assert(runtime.semantics.safe_area.size()==1)
	var safe:Dictionary=runtime.semantics.safe_area[0]
	assert(bool(safe.return_anchor) and bool(safe.death_return_anchor) and bool(safe.logout_return_anchor))
	var expected_home:=MapEditorRuntimeBridge.tile_to_world(runtime,safe.get("return_tile",safe.get("tile",[32,32])))
	assert(MapEditorRuntimeBridge.home_position().is_equal_approx(expected_home))
	var content:=MapEditorRuntimeBridge.game_content()
	assert(content.safe_areas.size()==1 and content.spawns.size()==33 and content.npcs.size()==5)
	var roles:=[]
	for npc:Dictionary in content.npcs:roles.append(str(npc.kind))
	assert(roles.count("shop")==3 and roles.has("trainer") and roles.has("quest"))
	var safe_zone:Dictionary=content.safe_areas[0]
	var safe_center:Vector2=safe_zone.center
	var safe_radius:=float(safe_zone.radius)
	assert(safe_zone.shape=="circle" and safe_zone.polygon.is_empty())
	assert(safe_center.is_equal_approx(expected_home))
	assert(is_equal_approx(float(safe_zone.radius_tiles),9.0) and is_equal_approx(safe_radius,9.0*ArtSpec.TILE_SIZE))
	for spawn:Dictionary in content.spawns:
		assert(not GameData.get_monster(str(spawn.name)).is_empty())
		assert(spawn.position.distance_to(safe_center)>safe_radius)
	var enemy:=EnemyActor.new();enemy.set_meta("safe_zones",content.safe_areas)
	assert(enemy._point_inside_safe_zone(safe_center))
	assert(enemy._point_inside_safe_zone(safe_center+Vector2.RIGHT*(safe_radius-0.1)))
	assert(not enemy._point_inside_safe_zone(safe_center+Vector2.RIGHT*(safe_radius+0.1)))
	enemy.free()
	print("BICH_CONTENT_1_PASS")
	get_tree().quit()
