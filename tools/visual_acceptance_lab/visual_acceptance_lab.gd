extends Control

const MonsterDraftScript := preload(
	"res://scripts/monster_ground_alignment_draft.gd"
)
const MonsterGroundSpikeEffectScript := preload(
	"res://scripts/monster_ground_spike_effect.gd"
)
const ACTIONS := ["idle", "walk", "attack", "cast", "hit", "death"]
const ACTION_LABELS := ["站立", "行走", "攻击", "施法", "受击", "死亡"]
const MONSTER_ACTIONS := ["idle", "walk", "attack", "hit", "death"]
const MONSTER_ACTION_LABELS := ["站立", "行走", "攻击", "受击", "死亡"]
const WARRIOR_SKILL_ACTIONS := [
	"attack",
	"攻杀剑术",
	"刺杀剑术",
	"半月弯刀",
	"烈火剑法",
	"野蛮冲撞",
]
const WARRIOR_SKILL_ACTION_LABELS := [
	"普通攻击",
	"攻杀剑术",
	"刺杀剑术",
	"半月弯刀",
	"烈火剑法",
	"野蛮冲撞",
]
const WARRIOR_SKILL_FILE_KEYS := {
	"attack": "normal_attack",
	"攻杀剑术": "slaying",
	"刺杀剑术": "thrusting",
	"半月弯刀": "half_moon",
	"烈火剑法": "fire_sword",
	"野蛮冲撞": "wild_rush",
}
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
const WARRIOR_SKILL_LAB_CONTRACT_ID := (
	"local.visual_acceptance_lab.warrior_skill_runtime.v1"
)
const WARRIOR_SKILL_BODY_ACTION := "attack"
const WARRIOR_SKILL_EXPECTED_FRAMES := 6
const WARRIOR_CONTACT_CELL_SIZE := Vector2i(240, 180)
const WARRIOR_CONTACT_OUTPUT_DIR := (
	"res://outputs/visual_acceptance/warrior_skill_audit"
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
const WARRIOR_SKILL_REVIEW_ARG := "--warrior-skill-review"
const MONSTER_ID_ARG_PREFIX := "--monster-id="
const GROUND_SPIKE_REVIEW_ARG := "--fixed-area-ground-spike-review"
const FIXED_AREA_GROUND_SPIKE_MONSTER_IDS := [180, 195]
const GROUND_SPIKE_TARGET_OFFSET := Vector2(105.0, 28.0)
const MONSTER_FOOT_MATCH_EPSILON := 0.01
const RUNTIME_TARGET_RING_OVERLAY_NAME := "RuntimeTargetRingOverlay"
const RUNTIME_TARGET_RING_COLOR := Color(1.0, 0.78, 0.18, 0.78)
const RUNTIME_TARGET_RING_WIDTH := 2.0

var _old_test_mode := false
var _player: PlayerCharacter
var _monster: EnemyActor
var _ground_spike_preview: Node2D
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
var _alignment_actions: HBoxContainer
var _align_center_button: Button
var _reset_alignment_button: Button
var _save_alignment_button: Button
var _warrior_skill_controls: VBoxContainer
var _body_layer_button: CheckButton
var _weapon_layer_button: CheckButton
var _main_effect_layer_button: CheckButton
var _passive_effect_layer_button: CheckButton
var _warrior_contact_button: Button
var _warrior_audit_label: Label
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
	var requested_monster_id := monster_id_from_args(OS.get_cmdline_user_args())
	if OS.get_cmdline_user_args().has(WARRIOR_SKILL_REVIEW_ARG):
		if DisplayServer.get_name() != "headless":
			get_window().title = "HardCore 战士技能动画验收"
		_mode_option.select(2)
		_on_mode_changed(2)
	elif (
		OS.get_cmdline_user_args().has(MONSTER_GROUND_REVIEW_ARG)
		or OS.get_cmdline_user_args().has(GROUND_SPIKE_REVIEW_ARG)
		or requested_monster_id > 0
	):
		if DisplayServer.get_name() != "headless":
			get_window().title = (
				"HardCore 赤月 / 千年树妖地刺攻击验收"
				if OS.get_cmdline_user_args().has(GROUND_SPIKE_REVIEW_ARG)
				else "HardCore 怪物脚点 / 黄色光圈验收"
			)
		_mode_option.select(1)
		_on_mode_changed(1)
		if requested_monster_id > 0:
			_select_monster_id(requested_monster_id)
		if OS.get_cmdline_user_args().has(GROUND_SPIKE_REVIEW_ARG):
			_action_option.select(2)
			_on_selection_changed(2)
	else:
		_apply_selection()
	_start_playback_timer()


static func monster_id_from_args(args: Variant) -> int:
	var expect_value := false
	for raw_arg: Variant in args:
		var arg := str(raw_arg)
		if expect_value:
			expect_value = false
			if arg.is_valid_int():
				var separated_id := int(arg)
				return separated_id if separated_id > 0 else -1
			continue
		if arg == "--monster-id" or arg == "-monster-id":
			expect_value = true
			continue
		if arg.begins_with(MONSTER_ID_ARG_PREFIX):
			var inline_id := int(arg.trim_prefix(MONSTER_ID_ARG_PREFIX))
			return inline_id if inline_id > 0 else -1
	return -1


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
	subtitle.text = "正式运行时只读；仅保存 outputs 验收图 / 对齐草稿"
	subtitle.modulate = Color("#9fb0bf")
	controls.add_child(subtitle)
	controls.add_child(HSeparator.new())

	_mode_option = _add_option(controls, "检测对象", [
		"人物", "怪物", "战士技能",
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

	_warrior_skill_controls = VBoxContainer.new()
	_warrior_skill_controls.visible = false
	_warrior_skill_controls.add_theme_constant_override("separation", 6)
	controls.add_child(_warrior_skill_controls)
	var layer_title := Label.new()
	layer_title.text = "技能合成分层（只读）"
	layer_title.modulate = Color("#f0ca78")
	_warrior_skill_controls.add_child(layer_title)
	var primary_layers := HBoxContainer.new()
	primary_layers.add_theme_constant_override("separation", 8)
	_warrior_skill_controls.add_child(primary_layers)
	_body_layer_button = CheckButton.new()
	_body_layer_button.text = "人物主体"
	_body_layer_button.button_pressed = true
	primary_layers.add_child(_body_layer_button)
	_weapon_layer_button = CheckButton.new()
	_weapon_layer_button.text = "武器"
	_weapon_layer_button.button_pressed = true
	primary_layers.add_child(_weapon_layer_button)
	var effect_layers := HBoxContainer.new()
	effect_layers.add_theme_constant_override("separation", 8)
	_warrior_skill_controls.add_child(effect_layers)
	_main_effect_layer_button = CheckButton.new()
	_main_effect_layer_button.text = "主技能特效"
	_main_effect_layer_button.button_pressed = true
	effect_layers.add_child(_main_effect_layer_button)
	_passive_effect_layer_button = CheckButton.new()
	_passive_effect_layer_button.text = "强制攻杀叠加"
	_passive_effect_layer_button.button_pressed = false
	effect_layers.add_child(_passive_effect_layer_button)
	_warrior_contact_button = _button("生成八方向 × 六帧总览")
	_warrior_contact_button.pressed.connect(_save_warrior_contact_sheet)
	_warrior_skill_controls.add_child(_warrior_contact_button)
	_warrior_audit_label = Label.new()
	_warrior_audit_label.text = (
		"主特效与攻杀触发层可独立开关；总览图只写入 outputs。"
	)
	_warrior_audit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warrior_audit_label.modulate = Color("#9fb0bf")
	_warrior_skill_controls.add_child(_warrior_audit_label)

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
	_alignment_actions = HBoxContainer.new()
	_alignment_actions.add_theme_constant_override("separation", 8)
	controls.add_child(_alignment_actions)
	_align_center_button = _button("脚点对齐中心")
	_align_center_button.pressed.connect(_align_visual_foot_to_standard)
	_alignment_actions.add_child(_align_center_button)
	_reset_alignment_button = _button("恢复运行时")
	_reset_alignment_button.pressed.connect(_reset_visual_alignment)
	_alignment_actions.add_child(_reset_alignment_button)
	_save_alignment_button = _button("保存对齐草稿")
	_save_alignment_button.pressed.connect(_save_alignment_draft)
	controls.add_child(_save_alignment_button)
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
	_body_layer_button.toggled.connect(_on_warrior_layer_toggled)
	_weapon_layer_button.toggled.connect(_on_warrior_layer_toggled)
	_main_effect_layer_button.toggled.connect(_on_warrior_layer_toggled)
	_passive_effect_layer_button.toggled.connect(
		_on_warrior_layer_toggled
	)


func _build_preview_actor() -> void:
	_player = PlayerCharacter.new()
	_player.name = "AcceptancePlayer"
	_preview_root.add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	if _player.health_bar != null:
		_player.health_bar.visible = false
	# Resolve the same normalized equipment/body anchor used by the APK before
	# freezing the validator actor's processing.
	_player.visual._process(0.0)
	_player.visual.set_process(false)
	_runtime_visual_origin = _player.visual.position
	_load_formal_alignment_contract()
	_ground_spike_preview = MonsterGroundSpikeEffectScript.create_visual({
		"effect_id": MonsterGroundSpikeEffectScript.EFFECT_ID,
		"release_id": "visual-acceptance-ground-spike",
		"target_world_px": Vector2.ZERO,
	})
	_ground_spike_preview.name = "FixedAreaGroundSpikePreview"
	_preview_root.add_child(_ground_spike_preview)
	_ground_spike_preview.set_process(false)
	_ground_spike_preview.visible = false
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
	PlayerState.profession = (
		"战士"
		if _is_warrior_skill_mode()
		else ProfessionRules.PROFESSION_CATALOG.values()[
			_profession_option.selected
		]
	)
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
	if _is_warrior_skill_mode():
		_apply_forced_passive_proc_state(visual, frame_count)
	else:
		_clear_forced_passive_proc_state(visual)
	visual._process(0.0)
	if _is_warrior_skill_mode():
		_apply_warrior_audit_layers(visual)
	_update_overlay()
	_update_status()


func _apply_forced_passive_proc_state(
	visual: Node,
	frame_count: int,
) -> void:
	if (
		_passive_effect_layer_button == null
		or not _passive_effect_layer_button.button_pressed
	):
		_clear_forced_passive_proc_state(visual)
		return
	var duration := float(maxi(1, frame_count))
	visual._passive_proc_effect_name = "攻杀剑术"
	visual._passive_proc_effect_duration = duration
	visual._passive_proc_effect_remaining = maxf(
		0.01,
		duration - float(_current_frame) - 0.01,
	)


func _clear_forced_passive_proc_state(visual: Node) -> void:
	if visual == null:
		return
	visual._passive_proc_effect_name = ""
	visual._passive_proc_effect_duration = 0.0
	visual._passive_proc_effect_remaining = 0.0
	if visual.passive_proc_effect_sprite != null:
		visual.passive_proc_effect_sprite.visible = false


func _apply_warrior_audit_layers(visual: Node) -> void:
	var show_body := _body_layer_button.button_pressed
	for layer: CanvasItem in [
		visual.sprite,
		visual.worn_hair_sprite,
		visual.worn_helmet_back_sprite,
		visual.worn_helmet_sprite,
		visual.head_occlusion_mask_sprite,
		visual.armor_accent,
		visual.helmet_accent,
	]:
		if layer != null:
			layer.visible = layer.visible and show_body
	if visual.worn_weapon_sprite != null:
		visual.worn_weapon_sprite.visible = (
			visual.worn_weapon_sprite.visible
			and _weapon_layer_button.button_pressed
		)
	if visual.weapon_accent != null:
		visual.weapon_accent.visible = (
			visual.weapon_accent.visible
			and _weapon_layer_button.button_pressed
		)
	if visual.skill_effect_sprite != null:
		visual.skill_effect_sprite.visible = (
			visual.skill_effect_sprite.visible
			and _main_effect_layer_button.button_pressed
		)
	if visual.skill_effect != null:
		visual.skill_effect.visible = (
			visual.skill_effect.visible
			and _main_effect_layer_button.button_pressed
		)
	if visual.passive_proc_effect_sprite != null:
		visual.passive_proc_effect_sprite.visible = (
			visual.passive_proc_effect_sprite.visible
			and _passive_effect_layer_button.button_pressed
		)


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
	var body_frame_count := maxi(
		1,
		MonsterAnimationPolicy.frame_count(
			visual.active_resources,
			StringName(action),
		),
	)
	var body_frame := mini(_current_frame, body_frame_count - 1)
	visual.current_frame = body_frame
	visual.sprite.texture = visual.active_resources.get(action)
	visual.sprite.region_rect = Rect2(
		body_frame * visual.frame_size.x,
		visual.current_direction * visual.frame_size.y,
		visual.frame_size.x,
		visual.frame_size.y,
	)
	_apply_ground_spike_preview_frame()
	_update_overlay()
	_update_status()


func _apply_ground_spike_preview_frame() -> void:
	if _ground_spike_preview == null:
		return
	var show_spike := _fixed_area_ground_spike_preview_active()
	_ground_spike_preview.visible = show_spike
	if _is_monster_mode():
		_player.visible = show_spike
	if not show_spike:
		return
	_player.position = GROUND_SPIKE_TARGET_OFFSET
	_player.velocity = Vector2.ZERO
	_ground_spike_preview.position = _preview_root.to_local(
		_player.approved_ground_footpoint_world_px()
	)
	_ground_spike_preview.call(
		"_set_frame",
		mini(_current_frame, MonsterGroundSpikeEffectScript.FRAME_COUNT - 1)
	)


func _fixed_area_ground_spike_preview_active() -> bool:
	return (
		_is_monster_mode()
		and _active_monster_id in FIXED_AREA_GROUND_SPIKE_MONSTER_IDS
		and _selected_action() == "attack"
	)


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
	# EnemyActor protects the game from invalid overlapping spawns by moving a
	# newly created monster away from its target. The original calibration lab's
	# deterministic S displacement is now normalized inside MonsterVisual:
	# preview the real actor at (0,0), add that displacement to the visual root,
	# and subtract it from the visual-foot vector. This preserves every frozen
	# draft field while making the lab and the game use the same transform chain.
	_monster.position = Vector2.ZERO
	_monster.set_process(false)
	_monster.set_physics_process(false)
	_monster.velocity = Vector2.ZERO
	# The acceptance lab previews authored frames directly. Boss emergence and
	# burrow mechanics remain active in the game, but must not hide those frames
	# while the user is inspecting animation and ground alignment.
	_monster._burrowed = false
	_monster.dormant = false
	# Calibration review deliberately uses the same selected state as gameplay.
	# MonsterVisual therefore owns the yellow ring through its normal _draw path;
	# the lab overlay below is limited to the human foot/collision/map guides.
	_monster.set_targeted(true)
	if _monster.visual != null:
		_monster.visual.set_process(false)
		_monster.visual.visible = true
	if _monster.overhead != null:
		_monster.overhead.visible = false
	_active_monster_id = monster_id
	_monster_runtime_visual_origin = (
		_monster.visual.position
		- _monster_manual_replay_displacement()
	)
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
	_apply_monster_visual_position()
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
		foot_origin, ArtSpec.PLAYER_COLLISION_RADIUS_PX
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
	if _is_warrior_skill_mode():
		if (
			visual.skill_effect_sprite != null
			and visual.skill_effect_sprite.visible
		):
			_add_rect_line(
				_overlay_root,
				Rect2(
					visual.position + visual.skill_effect_sprite.position,
					visual.skill_effect_sprite.region_rect.size,
				),
				Color("#66e3ff"),
				1.0,
			)
		if (
			visual.passive_proc_effect_sprite != null
			and visual.passive_proc_effect_sprite.visible
		):
			_add_rect_line(
				_overlay_root,
				Rect2(
					visual.position
						+ visual.passive_proc_effect_sprite.position,
					visual.passive_proc_effect_sprite.region_rect.size,
				),
				Color("#ffb347"),
				1.0,
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
	var runtime_ring_center := _visual_foot_origin()
	var runtime_ring_radii := _monster.ground_indicator_radii()
	_draw_canonical_ground_overlay(
		runtime_ring_center, _monster.collision_radius_px
	)
	_draw_runtime_target_ring_overlay(
		runtime_ring_center, runtime_ring_radii
	)
	if _fixed_area_ground_spike_preview_active() and _player != null:
		# Reuse the exact point from the original approved player draft. This
		# cyan cross stays above the effect so visual acceptance is unambiguous.
		_add_cross(
			_overlay_root,
			_preview_root.to_local(
				_player.approved_ground_footpoint_world_px()
			),
			Color("#4de1ff"),
			11.0,
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


func _draw_runtime_target_ring_overlay(
	center: Vector2,
	radii: Vector2,
) -> void:
	if _overlay_root == null:
		return
	# _update_overlay() normally clears all diagnostic children first. Remove a
	# queued prior ring as well so repeated updates never expose two named rings
	# in the same frame.
	for child: Node in _overlay_root.get_children():
		if child.name == RUNTIME_TARGET_RING_OVERLAY_NAME:
			child.free()
	var ring := Line2D.new()
	ring.name = RUNTIME_TARGET_RING_OVERLAY_NAME
	ring.default_color = RUNTIME_TARGET_RING_COLOR
	ring.width = RUNTIME_TARGET_RING_WIDTH
	ring.antialiased = true
	ring.set_meta("center", center)
	ring.set_meta("radii", radii)
	ring.set_meta("source", "monster_visual_runtime_target_ring")
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(
			center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
		)
	ring.points = points
	_overlay_root.add_child(ring)


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
	var footprint := WorldSpatialRules.actor_footprint_polygon_px(
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
	if _is_warrior_skill_mode():
		var audit := warrior_skill_audit_snapshot()
		var main_text := (
			"%s / 源帧 #%d" % [
				str(audit.get("mainEffectAsset", "")),
				int(audit.get("sourceIndex", -1)),
			]
			if bool(audit.get("mainEffectSupported", false))
			else "无独立正式特效（仅人物动作）"
		)
		var passive_text := (
			"强制同帧显示"
			if bool(audit.get("passiveEffectVisible", false))
			else "关闭"
		)
		var fire_alignment: Vector2 = audit.get(
			"fireWeaponHeadAlignment", Vector2.ZERO
		)
		var fire_text := (
			"\n烈火武器头-点火点校正=(%+.1f, %+.1f)" % [
				fire_alignment.x,
				fire_alignment.y,
			]
			if str(audit.get("skillAction", "")) == "烈火剑法"
			else ""
		)
		var duplicate_warning := (
			"\n注意：当前同时显示主动攻杀与被动攻杀，用于核对叠层。"
			if (
				str(audit.get("skillAction", "")) == "攻杀剑术"
				and bool(audit.get("passiveEffectVisible", false))
			)
			else ""
		)
		_status.text = (
			"%s　%s / %s　帧 %d/%d　倍率 %dx\n"
			+ "人物动作=attack　主特效=%s　攻杀触发层=%s\n"
			+ "青框=主技能图幅　橙框=攻杀触发图幅"
			+ "%s%s"
		) % [
			WARRIOR_SKILL_LAB_CONTRACT_ID,
			WARRIOR_SKILL_ACTION_LABELS[_action_option.selected],
			DIRECTION_LABELS[_direction_option.selected],
			_current_frame + 1,
			_frame_count(),
			int(_zoom_slider.value),
			main_text,
			passive_text,
			fire_text,
			duplicate_warning,
		]
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
			+ "黄轴=怪物物理原点　青十字=人工视觉脚点　"
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


func warrior_skill_audit_snapshot() -> Dictionary:
	if (
		not _is_warrior_skill_mode()
		or _player == null
		or _player.visual == null
	):
		return {}
	var visual := _player.visual
	var action := _selected_action()
	var direction := _direction_option.selected
	var runtime_effect: Dictionary = visual.CLIENT_EFFECTS.get(action, {})
	var supported := not runtime_effect.is_empty()
	var asset_name := ""
	if supported:
		var assets: Variant = runtime_effect.get("assets", [])
		if assets is Array and not assets.is_empty():
			var directions_per_atlas := int(
				runtime_effect.get("directions_per_atlas", 4)
			)
			var frames_per_atlas := int(
				runtime_effect.get("frames_per_atlas", 3)
			)
			var direction_group := direction / directions_per_atlas
			var frame_group := _current_frame / frames_per_atlas
			asset_name = str(assets[direction_group][frame_group])
		else:
			asset_name = str(runtime_effect.get("asset", ""))
	var source_index := -1
	var source_effects: Variant = GameData.warrior_client_art.get(
		"effects", {}
	)
	if source_effects is Dictionary:
		var source_effect: Variant = source_effects.get(action, {})
		if source_effect is Dictionary:
			var source_frames: Variant = source_effect.get(
				"sourceFrames", []
			)
			var source_offset := direction * _frame_count() + _current_frame
			if (
				source_frames is Array
				and source_offset >= 0
				and source_offset < source_frames.size()
			):
				var source_frame: Variant = source_frames[source_offset]
				if source_frame is Dictionary:
					source_index = int(source_frame.get("index", -1))
	return {
		"contractId": WARRIOR_SKILL_LAB_CONTRACT_ID,
		"skillAction": action,
		"bodyAction": WARRIOR_SKILL_BODY_ACTION,
		"direction": direction,
		"directionLabel": DIRECTION_LABELS[direction],
		"frame": _current_frame,
		"frameCount": _frame_count(),
		"bodyRegion": (
			visual.sprite.region_rect
			if visual.sprite != null
			else Rect2()
		),
		"weaponRegion": (
			visual.worn_weapon_sprite.region_rect
			if visual.worn_weapon_sprite != null
			else Rect2()
		),
		"mainEffectSupported": supported,
		"mainEffectAsset": asset_name,
		"mainEffectVisible": (
			visual.skill_effect_sprite != null
			and visual.skill_effect_sprite.visible
		),
		"mainEffectRegion": (
			visual.skill_effect_sprite.region_rect
			if visual.skill_effect_sprite != null
			else Rect2()
		),
		"mainEffectPosition": (
			visual.skill_effect_sprite.position
			if visual.skill_effect_sprite != null
			else Vector2.ZERO
		),
		"passiveEffectVisible": (
			visual.passive_proc_effect_sprite != null
			and visual.passive_proc_effect_sprite.visible
		),
		"passiveEffectRegion": (
			visual.passive_proc_effect_sprite.region_rect
			if visual.passive_proc_effect_sprite != null
			else Rect2()
		),
		"sourceIndex": source_index,
		"fireWeaponHeadAlignment": (
			visual._fire_weapon_head_alignment()
			if action == "烈火剑法"
			else Vector2.ZERO
		),
		"layers": {
			"body": _body_layer_button.button_pressed,
			"weapon": _weapon_layer_button.button_pressed,
			"mainEffect": _main_effect_layer_button.button_pressed,
			"passiveProc": _passive_effect_layer_button.button_pressed,
		},
	}


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
			- _monster_manual_replay_displacement()
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
			point
			- _monster.visual.position
			+ _monster_manual_replay_displacement()
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
		_apply_monster_visual_position()
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
	if _is_warrior_skill_mode():
		_update_status("战士技能验收模式为只读，不修改人物脚点。")
		return
	if _is_monster_mode():
		_set_visual_alignment_offset(
			_monster_visual_alignment_offset - _visual_foot_origin()
		)
		return
	_set_visual_alignment_offset(
		_visual_alignment_offset - _visual_foot_origin()
	)


func _reset_visual_alignment() -> void:
	if _is_warrior_skill_mode():
		_player.visual.position = (
			_runtime_visual_origin + _visual_alignment_offset
		)
		_apply_preview_frame()
		return
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
	if _is_warrior_skill_mode():
		_alignment_offset_label.text = (
			"只读审核：不写脚点、不写动作、不改正式技能素材。"
		)
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


func _monster_manual_replay_displacement() -> Vector2:
	if _monster == null or _monster.visual == null:
		return Vector2.ZERO
	return _monster.visual.manual_alignment_replay_displacement()


func _apply_monster_visual_position() -> void:
	if _monster == null or _monster.visual == null:
		return
	_monster.visual.position = (
		_monster_runtime_visual_origin
		+ _monster_visual_alignment_offset
		+ _monster_manual_replay_displacement()
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
			_monster.collision_radius_px,
			_monster.collision_radius_px * 0.5,
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
	if _is_warrior_skill_mode():
		_update_status("战士技能验收模式不会写入任何对齐草稿。")
		return
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
	var runtime_layout := _monster.visual.ground_shadow_layout_snapshot()
	return {
		"monsterId": _active_monster_id,
		"draftLoaded": _active_monster_draft_loaded,
		"projectionStrategy": projection_strategy,
		"actorGroundOrigin": actor_origin,
		"manualFootCenter": manual_foot,
		"expectedTargetCenter": expected_target,
		"runtimeRingCenter": runtime_ring,
		"runtimeRingRadii": _monster.ground_indicator_radii(),
		"runtimeSelected": _monster.is_targeted,
		"runtimeRingVisible": bool(runtime_layout.get("ring_visible", false)),
		"runtimeRingOwner": str(runtime_layout.get("owner", "")),
		"runtimeRingMode": str(runtime_layout.get("mode", "")),
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
		else (
			"warrior_skill"
			if _is_warrior_skill_mode()
			else "player"
		)
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


func warrior_contact_sheet_layout() -> Dictionary:
	var frame_count := (
		_frame_count()
		if _is_warrior_skill_mode()
		else WARRIOR_SKILL_EXPECTED_FRAMES
	)
	return {
		"contractId": WARRIOR_SKILL_LAB_CONTRACT_ID,
		"columns": DIRECTION_LABELS.size(),
		"rows": frame_count,
		"columnOrder": DIRECTION_LABELS.duplicate(),
		"rowFrames": range(frame_count),
		"cellSize": WARRIOR_CONTACT_CELL_SIZE,
		"imageSize": Vector2i(
			WARRIOR_CONTACT_CELL_SIZE.x * DIRECTION_LABELS.size(),
			WARRIOR_CONTACT_CELL_SIZE.y * frame_count,
		),
	}


func _save_warrior_contact_sheet() -> void:
	var result := generate_warrior_contact_sheet()
	_update_status(
		"八方向 × 六帧总览已保存：%s" % str(result.get("path", ""))
		if bool(result.get("ok", false))
		else "总览保存失败：%s" % str(result.get("error", ""))
	)


func generate_warrior_contact_sheet(path_override := "") -> Dictionary:
	if not _is_warrior_skill_mode():
		return {
			"ok": false,
			"path": "",
			"error": "请先选择“战士技能”检测对象。",
		}
	var layout := warrior_contact_sheet_layout()
	var frame_count := int(layout.get("rows", 0))
	if frame_count != WARRIOR_SKILL_EXPECTED_FRAMES:
		return {
			"ok": false,
			"path": "",
			"error": (
				"正式攻击动作应为 %d 帧，当前为 %d 帧。"
				% [WARRIOR_SKILL_EXPECTED_FRAMES, frame_count]
			),
		}
	var saved_state := {
		"playing": _playing,
		"clock": _clock,
		"frame": _current_frame,
		"direction": _direction_option.selected,
		"zoom": _zoom_slider.value,
	}
	_playing = false
	_play_button.text = "播放"
	_zoom_slider.set_value_no_signal(1.0)
	_preview_root.scale = Vector2.ONE
	var image_size: Vector2i = layout.get("imageSize", Vector2i.ZERO)
	var sheet := Image.create(
		image_size.x,
		image_size.y,
		false,
		Image.FORMAT_RGBA8,
	)
	sheet.fill(Color("#161c22"))
	for frame_index: int in frame_count:
		for direction_index: int in DIRECTION_LABELS.size():
			_direction_option.select(direction_index)
			_current_frame = frame_index
			_frame_spin.set_value_no_signal(_current_frame)
			_apply_preview_frame()
			RenderingServer.force_draw(false)
			var captured := _viewport.get_texture().get_image()
			if captured == null or captured.is_empty():
				_restore_warrior_contact_state(saved_state)
				return {
					"ok": false,
					"path": "",
					"error": (
						"当前渲染驱动不支持总览截图；"
						+ "请从本地验收台窗口执行。"
					),
				}
			captured.resize(
				WARRIOR_CONTACT_CELL_SIZE.x,
				WARRIOR_CONTACT_CELL_SIZE.y,
				Image.INTERPOLATE_NEAREST,
			)
			sheet.blit_rect(
				captured,
				Rect2i(Vector2i.ZERO, WARRIOR_CONTACT_CELL_SIZE),
				Vector2i(
					direction_index * WARRIOR_CONTACT_CELL_SIZE.x,
					frame_index * WARRIOR_CONTACT_CELL_SIZE.y,
				),
			)
	_restore_warrior_contact_state(saved_state)
	var output_dir := ProjectSettings.globalize_path(
		WARRIOR_CONTACT_OUTPUT_DIR
	)
	var error := DirAccess.make_dir_recursive_absolute(output_dir)
	if error != OK:
		return {
			"ok": false,
			"path": "",
			"error": "总览目录创建失败：%s" % error_string(error),
		}
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var action_key := str(
		WARRIOR_SKILL_FILE_KEYS.get(_selected_action(), "skill")
	)
	var path := (
		ProjectSettings.globalize_path(path_override)
		if not path_override.is_empty()
		else output_dir.path_join(
			"%s_8dir_6frame_%s.png" % [action_key, timestamp]
		)
	)
	error = sheet.save_png(path)
	return {
		"ok": error == OK,
		"path": path,
		"error": "" if error == OK else error_string(error),
	}


func _restore_warrior_contact_state(saved_state: Dictionary) -> void:
	_playing = bool(saved_state.get("playing", false))
	_play_button.text = "暂停" if _playing else "播放"
	_clock = float(saved_state.get("clock", 0.0))
	_direction_option.select(int(saved_state.get("direction", 0)))
	_current_frame = int(saved_state.get("frame", 0))
	_frame_spin.set_value_no_signal(_current_frame)
	var zoom := float(saved_state.get("zoom", 3.0))
	_zoom_slider.set_value_no_signal(zoom)
	_preview_root.scale = Vector2.ONE * zoom
	_apply_preview_frame()


func _frame_count() -> int:
	if _is_monster_mode():
		if _monster == null or _monster.visual == null:
			return 1
		var body_frame_count := maxi(
			1,
			MonsterAnimationPolicy.frame_count(
				_monster.visual.active_resources,
				StringName(_selected_action()),
			),
		)
		return maxi(
			body_frame_count,
			MonsterGroundSpikeEffectScript.FRAME_COUNT,
		) if _fixed_area_ground_spike_preview_active() else body_frame_count
	if _player == null or _player.visual == null:
		return 1
	var action_key := (
		WARRIOR_SKILL_BODY_ACTION
		if _is_warrior_skill_mode()
		else _selected_action()
	)
	return maxi(1, _player.visual._frame_count_for_action(action_key))


func _selected_action() -> String:
	return (
		MONSTER_ACTIONS[_action_option.selected]
		if _is_monster_mode()
		else (
			WARRIOR_SKILL_ACTIONS[_action_option.selected]
			if _is_warrior_skill_mode()
			else ACTIONS[_action_option.selected]
		)
	)


func _selected_speed() -> float:
	return float(SPEEDS[_speed_option.selected])


func _action_fps(action: String) -> float:
	return 12.0 if (
		action in ["attack", "cast", "hit", "death"]
		or action in WARRIOR_SKILL_ACTIONS
	) else (
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
	_profession_option.disabled = _is_warrior_skill_mode()
	if _is_warrior_skill_mode():
		_profession_option.select(0)
	_monster_option.get_parent().visible = _is_monster_mode()
	var action_labels: Array = ACTION_LABELS
	if _is_monster_mode():
		action_labels = MONSTER_ACTION_LABELS
	elif _is_warrior_skill_mode():
		action_labels = WARRIOR_SKILL_ACTION_LABELS
	_replace_action_options(action_labels)
	_warrior_skill_controls.visible = _is_warrior_skill_mode()
	_foot_pick_button.visible = not _is_warrior_skill_mode()
	_alignment_button.visible = not _is_warrior_skill_mode()
	_alignment_actions.visible = not _is_warrior_skill_mode()
	_save_alignment_button.visible = not _is_warrior_skill_mode()
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


func _select_monster_id(monster_id: int) -> bool:
	if _monster_option == null:
		return false
	for row_index in _monster_rows.size():
		if int(_monster_rows[row_index].get("monster_id", -1)) != monster_id:
			continue
		_monster_option.select(row_index)
		_on_monster_changed(row_index)
		return _active_monster_id == monster_id
	_update_status("当前主树目录没有 monster_id=%d。" % monster_id)
	return false


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


func _is_warrior_skill_mode() -> bool:
	return _mode_option != null and _mode_option.selected == 2


func _on_warrior_layer_toggled(_pressed: bool) -> void:
	if not _is_warrior_skill_mode():
		return
	_apply_preview_frame()


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
