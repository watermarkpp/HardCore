extends Control


const ReviewCanvas := preload(
	"res://tools/map_assets/manual_footprint_review_canvas.gd"
)

const REVIEW_PATH := (
	"res://assets/data/expansions/"
	+ "personal_expansion_001/"
	+ "map_asset_footprint_review_state.json"
)

const REVIEW_CONTRACT_ID := (
	"maps.manual_footprint_review_v1"
)

const STATUS_VERIFIED := "verified"
const STATUS_REWORK := "rework"


var assets: Array[Dictionary] = []
var current_index := -1
var review_state: Dictionary = {}

var preview
var progress_label: Label
var asset_name_label: Label
var asset_id_label: Label
var palette_label: Label
var type_label: Label
var current_fp_label: Label
var base_fp_label: Label
var review_status_label: Label
var message_label: Label

var width_spin: SpinBox
var height_spin: SpinBox
var zoom_slider: HSlider
var filter_option: OptionButton
var search_edit: LineEdit


func _ready() -> void:
	_build_ui()
	_load_review_state()
	_load_assets()

	if assets.is_empty():
		message_label.text = (
			"没有找到当前可摆放素材"
		)
		return

	_seek_first_matching()
	_show_current()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT,
		Control.PRESET_MODE_MINSIZE,
		10
	)
	root.add_theme_constant_override(
		"separation",
		8
	)
	add_child(root)

	var title := Label.new()
	title.text = (
		"地图素材人工初始占位核定工具"
	)
	title.add_theme_font_size_override(
		"font_size",
		20
	)
	root.add_child(title)

	var note := Label.new()
	note.text = (
		"本工具只记录审核草稿，"
		+ "不会修改正式 footprint、地图或素材。"
		+ "黄色菱形为拟确认占位，"
		+ "红点为底部顶点。"
	)
	note.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	root.add_child(note)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)

	progress_label = Label.new()
	progress_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	toolbar.add_child(progress_label)

	filter_option = OptionButton.new()
	filter_option.add_item(
		"仅未核定",
		0
	)
	filter_option.add_item(
		"全部素材",
		1
	)
	filter_option.add_item(
		"仅需返工",
		2
	)
	filter_option.item_selected.connect(
		_on_filter_changed
	)
	toolbar.add_child(filter_option)

	search_edit = LineEdit.new()
	search_edit.placeholder_text = (
		"搜索名称 / asset_id / 分类"
	)
	search_edit.custom_minimum_size.x = 260
	toolbar.add_child(search_edit)

	var search_button := Button.new()
	search_button.text = "搜索"
	search_button.pressed.connect(
		_on_search
	)
	toolbar.add_child(search_button)

	var body := HSplitContainer.new()
	body.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)
	root.add_child(body)

	preview = ReviewCanvas.new()
	preview.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	preview.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)
	body.add_child(preview)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 330
	side.add_theme_constant_override(
		"separation",
		8
	)
	body.add_child(side)

	asset_name_label = Label.new()
	asset_name_label.add_theme_font_size_override(
		"font_size",
		17
	)
	asset_name_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	side.add_child(asset_name_label)

	asset_id_label = Label.new()
	asset_id_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	side.add_child(asset_id_label)

	palette_label = Label.new()
	palette_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	side.add_child(palette_label)

	type_label = Label.new()
	side.add_child(type_label)

	current_fp_label = Label.new()
	side.add_child(current_fp_label)

	base_fp_label = Label.new()
	side.add_child(base_fp_label)

	review_status_label = Label.new()
	side.add_child(review_status_label)

	var width_row := HBoxContainer.new()
	side.add_child(width_row)

	var width_label := Label.new()
	width_label.text = "占位宽："
	width_row.add_child(width_label)

	width_spin = SpinBox.new()
	width_spin.min_value = 1
	width_spin.max_value = 24
	width_spin.step = 1
	width_spin.value_changed.connect(
		_on_footprint_changed
	)
	width_row.add_child(width_spin)

	var height_row := HBoxContainer.new()
	side.add_child(height_row)

	var height_label := Label.new()
	height_label.text = "占位深："
	height_row.add_child(height_label)

	height_spin = SpinBox.new()
	height_spin.min_value = 1
	height_spin.max_value = 24
	height_spin.step = 1
	height_spin.value_changed.connect(
		_on_footprint_changed
	)
	height_row.add_child(height_spin)

	var zoom_label := Label.new()
	zoom_label.text = "查看缩放"
	side.add_child(zoom_label)

	zoom_slider = HSlider.new()
	zoom_slider.min_value = 0.25
	zoom_slider.max_value = 2.5
	zoom_slider.step = 0.05
	zoom_slider.value = 1.0
	zoom_slider.value_changed.connect(
		_on_zoom_changed
	)
	side.add_child(zoom_slider)

	var previous_button := Button.new()
	previous_button.text = "上一个"
	previous_button.pressed.connect(
		func():
			_step(-1)
	)
	side.add_child(previous_button)

	var next_button := Button.new()
	next_button.text = "跳过 / 下一个"
	next_button.pressed.connect(
		func():
			_step(1)
	)
	side.add_child(next_button)

	var verify_button := Button.new()
	verify_button.text = (
		"确认当前占位并下一个"
	)
	verify_button.pressed.connect(
		_on_verify
	)
	side.add_child(verify_button)

	var rework_button := Button.new()
	rework_button.text = (
		"标记需返工并下一个"
	)
	rework_button.pressed.connect(
		_on_rework
	)
	side.add_child(rework_button)

	var clear_button := Button.new()
	clear_button.text = (
		"清除当前审核记录"
	)
	clear_button.pressed.connect(
		_on_clear_current
	)
	side.add_child(clear_button)

	message_label = Label.new()
	message_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	side.add_child(message_label)


