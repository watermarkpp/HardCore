extends Control

const MonsterDraftScript := preload(
	"res://scripts/monster_ground_alignment_draft.gd"
)
const ACTIONS := ["idle", "walk", "attack", "cast", "hit", "death"]
const ACTION_LABELS := ["站立", "行走", "攻击", "施法", "受击", "死亡"]
const MONSTER_ACTIONS := ["idle", "walk", "attack", "hit", "death"]
const MONSTER_ACTION_LABELS := ["站立", "行走", "攻击", "受击", "死亡"]
const DIRECTION_LABELS := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
const DIRECTIONS: Array[Vector2] = [
	Vector2.DOWN,
	Vector2(-0.70710678, 0.70710678),
	Vector2.LEFT,
	Vector2(-0.70710678, -0.70710678),
	Vector2.UP,
	Vector2(0.70710678, -0.70710678),
	Vector2.RIGHT,
	Vector2(0.70710678, 0.70710678),
]
const SPEEDS := [0.25, 0.5, 1.0, 2.0]
const SPEED_LABELS := ["25%", "50%", "100%", "200%"]
const LAB_CONTRACT_ID := "local.visual_acceptance_lab.player_runtime.v1"
const MONSTER_LAB_CONTRACT_ID := (
	"local.visual_acceptance_lab.monster_runtime.v1"
)
const ALIGNMENT_DRAFT_CONTRACT_ID := (
	"local.visual_acceptance_lab.player_alignment_draft.v1"
)
const ALIGNMENT_DRAFT_PATH := (
	"res://outputs/visual_acceptance/player_visual_alignment_draft.json"
)
const FORMAL_ALIGNMENT_CONTRACT_PATH := (
	"res://assets/data/player_visual_alignment.json"
)
const ALIGNMENT_NUDGE := 0.5
const PLAYBACK_TICK_SECONDS := 1.0 / 60.0
const MONSTER_GROUND_REVIEW_ARG := "--monster-ground-review"
const MONSTER_FOOT_MATCH_EPSILON := 0.01
const MONSTER_TARGET_RING_COLOR := Color("#ffd54f")
const MONSTER_FOOT_DELTA_COLOR := Color("#ff6b6b")
const MONSTER_ACTOR_ORIGIN_COLOR := Color("#ff9f43")

var _old_test_mode := false
var _player: PlayerCharacter
var _monster: EnemyActor
var _monster_rows: Array[Dictionary] = []
var _active_monster_id := -1
var _preview_root: Node2D
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _background: ColorRect
var _grid_root: Node2D
var _overlay_root: Node2D
var _mode_option: OptionButton
var _action_option: OptionButton
var _direction_option: OptionButton
var _profession_option: OptionButton
var _monster_option: OptionButton
var _speed_option: OptionButton
var _background_option: OptionButton
var _frame_spin: SpinBox
var _zoom_slider: HSlider
var _play_button: Button
var _overlay_button: CheckButton
var _foot_pick_button: CheckButton
var _alignment_button: CheckButton
var _alignment_offset_label: Label
var _status: Label
var _playback_timer: Timer
var _playing := true
var _clock := 0.0
var _current_frame := 0
var _foot_pick_mode := false
var _alignment_mode := false
var _dragging_visual := false
var _runtime_visual_origin := Vector2.ZERO
var _runtime_foot_anchor_adjustment := Vector2.ZERO
var _visual_alignment_offset := Vector2.ZERO
var _visual_foot_anchor_adjustment := Vector2.ZERO
var _monster_runtime_visual_origin := Vector2.ZERO
var _monster_visual_alignment_offset := Vector2.ZERO
var _monster_picked_visual_foot_offset := Vector2.ZERO
var _monster_formal_visual_foot_offset := Vector2.ZERO
var _active_monster_draft_loaded := false
var _monster_saved_selection: Dictionary = {}


func _ready() -> void:
	_old_test_mode = PlayerState.test_mode
	PlayerState.test_mode = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_monster_rows = MonsterDraftScript.catalog_rows()
	if DisplayServer.get_name() != "headless":
		get_window().min_size = Vector2i(1100, 650)
		get_window().size = Vector2i(1280, 720)
	_build_ui()
	_build_preview_actor()
	_load_alignment_draft()
	_on_zoom_changed(_zoom_slider.value)
	if OS.get_cmdline_user_args().has(MONSTER_GROUND_REVIEW_ARG):
		if DisplayServer.get_name() != "headless":
			get_window().title = "HardCore 怪物脚点 / 黄色光圈验收"
		_mode_option.select(1)
		_on_mode_changed(1)
	else:
		_apply_selection()
	_start_playback_timer()


func _exit_tree() -> void:
	PlayerState.test_mode = _old_test_mode


func _start_playback_timer() -> void:
	_playback_timer = Timer.new()
	_playback_timer.name = "PlaybackTimer"
	_playback_timer.wait_time = PLAYBACK_TICK_SECONDS
	_playback_timer.one_shot = false
	_playback_timer.autostart = true
	_playback_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_playback_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_playback_timer.timeout.connect(_advance_playback.bind(PLAYBACK_TICK_SECONDS))
	add_child(_playback_timer)


