extends Node

func _ready()->void:
	PlayerState.ensure_developer_test_character()
	PlayerState.ensure_zuma_test_character()
	var found:Dictionary={}
	for profile:Dictionary in PlayerState.list_characters():
		if str(profile.id)=="developer_warrior_30":found=profile;break
	assert(not found.is_empty() and int(found.level)==30)
	assert(PlayerState.select_character("developer_warrior_30"))
	assert(PlayerState.level==30 and PlayerState.profession=="战士")
	for slot:String in ["武器", "衣服", "头盔", "项链", "左手镯", "右手镯", "左戒指", "右戒指"]:assert(not PlayerState.equipment[slot].is_empty())
	assert(PlayerState.equipment["圣物"].is_empty() and PlayerState.equipment["徽章"].is_empty())
	assert(PlayerState.learned_skills.size()>=6 and PlayerState.quick_slots==["","刺杀剑术","半月弯刀","烈火剑法"])
	assert(PlayerState.saved_map_id==910001 and PlayerState.saved_position==Vector2.ZERO)
	var zuma_found:Dictionary={}
	for profile:Dictionary in PlayerState.list_characters():
		if str(profile.id)=="developer_zuma_warrior_40":zuma_found=profile;break
	assert(not zuma_found.is_empty() and int(zuma_found.level)==40)
	assert(PlayerState.select_character("developer_zuma_warrior_40"))
	assert(str(PlayerState.equipment["武器"].get("name",""))=="裁决之杖")
	assert(str(PlayerState.equipment["衣服"].get("name",""))=="战神盔甲(男)")
	assert(str(PlayerState.equipment["头盔"].get("name",""))=="黑铁头盔")
	assert(str(PlayerState.equipment["项链"].get("name",""))=="绿色项链")
	assert(str(PlayerState.equipment["左手镯"].get("name",""))=="骑士手镯" and str(PlayerState.equipment["右手镯"].get("name",""))=="骑士手镯")
	assert(str(PlayerState.equipment["左戒指"].get("name",""))=="力量戒指" and str(PlayerState.equipment["右戒指"].get("name",""))=="力量戒指")
	var game:Node=load("res://scenes/main.tscn").instantiate();add_child(game)
	await get_tree().process_frame;await get_tree().process_frame
	var visual:Node2D=game.player.get_node("PlayerVisual");visual._process(0.01)
	assert(visual.get_node("BodySprite").texture.resource_path.ends_with("dress_006_idle.png"),"祖玛测试号战神盔甲未联动人物外观")
	assert(visual.get_node("ClientWeaponLayer").texture.resource_path.ends_with("weapon_048_idle.png"),"祖玛测试号裁决未联动正确的人物外观")
	var weapon_layer:Sprite2D=visual.get_node("ClientWeaponLayer")
	var behind_rows:=[7,0,1]
	for row in range(8):
		assert(visual.weapon_draws_behind(row)==(row in behind_rows),"裁决八方向前后遮挡错误：row=%d"%row)
	var directions:=[Vector2.UP,Vector2(1,-1),Vector2.RIGHT,Vector2(1,1),Vector2.DOWN,Vector2(-1,1),Vector2.LEFT,Vector2(-1,-1)]
	for row in range(8):
		game.player.facing=directions[row];visual._process(0.01)
		assert(visual.current_direction==row,"裁决方向映射错误：row=%d"%row)
		assert(weapon_layer.region_rect.position.y==row*visual._weapon_frame_size.y,"裁决方向图集行错误：row=%d"%row)
		assert(weapon_layer.z_index==0,"裁决装备层不得逃逸Actor/墙体统一Z平面：row=%d"%row)
		assert(visual.get_node("ClientHelmetLayer").region_rect.position.y==row*ArtSpec.WARRIOR_FRAME.y,"头盔方向图集行错误：row=%d"%row)
		assert(visual.get_node("ClientHairLayer").region_rect.position.y==row*ArtSpec.WARRIOR_FRAME.y,"头发方向图集行错误：row=%d"%row)
	assert(not visual.get_node("ClientHelmetLayer").visible,"世界人物不应显示黑铁头盔")
	assert(visual.get_node("ClientHairLayer").visible and visual.get_node("ClientHairLayer").texture==visual._hair_action_textures.get("idle",null),"世界人物未显示原客户端男性头发")
	assert(not visual.get_node("HelmetAccent").visible,"头部右侧半透明几何残留仍可见")
	var preview:=EquipmentCharacterPreview.new();preview.configure_presentation_mode("classic_avatar");preview.size=Vector2(230,286);add_child(preview);await get_tree().process_frame
	assert(preview._direction_row==4,"装备预览不是固定正面")
	assert(preview._base_source_texture!=null and preview._base_source_texture.resource_path.ends_with("base_male_00376_anatomy.png"),"装备预览没有绑定原客户端男性平面底图源")
	assert(preview.paper_layer_source_index("衣服")==62,"装备预览战神盔甲没有使用原客户端 StateItem 62")
	assert(preview.paper_layer_source_index("武器")==55,"装备预览裁决没有使用原客户端 StateItem 55")
	assert(preview.paper_layer_source_index("头盔")==151,"装备预览黑铁头盔没有使用人工冻结的最终头盔校准151")
	assert(preview._helmet_texture!=null and preview._helmet_texture.resource_path.ends_with("item_00151_paper_doll.png"),"装备预览未显示最终黑铁头盔校准层")
	var bar_anchor:Vector2=visual.health_bar_anchor()
	assert(bar_anchor==ArtSpec.PLAYER_HEALTH_BAR_OFFSET and game.player.get_node("HealthBar").position==bar_anchor,"人物血条没有使用独立固定锚点")
	print("DEVELOPER_CHARACTER_PASS")
	get_tree().quit()