func _load_review_state() -> void:
	if not FileAccess.file_exists(
		REVIEW_PATH
	):
		review_state = {
			"contract_id":
				REVIEW_CONTRACT_ID,
			"items": {},
		}
		return

	var file := FileAccess.open(
		REVIEW_PATH,
		FileAccess.READ
	)

	if file == null:
		review_state = {
			"contract_id":
				REVIEW_CONTRACT_ID,
			"items": {},
		}
		return

	var parsed: Variant = JSON.parse_string(
		file.get_as_text()
	)

	if not parsed is Dictionary:
		review_state = {
			"contract_id":
				REVIEW_CONTRACT_ID,
			"items": {},
		}
		return

	review_state = parsed

	if str(
		review_state.get(
			"contract_id",
			""
		)
	) != REVIEW_CONTRACT_ID:
		review_state = {
			"contract_id":
				REVIEW_CONTRACT_ID,
			"items": {},
		}

	if not review_state.has("items"):
		review_state["items"] = {}


func _load_assets() -> void:
	MapAssetCatalogService.invalidate_cache()

	assets.clear()

	for raw: Dictionary in (
		MapAssetCatalogService.all_assets()
	):
		if not bool(
			raw.get(
				"placeable",
				false
			)
		):
			continue

		var image_path := str(
			raw.get("image", "")
		)

		if image_path.is_empty():
			continue

		assets.append(
			raw.duplicate(true)
		)

	assets.sort_custom(
		_asset_less
	)

	_refresh_progress()


func _asset_less(
	a: Dictionary,
	b: Dictionary
) -> bool:
	var a_key := (
		str(a.get("palette_path", ""))
		+ "|"
		+ str(a.get("display_name", ""))
		+ "|"
		+ str(a.get("asset_id", ""))
	)

	var b_key := (
		str(b.get("palette_path", ""))
		+ "|"
		+ str(b.get("display_name", ""))
		+ "|"
		+ str(b.get("asset_id", ""))
	)

	return (
		a_key.naturalnocasecmp_to(
			b_key
		) < 0
	)


func _asset_fingerprint_fields(
	asset: Dictionary
) -> Dictionary:
	return {
		"image":
			str(
				asset.get(
					"image",
					""
				)
			),
		"source_sha256":
			str(
				asset.get(
					"source_sha256",
					""
				)
			),
		"output_sha256":
			str(
				asset.get(
					"output_sha256",
					""
				)
			),
	}


func _review_item(
	asset: Dictionary
) -> Dictionary:
	var items: Dictionary = (
		review_state.get(
			"items",
			{}
		)
	)

	var asset_id := str(
		asset.get("asset_id", "")
	)

	var item: Variant = items.get(
		asset_id,
		{}
	)

	if not item is Dictionary:
		return {}

	var item_dict: Dictionary = item

	var fingerprint := (
		_asset_fingerprint_fields(
			asset
		)
	)

	for key: String in [
		"image",
		"source_sha256",
		"output_sha256",
	]:
		if str(
			item_dict.get(
				key,
				""
			)
		) != str(
			fingerprint.get(
				key,
				""
			)
		):
			return {}

	return item_dict