func _advance_playback(delta: float) -> void:
	if not _playing or not _active_visual_available():
		return
	var frame_count := _frame_count()
	if frame_count <= 1:
		return
	_clock += delta * _selected_speed()
	var fps := _action_fps(_selected_action())
	var next_frame := int(floor(_clock * fps)) % frame_count
	if next_frame != _current_frame:
		_current_frame = next_frame
		_frame_spin.set_value_no_signal(_current_frame)
		_apply_preview_frame()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if (_alignment_mode or _foot_pick_mode) and event.keycode in [
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN,
	]:
		var nudge := Vector2.ZERO
		match event.keycode:
			KEY_LEFT:
				nudge.x = -ALIGNMENT_NUDGE
			KEY_RIGHT:
				nudge.x = ALIGNMENT_NUDGE
			KEY_UP:
				nudge.y = -ALIGNMENT_NUDGE
			KEY_DOWN:
				nudge.y = ALIGNMENT_NUDGE
		if _foot_pick_mode:
			_nudge_visual_foot_anchor(nudge)
		else:
			_nudge_visual_alignment(nudge)
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_SPACE:
			_toggle_playback()
		KEY_LEFT:
			_step_frame(-1)
		KEY_RIGHT:
			_step_frame(1)
		KEY_UP:
			_step_direction(-1)
		KEY_DOWN:
			_step_direction(1)
		KEY_F:
			_overlay_button.button_pressed = not _overlay_button.button_pressed
			_update_overlay()
		KEY_S:
			_save_screenshot()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root_background := ColorRect.new()
	root_background.color = Color("#11151a")
	root_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_background)

	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	layout.add_theme_constant_override("separation", 14)
	add_child(layout)

	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(330, 0)
	var sidebar_style := StyleBoxFlat.new()
	sidebar_style.bg_color = Color("#1c232b")
	sidebar_style.border_color = Color("#465563")
	sidebar_style.set_border_width_all(1)
	sidebar_style.set_corner_radius_all(8)
	sidebar.add_theme_stylebox_override("panel", sidebar_style)
	layout.add_child(sidebar)

	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(sidebar_scroll)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(310, 0)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 10)
	sidebar_scroll.add_child(controls)
	var title := Label.new()
	title.text = "HardCore 本地视觉验收台"
	title.add_theme_font_size_override("font_size", 24)
	controls.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "正式运行时只读；仅保存 outputs 对齐草稿"
	subtitle.modulate = Color("#9fb0bf")
	controls.add_child(subtitle)
	controls.add_child(HSeparator.new())

	_mode_option = _add_option(controls, "检测对象", [
		"人物", "怪物",
	])
	_profession_option = _add_option(controls, "职业", [
		"战士", "法师", "道士",
	])
	_monster_option = _add_option(
		controls, "怪物", _monster_option_labels()
	)
	_monster_option.get_parent().visible = false
	_action_option = _add_option(controls, "动作", ACTION_LABELS)
	_direction_option = _add_option(controls, "方向", DIRECTION_LABELS)
	_speed_option = _add_option(controls, "播放速度", SPEED_LABELS)
	_speed_option.select(2)
	_background_option = _add_option(controls, "背景", [
		"深色", "亮灰", "绿幕",
	])

	var frame_row := _labelled_row(controls, "帧")
	_frame_spin = SpinBox.new()
	_frame_spin.min_value = 0
	_frame_spin.max_value = 0
	_frame_spin.step = 1
	_frame_spin.allow_greater = false
	_frame_spin.allow_lesser = false
	_frame_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_row.add_child(_frame_spin)

	var zoom_row := _labelled_row(controls, "显示倍率")
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 1.0
	_zoom_slider.max_value = 4.0
	_zoom_slider.step = 1.0
	_zoom_slider.value = 3.0
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zoom_row.add_child(_zoom_slider)

	var playback := HBoxContainer.new()
	playback.add_theme_constant_override("separation", 8)
	controls.add_child(playback)
	var previous := _button("上一帧")
	previous.pressed.connect(_step_frame.bind(-1))
	playback.add_child(previous)
	_play_button = _button("暂停")
	_play_button.pressed.connect(_toggle_playback)
	playback.add_child(_play_button)
	var next := _button("下一帧")
	next.pressed.connect(_step_frame.bind(1))
	playback.add_child(next)

	_overlay_button = CheckButton.new()
	_overlay_button.text = "显示锚点 / 碰撞脚印 / 帧边界"
	_overlay_button.button_pressed = true
	controls.add_child(_overlay_button)
	_foot_pick_button = CheckButton.new()
	_foot_pick_button.text = "① 点击鞋底中点设置蓝色脚点"
	controls.add_child(_foot_pick_button)
	_alignment_button = CheckButton.new()
	_alignment_button.text = "② 移动整个视觉（拖动 / 方向键 0.5px）"
	controls.add_child(_alignment_button)
	_alignment_offset_label = Label.new()
	_alignment_offset_label.modulate = Color("#9fd8ff")
	controls.add_child(_alignment_offset_label)
	var alignment_actions := HBoxContainer.new()
	alignment_actions.add_theme_constant_override("separation", 8)
	controls.add_child(alignment_actions)
	var align_center := _button("脚点对齐中心")
	align_center.pressed.connect(_align_visual_foot_to_standard)
	alignment_actions.add_child(align_center)
	var reset_alignment := _button("恢复运行时")
	reset_alignment.pressed.connect(_reset_visual_alignment)
	alignment_actions.add_child(reset_alignment)
	var save_alignment := _button("保存对齐草稿")
	save_alignment.pressed.connect(_save_alignment_draft)
	controls.add_child(save_alignment)
	var screenshot := _button("保存当前截图")
	screenshot.pressed.connect(_save_screenshot)
	controls.add_child(screenshot)
	var reload := _button("重新加载当前正式素材")
	reload.pressed.connect(_reload_runtime_art)
	controls.add_child(reload)
	controls.add_spacer(false)

	var shortcuts := Label.new()
	shortcuts.text = (
		"快捷键：空格 播放/暂停\n"
		+ "普通：←/→ 逐帧　↑/↓ 换方向\n"
		+ "对齐：拖动视觉或方向键 0.5px\n"
		+ "F 辅助线　S 截图"
	)
	shortcuts.modulate = Color("#9fb0bf")
	controls.add_child(shortcuts)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 72)
	controls.add_child(_status)

	var stage_panel := PanelContainer.new()
	stage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stage_style := StyleBoxFlat.new()
	stage_style.bg_color = Color("#07090c")
	stage_style.border_color = Color("#465563")
	stage_style.set_border_width_all(1)
	stage_style.set_corner_radius_all(8)
	stage_panel.add_theme_stylebox_override("panel", stage_style)
	layout.add_child(stage_panel)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.gui_input.connect(_on_preview_gui_input)
	stage_panel.add_child(_viewport_container)
	_viewport = SubViewport.new()
	_viewport.name = "AcceptanceViewport"
	_viewport.size = Vector2i(900, 680)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport_container.add_child(_viewport)
	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.color = Color("#161c22")
	_viewport.add_child(_background)
	_grid_root = Node2D.new()
	_grid_root.name = "CoordinateGrid"
	_viewport.add_child(_grid_root)
	_build_coordinate_grid()
	_preview_root = Node2D.new()
	_preview_root.name = "RuntimePreview"
	_preview_root.position = Vector2(450, 380)
	_viewport.add_child(_preview_root)

	_mode_option.item_selected.connect(_on_mode_changed)
	_profession_option.item_selected.connect(_on_selection_changed)
	_monster_option.item_selected.connect(_on_monster_changed)
	_action_option.item_selected.connect(_on_selection_changed)
	_direction_option.item_selected.connect(_on_selection_changed)
	_speed_option.item_selected.connect(_on_speed_changed)
	_background_option.item_selected.connect(_on_background_changed)
	_frame_spin.value_changed.connect(_on_frame_changed)
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	_overlay_button.toggled.connect(_on_overlay_toggled)
	_foot_pick_button.toggled.connect(_on_foot_pick_toggled)
	_alignment_button.toggled.connect(_on_alignment_toggled)


