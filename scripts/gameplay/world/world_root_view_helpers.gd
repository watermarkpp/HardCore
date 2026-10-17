extends "res://scripts/gameplay/world/world_root_phase_adapter.gd"

## Original numeric view helpers. Immediate combat remains in the same Core.
const CameraFollow := preload("res://scripts/world_camera_follow.gd")
const OriginalTownMusic := preload("res://scripts/town_music_controller.gd")
const OriginalArt := preload("res://scripts/art_spec.gd")

func _update_town_music_presence() -> void:
	var controller: Variant = _fields.read_source_field(&"_town_music_controller")
	if controller == null or _fields.read_source_field(&"_map_transition_in_progress") or _fields.read_source_field(&"_world_bootstrap_in_progress"): return
	var safe: Dictionary = _fields.read_source_field(&"_player_safe_zone_cache")
	controller.set_town_presence(OriginalTownMusic.is_main_city_map(current_map_id) and bool(safe.get("valid",false)) and int(safe.get("map_id",-1)) == current_map_id and bool(safe.get("inside",false)))

func _update_world_camera_constraint(delta := 1.0 / 60.0) -> void:
	var camera: Variant = _fields.read_source_field(&"_world_camera")
	var player: Object = _world.skills.player
	if camera == null or not _world.skill_actors.is_runtime_present(player): return
	var maps: RefCounted = _world.environment_factory.runtime_maps
	var base_zoom := Vector2.ONE * OriginalArt.CAMERA_ZOOM
	if current_map_id == -1 or not maps.has_runtime_map(current_map_id):
		camera.zoom = base_zoom
		camera.position = Vector2.ZERO
		camera.offset = Vector2.ZERO
		_world_camera_presented_center = Vector2.INF
		return
	var runtime: Dictionary = maps.load_map(current_map_id)
	var raw_size: Array = runtime.get("design",{}).get("design_size",[])
	if raw_size.size() != 2:
		camera.zoom = base_zoom
		camera.position = Vector2.ZERO
		camera.offset = Vector2.ZERO
		_world_camera_presented_center = Vector2.INF
		return
	var viewport: RefCounted = required_owner_service(&"VisualViewport")
	var actual: Dictionary = viewport.root_viewport_snapshot()
	var viewport_half: Vector2 = actual.visible_rect.size * 0.5
	var constraint: RefCounted = required_owner_service(&"CameraConstraint")
	var camera_center: Vector2 = constraint.apply_player_visibility_guard(Vector2i(int(raw_size[0]),int(raw_size[1])),viewport_half,base_zoom,player.global_position,_original_player_display_extent_world_px())
	if _fields.read_source_field(&"_world_camera_follow_map_id") != current_map_id:
		_world_camera_presented_center = Vector2.INF
		_fields.write_source_field(&"_world_camera_follow_map_id",current_map_id)
	_world_camera_presented_center = CameraFollow.advance(_world_camera_presented_center,camera_center,delta)
	if camera.zoom != base_zoom: camera.zoom = base_zoom
	camera.global_position = camera_center
	camera.offset = _world_camera_presented_center - camera_center
	camera.force_update_scroll()

func _original_player_display_extent_world_px() -> Vector3:
	var frame_size := Vector2(OriginalArt.CHARACTER_FRAME)
	var foot_in_frame := Vector2(OriginalArt.CHARACTER_FOOT_ANCHOR)
	var composite: Vector2 = OriginalArt.PLAYER_VISUAL_RUNTIME_POSITION
	var left := foot_in_frame.x - composite.x
	var right := frame_size.x - foot_in_frame.x + composite.x
	var above := foot_in_frame.y - composite.y
	var below := frame_size.y - foot_in_frame.y + composite.y
	return Vector3(maxf(left,right),above,below)

func _update_stealth_alpha() -> void:
	var player: Object = _world.skills.player
	if not _world.skill_actors.is_runtime_present(player): return
	_world.emit_original_main_event(&"set_actor_stealth_alpha",[_world.skill_actors.runtime_actor_id(player),player.is_stealthed(),false])
	for model: Object in _world.skill_actors.actors_in_group(&"summons"):
		if model != null and _world.skill_actors.is_kind(model,&"summon") and model.owner_player == player:
			_world.emit_original_main_event(&"set_actor_stealth_alpha",[_world.skill_actors.runtime_actor_id(model),model.is_stealthed(),true])

func _update_taoist_buff_hints() -> void:
	if not source_hud_is_present() or not _world.skill_actors.is_runtime_present(_world.skills.player): return
	var entries := _original_status_buff_entries()
	var signature: Array = []
	for entry: Dictionary in entries:
		signature.append([entry.id,ceili(entry.remaining),entry.started_at,entry.get("item_id",-1)])
	var hint_text := str(signature)
	if hint_text == _fields.read_source_field(&"_last_taoist_buff_hint_text"): return
	_fields.write_source_field(&"_last_taoist_buff_hint_text",hint_text)
	hud.update_status_buffs(entries)

func _original_status_buff_entries() -> Array:
	var player: Object = _world.skills.player
	var entries: Array = []
	for spec: Array in [["ac",player.defense_buff_time,player.defense_buff > 0],["mac",player.mac_buff_time,player.mac_buff > 0],["shield",player.shield_time,player.shield_capacity > 0.0],["stealth",player.stealth_time,player.is_stealthed()]]:
		if not bool(spec[2]) or (float(spec[1]) <= 0.0 and spec[0] != "stealth"): continue
		var entry := {"id":spec[0],"remaining":spec[1],"started_at":int(player.status_buff_started_at.get(spec[0],0))}
		if spec[0] == "shield": entry.skill = "魔法盾"
		if spec[0] == "stealth": entry.skill = "隐身术"
		entries.append(entry)
	var heal_remaining := 0.0
	var heal_started := 9223372036854775807
	for heal: Dictionary in _world.skills._ongoing_heals:
		if int(heal.target_instance_id) != _world.skill_actors.runtime_actor_id(player): continue
		heal_remaining = maxf(heal_remaining,int(heal.remaining_ticks)*float(heal.tick_interval_seconds)-float(heal.elapsed))
		heal_started = mini(heal_started,int(heal.get("started_at_usec",0)))
	if heal_remaining > 0.0: entries.append({"id":"heal","skill":"治愈术","remaining":heal_remaining,"started_at":heal_started})
	for buff: Dictionary in _world.profile.temporary_item_buffs.values():
		if float(buff.remaining) <= 0.0: continue
		entries.append({"id":"item:"+str(buff.buffGroup),"entity_id":str(buff.get("entity_id","")),"item_id":int(buff.get("item_id",-1)),"remaining":float(buff.remaining),"started_at":int(buff.get("started_at_usec",0))})
	var relic_proc: Dictionary = _world.profile.relic_proc_status()
	if float(relic_proc.get("remaining",0.0)) > 0.0: entries.append({"id":"relic:%d" % int(relic_proc.get("item_id",-1)),"item_id":int(relic_proc.get("item_id",-1)),"remaining":float(relic_proc.remaining),"started_at":int(relic_proc.get("started_at_usec",0))})
	return entries

func _pump_pending_warm_textures() -> void:
	required_owner_service(&"WorldBootstrapPipeline").pump_pending_warm_textures()

var _frame_texture_threaded: Dictionary:
	get: return required_owner_service(&"WorldBootstrapPipeline").original_frame_texture_claim_facts()
