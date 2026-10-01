class_name EnhancementPanel
extends "res://scripts/inventory_panel.gd"

const ForgeInitialTexture := preload("res://assets/ui/forge/forge_initial.png")
const ForgeSuccessTexture := preload("res://assets/ui/forge/forge_success.png")
const ForgeFailureTexture := preload("res://assets/ui/forge/forge_failure.png")
const ForgeSound := preload("res://assets/audio/ui/forge/forging.wav")
const SynthesisSound := preload("res://assets/audio/ui/forge/synthesis.wav")
const PlainWideButtonFrame := preload("res://assets/ui/forge/plain_286x72.png")
const PlainSmallButtonFrame := preload("res://assets/ui/gothic_theme/v1/character_hall_exact_frames/plain_184x81.png")
const ForgeLayoutScript := preload("res://scripts/ui_runtime_layout_overrides.gd")
const RelicRules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")

const FORGE_SLOT_COUNT := 9
const SYNTHESIS_RECIPE_COLUMNS := 4
const SYNTHESIS_RECIPE_ROWS := 10
const SYNTHESIS_RECIPE_VISIBLE_ROWS := 3
const FORGE_SLOT_SIZE := BAG_CELL_SIZE
const FORGE_SLOT_COLUMNS := 3
const FORGE_DETAIL_GAP := 20.0
const FORGE_DETAIL_WIDTH := 230.0
const FORGE_SLOT_HORIZONTAL_STEP := BAG_CELL_SIZE.x + BAG_HORIZONTAL_SEPARATION
const FORGE_SLOT_VERTICAL_STEP := BAG_CELL_SIZE.y + BAG_VERTICAL_SEPARATION
const SYNTHESIS_INPUT_SLOTS := [0, 1, 2, 3, 4, 5, 6, 7, 8]

var forge_tab_button: Button
var synthesis_tab_button: Button
var forge_button: Button
var forge_slots: Array[Button] = []
var _forge_glow_overlays: Array[Panel] = []
var forge_artwork: Dictionary = {}
var synthesis_recipe_scroll: ScrollContainer
var synthesis_recipe_slots: Array[Button] = []
var _synthesis_recipe_previews: Array[Dictionary] = []
var _selected_synthesis_recipe := -1
var chance_label: RichTextLabel
var fee_label: RichTextLabel
var rules_label: Label
var _forging := false
var _mode := "forge"
var _forge_quote: Dictionary = {}
var _synthesis_quote: Dictionary = {}
var _selected_workbench_slot := -1
var _forge_audio: AudioStreamPlayer
var _synthesis_audio: AudioStreamPlayer
var _forge_audio_plays_in_cycle := 0
var _synthesis_audio_plays_in_cycle := 0


func _ready() -> void:
	# Keep the source inventory layout, including its calibrated BagPanel.
	# Only the two paper-doll sections are retired from this derived page.
	set_meta("calibration_retired_prefixes", ["AttributePanel", "EquipmentPanel"])
	super._ready()
	# InventoryPanel owns the accepted 100-cell bag and its selection behaviour.
	# The two paper-doll sections are not part of this panel's layout.
	_hide_inherited_left_sections()
	var title := get_node_or_null("TitleFrame/Title") as Label
	if title != null:
		title.text = "装备锻造"
	_build_forge_slots()
	_build_forge_artwork()
	_build_synthesis_recipe_grid()
	_build_forge_information()
	_build_forge_action()
	_forge_audio = AudioStreamPlayer.new()
	_forge_audio.name = "ForgeAudio"
	_forge_audio.stream = ForgeSound
	_forge_audio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_forge_audio)
	_synthesis_audio = AudioStreamPlayer.new()
	_synthesis_audio.name = "SynthesisAudio"
	_synthesis_audio.stream = SynthesisSound
	_synthesis_audio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_synthesis_audio)
	_build_forge_tabs()
	var recipe_entries: Array[Dictionary] = []
	for item: Dictionary in RelicRules.records():
		for profession: String in RelicRules.recipe_professions(int(item.itemId)):
			recipe_entries.append({"item_id": int(item.itemId), "profession": profession, "title": "%s · %s技能" % [str(item.name), ProfessionRules.profession_display_name(profession)], "icon": UIItemTextureCacheScript.texture_for(item)})
	set_synthesis_recipe_previews(recipe_entries)
	ForgeLayoutScript.apply_profile(self, "forge")
	_show_forge_artwork("initial")
	_refresh_forge_information()