func _build_preview_actor() -> void:
	_player = PlayerCharacter.new()
	_player.name = "AcceptancePlayer"
	_preview_root.add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	if _player.health_bar != null:
		_player.health_bar.visible = false
	_player.visual.set_process(false)
	_runtime_visual_origin = _player.visual.position
	_load_formal_alignment_contract()
	_overlay_root = Node2D.new()
	_overlay_root.name = "DiagnosticsOverlay"
	_overlay_root.z_index = 100
	_preview_root.add_child(_overlay_root)


func _build_coordinate_grid() -> void:
	for x in range(0, _viewport.size.x + 1, 32):
		_add_line(
			_grid_root,
			PackedVector2Array([Vector2(x, 0), Vector2(x, _viewport.size.y)]),
			Color(0.36, 0.44, 0.50, 0.11),
			1.0
		)
	for y in range(0, _viewport.size.y + 1, 32):
		_add_line(
			_grid_root,
			PackedVector2Array([Vector2(0, y), Vector2(_viewport.size.x, y)]),
			Color(0.36, 0.44, 0.50, 0.11),
			1.0
		)


func _apply_selection() -> void:
	if _is_monster_mode():
		var rebuilt_from_draft := _rebuild_monster_actor()
		if not rebuilt_from_draft:
			_current_frame = 0
			_clock = 0.0
		_update_frame_limits()
		_apply_preview_frame()
		return
	PlayerState.profession = ProfessionRules.PROFESSION_CATALOG.values()[
		_profession_option.selected
	]
	_player.visual.refresh_profession()
	_current_frame = 0
	_clock = 0.0
	_update_frame_limits()
	_apply_preview_frame()


func _apply_preview_frame() -> void:
	if _is_monster_mode():
		_apply_monster_preview_frame()
		return
	if _player == null or _player.visual == null:
		return
	var action := _selected_action()
	var direction := DIRECTIONS[_direction_option.selected]
	_player.facing = direction
	_player.actual_motion_facing = direction
	_player.velocity = direction * 90.0 if action == "walk" else Vector2.ZERO
	var visual := _player.visual
	var frame_count := _frame_count()
	_current_frame = clampi(_current_frame, 0, maxi(0, frame_count - 1))
	if action in ["idle", "walk"]:
		visual._action_remaining = 0.0
		visual._last_state = action
		visual._elapsed = (
			(float(_current_frame) + 0.01) / _action_fps(action)
		)
	else:
		visual._action_name = action
		visual._action_duration = float(frame_count)
		visual._action_remaining = float(frame_count)
		visual._last_state = "action"
		visual._elapsed = float(_current_frame) + 0.01
	visual._process(0.0)
	_update_overlay()
	_update_status()


func _apply_monster_preview_frame() -> void:
	if (
		_monster == null
		or _monster.visual == null
		or _monster.visual.sprite == null
	):
		return
	var action := _selected_action()
	var visual := _monster.visual
	var frame_count := _frame_count()
	_current_frame = clampi(
		_current_frame, 0, maxi(0, frame_count - 1)
	)
	visual.current_state = action
	visual.current_direction = visual._direction_row(
		DIRECTIONS[_direction_option.selected]
	)
	visual.current_frame = _current_frame
	visual.sprite.texture = visual.active_resources.get(action)
	visual.sprite.region_rect = Rect2(
		_current_frame * visual.frame_size.x,
		visual.current_direction * visual.frame_size.y,
		visual.frame_size.x,
		visual.frame_size.y,
	)
	_update_overlay()
	_update_status()


func _rebuild_monster_actor(force := false) -> bool:
	if _monster_rows.is_empty() or _preview_root == null:
		return false
	var row := _monster_rows[
		clampi(_monster_option.selected, 0, _monster_rows.size() - 1)
	]
	var monster_id := int(row.get("monster_id", -1))
	if (
		not force
		and _monster != null
		and _active_monster_id == monster_id
	):
		_monster.visible = true
		return false
	if _monster != null:
		_monster.free()
		_monster = null
	var data := GameData.get_monster_by_id(monster_id).duplicate(true)
	if data.is_empty():
		_update_status("怪物 #%d 缺少正式运行时数据。" % monster_id)
		return false
	_monster = EnemyActor.new()
	_monster.name = "AcceptanceMonster_%d" % monster_id
	_monster.setup(data, _player, _is_boss_monster(monster_id))
	_preview_root.add_child(_monster)
	# The lab owns its diagnostic overlays. A runtime-selected MonsterVisual can
	# now draw the game's yellow target ring itself, which would duplicate the
	# saved-draft overlay and make sub-pixel differences look like changed user
	# data. Keep the preview actor unselected so draft review remains a single,
	# read-only coordinate presentation.
	_monster.set_targeted(false)
	_monster.set_process(false)
	_monster.set_physics_process(false)
	_monster.velocity = Vector2.ZERO
	# The acceptance lab previews authored frames directly. Boss emergence and
	# burrow mechanics remain active in the game, but must not hide those frames
	# while the user is inspecting animation and ground alignment.
	_monster._burrowed = false
	_monster.dormant = false
	if _monster.visual != null:
		_monster.visual.set_process(false)
		_monster.visual.visible = true
	if _monster.overhead != null:
		_monster.overhead.visible = false
	_active_monster_id = monster_id
	_monster_runtime_visual_origin = _monster.visual.position
	var formal := MonsterDraftScript.formal_entry(monster_id)
	_monster_formal_visual_foot_offset = _vector2_from_array(
		formal.get("visualFootOffset", []), Vector2.ZERO
	)
	_monster_picked_visual_foot_offset = (
		_monster_formal_visual_foot_offset
	)
	_monster_visual_alignment_offset = Vector2.ZERO
	_monster_saved_selection = _normalized_monster_selection(
		formal.get("selection", {})
	)
	_apply_monster_selection(_monster_saved_selection)
	_clock = 0.0
	_load_monster_alignment_draft()
	_monster.visual.position = (
		_monster_runtime_visual_origin
		+ _monster_visual_alignment_offset
	)
	return true


