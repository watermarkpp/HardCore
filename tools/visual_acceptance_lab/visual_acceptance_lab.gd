extends Control

const ACTIONS := ["idle", "walk", "attack", "cast", "hit", "death"]
const ACTION_LABELS := ["站立", "行走", "攻击", "施法", "受击", "死亡"]
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
const PLAYBACK_TICK_SECONDS := 1.0 / 60.0

var _old_test_mode := false
var _player: PlayerCharacter
var _preview_root: Node2D
var _viewport: SubViewport
var _background: ColorRect
var _grid_root: Node2D
var _overlay_root: Node2D
var _action_option: OptionButton
var _direction_option: OptionButton
var _profession_option: OptionButton
var _speed_option: OptionButton
var _background_option: OptionButton
var _frame_spin: SpinBox
var _zoom_slider: HSlider
var _play_button: Button
var _overlay_button: CheckButton
var _status: Label
var _playback_timer: Timer
var _playing := true
var _clock := 0.0
var _current_frame := 0


func _ready() -> void:
	_old_test_mode = PlayerState.test_mode
	PlayerState.test_mode = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless":
		get_window().min_size = Vector2i(1100, 650)
		get_window().size = Vector2i(1280, 720)
	_build_ui()
	_build_preview_actor()
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
	if not _playing or _player == null or _player.visual == null:
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

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	sidebar.add_child(controls)
	var title := Label.new()
	title.text = "HardCore 本地视觉验收台"
	title.add_theme_font_size_override("font_size", 24)
	controls.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "只读正式运行时素材，不写入校准数据"
	subtitle.modulate = Color("#9fb0bf")
	controls.add_child(subtitle)
	controls.add_child(HSeparator.new())

	_profession_option = _add_option(controls, "职业", [
		"战士", "法师", "道士",
	])
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
	var screenshot := _button("保存当前截图")
	screenshot.pressed.connect(_save_screenshot)
	controls.add_child(screenshot)
	var reload := _button("重新加载当前正式素材")
	reload.pressed.connect(_reload_runtime_art)
	controls.add_child(reload)
	controls.add_spacer(false)

	var shortcuts := Label.new()
	shortcuts.text = "快捷键：空格 播放/暂停\n←/→ 逐帧　↑/↓ 换方向\nF 辅助线　S 截图"
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

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_panel.add_child(viewport_container)
	_viewport = SubViewport.new()
	_viewport.name = "AcceptanceViewport"
	_viewport.size = Vector2i(900, 680)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	viewport_container.add_child(_viewport)
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

	_profession_option.item_selected.connect(_on_selection_changed)
	_action_option.item_selected.connect(_on_selection_changed)
	_direction_option.item_selected.connect(_on_selection_changed)
	_speed_option.item_selected.connect(_on_speed_changed)
	_background_option.item_selected.connect(_on_background_changed)
	_frame_spin.value_changed.connect(_on_frame_changed)
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	_overlay_button.toggled.connect(_on_overlay_toggled)


func _build_preview_actor() -> void:
	_player = PlayerCharacter.new()
	_player.name = "AcceptancePlayer"
	_preview_root.add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	if _player.health_bar != null:
		_player.health_bar.visible = false
	_player.visual.set_process(false)
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
	PlayerState.profession = ProfessionRules.PROFESSION_CATALOG.values()[
		_profession_option.selected
	]
	_player.visual.refresh_profession()
	_current_frame = 0
	_clock = 0.0
	_update_frame_limits()
	_apply_preview_frame()


func _apply_preview_frame() -> void:
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
	if not _overlay_root.visible or _player == null or _player.visual == null:
		return
	var visual := _player.visual
	var body_sprite: Sprite2D = visual.sprite
	var foot_origin := (
		visual.position
		+ body_sprite.position
		+ Vector2(ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR)
	)
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
		ArtSpec.PLAYER_COLLISION_RADIUS, 32
	)
	_add_closed_line(_overlay_root, footprint, Color("#ff5c78"), 1.5)
	var diamond := PackedVector2Array([
		Vector2(0, -16), Vector2(32, 0), Vector2(0, 16), Vector2(-32, 0),
	])
	_add_closed_line(_overlay_root, diamond, Color(0.55, 0.75, 1.0, 0.65), 1.0)
	if body_sprite != null:
		var rect := Rect2(
			visual.position + body_sprite.position,
			Vector2(body_sprite.region_rect.size)
		)
		_add_rect_line(_overlay_root, rect, Color(0.55, 1.0, 0.52, 0.75), 1.0)


func _update_status(message := "") -> void:
	if not message.is_empty():
		_status.text = message
		return
	_status.text = (
		"%s　%s / %s　帧 %d/%d　倍率 %dx\n黄=角色坐标　蓝=视觉脚点　红=物理脚印　绿=当前帧边界"
		% [
			LAB_CONTRACT_ID,
			ACTION_LABELS[_action_option.selected],
			DIRECTION_LABELS[_direction_option.selected],
			_current_frame + 1,
			_frame_count(),
			int(_zoom_slider.value),
		]
	)


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


func _reload_runtime_art() -> void:
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
	var file_name := "player_%s_%s_f%02d_%s.png" % [
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
	if _player == null or _player.visual == null:
		return 1
	return maxi(1, _player.visual._frame_count_for_action(_selected_action()))


func _selected_action() -> String:
	return ACTIONS[_action_option.selected]


func _selected_speed() -> float:
	return float(SPEEDS[_speed_option.selected])


func _action_fps(action: String) -> float:
	return 12.0 if action in ["attack", "cast", "hit", "death"] else (
		10.0 if action == "walk" else 6.0
	)


func _on_selection_changed(_index: int) -> void:
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