func _asset_status(
	asset: Dictionary
) -> String:
	var item := _review_item(asset)

	if item.is_empty():
		return "pending"

	var status := str(
		item.get(
			"status",
			"pending"
		)
	)

	if status not in [
		STATUS_VERIFIED,
		STATUS_REWORK,
	]:
		return "pending"

	return status


func _matches_filter(
	asset: Dictionary
) -> bool:
	var mode := filter_option.selected
	var status := _asset_status(asset)

	if mode == 0:
		return status == "pending"

	if mode == 2:
		return status == STATUS_REWORK

	return true


func _seek_first_matching() -> void:
	current_index = -1

	for index in assets.size():
		if _matches_filter(
			assets[index]
		):
			current_index = index
			return


func _step(direction: int) -> void:
	if assets.is_empty():
		return

	var index := current_index

	for _attempt in assets.size():
		index += direction

		if index < 0:
			index = assets.size() - 1

		if index >= assets.size():
			index = 0

		if _matches_filter(
			assets[index]
		):
			current_index = index
			_show_current()
			return

	message_label.text = (
		"当前筛选条件下没有素材"
	)


func _current_asset() -> Dictionary:
	if (
		current_index < 0
		or current_index >= assets.size()
	):
		return {}

	return assets[current_index]


func _review_footprint_for(
	asset: Dictionary
) -> Vector2i:
	var item := _review_item(asset)

	var raw: Array

	if (
		not item.is_empty()
		and item.has(
			"footprint_tiles"
		)
	):
		raw = item.get(
			"footprint_tiles",
			[1, 1]
		)
	else:
		raw = asset.get(
			"footprint_tiles",
			[1, 1]
		)

	return Vector2i(
		maxi(1, int(raw[0])),
		maxi(1, int(raw[1]))
	)


func _review_anchor_for(
	asset: Dictionary
) -> Vector2:
	var item := _review_item(asset)

	if not item.is_empty() and item.has("anchor_px"):
		var raw: Array = item.get("anchor_px", [0, 0])
		return Vector2(
			float(raw[0]),
			float(raw[1])
		)

	var raw: Array = asset.get(
		"anchor_px",
		[0, 0]
	)
	return Vector2(
		float(raw[0]),
		float(raw[1])
	)


func _show_current() -> void:
	var asset := _current_asset()

	if asset.is_empty():
		preview.set_review_asset(
			{},
			Vector2i.ONE
		)
		return

	var asset_id := str(
		asset.get("asset_id", "")
	)

	var display_name := str(
		asset.get(
			"display_name",
			asset_id
		)
	)

	asset_name_label.text = display_name
	asset_id_label.text = (
		"asset_id："
		+ asset_id
	)

	palette_label.text = (
		"分类："
		+ str(
			asset.get(
				"palette_path",
				"未分类"
			)
		)
	)

	type_label.text = (
		"类型："
		+ str(
			asset.get(
				"asset_type",
				""
			)
		)
	)

	var current_raw: Array = asset.get(
		"footprint_tiles",
		[1, 1]
	)

	current_fp_label.text = (
		"当前有效占位：%d × %d"
		% [
			int(current_raw[0]),
			int(current_raw[1]),
		]
	)

	var base := (
		MapAssetCatalogService.find_base_asset(
			asset_id
		)
	)

	var base_raw: Array = base.get(
		"footprint_tiles",
		current_raw
	)

	base_fp_label.text = (
		"Catalog 原始占位：%d × %d"
		% [
			int(base_raw[0]),
			int(base_raw[1]),
		]
	)

	var status := _asset_status(asset)

	review_status_label.text = (
		"人工审核状态："
		+ status
	)

	var fp := _review_footprint_for(
		asset
	)

	var anchor := _review_anchor_for(
		asset
	)

	width_spin.set_value_no_signal(
		fp.x
	)
	height_spin.set_value_no_signal(
		fp.y
	)

	var ground_locked := (
		str(
			asset.get(
				"asset_type",
				""
			)
		) == "ground_brush"
	)

	width_spin.editable = (
		not ground_locked
	)
	height_spin.editable = (
		not ground_locked
	)

	if ground_locked:
		width_spin.set_value_no_signal(1)
		height_spin.set_value_no_signal(1)

	preview.set_review_asset(
		asset,
		Vector2i(
			int(width_spin.value),
			int(height_spin.value)
		),
		anchor
	)

	message_label.text = (
		"Enter：确认并下一个；"
		+ "PageUp/PageDown：上一/下一；"
		+ "W/A/S/D：占位；"
		+ "I/J/K/L：锚点；"
		+ "Delete：删除"
	)


