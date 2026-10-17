extends RefCounted
## Original TargetMagic P clock and priest occlusion. HP was settled by Enemy.
const Original:=preload("res://scripts/monster_target_magic_effect.gd")
const Rules:=preload("res://scripts/world_spatial_rules.gd")
var _core: WeakRef
var _handle: Object
var release_descriptor: Dictionary
var _elapsed_seconds:=0.0
var _duration_seconds:=0.0
var _fly_duration_seconds:=0.0
var _fly_previous_world_px: Vector2
var _fly_blocked_by_world:=false
var _finished:=false
var _closed:=false
var source_world_px: Vector2
var target_world_px: Vector2
var source_direction8: int
var source_monster_id: int
signal playback_finished(effect: RefCounted)
func configure_source(core: RefCounted, descriptor: Dictionary, source_position: Vector2, direction: int) -> bool:
	if descriptor.get("effect_id")!=Original.EFFECT_ID or not descriptor.get("target_world_px") is Vector2 or not descriptor.target_world_px.is_finite() or not source_position.is_finite(): return false
	_core=weakref(core);release_descriptor=descriptor.duplicate(true);release_descriptor.make_read_only()
	source_monster_id=int(descriptor.get("source_monster_id",-1));source_world_px=source_position;target_world_px=descriptor.target_world_px;source_direction8=posmod(direction,8);_fly_previous_world_px=source_world_px
	var profile: Dictionary
	if source_monster_id==Original.COW_KING_ID:
		profile=core.required_owner_service(&"SourceFrames",["profile_for_id"]).profile_for_id(source_monster_id).duplicate(true)
		profile.presentation_effect_id=Original.COW_KING_PRESENTATION_EFFECT_ID
	else:
		# Immutable formal numeric frame metadata, no shared Main static cache.
		var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(Original.SOURCE_MANIFEST_PATH))
		if not manifest is Dictionary: return false
		profile=manifest.get("effects_by_monster_id",{}).get(str(source_monster_id),{})
	if str(profile.get("presentation_effect_id",""))!=Original.presentation_effect_id_for_monster_id(source_monster_id) or profile.is_empty(): return false
	var assets: Dictionary={}
	for asset: Dictionary in profile.get("assets",[]): assets[str(asset.get("role",""))]=asset.get("frames",[])
	if source_monster_id==Original.COW_KING_ID:
		if profile.get("frames",[]).size()!=20: return false
		_duration_seconds=Original.CLIENT_MAGIC_RELEASE_SECONDS+0.02*float(profile.frames.size())
	elif source_monster_id==Original.COW_MAGE_ID:
		if assets.get("target_thunder",[]).size()!=6: return false
		_duration_seconds=Original.CLIENT_MAGIC_RELEASE_SECONDS+Original.MAGE_FRAME_SECONDS*float(assets.target_thunder.size())
	elif source_monster_id==Original.COW_PRIEST_ID:
		if assets.get("caster_directional_overlay",[]).size()!=48 or assets.get("flying_spell",[]).size()!=96: return false
		_fly_duration_seconds=maxf(Original.PRIEST_FLY_FRAME_SECONDS,(target_world_px-source_world_px).length()/Original.PRIEST_FLY_SPEED_PX_PER_SECOND)
		_duration_seconds=maxf(Original.PRIEST_CAST_FRAME_SECONDS*6.0,Original.CLIENT_MAGIC_RELEASE_SECONDS+_fly_duration_seconds)
	else: return false
	_handle=core.allocate_cast_model(self,&"field")
	return _handle!=null
func initialize_gameplay() -> void:
	var core: RefCounted=_core.get_ref()
	core.enter_cast_group(self,&"zone_content")
	core.set_cast_physics_processing(self,false)
	var scope: RefCounted=core._actor_scopes[_handle.get_instance_id()]
	scope.process_processing_enabled=true;scope.ordinary_p_enabled=true
	core.emit_original_main_event(&"enemy_create_effect",[_handle.get_instance_id(),&"target_magic",release_descriptor,{"source_world_px":source_world_px,"source_direction8":source_direction8}])
func _process(delta: float) -> void:
	if _finished: return
	_elapsed_seconds=minf(_duration_seconds,_elapsed_seconds+maxf(0.0,delta))
	if source_monster_id==Original.COW_PRIEST_ID and not _fly_blocked_by_world and _elapsed_seconds>=Original.CLIENT_MAGIC_RELEASE_SECONDS:
		var progress:=clampf((_elapsed_seconds-Original.CLIENT_MAGIC_RELEASE_SECONDS)/maxf(_fly_duration_seconds,Original.PRIEST_FLY_FRAME_SECONDS),0.0,1.0)
		var next: Vector2=source_world_px.lerp(target_world_px,progress)
		var clear:=true
		if not _fly_previous_world_px.is_equal_approx(next):
			var result: Dictionary=_core.get_ref().native_world.intersect_ray(_fly_previous_world_px,next,Rules.WORLD_MASK,[],true,true,false)
			if result.get("ok")!=true: _core.get_ref().fault("enemy_magic_native_ray_failed",result);return
			clear=not result.collided
		if not clear:
			_fly_blocked_by_world=true;_duration_seconds=minf(_duration_seconds,Original.PRIEST_CAST_FRAME_SECONDS*6.0)
		else: _fly_previous_world_px=next
	var core: RefCounted=_core.get_ref()
	core.emit_original_main_event(&"enemy_effect_tick",[_handle.get_instance_id(),{"elapsed":_elapsed_seconds,"duration":_duration_seconds,"position":target_world_px,"blocked":_fly_blocked_by_world,"finished":_elapsed_seconds>=_duration_seconds}])
	if _elapsed_seconds>=_duration_seconds:
		_finished=true
		var scope: RefCounted=core._actor_scopes[_handle.get_instance_id()]
		scope.process_processing_enabled=false;scope.ordinary_p_enabled=false
		playback_finished.emit(self)
		core.queue_cast_retirement(self)
func close_effect() -> void:
	if _closed: return
	_closed=true
	_core.get_ref().emit_original_main_event(&"retire_enemy_effect",[_handle.get_instance_id()])