func _is_boss_monster(monster_id: int) -> bool:
	for value: Variant in GameData.bosses:
		if (
			value is Dictionary
			and int(value.get("monsterId", -1)) == monster_id
		):
			return true
	return false


func _update_frame_limits() -> void:
	var count := _frame_count()
	_frame_spin.max_value = maxi(0, count - 1)
	_frame_spin.set_value_no_signal(clampi(_current_frame, 0, maxi(0, count - 1)))


func _update_overlay() -> void:
	if _overlay_root == null:
		return
	for child: Node in _overlay_root.get_children():
		child.queue_free()
	_overlay_root.visible = _overlay_button.button_pressed
	if not _overlay_root.visible:
		return
	if _is_monster_mode():
		_update_monster_overlay()
		return
	if _player == null or _player.visual == null:
		return
	var visual := _player.visual
	var body_sprite: Sprite2D = visual.sprite
	var foot_origin := _visual_foot_origin()
	_draw_canonical_ground_overlay(
		foot_origin, ArtSpec.PLAYER_COLLISION_RADIUS
	)
	if body_sprite != null:
		var rect := Rect2(
			visual.position + body_sprite.position,
			Vector2(body_sprite.region_rect.size)
		)
		_add_rect_line(
			_overlay_root,
			rect,
			Color(0.55, 1.0, 0.52, 0.75),
			1.0
		)


func _update_monster_overlay() -> void:
	if (
		_monster == null
		or _monster.visual == null
		or _monster.visual.sprite == null
	):
		return
	var visual := _monster.visual
	var body_sprite: Sprite2D = visual.sprite
	_draw_canonical_ground_overlay(
		_visual_foot_origin(), _monster.collision_radius
	)
	var formal_center := (
		visual.position + visual.ground_contact_offset()
	)
	var formal_radii := visual.ground_indicator_radii(Vector2(22, 7))
	_add_ellipse_line(
		_overlay_root,
		formal_center,
		formal_radii,
		Color(1.0, 0.62, 0.20, 0.72),
		1.0,
	)
	var rect := Rect2(
		visual.position + body_sprite.position,
		Vector2(body_sprite.region_rect.size)
	)
	_add_rect_line(
		_overlay_root,
		rect,
		Color(0.55, 1.0, 0.52, 0.75),
		1.0
	)


func _draw_canonical_ground_overlay(
	foot_origin: Vector2,
	collision_radius: float,
) -> void:
	_add_line(
		_overlay_root,
		PackedVector2Array([Vector2(-24, 0), Vector2(24, 0)]),
		Color("#ffcc4d"),
		1.0
	)
	_add_line(
		_overlay_root,
		PackedVector2Array([Vector2(0, -24), Vector2(0, 24)]),
		Color("#ffcc4d"),
		1.0
	)
	_add_cross(_overlay_root, foot_origin, Color("#4de1ff"), 9.0)
	var footprint := WorldSpatialRules.actor_footprint_polygon(
		collision_radius, 32
	)
	_add_closed_line(_overlay_root, footprint, Color("#ff5c78"), 1.5)
	var diamond := PackedVector2Array([
		Vector2(0, -16), Vector2(32, 0), Vector2(0, 16), Vector2(-32, 0),
	])
	_add_closed_line(_overlay_root, diamond, Color(0.55, 0.75, 1.0, 0.65), 1.0)


func _update_status(message := "") -> void:
	_update_alignment_offset_label()
	if not message.is_empty():
		_status.text = message
		return
	if _is_monster_mode():
		var row := _selected_monster_row()
		var monster_name := str(row.get("name", ""))
		var monster_id := int(row.get("monster_id", -1))
		var review := monster_ground_review_snapshot()
		var manual_foot: Vector2 = review.get(
			"manualFootCenter", Vector2.ZERO
		)
		var runtime_ring: Vector2 = review.get(
			"runtimeRingCenter", Vector2.ZERO
		)
		var target_delta: Vector2 = review.get(
			"runtimeTargetDelta", Vector2.ZERO
		)
		var visual_delta: Vector2 = review.get(
			"manualFootDelta", Vector2.ZERO
		)
		var match_text := (
			"坐标合同一致"
			if bool(review.get("matches", false))
			else "坐标合同有差异"
		)
		var pose_text := (
			"当前就是保存校准姿态"
			if bool(review.get("poseMatchesCalibration", false))
			else "当前不是保存校准姿态"
		)
		var source_text := (
			"人工草稿"
			if bool(review.get("draftLoaded", false))
			else "正式合同（无人工草稿）"
		)
		_status.text = (
			"%s　#%d %s　%s / %s　帧 %d/%d　倍率 %dx\n"
			+ "橙十字=怪物物理原点　青十字=人工视觉脚点　"
			+ "黄圈/黄小十字=游戏实时目标光圈\n"
			+ "来源=%s　保存姿态=%s【%s】\n"
			+ "人工脚点=(%.1f, %.1f)　实时黄圈=(%.1f, %.1f)　"
			+ "黄圈-目标=(%+.1f, %+.1f)　脚点-原点=(%+.1f, %+.1f)"
			+ "【%s】"
		) % [
			MONSTER_LAB_CONTRACT_ID,
			monster_id,
			monster_name,
			MONSTER_ACTION_LABELS[_action_option.selected],
			DIRECTION_LABELS[_direction_option.selected],
			_current_frame + 1,
			_frame_count(),
			int(_zoom_slider.value),
			source_text,
			_monster_selection_label(
				review.get("calibrationSelection", {})
			),
			pose_text,
			manual_foot.x,
			manual_foot.y,
			runtime_ring.x,
			runtime_ring.y,
			target_delta.x,
			target_delta.y,
			visual_delta.x,
			visual_delta.y,
			match_text,
		]
		return
	var status_template := (
		"%s　%s / %s　帧 %d/%d　倍率 %dx\n"
		+ "黄=角色地面原点　蓝十字=视觉脚点　粉=物理脚印　"
		+ "蓝菱形=64×32地图格\n"
		+ "①蓝点放鞋底中点　②移动人物使蓝黄重合；"
		+ "粉/蓝菱形中心锁定"
	)
	_status.text = status_template % [
		LAB_CONTRACT_ID,
		ACTION_LABELS[_action_option.selected],
		DIRECTION_LABELS[_direction_option.selected],
		_current_frame + 1,
		_frame_count(),
		int(_zoom_slider.value),
	]