func _on_footprint_changed(
	_value: float
) -> void:
	var asset := _current_asset()

	if asset.is_empty():
		return

	if str(
		asset.get(
			"asset_type",
			""
		)
	) == "ground_brush":
		width_spin.set_value_no_signal(1)
		height_spin.set_value_no_signal(1)

	preview.set_review_asset(
		asset,
		Vector2i(
			int(width_spin.value),
			int(height_spin.value)
		),
		_review_anchor_for(asset)
	)


func _on_zoom_changed(
	value: float
) -> void:
	preview.set_view_zoom(value)


func _adjust_footprint(dx: int, dy: int) -> void:
	var asset := _current_asset()
	if asset.is_empty():
		return
	if str(asset.get("asset_type", "")) == "ground_brush":
		return
	var new_w := clampi(int(width_spin.value) + dx, 1, 24)
	var new_h := clampi(int(height_spin.value) + dy, 1, 24)
	width_spin.set_value_no_signal(new_w)
	height_spin.set_value_no_signal(new_h)
	preview.set_review_asset(
		asset,
		Vector2i(new_w, new_h),
		_review_anchor_for(asset)
	)


func _adjust_anchor(dx: int, dy: int) -> void:
	var asset := _current_asset()
	if asset.is_empty():
		return
	var current_anchor := _review_anchor_for(asset)
	var new_anchor := Vector2(
		current_anchor.x + dx,
		current_anchor.y + dy
	)
	preview.review_anchor_px = new_anchor
	preview.queue_redraw()


func _save_review(
	status: String
) -> bool:
	var asset := _current_asset()

	if asset.is_empty():
		return false

	var asset_id := str(
		asset.get("asset_id", "")
	)

	if asset_id.is_empty():
		return false

	var fp := Vector2i(
		maxi(
			1,
			int(width_spin.value)
		),
		maxi(
			1,
			int(height_spin.value)
		)
	)

	if str(
		asset.get(
			"asset_type",
			""
		)
	) == "ground_brush":
		fp = Vector2i.ONE

	var fingerprint := (
		_asset_fingerprint_fields(
			asset
		)
	)

	var item := {
		"status": status,
		"footprint_tiles": [
			fp.x,
			fp.y,
		],
		"anchor_px": [
			int(preview.review_anchor_px.x),
			int(preview.review_anchor_px.y),
		],
		"display_name":
			str(
				asset.get(
					"display_name",
					asset_id
				)
			),
		"palette_path":
			str(
				asset.get(
					"palette_path",
					""
				)
			),
		"image":
			fingerprint.image,
		"source_sha256":
			fingerprint.source_sha256,
		"output_sha256":
			fingerprint.output_sha256,
	}

	var items: Dictionary = (
		review_state.get(
			"items",
			{}
		)
	)

	items[asset_id] = item

	review_state["contract_id"] = (
		REVIEW_CONTRACT_ID
	)
	review_state["items"] = items

	var result := (
		MapAssetCalibrationService._write_atomic(
			REVIEW_PATH,
			review_state
		)
	)

	if not bool(
		result.get("ok", false)
	):
		message_label.text = (
			"保存审核记录失败："
			+ str(
				result.get(
					"errors",
					[]
				)
			)
		)
		return false

	_refresh_progress()
	return true


func _on_verify() -> void:
	if _save_review(
		STATUS_VERIFIED
	):
		message_label.text = (
			"已记录人工核定结果"
		)
		_step(1)


func _on_rework() -> void:
	if _save_review(
		STATUS_REWORK
	):
		message_label.text = (
			"已标记需返工"
		)
		_step(1)