func refresh() -> void:
	super.refresh()
	_hide_inherited_left_sections()
	if not forge_slots.is_empty() and not _forging:
		_refresh_forge_information()


func _on_runtime_layout_profile_applied(profile_id: String) -> void:
	super._on_runtime_layout_profile_applied(profile_id)
	_hide_inherited_left_sections()


func _hide_inherited_left_sections() -> void:
	for node_name: String in ["AttributePanel", "EquipmentPanel"]:
		var section := get_node_or_null(node_name) as Control
		if section != null:
			section.hide()
	if item_detail_presenter != null:
		item_detail_presenter.hide_detail()


func _build_forge_tabs() -> void:
	forge_tab_button = Button.new()
	forge_tab_button.name = "ForgeTab"
	forge_tab_button.text = "锻造"
	forge_tab_button.position = Vector2(79.5, 90)
	forge_tab_button.size = Vector2(128, 51)
	forge_tab_button.theme_type_variation = "GothicShopTradeTabSelectedGemButton"
	forge_tab_button.pressed.connect(_set_mode.bind("forge"))
	add_child(forge_tab_button)
	synthesis_tab_button = Button.new()
	synthesis_tab_button.name = "SynthesisTab"
	synthesis_tab_button.text = "合成"
	synthesis_tab_button.position = Vector2(223.5, 90)
	synthesis_tab_button.size = Vector2(128, 51)
	synthesis_tab_button.theme_type_variation = "GothicShopTradeTabGemButton"
	synthesis_tab_button.pressed.connect(_set_mode.bind("synthesis"))
	add_child(synthesis_tab_button)


func _build_forge_slots() -> void:
	var section := _forge_section("ForgeMaterialPanel", Vector2(32, 148), Vector2(300, 270))
	var grid := Control.new()
	grid.name = "ForgeMaterialGrid"
	grid.position = Vector2(65, 42)
	grid.size = Vector2(
		FORGE_SLOT_SIZE.x * FORGE_SLOT_COLUMNS + BAG_HORIZONTAL_SEPARATION * (FORGE_SLOT_COLUMNS - 1),
		FORGE_SLOT_SIZE.y * FORGE_SLOT_COLUMNS + BAG_VERTICAL_SEPARATION * (FORGE_SLOT_COLUMNS - 1)
	)
	grid.set_meta("calibration_layer", true)
	section.add_child(grid)
	for index in FORGE_SLOT_COUNT:
		var slot := Button.new()
		slot.name = "ForgeSlot_%d" % index
		slot.position = Vector2(
			(index % FORGE_SLOT_COLUMNS) * FORGE_SLOT_HORIZONTAL_STEP,
			(index / FORGE_SLOT_COLUMNS) * FORGE_SLOT_VERTICAL_STEP
		)
		slot.size = FORGE_SLOT_SIZE
		slot.theme_type_variation = "GothicComponentSlotButton"
		slot.focus_mode = Control.FOCUS_NONE
		slot.tooltip_text = "装备或材料，格子不限"
		grid.add_child(slot)
		UIActivationOnceScript.attach(slot, _on_forge_slot_pressed.bind(index))
		_sync_forge_slot_visual(slot, false)
		var glow := Panel.new()
		glow.name = "ForgeGlow"
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.z_index = 5
		glow.modulate.a = 0.0
		glow.set_meta("calibration_internal_visual", true)
		var glow_style := StyleBoxFlat.new()
		glow_style.bg_color = Color(1.0, 0.55, 0.08, 0.12)
		glow_style.border_color = Color(1.0, 0.77, 0.22, 0.95)
		glow_style.set_border_width_all(2)
		glow_style.shadow_color = Color(1.0, 0.48, 0.05, 0.65)
		glow_style.shadow_size = 7
		glow.add_theme_stylebox_override("panel", glow_style)
		slot.add_child(glow)
		_forge_glow_overlays.append(glow)
		forge_slots.append(slot)
	var hint := Label.new()
	hint.name = "ForgeMaterialHint"
	hint.text = "装备与材料可放任意格，顺序不限"
	hint.position = Vector2(20, 244)
	hint.size = Vector2(260, 25)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.theme_type_variation = "GothicMutedLabel"
	section.add_child(hint)