func _step_frame(delta: int) -> void:
	_playing = false
	_play_button.text = "播放"
	var count := _frame_count()
	_current_frame = wrapi(_current_frame + delta, 0, maxi(1, count))
	_frame_spin.set_value_no_signal(_current_frame)
	_apply_preview_frame()


func _step_direction(delta: int) -> void:
	_direction_option.select(wrapi(_direction_option.selected + delta, 0, 8))
	_current_frame = 0
	_update_frame_limits()
	_apply_preview_frame()


func _toggle_playback() -> void:
	_playing = not _playing
	_play_button.text = "暂停" if _playing else "播放"
	_clock = float(_current_frame) / _action_fps(_selected_action())


func _visual_foot_origin() -> Vector2:
	if _is_monster_mode():
		if _monster == null or _monster.visual == null:
			return Vector2.ZERO
		return (
			_monster.visual.position
			+ _monster_picked_visual_foot_offset
		)
	if _player == null or _player.visual == null:
		return Vector2.ZERO
	var visual := _player.visual
	if visual.sprite == null:
		return Vector2.ZERO
	return (
		visual.position
		+ visual.sprite.position
		+ Vector2(ArtSpec.WARRIOR_FOOT_ANCHOR)
		+ _visual_foot_anchor_adjustment
	)


func _on_foot_pick_toggled(pressed: bool) -> void:
	_foot_pick_mode = pressed
	_dragging_visual = false
	if _foot_pick_mode:
		_alignment_button.set_pressed_no_signal(false)
		_alignment_mode = false
		_playing = false
		_play_button.text = "播放"
	_update_status()


func _on_alignment_toggled(pressed: bool) -> void:
	_alignment_mode = pressed
	_dragging_visual = false
	if _alignment_mode:
		_foot_pick_button.set_pressed_no_signal(false)
		_foot_pick_mode = false
		_playing = false
		_play_button.text = "播放"
	_update_status()


func _on_preview_gui_input(event: InputEvent) -> void:
	if not _alignment_mode and not _foot_pick_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _foot_pick_mode and event.pressed:
			_set_visual_foot_anchor_from_preview(
				_preview_local_from_container(event.position)
			)
			_viewport_container.accept_event()
			return
		_dragging_visual = event.pressed
		_viewport_container.accept_event()
	elif event is InputEventMouseMotion and _dragging_visual:
		var zoom := maxf(1.0, float(_zoom_slider.value))
		_nudge_visual_alignment(event.relative / zoom)
		_viewport_container.accept_event()


func _preview_local_from_container(point: Vector2) -> Vector2:
	var container_size := _viewport_container.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return Vector2.ZERO
	var viewport_point := Vector2(
		point.x * float(_viewport.size.x) / container_size.x,
		point.y * float(_viewport.size.y) / container_size.y
	)
	return (
		viewport_point - _preview_root.position
	) / _preview_root.scale


func _set_visual_foot_anchor_from_preview(point: Vector2) -> void:
	if _is_monster_mode():
		if _monster == null or _monster.visual == null:
			return
		_set_visual_foot_anchor_adjustment(
			point - _monster.visual.position
		)
		return
	_set_visual_foot_anchor_adjustment(
		_visual_foot_anchor_adjustment + point - _visual_foot_origin()
	)


func _nudge_visual_foot_anchor(delta: Vector2) -> void:
	if _is_monster_mode():
		_set_visual_foot_anchor_adjustment(
			_monster_picked_visual_foot_offset + delta
		)
		return
	_set_visual_foot_anchor_adjustment(
		_visual_foot_anchor_adjustment + delta
	)


func _set_visual_foot_anchor_adjustment(value: Vector2) -> void:
	if _is_monster_mode():
		_monster_picked_visual_foot_offset = _snapped_alignment(value)
		_update_overlay()
		_update_status()
		return
	_visual_foot_anchor_adjustment = Vector2(
		roundf(value.x / ALIGNMENT_NUDGE) * ALIGNMENT_NUDGE,
		roundf(value.y / ALIGNMENT_NUDGE) * ALIGNMENT_NUDGE
	)
	_update_overlay()
	_update_status()


func _nudge_visual_alignment(delta: Vector2) -> void:
	if _is_monster_mode():
		_set_visual_alignment_offset(
			_monster_visual_alignment_offset + delta
		)
		return
	_set_visual_alignment_offset(_visual_alignment_offset + delta)


func _set_visual_alignment_offset(value: Vector2) -> void:
	if _is_monster_mode():
		_monster_visual_alignment_offset = _snapped_alignment(value)
		if _monster == null or _monster.visual == null:
			return
		_monster.visual.position = (
			_monster_runtime_visual_origin
			+ _monster_visual_alignment_offset
		)
		_apply_preview_frame()
		return
	_visual_alignment_offset = Vector2(
		roundf(value.x / ALIGNMENT_NUDGE) * ALIGNMENT_NUDGE,
		roundf(value.y / ALIGNMENT_NUDGE) * ALIGNMENT_NUDGE
	)
	if _player == null or _player.visual == null:
		return
	_player.visual.position = _runtime_visual_origin + _visual_alignment_offset
	_apply_preview_frame()


func _align_visual_foot_to_standard() -> void:
	if _is_monster_mode():
		_set_visual_alignment_offset(
			_monster_visual_alignment_offset - _visual_foot_origin()
		)
		return
	_set_visual_alignment_offset(
		_visual_alignment_offset - _visual_foot_origin()
	)


