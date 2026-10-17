extends Node2D

const PlayerVisual := preload("res://scripts/gameplay/presentation/player_main_visual_projection.gd")
const PlayerBar := preload("res://scripts/gameplay/presentation/player_main_health_bar.gd")
const EnemyVisual := preload("res://scripts/gameplay/presentation/enemy_main_visual_projection.gd")
const EnemyOverhead := preload("res://scripts/gameplay/presentation/enemy_main_overhead_projection.gd")
const OriginalMonsterVisual := preload("res://scripts/monster_visual.gd")
const BOSS_PHASE_GROUND_RING_VISIBLE := false
const POISON_INDICATOR_DOT_RADIUS := 3.0
var _snapshot: Dictionary
var _identity: Dictionary
var _profile_view: RefCounted
var _assets: RefCounted
var _kind: String
var visual: Node2D
var health_bar: Node2D
var overhead: Node2D
var _configured := false

func configure_main(publication: Dictionary, assets: RefCounted, phase_bridge: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _configured or assets == null or not assets.is_actual_loading_bound(): return false
	_snapshot = publication; _identity = publication.identity; _kind = publication.kind; _assets = assets
	_profile_view = ProfileDisplay.new(publication.profile)
	position = publication.actor.position_screen_px
	z_index = 0; z_as_relative = true; y_sort_enabled = true
	if _kind == "player":
		visual = PlayerVisual.new(); visual.name = "PlayerVisual"
		if not visual.configure_original_projection(self,_profile_view,assets): return false
		health_bar = PlayerBar.new(); health_bar.name = "HealthBar"
		if not health_bar.configure_original_projection(_profile_view): return false
		health_bar.position = ArtSpec.PLAYER_HEALTH_BAR_OFFSET; health_bar.z_index = 20
		health_bar.setup(current_hp,max_hp)
		add_child(visual); add_child(health_bar)
	elif _kind == "enemy":
		OriginalMonsterVisual.configure_actor_y_sort_item(self,"actor_root")
		if visual == null:
			visual = EnemyVisual.new(); visual.name = "MonsterVisual"
			if not visual.configure_main(self,int(publication.enemy_visual.service_id),assets,phase_bridge): return false
			add_child(visual)
		elif visual.canonical_service_id != publication.enemy_visual.service_id or visual.get_parent() != self: return false
		# Header-created renderer retains its actual physical vault; complete
		# Actor assets only supply the genuine font/overhead/layout closure.
		set_meta("spawn_context",publication.actor.spawn_context)
		if not visual.publish_snapshot_checked(publication.enemy_visual): return false
	else: return false
	_configured = true
	set_process(false); set_physics_process(false); set_process_input(false); set_process_unhandled_input(false)
	return true

func apply_source_publication(publication: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not _configured or publication.identity != _identity: return false
	_snapshot = publication; _profile_view.adopt(publication.profile)
	position = publication.actor.position_screen_px
	if _kind == "player":
		health_bar.set_health(current_hp,max_hp); health_bar._refresh_level_label()
		visual._refresh_equipment_visuals()
		if publication.advance_visual:
			visual.advance_original_source_process(float(publication.scaled_delta))
	else:
		if overhead != null:
			overhead.set_health(current_hp,max_hp); overhead.set_anchor_y(publication.enemy_root.health_bar_anchor_y)
		if not visual.publish_snapshot_checked(publication.enemy_visual): return false
	queue_redraw()
	return not _assets.is_faulted()

func accept_actual_original_player_identity_rehome(before: Dictionary, after: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not _configured or _kind != "player" or _identity != before or _assets.owner_descriptor().get("actor_identity") != after or before.runtime_id != after.get("runtime_id"): return false
	# The immutable last Source snapshot remains the prior observation until
	# the next real publication. No animation, HP, material or node is rebuilt.
	_identity = after.duplicate(true)
	return true

func apply_original_player_fact(event: String, payload: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _kind != "player" or not _configured: return false
	match event:
		"play_hit": visual.play_hit(float(payload.duration))
		"play_death": visual.play_death()
		"play_action": visual.play_action(str(payload.action),float(payload.duration))
		"refresh_profession": visual.refresh_profession()
		"catalog_reloaded": visual._on_database_reloaded()
		"redraw": queue_redraw()
		"stats_changed", "resources_changed": health_bar.set_health(current_hp,max_hp)
		_: return false
	return not _assets.is_faulted()

func create_original_overhead(title: String, boss: bool, hp: int, maximum: int) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _kind != "enemy" or not _configured or overhead != null: return false
	overhead = EnemyOverhead.new(); overhead.name = "MonsterOverhead"
	if not overhead.configure_original_projection(_assets): return false
	OriginalMonsterVisual.configure_actor_y_sort_item(overhead,"overhead_root")
	overhead.setup(title,boss,hp,maximum)
	add_child(overhead)
	return not _assets.is_faulted()

func original_source_combat_time_s() -> float: return float(_snapshot.combat_time_s)
func poison_status_remaining() -> float: return float(_snapshot.actor.poison_remaining)
func canonical_red_poison_active() -> bool: return bool(_snapshot.enemy_root.red_poison_active)
func ground_indicator_center() -> Vector2: return _snapshot.enemy_root.ground_center
func ground_indicator_radii() -> Vector2: return _snapshot.enemy_root.ground_radii
func poison_indicator_center() -> Vector2: return _snapshot.enemy_root.poison_center
func red_poison_indicator_center() -> Vector2: return _snapshot.enemy_root.red_poison_center
func should_draw_synthetic_ground_shadow() -> bool: return _snapshot.enemy_root.procedural_fallback
var current_hp: int:
	get: return int(_snapshot.actor.current_hp)
var max_hp: int:
	get: return int(_snapshot.actor.max_hp)
var control_time: float:
	get: return float(_snapshot.actor.control_time)
var poison_time: float:
	get: return float(_snapshot.actor.poison_remaining)
var charm_time: float:
	get: return float(_snapshot.actor.get("charm_time",0.0))
var facing: Vector2:
	get: return _snapshot.actor.facing
var velocity: Vector2:
	get: return _snapshot.actor.velocity
var movement_facing: Vector2:
	get: return _snapshot.actor.movement_facing
var actual_motion_facing: Vector2:
	get: return _snapshot.actor.actual_motion_facing
var movement_input_active: bool:
	get: return bool(_snapshot.actor.movement_input_active)
var locomotion_state: String:
	get: return str(_snapshot.actor.locomotion_state)
var is_boss: bool:
	get: return bool(_snapshot.actor.is_boss)
var _dying: bool:
	get: return bool(_snapshot.actor.dying)
var is_targeted: bool:
	get: return bool(_snapshot.actor.targeted)
var _boss_phase_two: bool:
	get: return bool(_snapshot.actor.boss_phase_two)
var _boss_warning: float:
	get: return float(_snapshot.actor.boss_warning)
var monster_id: int:
	get: return int(_snapshot.actor.monster_id)
var display_name: String:
	get: return str(_snapshot.actor.display_name)
var monster_data: Dictionary:
	get: return _snapshot.actor.monster_data

class ProfileDisplay:
	extends RefCounted
	var _data: Dictionary
	func _init(value: Dictionary) -> void: _data = value
	func adopt(value: Dictionary) -> void: _data = value
	var profession_id: String:
		get: return str(_data.profession_id)
	var gender: String:
		get: return str(_data.gender)
	var level: int:
		get: return int(_data.level)
	var equipment: Dictionary:
		get: return _data.equipment

func _draw() -> void:
	if not _configured: return
	if _kind == "player": _draw_player_original()
	else: _draw_enemy_original()


func _draw_player_original() -> void:
	# Final MIR2 character frames already contain their own direction-aware
	# ground shadow. Drawing another ellipse at the actor origin creates two
	# separated shadows and makes the body look airborne.
	if visual == null or not visual.uses_final_art():
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.48))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if visual == null or not visual.uses_final_art():
		draw_circle(Vector2(0, -8), 17.0, Color(0.76, 0.66, 0.46))
		var profession_color: Color = {"hc.profession.warrior": Color(0.24, 0.34, 0.48), "hc.profession.wizard": Color(0.20, 0.28, 0.56), "hc.profession.taoist": Color(0.36, 0.42, 0.24)}.get(_profile_view.profession_id, Color(0.24, 0.34, 0.48))
		draw_colored_polygon(PackedVector2Array([Vector2(-17, -5), Vector2(17, -5), Vector2(13, 23), Vector2(-13, 23)]), profession_color)
		draw_line(Vector2(0, 7), facing * 27.0 + Vector2(0, 7), Color(0.92, 0.86, 0.65), 5.0)
	# Neither paralysis nor poison draws a ground ring under the character any
	# more (R1.1). Both states present as fixed-slot dots on the status marker
	# row under the overhead HP bar (see PlayerStatusMarkerStrip attached by
	# player_health_bar.gd). Gameplay timers are only read, never changed here.

func _draw_enemy_original() -> void:
	var radius_px := 27.0 if is_boss else 16.0
	var ground_center_px := ground_indicator_center()
	var draw_procedural_fallback := should_draw_synthetic_ground_shadow()
	# Authored WIL actors may briefly wait for their asynchronously loaded
	# atlases. They already own a direction-aware source shadow, so that waiting
	# window must not leave a cached procedural ellipse under the final sprite.
	if draw_procedural_fallback:
		draw_ellipse_shadow(radius_px, ground_center_px)
	if _dying:
		return
	if is_targeted and (visual == null or not visual.uses_final_art()):
		# 细线选中圈与脚底接触阴影共面，避免形成托起Boss的发光平台。
		_draw_ground_indicator_ellipse(
			ground_center_px,
			ground_indicator_radii(),
			Color(1.0, 0.78, 0.18, 0.78),
			2.0,
		)
	var fallback_attacking := draw_procedural_fallback and visual != null and _fallback_is_fallback_attacking()
	var body_center_px := Vector2(0, -5) + (_fallback_fallback_lunge_offset_px(facing) if fallback_attacking else Vector2.ZERO)
	if draw_procedural_fallback:
		var body_color := Color(0.55, 0.11, 0.09) if is_boss else Color(0.30, 0.48, 0.18)
		var attack_scale:=_fallback_fallback_attack_scale() if visual!=null else Vector2.ONE
		var attack_angle:=_fallback_fallback_attack_angle(facing) if visual!=null else 0.0
		draw_set_transform(body_center_px,attack_angle,attack_scale)
		draw_circle(Vector2.ZERO, radius_px, body_color.lightened(0.18) if fallback_attacking else body_color)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
		if fallback_attacking:
			var strike_angle := facing.angle()
			var progress:=_fallback_fallback_attack_progress();var tip_px:=body_center_px+facing.normalized()*(radius_px+6.0+sin(progress*PI)*10.0)
			draw_arc(tip_px, radius_px + 8.0, strike_angle - 0.82, strike_angle + 0.82, 12, Color(1.0, 0.78, 0.26, 0.90), 4.0)
			draw_circle(tip_px,4.0+sin(progress*PI)*3.0,Color(1.0,0.9,0.5,0.82))
	# Phase two remains fully active for stats, skills and AI. Its former
	# persistent red ground outline is controlled independently and permanently
	# disabled; temporary attack telegraphs and the selected-target ring remain.
	if BOSS_PHASE_GROUND_RING_VISIBLE and is_boss and _boss_phase_two:
		draw_circle(
			Vector2(0, -5),
			radius_px + 7.0,
			Color(0.90, 0.15, 0.05, 0.22),
			false,
			4.0,
		)
	if poison_time > 0.0:
		# One compact green dot denotes the damage-over-time poison. Keeping it
		# below the HP bar avoids both the former three-diamond cluster and any
		# ground-ring/portal ambiguity.
		draw_circle(
			poison_indicator_center(),
			POISON_INDICATOR_DOT_RADIUS,
			Color(0.36, 0.92, 0.28, 0.90)
		)
	if canonical_red_poison_active():
		# Red poison shares the same row and uses one dot of its own. The fixed
		# center gap keeps both states distinct without forming a badge stack.
		draw_circle(
			red_poison_indicator_center(),
			POISON_INDICATOR_DOT_RADIUS,
			Color(0.92, 0.16, 0.12, 0.95)
		)
	if control_time > 0.0 or charm_time > 0.0:
		draw_circle(Vector2(0, -5), radius_px + 8.0, Color(0.35, 0.65, 1.0, 0.55), false, 3.0)
	# No dormant ground marker: dormancy is an AI state only. The former gray
	# translucent disc was never an authored affordance and duplicated the
	# normal contact shadow under every sleeping monster.
	if _boss_warning > 0.0:
		_draw_boss_warning_ground_projection()
	if draw_procedural_fallback:
		draw_circle(body_center_px + Vector2(-radius_px * 0.35, -3), 3.0, Color(0.95, 0.75, 0.25))
		draw_circle(body_center_px + Vector2(radius_px * 0.35, -3), 3.0, Color(0.95, 0.75, 0.25))

func _draw_boss_warning_ground_projection() -> void:
	var warning_polygon_px: PackedVector2Array = _snapshot.enemy_root.warning_polygon
	if warning_polygon_px.size() < 3: return
	var is_cone: bool = _snapshot.enemy_root.warning_is_cone
	draw_colored_polygon(
		warning_polygon_px,
		Color(0.95, 0.12, 0.04, 0.22) if is_cone else Color(0.95, 0.18, 0.06, 0.16),
	)
	var outline_px := warning_polygon_px.duplicate()
	outline_px.append(warning_polygon_px[0])
	draw_polyline(
		outline_px,
		Color(1.0, 0.34, 0.08, 0.92) if is_cone else Color(1.0, 0.36, 0.12, 0.85),
		5.0,
		true,
	)

func _draw_ground_indicator_ellipse(
	center_px: Vector2,
	radii_px: Vector2,
	color: Color,
	width_px: float,
) -> void:
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(
			center_px + Vector2(cos(angle) * radii_px.x, sin(angle) * radii_px.y)
		)
	draw_polyline(points, color, width_px, true)

func draw_ellipse_shadow(radius_px: float, center_px := Vector2.ZERO) -> void:
	draw_set_transform(center_px, 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, radius_px, Color(0, 0, 0, 0.30))
	draw_circle(Vector2(0, -radius_px * 0.08), radius_px * 0.56, Color(0, 0, 0, 0.58))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _fallback_is_fallback_attacking() -> bool: return bool(_snapshot.enemy_root.fallback.attacking)
func _fallback_fallback_attack_scale() -> Vector2: return _snapshot.enemy_root.fallback.scale
func _fallback_fallback_attack_angle(_direction: Vector2) -> float: return float(_snapshot.enemy_root.fallback.angle)
func _fallback_fallback_attack_progress() -> float: return float(_snapshot.enemy_root.fallback.progress)
func _fallback_fallback_lunge_offset_px(_direction: Vector2) -> Vector2: return _snapshot.enemy_root.fallback.offset


func prepare_original_enemy_actor_header(identity: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _configured or not _identity.is_empty() or visual != null or get_child_count() != 0: return false
	_identity = identity; _kind = "enemy"
	# Keep real Node2D defaults, including visible=true and no sprite/state.
	set_process(false); set_physics_process(false); set_process_input(false); set_process_unhandled_input(false)
	return true

func retire_original_overhead() -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _kind != "enemy": return false
	if overhead == null: return true
	if not is_instance_valid(overhead) or overhead.get_parent() != self: return false
	if not overhead.is_queued_for_deletion(): overhead.queue_free()
	return true # Actual child destruction remains observed by Node lifecycle.

func prepare_original_enemy_visual_header(service_id: int, actual_resources: RefCounted, phase_bridge: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _kind != "enemy" or _identity.is_empty() or _configured or visual != null or service_id <= 0 or actual_resources == null: return false
	visual = EnemyVisual.new(); visual.name = "MonsterVisual"
	if not visual.configure_main(self,service_id,actual_resources,phase_bridge): return false
	add_child(visual)
	# Original mutations, not this header, create Sprite or change visible.
	return visual.sprite == null and visual.visible and visual.get_child_count() == 0

var actual_source_input_pickable := false
var _last_pickable_ordinal := 0
func apply_original_source_pickable_fact(value: bool, ordinal: int) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not is_inside_tree() or is_queued_for_deletion() or ordinal<=_last_pickable_ordinal: return false
	actual_source_input_pickable=value;_last_pickable_ordinal=ordinal
	return true