func _build_forge_artwork() -> void:
	var section := _forge_section("ForgeArtworkPanel", Vector2(344, 148), Vector2(340, 270))
	for entry: Dictionary in [
		{"name": "ForgeImageInitial", "texture": ForgeInitialTexture},
		{"name": "ForgeImageSuccess", "texture": ForgeSuccessTexture},
		{"name": "ForgeImageFailure", "texture": ForgeFailureTexture},
	]:
		var art := TextureRect.new()
		art.name = str(entry["name"])
		art.texture = entry["texture"] as Texture2D
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.position = Vector2(50, 15)
		art.size = Vector2(240, 240)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_meta("calibration_layer", true)
		section.add_child(art)
		forge_artwork[art.name] = art


func _build_synthesis_recipe_grid() -> void:
	var section := get_node("ForgeArtworkPanel") as Control
	synthesis_recipe_scroll = ScrollContainer.new()
	synthesis_recipe_scroll.name = "SynthesisRecipeScroll"
	synthesis_recipe_scroll.position = Vector2(44, 1)
	synthesis_recipe_scroll.size = Vector2(252, BAG_CELL_SIZE.y * SYNTHESIS_RECIPE_VISIBLE_ROWS + BAG_VERTICAL_SEPARATION * (SYNTHESIS_RECIPE_VISIBLE_ROWS - 1))
	synthesis_recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	synthesis_recipe_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var viewport_style := StyleBoxEmpty.new()
	synthesis_recipe_scroll.add_theme_stylebox_override("panel", viewport_style)
	synthesis_recipe_scroll.set_meta("calibration_layer", true)
	section.add_child(synthesis_recipe_scroll)
	var grid := GridContainer.new()
	grid.name = "SynthesisRecipeGrid"
	grid.columns = SYNTHESIS_RECIPE_COLUMNS
	grid.custom_minimum_size = Vector2(
		BAG_CELL_SIZE.x * SYNTHESIS_RECIPE_COLUMNS + BAG_HORIZONTAL_SEPARATION * (SYNTHESIS_RECIPE_COLUMNS - 1),
		BAG_CELL_SIZE.y * SYNTHESIS_RECIPE_ROWS + BAG_VERTICAL_SEPARATION * (SYNTHESIS_RECIPE_ROWS - 1)
	)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", BAG_HORIZONTAL_SEPARATION)
	grid.add_theme_constant_override("v_separation", BAG_VERTICAL_SEPARATION)
	synthesis_recipe_scroll.add_child(grid)
	for index in SYNTHESIS_RECIPE_COLUMNS * SYNTHESIS_RECIPE_ROWS:
		var slot := Button.new()
		slot.name = "RecipeSlot_%02d" % index
		slot.custom_minimum_size = BAG_CELL_SIZE
		slot.size = BAG_CELL_SIZE
		slot.disabled = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.tooltip_text = "暂无合成配方"
		slot.theme_type_variation = "GothicComponentSlotButton"
		grid.add_child(slot)
		UIActivationOnceScript.attach(slot, _on_synthesis_recipe_pressed.bind(index))
		var class_label := Label.new()
		class_label.name = "RecipeProfession"
		class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		class_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		class_label.add_theme_font_size_override("font_size", 11)
		class_label.add_theme_color_override("font_color", Color("f3d395"))
		class_label.add_theme_color_override("font_outline_color", Color.BLACK)
		class_label.add_theme_constant_override("outline_size", 3)
		class_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(class_label)
		class_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		synthesis_recipe_slots.append(slot)
	synthesis_recipe_scroll.hide()