func _on_clear_current() -> void:
	var asset := _current_asset()

	if asset.is_empty():
		return

	var asset_id := str(
		asset.get("asset_id", "")
	)

	var items: Dictionary = (
		review_state.get(
			"items",
			{}
		)
	)

	items.erase(asset_id)
	review_state["items"] = items

	var result := (
		MapAssetCalibrationService._write_atomic(
			REVIEW_PATH,
			review_state
		)
	)

	if bool(
		result.get("ok", false)
	):
		message_label.text = (
			"已清除当前审核记录"
		)
		_refresh_progress()
		_show_current()
	else:
		message_label.text = (
			"清除失败："
			+ str(
				result.get(
					"errors",
					[]
				)
			)
		)


func _on_delete() -> void:
	var asset := _current_asset()
	if asset.is_empty():
		return

	var asset_id := str(
		asset.get("asset_id", "")
	)

	if asset_id.is_empty():
		return

	var confirm := (
		"确认要删除当前素材？\n\n"
		+ "asset_id：" + asset_id + "\n"
		+ "名称：" + str(asset.get("display_name", ""))
	)

	var dialog := AcceptDialog.new()
	dialog.dialog_text = confirm
	dialog.ok_button_text = "确认删除"
	dialog.cancel_button_text = "取消"
	dialog.canceled.connect(
		func():
			message_label.text = "已取消删除"
	)
	add_child(dialog)
	dialog.popup_centered()

	dialog.confirmed.connect(
		func():
			var result := MapAssetCalibrationService.delete_from_palette(
				asset_id
			)
			if bool(result.get("ok", false)):
				message_label.text = "已删除：" + asset_id
				_load_assets()
				_seek_first_matching()
				_show_current()
			else:
				message_label.text = "删除失败：" + str(result.get("errors", []))
	)


func _refresh_progress() -> void:
	if progress_label == null:
		return

	var verified := 0
	var rework := 0
	var pending := 0

	for asset: Dictionary in assets:
		match _asset_status(asset):
			STATUS_VERIFIED:
				verified += 1
			STATUS_REWORK:
				rework += 1
			_:
				pending += 1

	progress_label.text = (
		"总数 %d｜已核定 %d｜需返工 %d｜未检查 %d"
		% [
			assets.size(),
			verified,
			rework,
			pending,
		]
	)


func _on_filter_changed(
	_index: int
) -> void:
	_seek_first_matching()
	_show_current()


func _on_search() -> void:
	var query := (
		search_edit.text
		.strip_edges()
		.to_lower()
	)

	if query.is_empty():
		return

	for index in assets.size():
		var asset := assets[index]

		var haystack := (
			str(
				asset.get(
					"display_name",
					""
				)
			)
			+ "|"
			+ str(
				asset.get(
					"asset_id",
					""
				)
			)
			+ "|"
			+ str(
				asset.get(
					"palette_path",
					""
				)
			)
		).to_lower()

		if query in haystack:
			filter_option.select(1)
			current_index = index
			_show_current()
			return

	message_label.text = (
		"没有找到："
		+ search_edit.text
	)


func _unhandled_key_input(
	event: InputEvent
) -> void:
	if not event is InputEventKey:
		return

	var key_event := (
		event as InputEventKey
	)

	if not key_event.pressed:
		return

	if key_event.echo:
		return

	match key_event.keycode:
		KEY_ENTER:
			_on_verify()
			get_viewport().set_input_as_handled()
		KEY_PAGEUP:
			_step(-1)
			get_viewport().set_input_as_handled()
		KEY_PAGEDOWN:
			_step(1)
			get_viewport().set_input_as_handled()
		KEY_A:
			_adjust_footprint(-1, 0)
			get_viewport().set_input_as_handled()
		KEY_D:
			_adjust_footprint(1, 0)
			get_viewport().set_input_as_handled()
		KEY_S:
			_adjust_footprint(0, -1)
			get_viewport().set_input_as_handled()
		KEY_W:
			_adjust_footprint(0, 1)
			get_viewport().set_input_as_handled()
		KEY_J:
			_adjust_anchor(-1, 0)
			get_viewport().set_input_as_handled()
		KEY_L:
			_adjust_anchor(1, 0)
			get_viewport().set_input_as_handled()
		KEY_I:
			_adjust_anchor(0, -1)
			get_viewport().set_input_as_handled()
		KEY_K:
			_adjust_anchor(0, 1)
			get_viewport().set_input_as_handled()
		KEY_DELETE:
			_on_delete()
			get_viewport().set_input_as_handled()