func _reset_visual_alignment() -> void:
	if _is_monster_mode():
		_monster_picked_visual_foot_offset = (
			_monster_formal_visual_foot_offset
		)
		_set_visual_alignment_offset(Vector2.ZERO)
		return
	_visual_foot_anchor_adjustment = _runtime_foot_anchor_adjustment
	_set_visual_alignment_offset(Vector2.ZERO)


func _update_alignment_offset_label() -> void:
	if _alignment_offset_label == null:
		return
	var foot := _visual_foot_origin()
	if _is_monster_mode():
		_alignment_offset_label.text = (
			"怪物整体 X %+.1f/Y %+.1f　局部脚点 X %+.1f/Y %+.1f\n"
			+ "青色脚点坐标 X %+.1f/Y %+.1f"
		) % [
			_monster_visual_alignment_offset.x,
			_monster_visual_alignment_offset.y,
			_monster_picked_visual_foot_offset.x,
			_monster_picked_visual_foot_offset.y,
			foot.x,
			foot.y,
		]
		return
	var offset_template := (
		"人物 X %+.1f/Y %+.1f　脚点修正 X %+.1f/Y %+.1f\n"
		+ "蓝色脚点坐标 X %+.1f/Y %+.1f"
	)
	_alignment_offset_label.text = offset_template % [
		_visual_alignment_offset.x,
		_visual_alignment_offset.y,
		_visual_foot_anchor_adjustment.x,
		_visual_foot_anchor_adjustment.y,
		foot.x,
		foot.y,
	]


func _snapped_alignment(value: Vector2) -> Vector2:
	return Vector2(
		roundf(value.x / ALIGNMENT_NUDGE) * ALIGNMENT_NUDGE,
		roundf(value.y / ALIGNMENT_NUDGE) * ALIGNMENT_NUDGE
	)


func alignment_draft_payload() -> Dictionary:
	var foot := _visual_foot_origin()
	return {
		"contractId": ALIGNMENT_DRAFT_CONTRACT_ID,
		"savedAt": Time.get_datetime_string_from_system(),
		"scope": "male_formal_player_visual",
		"profession": str(PlayerState.profession),
		"visualOffset": [
			_visual_alignment_offset.x, _visual_alignment_offset.y,
		],
		"visualFootAnchorAdjustment": [
			_visual_foot_anchor_adjustment.x,
			_visual_foot_anchor_adjustment.y,
		],
		"runtimeVisualOrigin": [
			_runtime_visual_origin.x, _runtime_visual_origin.y,
		],
		"visualFootPoint": [foot.x, foot.y],
		"canonicalCenters": {
			"actorGroundOrigin": [0.0, 0.0],
			"physicsFootprint": [0.0, 0.0],
			"mapDiamond": [0.0, 0.0],
		},
		"formalRuntimeWritten": _current_alignment_matches_formal(),
		"formalContractPath": FORMAL_ALIGNMENT_CONTRACT_PATH,
	}


func monster_alignment_draft_payload() -> Dictionary:
	if _monster == null or _monster.visual == null:
		return {}
	return MonsterDraftScript.build_payload(
		_active_monster_id,
		{
			"action": _selected_action(),
			"direction": _direction_option.selected,
			"frame": _current_frame,
		},
		_monster_runtime_visual_origin,
		_monster_visual_alignment_offset,
		_monster_picked_visual_foot_offset,
		Vector2(
			_monster.collision_radius,
			_monster.collision_radius * 0.5,
		),
	)


func _current_alignment_matches_formal() -> bool:
	return (
		_visual_alignment_offset.is_zero_approx()
		and _visual_foot_anchor_adjustment.is_equal_approx(
			_runtime_foot_anchor_adjustment
		)
	)


func _load_formal_alignment_contract() -> void:
	_runtime_foot_anchor_adjustment = Vector2.ZERO
	if not FileAccess.file_exists(FORMAL_ALIGNMENT_CONTRACT_PATH):
		return
	var file := FileAccess.open(FORMAL_ALIGNMENT_CONTRACT_PATH, FileAccess.READ)
	var parsed: Variant = (
		JSON.parse_string(file.get_as_text()) if file != null else null
	)
	if not parsed is Dictionary:
		return
	var adjustment: Variant = parsed.get(
		"visualFootAnchorAdjustment", []
	)
	if adjustment is Array and adjustment.size() == 2:
		_runtime_foot_anchor_adjustment = Vector2(
			float(adjustment[0]), float(adjustment[1])
		)