func set_synthesis_recipe_previews(entries: Array[Dictionary]) -> void:
	_synthesis_recipe_previews = entries.slice(0, synthesis_recipe_slots.size())
	_selected_synthesis_recipe = -1
	for index in synthesis_recipe_slots.size():
		var slot := synthesis_recipe_slots[index]
		var entry: Dictionary = _synthesis_recipe_previews[index] if index < _synthesis_recipe_previews.size() else {}
		var icon := entry.get("icon") as Texture2D
		_set_button_texture(slot, icon, Vector2(32, 32) if not entry.is_empty() else Vector2.ZERO)
		slot.disabled = entry.is_empty()
		slot.tooltip_text = str(entry.get("title", "暂无合成配方"))
		(slot.get_node("RecipeProfession") as Label).text = ProfessionRules.profession_display_name(str(entry.get("profession", ""))).left(1)
		UIItemSelectionVisualScript.apply(slot, false, &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")
	if _mode == "synthesis":
		_refresh_forge_information()


func _on_synthesis_recipe_pressed(index: int) -> void:
	if _mode != "synthesis" or _forging or index >= _synthesis_recipe_previews.size():
		return
	_selected_synthesis_recipe = index
	_selected_workbench_slot = -1
	_ui_sync_empty_destinations()
	for slot_index in synthesis_recipe_slots.size():
		UIItemSelectionVisualScript.apply(synthesis_recipe_slots[slot_index], slot_index == index, &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")
	var recipe_id := int(_synthesis_recipe_previews[index].get("item_id", -1))
	var item := RelicRules.record_for_id(recipe_id)
	if not item.is_empty():
		_show_presented_item(item, {}, synthesis_recipe_slots[index], {"recipe_profession": str(_synthesis_recipe_previews[index].get("profession", ""))})
	_refresh_forge_information()


func _build_forge_information() -> void:
	var rules_panel := _forge_section("ForgeRulesPanel", Vector2(32, 424), Vector2(300, 210))
	var rules_title := _section_title("材料需求", 300)
	rules_title.name = "ForgeRulesTitle"
	rules_title.add_theme_font_size_override("font_size", 18)
	rules_title.size.y = 30
	rules_panel.add_child(rules_title)
	var rules_frame := NinePatchRect.new()
	rules_frame.name = "PlainButtonFrame"
	rules_frame.texture = PlainWideButtonFrame
	rules_frame.patch_margin_top = 18
	rules_frame.patch_margin_bottom = 18
	rules_frame.position = Vector2(7, 41)
	rules_frame.size = Vector2(286, 96)
	rules_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rules_frame.set_meta("calibration_layer", true)
	rules_panel.add_child(rules_frame)
	rules_label = Label.new()
	rules_label.name = "ForgeRulesText"
	rules_label.position = Vector2(16, 54)
	rules_label.size = Vector2(268, 70)
	rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_label.add_theme_font_size_override("font_size", 14)
	rules_label.add_theme_color_override("font_color", Color("e7d1a9"))
	rules_label.set_meta("calibration_runtime_text", true)
	rules_panel.add_child(rules_label)
	var chance_panel := Control.new()
	chance_panel.name = "ForgeChancePanel"
	chance_panel.position = Vector2(344, 424)
	chance_panel.size = Vector2(340, 150)
	add_child(chance_panel)
	for entry: Dictionary in [
		{"name": "ChanceFrame", "x": 0.0, "title": "成功率"},
		{"name": "FeeFrame", "x": 176.0, "title": "锻造费"},
	]:
		var cell := Control.new()
		cell.name = str(entry["name"])
		cell.position = Vector2(float(entry["x"]), 0)
		cell.size = Vector2(164, 120)
		chance_panel.add_child(cell)
		_add_plain_frame(cell, PlainSmallButtonFrame, Rect2(0, 40, 164, 72))
		var label := _section_title(str(entry["title"]), 164)
		label.name = "Title"
		label.add_theme_font_size_override("font_size", 18)
		label.size.y = 30
		cell.add_child(label)
	chance_label = RichTextLabel.new()
	chance_label.name = "ForgeChanceText"
	chance_label.position = Vector2(12, 61)
	chance_label.size = Vector2(140, 34)
	chance_label.bbcode_enabled = true
	chance_label.scroll_active = false
	chance_label.theme_type_variation = "GothicDetailText"
	chance_label.set_meta("calibration_runtime_text", true)
	chance_panel.get_node("ChanceFrame").add_child(chance_label)
	fee_label = RichTextLabel.new()
	fee_label.name = "ForgeFeeText"
	fee_label.position = Vector2(12, 61)
	fee_label.size = Vector2(140, 34)
	fee_label.bbcode_enabled = true
	fee_label.scroll_active = false
	fee_label.theme_type_variation = "GothicDetailText"
	fee_label.set_meta("calibration_runtime_text", true)
	chance_panel.get_node("FeeFrame").add_child(fee_label)


func _forge_section(node_name: String, at: Vector2, panel_size: Vector2) -> Control:
	var section := Control.new()
	section.name = node_name
	section.position = at
	section.size = panel_size
	add_child(section)
	return section


func _add_plain_frame(parent: Control, source: Texture2D, rect: Rect2) -> void:
	var frame := TextureRect.new()
	frame.name = "PlainButtonFrame"
	frame.texture = source
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.position = rect.position
	frame.size = rect.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)


func _build_forge_action() -> void:
	forge_button = Button.new()
	forge_button.name = "ForgeButton"
	forge_button.text = "开始锻造"
	forge_button.position = Vector2(394, 580)
	forge_button.size = Vector2(240, 54)
	forge_button.theme_type_variation = "GothicInventoryActionGemButton"
	forge_button.pressed.connect(_on_forge_pressed)
	add_child(forge_button)


func _set_mode(mode: String) -> void:
	if _forging or mode == _mode or mode not in ["forge", "synthesis"]:
		return
	_mode = mode
	_selected_workbench_slot = -1
	ForgeLayoutScript.apply_profile(self, mode)
	synthesis_recipe_scroll.visible = mode == "synthesis"
	if mode == "forge":
		_show_forge_artwork("initial")
	else:
		for art: TextureRect in forge_artwork.values():
			art.hide()
		if item_detail_presenter != null:
			item_detail_presenter.hide_detail()
	forge_tab_button.theme_type_variation = "GothicShopTradeTabSelectedGemButton" if mode == "forge" else "GothicShopTradeTabGemButton"
	synthesis_tab_button.theme_type_variation = "GothicShopTradeTabGemButton" if mode == "forge" else "GothicShopTradeTabSelectedGemButton"
	var title := get_node_or_null("TitleFrame/Title") as Label
	if title != null:
		title.text = "装备锻造" if mode == "forge" else "物品合成"
	var fee_title := get_node_or_null("ForgeChancePanel/FeeFrame/Title") as Label
	if fee_title != null:
		fee_title.text = "锻造费" if mode == "forge" else "合成费"
	var hint := get_node_or_null("ForgeMaterialPanel/ForgeMaterialHint") as Label
	if hint != null:
		hint.text = "装备与材料可放任意格，顺序不限" if mode == "forge" else "请选择配方，材料可放任意格"
	_ui_sync_empty_destinations()
	_refresh_forge_information()


func _show_forge_artwork(result: String) -> void:
	var selected_name: String = {
		"initial": "ForgeImageInitial",
		"success": "ForgeImageSuccess",
		"failure": "ForgeImageFailure",
	}.get(result, "ForgeImageInitial")
	for name: String in forge_artwork:
		(forge_artwork[name] as TextureRect).visible = name == selected_name


func preview_forge_artwork(result: String) -> void:
	# The calibration workbench uses this to expose each independently-sized
	# image without ever committing a forge transaction.
	_show_forge_artwork(result)


func preview_forge_animation() -> void:
	# The calibrator can inspect the production timing and glow without spending
	# gold or materials, generating a roll, or changing the saved layout.
	if _forging:
		return
	_play_forge_animation("initial")


func preview_synthesis_animation() -> void:
	# UI/audio preview only; no item, currency, or recipe transaction occurs.
	if _forging or _mode != "synthesis":
		return
	_play_synthesis_animation()


func _refresh_forge_information() -> void:
	if rules_label == null or chance_label == null or fee_label == null or forge_button == null:
		return
	_forge_quote.clear()
	_synthesis_quote.clear()
	var tray: Array[Dictionary] = PlayerState.workbench_tray(_mode)
	for index in forge_slots.size():
		var slot := forge_slots[index]
		var stack: Dictionary = tray[index]
		var item := GameData.get_item_record(stack) if not stack.is_empty() else {}
		_set_button_texture(slot, UIItemTextureCacheScript.texture_for_item(stack) if not stack.is_empty() else null, _item_icon_display_size(item, "inventoryIcon"))
		_sync_forge_slot_visual(slot, not stack.is_empty())
		if not stack.is_empty():
			slot.tooltip_text = str(stack.get("name", "物品")) + "：点击查看，再点取回背包"
		else:
			slot.tooltip_text = "装备或材料，格子不限"
	if _mode == "synthesis":
		rules_label.text = "请选择合成配方" if _selected_synthesis_recipe < 0 else "材料需求：远古圣物碎片 ×4"
		chance_label.text = "[center]—[/center]" if _selected_synthesis_recipe < 0 else "[center]100%[/center]"
		fee_label.text = "[center]—[/center]" if _selected_synthesis_recipe < 0 else "[center]400000[/center]"
		forge_button.text = "开始合成"
		forge_button.disabled = true
		if _selected_synthesis_recipe < 0:
			_synthesis_quote = {"valid": false, "message": "请选择需要合成的圣物或徽章。"}
			return
		var material_slots: Array[int] = []
		for slot_index: int in SYNTHESIS_INPUT_SLOTS:
			var stack: Dictionary = tray[slot_index]
			if not stack.is_empty() and int(GameData.get_item_record(stack).get("itemId", -1)) == RelicRules.FRAGMENT_ID and int(stack.get("count", 1)) == 1:
				material_slots.append(slot_index)

		if material_slots.size() != RelicRules.FRAGMENT_COUNT:
			_synthesis_quote = {"valid": false, "message": "需要4个远古圣物碎片，当前已放入%d个。" % material_slots.size()}
			return
		var recipe: Dictionary = _synthesis_recipe_previews[_selected_synthesis_recipe]
		_synthesis_quote = PlayerState.quote_relic_synthesis(int(recipe.get("item_id", -1)), material_slots, str(recipe.get("profession", "")))
		forge_button.disabled = _forging or not bool(_synthesis_quote.get("valid", false))
		return
	var has_target := false
	for stack: Dictionary in tray:
		if GameData.item_category_id(stack) in ["hc.item_category.weapon", "hc.item_category.armor", "hc.item_category.helmet"]:
			has_target = true
	rules_label.text = "材料需求：黑铁矿 ×1\n首饰 ×2" if has_target else "请在上方放入需要锻造的装备"
	chance_label.text = "[center]—[/center]"
	fee_label.text = "[center]—[/center]"
	forge_button.text = "开始锻造"
	forge_button.disabled = true
	_forge_quote = PlayerState.quote_forge_tray()
	forge_button.tooltip_text = str(_forge_quote.get("message", ""))
	if not bool(_forge_quote.get("valid", false)):
		return
	chance_label.text = "[center]%.2f%%[/center]" % [float(_forge_quote.final_success_bps) / 100.0]
	fee_label.text = "[center]%d[/center]" % int(_forge_quote.gold_cost)
	forge_button.disabled = _forging or PlayerState.gold < int(_forge_quote.gold_cost)

func _sync_forge_slot_visual(slot: Button, occupied: bool) -> void:
	UIItemSelectionVisualScript.apply(slot, occupied, &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")
	if occupied:
		return
	# Bag cells without an item render their disabled style. Forge cells must
	# accept an item, so use that same style for every transient button state.
	var empty_bag_style := slot.get_theme_stylebox("disabled", &"GothicComponentSlotButton")
	slot.begin_bulk_theme_override()
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
		slot.add_theme_stylebox_override(state, empty_bag_style)
	slot.end_bulk_theme_override()


func _on_forge_slot_pressed(index: int) -> void:
	if _forging:
		return
	var tray: Array[Dictionary] = PlayerState.workbench_tray(_mode)
	var occupied: Dictionary = tray[index]
	var selected_stack := _inventory_record(selected_inventory_index)
	if not occupied.is_empty():
		if _selected_workbench_slot == index and selected_stack.is_empty():
			await _take_selected_workbench_item()
		else:
			_clear_inventory_selection_styles()
			_selected_workbench_slot = index
			_show_forge_slot_detail(index, occupied)
		_ui_sync_empty_destinations()
		_refresh_forge_information()
		return
	_selected_workbench_slot = -1
	if selected_stack.is_empty():
		_ui_sync_empty_destinations()
		return
	var place_result: Dictionary = await PlayerState.transfer_workbench_immediate(_mode, index, selected_inventory_index)
	if not bool(place_result.get("success", false)):
		_show_error_message(str(place_result.get("message", "无法放入物品。")))
		return
	_clear_inventory_selection_styles()
	_refresh_forge_information()
	_selected_workbench_slot = index
	_ui_sync_empty_destinations()
	var placed: Array[Dictionary] = PlayerState.workbench_tray(_mode)
	_show_forge_slot_detail(index, placed[index])

func _can_receive_selected_item_to_index(index: int) -> bool:
	if _selected_workbench_slot < 0 or _forging:
		return false
	var tray: Array[Dictionary] = PlayerState.forge_tray if _mode == "forge" else PlayerState.synthesis_tray
	return (not tray[_selected_workbench_slot].is_empty() and index >= 0
		and index < BAG_CAPACITY and index < _bag_cells.size() and _inventory_record(index).is_empty())


func _receive_selected_item_to_index(index: int) -> void:
	if _can_receive_selected_item_to_index(index):
		await _take_selected_workbench_item(index)


func _take_selected_workbench_item(destination_slot := -1) -> void:
	var source_mode := _mode
	var source_slot := _selected_workbench_slot
	var result: Dictionary = await PlayerState.transfer_workbench_immediate(source_mode, source_slot, -1, destination_slot)
	if bool(result.get("success", false)):
		_show_success_message(str(result.get("message", "已取回物品")))
		if _mode == source_mode and _selected_workbench_slot == source_slot:
			_selected_workbench_slot = -1
			_hide_item_detail()
	else:
		_show_error_message(str(result.get("message", "无法取回物品。")))
	_refresh_forge_information()
	_ui_sync_empty_destinations()


func _ui_dismiss_selection() -> void:
	_selected_workbench_slot = -1
	super._ui_dismiss_selection()


func _select_inventory_item(index: int) -> void:
	if not _inventory_record(index).is_empty():
		_selected_workbench_slot = -1
		_ui_sync_empty_destinations()
	super._select_inventory_item(index)


func _show_forge_slot_detail(index: int, stack: Dictionary) -> void:
	if stack.is_empty() or item_detail_presenter == null:
		return
	var item := GameData.get_item_record(stack)
	if item.is_empty():
		return
	_show_presented_item(item, stack, forge_slots[index], {"presentation_zone": "forge", "count": int(stack.get("count", 1))})


func _ui_detail_region(context: Dictionary) -> Dictionary:
	if str(context.get("presentation_zone", "")) != "forge":
		return super._ui_detail_region(context)
	var grid := get_node_or_null("ForgeMaterialPanel/ForgeMaterialGrid") as Control
	if grid == null:
		return {"region": Rect2(), "side": "left"}
	var grid_rect := UIItemDetailDockScript.rect_in(self, grid)
	return {
		"region": Rect2(grid_rect.position.x - FORGE_DETAIL_GAP - FORGE_DETAIL_WIDTH, grid_rect.position.y, FORGE_DETAIL_WIDTH, grid_rect.size.y),
		"side": "left",
		"fill_height": true,
	}


func _on_forge_pressed() -> void:
	if _forging:
		return
	_refresh_forge_information()
	if _mode == "synthesis":
		if not bool(_synthesis_quote.get("valid", false)):
			_show_error_message(str(_synthesis_quote.get("message", "请先选择配方并放入4个远古圣物碎片。")))
			return
		_forging = true
		forge_button.disabled = true
		var result: Dictionary = await PlayerState.commit_workbench_immediate("synthesis", _synthesis_quote)
		if not bool(result.get("committed", false)):
			_forging = false
			_show_error_message(str(result.get("message", "合成失败，材料未消耗。")))
			_refresh_forge_information()
			return
		_selected_workbench_slot = -1
		await _play_synthesis_animation()
		_show_success_message(str(result.get("message", "合成成功")))
		return
	if not bool(_forge_quote.get("valid", false)):
		_show_error_message(str(_forge_quote.get("message", "请补齐装备和所需材料；放入顺序不限。")))
		return
	_forging = true
	forge_button.disabled = true
	var result: Dictionary = await PlayerState.commit_workbench_immediate("forge", _forge_quote)
	if not bool(result.get("committed", false)):
		_forging = false
		_show_error_message(str(result.get("message", "锻造失败，请重新选择材料。")))
		_refresh_forge_information()
		return
	await _play_forge_animation("success" if bool(result.forge_succeeded) else "failure")
	if bool(result.forge_succeeded):
		_show_success_message(str(result.message))
	else:
		_show_error_message(str(result.message))


func _play_forge_animation(result_artwork: String) -> void:
	_forging = true
	forge_button.disabled = true
	_show_forge_artwork("initial")
	var glow := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	glow.set_loops(3)
	for overlay: Panel in _forge_glow_overlays:
		glow.parallel().tween_property(overlay, "modulate:a", 1.0, 0.35)
	for overlay: Panel in _forge_glow_overlays:
		glow.parallel().tween_property(overlay, "modulate:a", 0.0, 0.65).set_delay(0.35)
	_forge_audio_plays_in_cycle = 0
	for beat in 3:
		_forge_audio.stop()
		_forge_audio.play()
		_forge_audio_plays_in_cycle += 1
		await get_tree().create_timer(1.0, true).timeout
	_forge_audio.stop()
	glow.kill()
	for overlay: Panel in _forge_glow_overlays:
		overlay.modulate.a = 0.0
	_show_forge_artwork(result_artwork)
	_forging = false
	_refresh_forge_information()


func _play_synthesis_animation() -> void:
	_forging = true
	forge_button.disabled = true
	var glow := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	glow.set_loops(3)
	for overlay: Panel in _forge_glow_overlays:
		glow.parallel().tween_property(overlay, "modulate:a", 1.0, 0.35)
	for overlay: Panel in _forge_glow_overlays:
		glow.parallel().tween_property(overlay, "modulate:a", 0.0, 0.65).set_delay(0.35)
	_synthesis_audio_plays_in_cycle = 0
	_synthesis_audio.stop()
	_synthesis_audio.play()
	_synthesis_audio_plays_in_cycle += 1
	await get_tree().create_timer(3.0, true).timeout
	_synthesis_audio.stop()
	glow.kill()
	for overlay: Panel in _forge_glow_overlays:
		overlay.modulate.a = 0.0
	_forging = false
	_refresh_forge_information()