func _save_alignment_draft() -> void:
	if _is_monster_mode():
		var result := MonsterDraftScript.save_draft(
			monster_alignment_draft_payload()
		)
		if bool(result.get("ok", false)):
			_active_monster_draft_loaded = true
			_monster_saved_selection = _current_monster_selection()
		_update_status(
			"怪物 #%d 对齐草稿已单独保存：%s；尚未写入正式运行时。"
			% [_active_monster_id, str(result.get("path", ""))]
			if bool(result.get("ok", false))
			else "怪物对齐草稿保存失败：%s" % str(result.get("error", ""))
		)
		return
	var path := ProjectSettings.globalize_path(ALIGNMENT_DRAFT_PATH)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		path.get_base_dir()
	)
	if directory_error != OK:
		_update_status(
			"对齐草稿目录创建失败：%s" % error_string(directory_error)
		)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_update_status("对齐草稿保存失败：%s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(alignment_draft_payload(), "\t") + "\n")
	file.close()
	_update_status(
		(
			"对齐草稿已保存：%s；当前参数已匹配正式运行时。"
			if _current_alignment_matches_formal()
			else "对齐草稿已保存：%s；等待接入正式运行时。"
		)
		% ALIGNMENT_DRAFT_PATH
	)


func _load_alignment_draft() -> void:
	var path := ProjectSettings.globalize_path(ALIGNMENT_DRAFT_PATH)
	if not FileAccess.file_exists(path):
		_reset_visual_alignment()
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = (
		JSON.parse_string(file.get_as_text()) if file != null else null
	)
	if (
		not parsed is Dictionary
		or str(parsed.get("contractId", "")) != ALIGNMENT_DRAFT_CONTRACT_ID
	):
		_reset_visual_alignment()
		return
	var draft_origin := _vector2_from_array(
		parsed.get("runtimeVisualOrigin", []), _runtime_visual_origin
	)
	var draft_offset := _vector2_from_array(
		parsed.get("visualOffset", []), Vector2.ZERO
	)
	var draft_foot_adjustment := _vector2_from_array(
		parsed.get("visualFootAnchorAdjustment", []),
		_runtime_foot_anchor_adjustment
	)
	var draft_already_formal := (
		(draft_origin + draft_offset).is_equal_approx(
			_runtime_visual_origin
		)
		and draft_foot_adjustment.is_equal_approx(
			_runtime_foot_anchor_adjustment
		)
	)
	if draft_already_formal:
		_reset_visual_alignment()
	else:
		_visual_foot_anchor_adjustment = draft_foot_adjustment
		_set_visual_alignment_offset(draft_offset)


func _load_monster_alignment_draft() -> void:
	_active_monster_draft_loaded = false
	var draft := MonsterDraftScript.load_draft(_active_monster_id)
	if draft.is_empty():
		return
	_active_monster_draft_loaded = true
	_restore_monster_alignment_draft(draft)


func monster_ground_review_snapshot() -> Dictionary:
	if _monster == null or _monster.visual == null:
		return {}
	var actor_origin := Vector2.ZERO
	var manual_foot := _visual_foot_origin()
	var runtime_ring := _monster.ground_indicator_center()
	var projection_strategy := _monster.visual.ground_projection_strategy()
	var expected_target := (
		_monster.visual.position
		+ _monster.visual.ground_contact_offset()
		if projection_strategy in ["flying", "hover"]
		else actor_origin
	)
	var manual_delta := manual_foot - actor_origin
	var runtime_target_delta := runtime_ring - expected_target
	var target_matches := (
		runtime_target_delta.length() <= MONSTER_FOOT_MATCH_EPSILON
	)
	var manual_matches := (
		manual_delta.length() <= MONSTER_FOOT_MATCH_EPSILON
	)
	var current_selection := _current_monster_selection()
	var pose_matches := (
		current_selection == _monster_saved_selection
	)
	return {
		"monsterId": _active_monster_id,
		"draftLoaded": _active_monster_draft_loaded,
		"projectionStrategy": projection_strategy,
		"actorGroundOrigin": actor_origin,
		"manualFootCenter": manual_foot,
		"expectedTargetCenter": expected_target,
		"runtimeRingCenter": runtime_ring,
		"runtimeRingRadii": _monster.ground_indicator_radii(),
		"manualFootDelta": manual_delta,
		"runtimeTargetDelta": runtime_target_delta,
		"delta": runtime_ring - manual_foot,
		"targetMatchesContract": target_matches,
		"manualFootMatchesActorOrigin": manual_matches,
		"calibrationSelection": _monster_saved_selection.duplicate(true),
		"currentSelection": current_selection,
		"poseMatchesCalibration": pose_matches,
		"matches": (
			target_matches
			and (
				manual_matches
				if projection_strategy == "grounded"
				else true
			)
		),
	}


func _restore_monster_alignment_draft(draft: Dictionary) -> void:
	# A saved draft is the frozen result of the user's manual calibration.
	# Replay that exact snapshot instead of reconstructing it from a later
	# runtime composite, including after formal import.
	_monster_runtime_visual_origin = _vector2_from_array(
		draft.get("runtimeVisualOrigin", []),
		_monster_runtime_visual_origin,
	)
	_monster_visual_alignment_offset = _vector2_from_array(
		draft.get("visualOffset", []), Vector2.ZERO
	)
	_monster_picked_visual_foot_offset = _vector2_from_array(
		draft.get("pickedVisualFootOffset", []),
		_monster_formal_visual_foot_offset,
	)
	var selection: Variant = draft.get("selection", {})
	if not selection is Dictionary:
		return
	_monster_saved_selection = _normalized_monster_selection(selection)
	_apply_monster_selection(_monster_saved_selection)
	_clock = float(_current_frame) / _action_fps(_selected_action())


func _current_monster_selection() -> Dictionary:
	return {
		"action": _selected_action(),
		"direction": _direction_option.selected,
		"frame": _current_frame,
	}


func _normalized_monster_selection(value: Variant) -> Dictionary:
	var selection: Dictionary = value if value is Dictionary else {}
	var action := str(selection.get("action", "idle"))
	if not action in MONSTER_ACTIONS:
		action = "idle"
	return {
		"action": action,
		"direction": clampi(
			int(selection.get("direction", 0)), 0, DIRECTIONS.size() - 1
		),
		"frame": maxi(0, int(selection.get("frame", 0))),
	}


func _apply_monster_selection(selection: Dictionary) -> void:
	var normalized := _normalized_monster_selection(selection)
	_action_option.select(
		maxi(0, MONSTER_ACTIONS.find(str(normalized.action)))
	)
	_direction_option.select(int(normalized.direction))
	_current_frame = int(normalized.frame)


func _monster_selection_label(value: Variant) -> String:
	var selection := _normalized_monster_selection(value)
	var action_index := MONSTER_ACTIONS.find(str(selection.action))
	return "%s/%s/帧%d" % [
		MONSTER_ACTION_LABELS[maxi(0, action_index)],
		DIRECTION_LABELS[int(selection.direction)],
		int(selection.frame) + 1,
	]


func _vector2_from_array(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


func _reload_runtime_art() -> void:
	if _is_monster_mode():
		MonsterVisual.reset_client_resource_cache()
		_rebuild_monster_actor(true)
		_update_frame_limits()
		_apply_preview_frame()
		_update_status(
			"已重新读取当前怪物正式素材，并恢复该 monster_id 的独立草稿。"
		)
		return
	_player.visual._refresh_equipment_visuals()
	_apply_preview_frame()
	_update_status("已重新读取正式运行时素材；未写入任何校准或存档数据。")


func _save_screenshot() -> void:
	var result := save_current_preview()
	_update_status(
		"截图已保存：%s" % str(result.path)
		if bool(result.ok)
		else "截图保存失败：%s" % str(result.error)
	)


func save_current_preview(path_override := "") -> Dictionary:
	var output_dir := ProjectSettings.globalize_path(
		"res://outputs/visual_acceptance"
	)
	var error := DirAccess.make_dir_recursive_absolute(output_dir)
	if error != OK:
		return {
			"ok": false,
			"path": "",
			"error": "截图目录创建失败：%s" % error_string(error),
		}
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var subject := (
		"monster_%d" % _active_monster_id
		if _is_monster_mode()
		else "player"
	)
	var file_name := "%s_%s_%s_f%02d_%s.png" % [
		subject,
		_selected_action(),
		DIRECTION_LABELS[_direction_option.selected].to_lower(),
		_current_frame,
		timestamp,
	]
	var path := (
		ProjectSettings.globalize_path(path_override)
		if not path_override.is_empty()
		else output_dir.path_join(file_name)
	)
	var image := _viewport.get_texture().get_image()
	if image == null:
		return {
			"ok": false,
			"path": path,
			"error": "当前渲染驱动不支持截图；请从本地验收台窗口执行截图。",
		}
	error = image.save_png(path)
	return {
		"ok": error == OK,
		"path": path,
		"error": "" if error == OK else error_string(error),
	}


func _frame_count() -> int:
	if _is_monster_mode():
		if _monster == null or _monster.visual == null:
			return 1
		return maxi(
			1,
			MonsterAnimationPolicy.frame_count(
				_monster.visual.active_resources,
				StringName(_selected_action()),
			),
		)
	if _player == null or _player.visual == null:
		return 1
	return maxi(1, _player.visual._frame_count_for_action(_selected_action()))


func _selected_action() -> String:
	return (
		MONSTER_ACTIONS[_action_option.selected]
		if _is_monster_mode()
		else ACTIONS[_action_option.selected]
	)


func _selected_speed() -> float:
	return float(SPEEDS[_speed_option.selected])


func _action_fps(action: String) -> float:
	return 12.0 if action in ["attack", "cast", "hit", "death"] else (
		10.0 if action == "walk" else 6.0
	)


func _on_selection_changed(_index: int) -> void:
	_apply_selection()


func _on_mode_changed(_index: int) -> void:
	_current_frame = 0
	_clock = 0.0
	_foot_pick_button.set_pressed_no_signal(false)
	_alignment_button.set_pressed_no_signal(false)
	_foot_pick_mode = false
	_alignment_mode = false
	_profession_option.get_parent().visible = not _is_monster_mode()
	_monster_option.get_parent().visible = _is_monster_mode()
	_replace_action_options(
		MONSTER_ACTION_LABELS if _is_monster_mode() else ACTION_LABELS
	)
	if _player != null:
		_player.visible = not _is_monster_mode()
	if _monster != null:
		_monster.visible = _is_monster_mode()
	_apply_selection()


func _on_monster_changed(_index: int) -> void:
	if not _is_monster_mode():
		return
	_active_monster_id = -1
	_apply_selection()


func _on_speed_changed(_index: int) -> void:
	_clock = float(_current_frame) / _action_fps(_selected_action())
	_update_status()


func _on_background_changed(index: int) -> void:
	_background.color = [
		Color("#161c22"), Color("#b6bdc4"), Color("#0a8f3c"),
	][index]


func _on_frame_changed(value: float) -> void:
	_playing = false
	_play_button.text = "播放"
	_current_frame = int(value)
	_apply_preview_frame()


func _on_zoom_changed(value: float) -> void:
	_preview_root.scale = Vector2.ONE * value
	_update_status()


func _on_overlay_toggled(_pressed: bool) -> void:
	_update_overlay()


func _is_monster_mode() -> bool:
	return _mode_option != null and _mode_option.selected == 1


func _active_visual_available() -> bool:
	if _is_monster_mode():
		return _monster != null and _monster.visual != null
	return _player != null and _player.visual != null


func _selected_monster_row() -> Dictionary:
	if _monster_rows.is_empty() or _monster_option == null:
		return {}
	return _monster_rows[
		clampi(_monster_option.selected, 0, _monster_rows.size() - 1)
	]


func _monster_option_labels() -> Array:
	var labels: Array = []
	for row: Dictionary in _monster_rows:
		labels.append(
			"#%d　%s" % [
				int(row.get("monster_id", -1)),
				str(row.get("name", "")),
			]
		)
	return labels


func _replace_action_options(labels: Array) -> void:
	_action_option.clear()
	for label: Variant in labels:
		_action_option.add_item(str(label))
	_action_option.select(0)


func _add_option(parent: VBoxContainer, label_text: String, items: Array) -> OptionButton:
	var row := _labelled_row(parent, label_text)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: Variant in items:
		option.add_item(str(item))
	row.add_child(option)
	return option


func _labelled_row(parent: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(82, 0)
	row.add_child(label)
	return row


func _button(text_value: String) -> Button:
	var result := Button.new()
	result.text = text_value
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


func _add_cross(parent: Node2D, center: Vector2, color: Color, radius: float) -> void:
	_add_line(
		parent,
		PackedVector2Array([
			center + Vector2(-radius, 0), center + Vector2(radius, 0),
		]),
		color,
		1.5
	)
	_add_line(
		parent,
		PackedVector2Array([
			center + Vector2(0, -radius), center + Vector2(0, radius),
		]),
		color,
		1.5
	)


func _add_rect_line(
	parent: Node2D,
	rect: Rect2,
	color: Color,
	width: float
) -> void:
	_add_closed_line(parent, PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]), color, width)


func _add_ellipse_line(
	parent: Node2D,
	center: Vector2,
	radii: Vector2,
	color: Color,
	width: float,
) -> void:
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(
			center
			+ Vector2(
				cos(angle) * radii.x,
				sin(angle) * radii.y,
			)
		)
	_add_closed_line(parent, points, color, width)


func _add_closed_line(
	parent: Node2D,
	points: PackedVector2Array,
	color: Color,
	width: float
) -> void:
	var closed := points.duplicate()
	if not closed.is_empty():
		closed.append(closed[0])
	_add_line(parent, closed, color, width)


func _add_line(
	parent: Node,
	points: PackedVector2Array,
	color: Color,
	width: float
) -> void:
	var line := Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.antialiased = false
	parent.add_child(line)
