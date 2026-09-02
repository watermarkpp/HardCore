class_name GothicUITheme
extends RefCounted

const GothicModalLayoutScript := preload("res://scripts/gothic_modal_layout.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const AdaptiveButtonStyleBoxScript := preload("res://scripts/adaptive_button_style_box.gd")

const COMPONENT_ROOT := "res://assets/ui/gothic_theme/v1/sample"
const COMPONENT_V3_ROOT := COMPONENT_ROOT
const COMPONENT_MODAL_FRAME := preload(COMPONENT_ROOT + "/modal_frame.png")
const COMPONENT_TITLE_BAR := preload(COMPONENT_ROOT + "/title_bar.png")
const COMPONENT_INSET_FRAME := preload(COMPONENT_ROOT + "/inset_frame_single_v2.png")
const COMPONENT_TAB_FRAME := preload(COMPONENT_ROOT + "/tab_frame_single_v2.png")
const COMPONENT_BUTTON_NORMAL := preload(COMPONENT_ROOT + "/button_normal_single_v2.png")
const COMPONENT_BUTTON_PRESSED := preload(COMPONENT_ROOT + "/button_pressed_single_v2.png")
const COMPONENT_BUTTON_DISABLED := preload(COMPONENT_ROOT + "/button_disabled_single_v2.png")
const BUTTON_COMPACT_V4 := preload(COMPONENT_V3_ROOT + "/button_compact_normal_v4.png")
const BUTTON_STANDARD_V4 := preload(COMPONENT_V3_ROOT + "/button_standard_normal_v4.png")
const BUTTON_WIDE_V4 := preload(COMPONENT_V3_ROOT + "/button_wide_normal_v4.png")
const BUTTON_SQUARE_V5 := preload(COMPONENT_V3_ROOT + "/button_square_normal_v5.png")
const BUTTON_SHORTWIDE_V5 := preload(COMPONENT_V3_ROOT + "/button_shortwide_normal_v5.png")
const BUTTON_WIDESMALL_V5 := preload(COMPONENT_V3_ROOT + "/button_widesmall_normal_v5.png")
const BUTTON_COMPACT_FEEDBACK_MASK_V1 := preload(COMPONENT_V3_ROOT + "/button_compact_normal_v4_feedback_mask_v1.png")
const BUTTON_COMPACT_FRAME_ONLY_V1 := preload(COMPONENT_V3_ROOT + "/button_compact_normal_v4_frame_only_v1.png")
const BUTTON_STANDARD_FEEDBACK_MASK_V1 := preload(COMPONENT_V3_ROOT + "/button_standard_normal_v4_feedback_mask_v1.png")
const BUTTON_STANDARD_FRAME_ONLY_V1 := preload(COMPONENT_V3_ROOT + "/button_standard_normal_v4_frame_only_v1.png")
const BUTTON_WIDE_FEEDBACK_MASK_V1 := preload(COMPONENT_V3_ROOT + "/button_wide_normal_v4_feedback_mask_v1.png")
const BUTTON_WIDE_FRAME_ONLY_V1 := preload(COMPONENT_V3_ROOT + "/button_wide_normal_v4_frame_only_v1.png")
const BUTTON_V5_FEEDBACK_MASK_PATHS := [
	COMPONENT_V3_ROOT + "/button_square_normal_v5_feedback_mask_v1.png",
	COMPONENT_V3_ROOT + "/button_shortwide_normal_v5_feedback_mask_v1.png",
	COMPONENT_V3_ROOT + "/button_widesmall_normal_v5_feedback_mask_v1.png",
]
const BUTTON_V5_FRAME_ONLY_PATHS := [
	COMPONENT_V3_ROOT + "/button_square_normal_v5_frame_only_v1.png",
	COMPONENT_V3_ROOT + "/button_shortwide_normal_v5_frame_only_v1.png",
	COMPONENT_V3_ROOT + "/button_widesmall_normal_v5_frame_only_v1.png",
]
const CHARACTER_AI_STATUS_FRAME_V7 := preload(COMPONENT_V3_ROOT + "/character_ai_status_frame_v7.png")
const CHARACTER_PROFESSION_FRAME_V7 := preload(COMPONENT_V3_ROOT + "/character_profession_frame_v7.png")
const CHARACTER_PROFILE_FRAME_V7 := preload(COMPONENT_V3_ROOT + "/character_profile_frame_v7.png")
const CHARACTER_AI_STATUS_FEEDBACK_MASK_V1 := preload(COMPONENT_V3_ROOT + "/character_ai_status_frame_v7_feedback_mask_v1.png")
const CHARACTER_AI_STATUS_FRAME_ONLY_V1 := preload(COMPONENT_V3_ROOT + "/character_ai_status_frame_v7_frame_only_v1.png")
const CHARACTER_PROFESSION_FEEDBACK_MASK_V1 := preload(COMPONENT_V3_ROOT + "/character_profession_frame_v7_feedback_mask_v1.png")
const CHARACTER_PROFESSION_FRAME_ONLY_V1 := preload(COMPONENT_V3_ROOT + "/character_profession_frame_v7_frame_only_v1.png")
const CHARACTER_PROFILE_FEEDBACK_MASK_V1 := preload(COMPONENT_V3_ROOT + "/character_profile_frame_v7_feedback_mask_v1.png")
const CHARACTER_PROFILE_FRAME_ONLY_V1 := preload(COMPONENT_V3_ROOT + "/character_profile_frame_v7_frame_only_v1.png")
const COMPONENT_INSET_FRAME_V3 := preload(COMPONENT_V3_ROOT + "/inset_frame_v3.png")
const SKILL_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/skill_exact_frames"
const SKILL_LIST_GEM_266X64 := preload(SKILL_EXACT_FRAME_ROOT + "/gem_266x64.png")
const SKILL_LIST_GEM_266X64_MASK := preload(SKILL_EXACT_FRAME_ROOT + "/gem_266x64_feedback_mask_v1.png")
const SKILL_LIST_GEM_266X64_FRAME := preload(SKILL_EXACT_FRAME_ROOT + "/gem_266x64_frame_only_v1.png")
const SKILL_CONFIG_PLAIN_230X82 := preload(SKILL_EXACT_FRAME_ROOT + "/plain_230x82.png")
const SKILL_CONFIG_PLAIN_230X82_MASK := preload(SKILL_EXACT_FRAME_ROOT + "/plain_230x82_feedback_mask_v1.png")
const SKILL_CONFIG_PLAIN_230X82_FRAME := preload(SKILL_EXACT_FRAME_ROOT + "/plain_230x82_frame_only_v1.png")
const SKILL_CONFIG_PLAIN_104X82 := preload(SKILL_EXACT_FRAME_ROOT + "/plain_104x82.png")
const SKILL_CONFIG_PLAIN_104X82_MASK := preload(SKILL_EXACT_FRAME_ROOT + "/plain_104x82_feedback_mask_v1.png")
const SKILL_CONFIG_PLAIN_104X82_FRAME := preload(SKILL_EXACT_FRAME_ROOT + "/plain_104x82_frame_only_v1.png")
const SKILL_CONFIG_PLAIN_108X60 := preload(SKILL_EXACT_FRAME_ROOT + "/plain_108x60.png")
const SKILL_CONFIG_PLAIN_108X60_MASK := preload(SKILL_EXACT_FRAME_ROOT + "/plain_108x60_feedback_mask_v1.png")
const SKILL_CONFIG_PLAIN_108X60_FRAME := preload(SKILL_EXACT_FRAME_ROOT + "/plain_108x60_frame_only_v1.png")
const SKILL_CONFIG_PLAIN_108X40 := preload(SKILL_EXACT_FRAME_ROOT + "/plain_108x40.png")
const SKILL_CONFIG_PLAIN_108X40_MASK := preload(SKILL_EXACT_FRAME_ROOT + "/plain_108x40_feedback_mask_v1.png")
const SKILL_CONFIG_PLAIN_108X40_FRAME := preload(SKILL_EXACT_FRAME_ROOT + "/plain_108x40_frame_only_v1.png")
const INVENTORY_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/inventory_exact_frames"
const INVENTORY_ACTION_GEM_176X62 := preload(INVENTORY_EXACT_FRAME_ROOT + "/gem_176x62.png")
const INVENTORY_ACTION_GEM_176X62_MASK := preload(INVENTORY_EXACT_FRAME_ROOT + "/gem_176x62_feedback_mask_v1.png")
const INVENTORY_ACTION_GEM_176X62_FRAME := preload(INVENTORY_EXACT_FRAME_ROOT + "/gem_176x62_frame_only_v1.png")
const MAP_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/map_exact_frames"
const MAP_CARD_PLAIN_230X82 := preload(MAP_EXACT_FRAME_ROOT + "/plain_230x82.png")
const MAP_CARD_PLAIN_230X82_MASK := preload(MAP_EXACT_FRAME_ROOT + "/plain_230x82_feedback_mask_v1.png")
const MAP_CARD_PLAIN_230X82_FRAME := preload(MAP_EXACT_FRAME_ROOT + "/plain_230x82_frame_only_v1.png")
const MAP_WORLD_NODE_GEM_342X50 := preload(MAP_EXACT_FRAME_ROOT + "/gem_342x50.png")
const MAP_WORLD_NODE_GEM_342X50_MASK := preload(MAP_EXACT_FRAME_ROOT + "/gem_342x50_feedback_mask_v1.png")
const MAP_WORLD_NODE_GEM_342X50_FRAME := preload(MAP_EXACT_FRAME_ROOT + "/gem_342x50_frame_only_v1.png")
const SHOP_SELL_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/shop_sell_exact_frames"
const SHOP_TRADE_TAB_GEM_128X51 := preload(SHOP_SELL_EXACT_FRAME_ROOT + "/gem_128x51.png")
const SHOP_TRADE_TAB_GEM_128X51_MASK := preload(SHOP_SELL_EXACT_FRAME_ROOT + "/gem_128x51_feedback_mask_v1.png")
const SHOP_TRADE_TAB_GEM_128X51_FRAME := preload(SHOP_SELL_EXACT_FRAME_ROOT + "/gem_128x51_frame_only_v1.png")
const SHOP_SELL_ACTION_GEM_270X51 := preload(SHOP_SELL_EXACT_FRAME_ROOT + "/gem_270x51.png")
const SHOP_SELL_ACTION_GEM_270X51_MASK := preload(SHOP_SELL_EXACT_FRAME_ROOT + "/gem_270x51_feedback_mask_v1.png")
const SHOP_SELL_ACTION_GEM_270X51_FRAME := preload(SHOP_SELL_EXACT_FRAME_ROOT + "/gem_270x51_frame_only_v1.png")
const SHOP_SELL_QUANTITY_PLAIN_58X46 := preload(SHOP_SELL_EXACT_FRAME_ROOT + "/plain_58x46.png")
const SHOP_SELL_QUANTITY_PLAIN_58X46_MASK := preload(SHOP_SELL_EXACT_FRAME_ROOT + "/plain_58x46_feedback_mask_v1.png")
const SHOP_SELL_QUANTITY_PLAIN_58X46_FRAME := preload(SHOP_SELL_EXACT_FRAME_ROOT + "/plain_58x46_frame_only_v1.png")
const QUEST_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/quest_exact_frames"
const QUEST_CARD_PLAIN_286X62 := preload(QUEST_EXACT_FRAME_ROOT + "/plain_286x62.png")
const QUEST_CARD_PLAIN_286X62_MASK := preload(QUEST_EXACT_FRAME_ROOT + "/plain_286x62_feedback_mask_v1.png")
const QUEST_CARD_PLAIN_286X62_FRAME := preload(QUEST_EXACT_FRAME_ROOT + "/plain_286x62_frame_only_v1.png")
const QUEST_ACTION_GEM_342X50 := preload(QUEST_EXACT_FRAME_ROOT + "/gem_342x50.png")
const QUEST_ACTION_GEM_342X50_MASK := preload(QUEST_EXACT_FRAME_ROOT + "/gem_342x50_feedback_mask_v1.png")
const QUEST_ACTION_GEM_342X50_FRAME := preload(QUEST_EXACT_FRAME_ROOT + "/gem_342x50_frame_only_v1.png")
const QUEST_ABANDON_PLAIN_128X52 := preload(QUEST_EXACT_FRAME_ROOT + "/plain_128x52.png")
const QUEST_ABANDON_PLAIN_128X52_MASK := preload(QUEST_EXACT_FRAME_ROOT + "/plain_128x52_feedback_mask_v1.png")
const QUEST_ABANDON_PLAIN_128X52_FRAME := preload(QUEST_EXACT_FRAME_ROOT + "/plain_128x52_frame_only_v1.png")
const SYSTEM_MENU_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/system_menu_exact_frames"
const SYSTEM_MENU_GEM_356X60 := preload(SYSTEM_MENU_EXACT_FRAME_ROOT + "/gem_356x60.png")
const SYSTEM_MENU_GEM_356X60_MASK := preload(SYSTEM_MENU_EXACT_FRAME_ROOT + "/gem_356x60_feedback_mask_v1.png")
const SYSTEM_MENU_GEM_356X60_FRAME := preload(SYSTEM_MENU_EXACT_FRAME_ROOT + "/gem_356x60_frame_only_v1.png")
const SYSTEM_SETTINGS_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/system_settings_exact_frames"
const SYSTEM_SETTINGS_ROW_GEM_356X68 := preload(SYSTEM_SETTINGS_EXACT_FRAME_ROOT + "/gem_356x68.png")
const SYSTEM_SETTINGS_ROW_GEM_356X68_MASK := preload(SYSTEM_SETTINGS_EXACT_FRAME_ROOT + "/gem_356x68_feedback_mask_v1.png")
const SYSTEM_SETTINGS_ROW_GEM_356X68_FRAME := preload(SYSTEM_SETTINGS_EXACT_FRAME_ROOT + "/gem_356x68_frame_only_v1.png")
const SYSTEM_SETTINGS_BACK_GEM_356X60 := preload(SYSTEM_SETTINGS_EXACT_FRAME_ROOT + "/gem_356x60.png")
const SYSTEM_SETTINGS_BACK_GEM_356X60_MASK := preload(SYSTEM_SETTINGS_EXACT_FRAME_ROOT + "/gem_356x60_feedback_mask_v1.png")
const SYSTEM_SETTINGS_BACK_GEM_356X60_FRAME := preload(SYSTEM_SETTINGS_EXACT_FRAME_ROOT + "/gem_356x60_frame_only_v1.png")
const CHARACTER_HALL_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/character_hall_exact_frames"
const CHARACTER_HALL_PROFILE_PLAIN_184X81 := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/plain_184x81.png")
const CHARACTER_HALL_PROFILE_PLAIN_184X81_MASK := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/plain_184x81_feedback_mask_v1.png")
const CHARACTER_HALL_PROFILE_PLAIN_184X81_FRAME := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/plain_184x81_frame_only_v1.png")
const CHARACTER_HALL_AI_PLAIN_80X81 := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/plain_80x81.png")
const CHARACTER_HALL_AI_PLAIN_80X81_MASK := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/plain_80x81_feedback_mask_v1.png")
const CHARACTER_HALL_AI_PLAIN_80X81_FRAME := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/plain_80x81_frame_only_v1.png")
const CHARACTER_HALL_PROFESSION_GEM_98X132 := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_98x132.png")
const CHARACTER_HALL_PROFESSION_GEM_98X132_MASK := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_98x132_feedback_mask_v1.png")
const CHARACTER_HALL_PROFESSION_GEM_98X132_FRAME := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_98x132_frame_only_v1.png")
const CHARACTER_HALL_ENTER_GEM_286X62 := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_286x62.png")
const CHARACTER_HALL_ENTER_GEM_286X62_MASK := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_286x62_feedback_mask_v1.png")
const CHARACTER_HALL_ENTER_GEM_286X62_FRAME := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_286x62_frame_only_v1.png")
const CHARACTER_HALL_DELETE_GEM_120X62 := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_120x62.png")
const CHARACTER_HALL_DELETE_GEM_120X62_MASK := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_120x62_feedback_mask_v1.png")
const CHARACTER_HALL_DELETE_GEM_120X62_FRAME := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_120x62_frame_only_v1.png")
const CHARACTER_HALL_CREATE_GEM_310X58 := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_310x58.png")
const CHARACTER_HALL_CREATE_GEM_310X58_MASK := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_310x58_feedback_mask_v1.png")
const CHARACTER_HALL_CREATE_GEM_310X58_FRAME := preload(CHARACTER_HALL_EXACT_FRAME_ROOT + "/gem_310x58_frame_only_v1.png")
const DEATH_REVIVAL_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/death_revival_exact_frames"
const DEATH_REVIVAL_GEM_440X64 := preload(DEATH_REVIVAL_EXACT_FRAME_ROOT + "/gem_440x64.png")
const DEATH_REVIVAL_GEM_440X64_MASK := preload(DEATH_REVIVAL_EXACT_FRAME_ROOT + "/gem_440x64_feedback_mask_v1.png")
const DEATH_REVIVAL_GEM_440X64_FRAME := preload(DEATH_REVIVAL_EXACT_FRAME_ROOT + "/gem_440x64_frame_only_v1.png")
const CONFIRMATION_EXACT_FRAME_ROOT := "res://assets/ui/gothic_theme/v1/confirmation_exact_frames"
const CONFIRMATION_GEM_202X58 := preload(CONFIRMATION_EXACT_FRAME_ROOT + "/gem_202x58.png")
const CONFIRMATION_GEM_202X58_MASK := preload(CONFIRMATION_EXACT_FRAME_ROOT + "/gem_202x58_feedback_mask_v1.png")
const CONFIRMATION_GEM_202X58_FRAME := preload(CONFIRMATION_EXACT_FRAME_ROOT + "/gem_202x58_frame_only_v1.png")
const BUTTON_V3_PATCH := Vector4(34, 8, 34, 8)
const BUTTON_ADAPTIVE_PATCH := Vector4(36, 0, 36, 0)
const COMPONENT_ITEM_SLOT := preload(COMPONENT_ROOT + "/item_slot_single_v2.png")
const COMPONENT_SHOP_CARD := preload(COMPONENT_ROOT + "/shop_card_single_v2.png")
const COMPONENT_CLOSE_RING := preload(COMPONENT_ROOT + "/close_ring_single_v2.png")

const IRON := Color("181513")
const IRON_HOVER := Color("2b2119")
const IRON_PRESSED := Color("100d0c")
const BRONZE := Color("8d6940")
const BRONZE_BRIGHT := Color("c59a61")
const PARCHMENT := Color("ead8b7")
const MUTED := Color("a99479")
const BLOOD := Color("6e1519")
const MANA := Color("173d79")
const MODAL_CONTENT_SAFE_INSET := GothicModalLayoutScript.FRAME_SAFE_INSET

# Button interaction is intentionally split into visual states and semantic
# ownership.  The theme supplies the visual cue; the owning panel decides when
# to enter/leave a state and which selection group is mutually exclusive.
const BUTTON_FEEDBACK_NORMAL := &"normal"
const BUTTON_FEEDBACK_SELECTED := &"selected"
const BUTTON_FEEDBACK_BUSY := &"busy"
const BUTTON_FEEDBACK_SUCCESS := &"success"
const BUTTON_FEEDBACK_FAILURE := &"failure"
const BUTTON_FEEDBACK_TRANSITION := &"transition"
const BUTTON_FEEDBACK_META_STATE := &"gothic_feedback_state"
const BUTTON_FEEDBACK_META_GROUP := &"gothic_feedback_selection_group"
const BUTTON_FEEDBACK_META_BACKUP := &"gothic_feedback_override_backup"
const BUTTON_FEEDBACK_META_FONT_BACKUP := &"gothic_feedback_font_override_backup"
## Interaction feedback is an interior cue, not a replacement frame.  Keep it
## in the approved dark-red family so a pressed/selected state never turns an
## otherwise antique-gold control orange.  Layered adaptive buttons draw the
## original source frame on top; flat HUD controls use the same restrained
## red-copper border instead of a second rectangular gold frame.
const BUTTON_PRESS_FILL := Color(0.24, 0.035, 0.075, 0.88)
const BUTTON_PRESS_BORDER := Color(0.66, 0.16, 0.20, 0.82)
const BUTTON_PRESS_SHADOW := Color(0.68, 0.12, 0.18, 0.68)
const BUTTON_SELECTED_FILL := Color(0.30, 0.045, 0.105, 0.90)
const BUTTON_SELECTED_BORDER := Color(0.78, 0.26, 0.28, 0.90)
const BUTTON_SELECTED_SHADOW := Color(0.76, 0.16, 0.24, 0.76)
const BUTTON_SUCCESS_FILL := Color(0.36, 0.28, 0.075, 0.28)
const BUTTON_SUCCESS_BORDER := Color(0.93, 0.82, 0.38, 0.96)
const BUTTON_SUCCESS_SHADOW := Color(0.94, 0.68, 0.18, 0.74)
const BUTTON_FAILURE_FILL := Color(0.40, 0.055, 0.035, 0.28)
const BUTTON_FAILURE_BORDER := Color(0.94, 0.30, 0.20, 0.94)
const BUTTON_FAILURE_SHADOW := Color(0.86, 0.16, 0.08, 0.68)
const BUTTON_PRESS_MODULATE := Color(1.24, 1.08, 0.86, 1.0)
# Character-hall feedback follows each source frame's alpha.  Character
# variations never draw the generic rectangular feedback layer.
const CHARACTER_SELECTED_FILL := Color(0.12, 0.035, 0.075, 0.94)
const CHARACTER_SELECTED_HOVER_FILL := Color(0.16, 0.045, 0.09, 0.96)
const CHARACTER_SELECTED_PRESSED_FILL := Color(0.20, 0.06, 0.11, 0.98)
const CHARACTER_PRESS_FILL := Color(0.10, 0.03, 0.045, 0.96)
const CHARACTER_FRAME_BASE_FILL := Color(0.045, 0.024, 0.025, 0.96)
const CHARACTER_TRANSITION_FILL := Color(0.18, 0.045, 0.085, 0.96)
const CHARACTER_SELECTED_FONT := Color("ffe0a6")
const CHARACTER_SELECTED_FONT_OUTLINE := Color(0.58, 0.22, 0.20, 0.82)
const CHARACTER_SELECTED_FONT_SHADOW := Color(0.78, 0.32, 0.20, 0.62)
const CHARACTER_TRANSITION_FONT := Color("ffe5b8")
const CHARACTER_TRANSITION_FONT_OUTLINE := Color(0.62, 0.24, 0.20, 0.86)
const CHARACTER_TRANSITION_FONT_SHADOW := Color(0.80, 0.34, 0.22, 0.68)

static var _shared_full_theme: Theme
static var _shared_character_hall_theme: Theme
static var _button_v5_feedback_masks: Array[Texture2D] = []
static var _button_v5_frame_only: Array[Texture2D] = []


static func build() -> Theme:
	if _shared_full_theme != null:
		return _shared_full_theme
	var result := _build_base_theme()
	result.set_color("font_color", "PopupMenu", PARCHMENT)
	result.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	result.set_stylebox("panel", "PopupMenu", _flat(Color(0.025, 0.018, 0.014, 0.98), BRONZE, 2, 8))
	result.set_stylebox("hover", "PopupMenu", _flat(Color(0.22, 0.08, 0.035, 0.96), BRONZE_BRIGHT, 1, 5))
	result.set_stylebox("separator", "PopupMenu", _flat(Color(0.18, 0.09, 0.04, 0.78), Color.TRANSPARENT, 0, 0))
	result.set_type_variation("GothicSectionTitle", "Label")
	result.set_color("font_color", "GothicSectionTitle", Color("f0c77f"))
	result.set_font_size("font_size", "GothicSectionTitle", 20)
	result.set_type_variation("GothicMutedLabel", "Label")
	result.set_color("font_color", "GothicMutedLabel", MUTED)
	result.set_font_size("font_size", "GothicMutedLabel", 14)
	result.set_type_variation("GothicDetailText", "RichTextLabel")
	result.set_color("default_color", "GothicDetailText", Color("d8c8ae"))
	result.set_font_size("normal_font_size", "GothicDetailText", 15)
	result.set_type_variation("GothicSearchField", "LineEdit")
	result.set_stylebox("normal", "GothicSearchField", _flat(Color(0.02, 0.016, 0.014, 0.96), Color(0.42, 0.31, 0.20, 0.92), 2, 8))
	result.set_stylebox("focus", "GothicSearchField", _flat(Color(0.035, 0.024, 0.018, 0.98), BRONZE_BRIGHT, 2, 8))
	result.set_stylebox("read_only", "GothicSearchField", _flat(Color(0.014, 0.012, 0.011, 0.90), Color(0.24, 0.19, 0.15, 0.9), 1, 8))
	result.set_color("font_color", "GothicSearchField", PARCHMENT)
	result.set_color("font_placeholder_color", "GothicSearchField", MUTED.darkened(0.12))
	result.set_color("caret_color", "GothicSearchField", BRONZE_BRIGHT)
	result.set_font_size("font_size", "GothicSearchField", 16)
	result.set_type_variation("GothicContentToggle", "CheckButton")
	result.set_stylebox("normal", "GothicContentToggle", _flat(Color(0.018, 0.015, 0.014, 0.86), Color(0.38, 0.28, 0.19, 0.8), 1, 8))
	result.set_stylebox("hover", "GothicContentToggle", _flat(Color(0.09, 0.055, 0.028, 0.92), BRONZE, 1, 8))
	result.set_stylebox("pressed", "GothicContentToggle", _flat(Color(0.14, 0.065, 0.025, 0.96), BRONZE_BRIGHT, 1, 8))
	result.set_stylebox("focus", "GothicContentToggle", _flat(Color(0.09, 0.055, 0.028, 0.92), BRONZE_BRIGHT, 1, 8))
	result.set_color("font_color", "GothicContentToggle", PARCHMENT)
	result.set_color("font_hover_color", "GothicContentToggle", Color.WHITE)
	result.set_color("font_pressed_color", "GothicContentToggle", Color("ffe2ad"))
	result.set_font_size("font_size", "GothicContentToggle", 14)
	result.set_type_variation("GothicSettingsSwitch", "CheckButton")
	var settings_switch_empty := StyleBoxEmpty.new()
	result.set_stylebox("normal", "GothicSettingsSwitch", settings_switch_empty)
	result.set_stylebox("hover", "GothicSettingsSwitch", settings_switch_empty)
	result.set_stylebox("pressed", "GothicSettingsSwitch", settings_switch_empty)
	result.set_stylebox("focus", "GothicSettingsSwitch", settings_switch_empty)
	result.set_stylebox("disabled", "GothicSettingsSwitch", settings_switch_empty)
	result.set_type_variation("GothicInfoPanel", "Panel")
	result.set_stylebox("panel", "GothicInfoPanel", _flat(Color(0.025, 0.02, 0.018, 0.88), Color(0.42, 0.31, 0.20, 0.92), 1, 16))
	result.set_type_variation("GothicTargetPanel", "Panel")
	result.set_stylebox("panel", "GothicTargetPanel", _flat(Color(0.035, 0.018, 0.015, 0.91), Color(0.58, 0.34, 0.20, 0.96), 2, 18))
	result.set_type_variation("GothicSkillDisc", "Panel")
	result.set_stylebox("panel", "GothicSkillDisc", _flat(Color(0.08, 0.055, 0.045, 0.97), BRONZE, 3, 36))
	result.set_type_variation("GothicArtPanelFill", "Panel")
	result.set_stylebox("panel", "GothicArtPanelFill", _flat(Color(0.018, 0.016, 0.015, 0.86), Color.TRANSPARENT, 0, 14))
	result.set_type_variation("GothicArtToggleFill", "Panel")
	result.set_stylebox("panel", "GothicArtToggleFill", _flat(Color(0.19, 0.08, 0.16, 0.82), Color.TRANSPARENT, 0, 12))
	result.set_type_variation("GothicArtNavFill", "Panel")
	result.set_stylebox("panel", "GothicArtNavFill", _flat(Color(0.055, 0.11, 0.16, 0.82), Color.TRANSPARENT, 0, 12))
	result.set_type_variation("GothicArtBagFill", "Panel")
	result.set_stylebox("panel", "GothicArtBagFill", _flat(Color(0.17, 0.085, 0.025, 0.82), Color.TRANSPARENT, 0, 12))
	result.set_type_variation("GothicArtCircleFill", "Panel")
	result.set_stylebox("panel", "GothicArtCircleFill", _flat(Color(0.018, 0.022, 0.022, 0.88), Color.TRANSPARENT, 0, 40))
	result.set_type_variation("GothicArtAttackFill", "Panel")
	result.set_stylebox("panel", "GothicArtAttackFill", _flat(Color(0.30, 0.018, 0.018, 0.90), Color.TRANSPARENT, 0, 60))
	result.set_type_variation("GothicArtItemFill", "Panel")
	result.set_stylebox("panel", "GothicArtItemFill", _flat(Color(0.018, 0.015, 0.014, 0.94), Color.TRANSPARENT, 0, 7))
	result.set_type_variation("GothicModalSurface", "Panel")
	result.set_stylebox("panel", "GothicModalSurface", _flat(Color(0.018, 0.014, 0.012, 0.94), Color.TRANSPARENT, 0, 24))
	result.set_type_variation("GothicModalScrim", "Panel")
	result.set_stylebox("panel", "GothicModalScrim", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	var modal_frame_style := _texture(COMPONENT_MODAL_FRAME, Vector4(112, 96, 112, 96), 0)
	modal_frame_style.content_margin_left = MODAL_CONTENT_SAFE_INSET.x
	modal_frame_style.content_margin_top = MODAL_CONTENT_SAFE_INSET.y
	modal_frame_style.content_margin_right = MODAL_CONTENT_SAFE_INSET.z
	modal_frame_style.content_margin_bottom = MODAL_CONTENT_SAFE_INSET.w
	result.set_type_variation("GothicModalFrame", "Panel")
	result.set_stylebox("panel", "GothicModalFrame", modal_frame_style)
	result.set_type_variation("GothicModalFrameOverlay", "Panel")
	result.set_stylebox("panel", "GothicModalFrameOverlay", modal_frame_style)
	result.set_type_variation("GothicTitleBar", "Panel")
	result.set_stylebox("panel", "GothicTitleBar", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	result.set_type_variation("GothicInsetFrame", "Panel")
	result.set_stylebox("panel", "GothicInsetFrame", GothicFrameFactoryScript.create_inset_frame_style_v3())
	result.set_type_variation("GothicTabFrame", "Panel")
	result.set_stylebox("panel", "GothicTabFrame", _texture(COMPONENT_TAB_FRAME, Vector4(22, 18, 22, 18), 14))
	result.set_type_variation("GothicEquipmentSlotCaption", "Panel")
	result.set_stylebox("panel", "GothicEquipmentSlotCaption", _flat(Color(0.035, 0.024, 0.018, 0.98), Color(0.52, 0.37, 0.21, 0.96), 1, 3))
	result.set_type_variation("GothicLootGroundPanel", "Panel")
	result.set_stylebox("panel", "GothicLootGroundPanel", _flat(Color(0.13, 0.13, 0.125, 0.68), Color(0.58, 0.56, 0.52, 0.62), 1, 4))
	result.set_type_variation("GothicLootRareGroundPanel", "Panel")
	result.set_stylebox("panel", "GothicLootRareGroundPanel", _flat(Color(0.13, 0.13, 0.125, 0.72), Color(0.76, 0.56, 0.30, 0.78), 1, 4))
	result.set_type_variation("GothicLootToastPanel", "Panel")
	result.set_stylebox("panel", "GothicLootToastPanel", _flat(Color(0.13, 0.13, 0.125, 0.68), Color(0.58, 0.56, 0.52, 0.62), 1, 4))
	result.set_type_variation("GothicLootErrorPanel", "Panel")
	result.set_stylebox("panel", "GothicLootErrorPanel", _flat(Color(0.13, 0.13, 0.125, 0.72), Color(0.73, 0.38, 0.31, 0.76), 1, 4))
	result.set_type_variation("GothicLootRareBanner", "Panel")
	result.set_stylebox("panel", "GothicLootRareBanner", _flat(Color(0.13, 0.13, 0.125, 0.72), Color(0.76, 0.56, 0.30, 0.78), 1, 4))
	_apply_button_variation(result, "GothicUtilityButton", _flat(IRON, BRONZE, 2, 13), _flat(IRON_HOVER, BRONZE_BRIGHT, 2, 13), _flat(IRON_PRESSED, BRONZE_BRIGHT, 3, 13))
	_apply_button_variation(result, "GothicSkillButton", _flat(Color(0.08, 0.035, 0.055, 0.96), BRONZE, 3, 36), _flat(Color(0.18, 0.045, 0.085, 0.98), BRONZE_BRIGHT, 3, 36), _flat(Color(0.28, 0.06, 0.12, 1.0), Color("f0bd70"), 4, 36))
	_apply_button_variation(result, "GothicAttackButton", _flat(Color(0.24, 0.025, 0.045, 0.96), BRONZE, 4, 60), _flat(Color(0.38, 0.045, 0.075, 1.0), BRONZE_BRIGHT, 4, 60), _flat(Color(0.52, 0.06, 0.12, 1.0), Color("ffd08a"), 5, 60))
	_apply_button_variation(result, "GothicItemButton", _flat(Color(0.018, 0.012, 0.018, 0.86), Color(0.55, 0.30, 0.34, 0.22), 1, 5), _flat(Color(0.16, 0.045, 0.085, 0.88), BRONZE_BRIGHT, 2, 5), _flat(Color(0.25, 0.06, 0.12, 0.92), Color("e6b56f"), 2, 5))
	_apply_button_variation(result, "GothicHUDItemHitButton", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0), _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 7), _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 7))
	# Main HUD controls sit above authored frames.  Keep every pointer state
	# transparent so interaction never paints a synthetic rectangle over them.
	_apply_button_variation(result, "GothicTransparentButton", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0), _flat(Color.TRANSPARENT, Color.TRANSPARENT, 1, 9), _flat(Color.TRANSPARENT, Color.TRANSPARENT, 2, 9))
	_apply_button_variation(result, "GothicPanelTransparentButton", _flat(Color.TRANSPARENT, Color(0.46, 0.33, 0.21, 0.86), 1, 9), _flat(Color(0.20, 0.03, 0.065, 0.72), Color(0.62, 0.14, 0.18, 0.58), 1, 9), _flat(Color(0.30, 0.045, 0.09, 0.82), Color(0.70, 0.18, 0.22, 0.70), 1, 9))
	result.set_stylebox("disabled", "GothicPanelTransparentButton", _flat(Color(0.035, 0.03, 0.028, 0.68), Color(0.24, 0.22, 0.20, 0.72), 1, 9))
	_apply_adaptive_button(result, "GothicComponentButton")
	_apply_adaptive_button(result, "GothicComponentSelectedButton")
	# 仓库五个 96x48 操作按钮统一使用有效像素最接近的无宝石框。
	_apply_warehouse_thin_button(result)
	_apply_small_button(result, &"GothicSkillConfigCompactButton")
	_apply_exact_skill_button(result, &"GothicSkillListGemButton", _visible_alpha_region(SKILL_LIST_GEM_266X64, Rect2(1, 3, 264, 56)), _visible_alpha_region(SKILL_LIST_GEM_266X64_MASK, Rect2(1, 3, 264, 56)), _visible_alpha_region(SKILL_LIST_GEM_266X64_FRAME, Rect2(1, 3, 264, 56)))
	_apply_exact_skill_button(result, &"GothicSkillListSelectedGemButton", _visible_alpha_region(SKILL_LIST_GEM_266X64, Rect2(1, 3, 264, 56)), _visible_alpha_region(SKILL_LIST_GEM_266X64_MASK, Rect2(1, 3, 264, 56)), _visible_alpha_region(SKILL_LIST_GEM_266X64_FRAME, Rect2(1, 3, 264, 56)), BUTTON_SELECTED_FILL)
	_apply_exact_skill_button(result, &"GothicSkillPrimaryPlainButton", _visible_alpha_region(SKILL_CONFIG_PLAIN_230X82, Rect2(1, 8, 228, 64)), _visible_alpha_region(SKILL_CONFIG_PLAIN_230X82_MASK, Rect2(1, 8, 228, 64)), _visible_alpha_region(SKILL_CONFIG_PLAIN_230X82_FRAME, Rect2(1, 8, 228, 64)))
	_apply_exact_skill_button(result, &"GothicSkillRestorePlainButton", _visible_alpha_region(SKILL_CONFIG_PLAIN_104X82, Rect2(1, 8, 102, 64)), _visible_alpha_region(SKILL_CONFIG_PLAIN_104X82_MASK, Rect2(1, 8, 102, 64)), _visible_alpha_region(SKILL_CONFIG_PLAIN_104X82_FRAME, Rect2(1, 8, 102, 64)))
	_apply_exact_skill_button(result, &"GothicSkillRingPlainButton", _visible_alpha_region(SKILL_CONFIG_PLAIN_108X60, Rect2(1, 5, 106, 48)), _visible_alpha_region(SKILL_CONFIG_PLAIN_108X60_MASK, Rect2(1, 5, 106, 48)), _visible_alpha_region(SKILL_CONFIG_PLAIN_108X60_FRAME, Rect2(1, 5, 106, 48)))
	_apply_exact_skill_button(result, &"GothicSkillClearPlainButton", _visible_alpha_region(SKILL_CONFIG_PLAIN_108X40, Rect2(1, 3, 106, 33)), _visible_alpha_region(SKILL_CONFIG_PLAIN_108X40_MASK, Rect2(1, 3, 106, 33)), _visible_alpha_region(SKILL_CONFIG_PLAIN_108X40_FRAME, Rect2(1, 3, 106, 33)))
	_apply_exact_skill_button(result, &"GothicInventoryActionGemButton", _visible_alpha_region(INVENTORY_ACTION_GEM_176X62, Rect2(1, 3, 174, 54)), _visible_alpha_region(INVENTORY_ACTION_GEM_176X62_MASK, Rect2(1, 3, 174, 54)), _visible_alpha_region(INVENTORY_ACTION_GEM_176X62_FRAME, Rect2(1, 3, 174, 54)))
	_apply_exact_skill_button(result, &"GothicMapCardPlainButton", _visible_alpha_region(MAP_CARD_PLAIN_230X82, Rect2(1, 8, 228, 64)), _visible_alpha_region(MAP_CARD_PLAIN_230X82_MASK, Rect2(1, 8, 228, 64)), _visible_alpha_region(MAP_CARD_PLAIN_230X82_FRAME, Rect2(1, 8, 228, 64)))
	_apply_exact_skill_button(result, &"GothicMapCardSelectedPlainButton", _visible_alpha_region(MAP_CARD_PLAIN_230X82, Rect2(1, 8, 228, 64)), _visible_alpha_region(MAP_CARD_PLAIN_230X82_MASK, Rect2(1, 8, 228, 64)), _visible_alpha_region(MAP_CARD_PLAIN_230X82_FRAME, Rect2(1, 8, 228, 64)), BUTTON_SELECTED_FILL)
	_apply_exact_skill_button(result, &"GothicMapWorldNodeGemButton", _visible_alpha_region(MAP_WORLD_NODE_GEM_342X50, Rect2(1, 2, 340, 46)), _visible_alpha_region(MAP_WORLD_NODE_GEM_342X50_MASK, Rect2(1, 2, 340, 46)), _visible_alpha_region(MAP_WORLD_NODE_GEM_342X50_FRAME, Rect2(1, 2, 340, 46)))
	_apply_exact_skill_button(result, &"GothicMapWorldNodeSelectedGemButton", _visible_alpha_region(MAP_WORLD_NODE_GEM_342X50, Rect2(1, 2, 340, 46)), _visible_alpha_region(MAP_WORLD_NODE_GEM_342X50_MASK, Rect2(1, 2, 340, 46)), _visible_alpha_region(MAP_WORLD_NODE_GEM_342X50_FRAME, Rect2(1, 2, 340, 46)), BUTTON_SELECTED_FILL)
	_offset_button_text_up(result, &"GothicMapWorldNodeGemButton", 2.0)
	_offset_button_text_up(result, &"GothicMapWorldNodeSelectedGemButton", 2.0)
	_apply_exact_skill_button(result, &"GothicShopTradeTabGemButton", _visible_alpha_region(SHOP_TRADE_TAB_GEM_128X51, Rect2(1, 2, 126, 45)), _visible_alpha_region(SHOP_TRADE_TAB_GEM_128X51_MASK, Rect2(1, 2, 126, 45)), _visible_alpha_region(SHOP_TRADE_TAB_GEM_128X51_FRAME, Rect2(1, 2, 126, 45)))
	_apply_exact_skill_button(result, &"GothicShopTradeTabSelectedGemButton", _visible_alpha_region(SHOP_TRADE_TAB_GEM_128X51, Rect2(1, 2, 126, 45)), _visible_alpha_region(SHOP_TRADE_TAB_GEM_128X51_MASK, Rect2(1, 2, 126, 45)), _visible_alpha_region(SHOP_TRADE_TAB_GEM_128X51_FRAME, Rect2(1, 2, 126, 45)), BUTTON_SELECTED_FILL)
	_apply_exact_skill_button(result, &"GothicShopBuyActionGemButton", _visible_alpha_region(SHOP_SELL_ACTION_GEM_270X51, Rect2(1, 2, 268, 45)), _visible_alpha_region(SHOP_SELL_ACTION_GEM_270X51_MASK, Rect2(1, 2, 268, 45)), _visible_alpha_region(SHOP_SELL_ACTION_GEM_270X51_FRAME, Rect2(1, 2, 268, 45)))
	_apply_exact_skill_button(result, &"GothicShopSellActionGemButton", _visible_alpha_region(SHOP_SELL_ACTION_GEM_270X51, Rect2(1, 2, 268, 45)), _visible_alpha_region(SHOP_SELL_ACTION_GEM_270X51_MASK, Rect2(1, 2, 268, 45)), _visible_alpha_region(SHOP_SELL_ACTION_GEM_270X51_FRAME, Rect2(1, 2, 268, 45)))
	_apply_exact_skill_button(result, &"GothicShopSellQuantityPlainButton", _visible_alpha_region(SHOP_SELL_QUANTITY_PLAIN_58X46, Rect2(1, 4, 56, 37)), _visible_alpha_region(SHOP_SELL_QUANTITY_PLAIN_58X46_MASK, Rect2(1, 4, 56, 37)), _visible_alpha_region(SHOP_SELL_QUANTITY_PLAIN_58X46_FRAME, Rect2(1, 4, 56, 37)))
	_offset_button_text_up(result, &"GothicShopTradeTabGemButton", 2.0)
	_offset_button_text_up(result, &"GothicShopTradeTabSelectedGemButton", 2.0)
	_offset_button_text_up(result, &"GothicShopBuyActionGemButton", 2.0)
	_offset_button_text_up(result, &"GothicShopSellActionGemButton", 2.0)
	_apply_exact_skill_button(result, &"GothicQuestCardPlainButton", _visible_alpha_region(QUEST_CARD_PLAIN_286X62, Rect2(1, 5, 284, 50)), _visible_alpha_region(QUEST_CARD_PLAIN_286X62_MASK, Rect2(1, 5, 284, 50)), _visible_alpha_region(QUEST_CARD_PLAIN_286X62_FRAME, Rect2(1, 5, 284, 50)))
	_apply_exact_skill_button(result, &"GothicQuestCardSelectedPlainButton", _visible_alpha_region(QUEST_CARD_PLAIN_286X62, Rect2(1, 5, 284, 50)), _visible_alpha_region(QUEST_CARD_PLAIN_286X62_MASK, Rect2(1, 5, 284, 50)), _visible_alpha_region(QUEST_CARD_PLAIN_286X62_FRAME, Rect2(1, 5, 284, 50)), BUTTON_SELECTED_FILL)
	_apply_exact_skill_button(result, &"GothicQuestActionGemButton", _visible_alpha_region(QUEST_ACTION_GEM_342X50, Rect2(1, 2, 340, 46)), _visible_alpha_region(QUEST_ACTION_GEM_342X50_MASK, Rect2(1, 2, 340, 46)), _visible_alpha_region(QUEST_ACTION_GEM_342X50_FRAME, Rect2(1, 2, 340, 46)))
	_apply_exact_skill_button(result, &"GothicQuestAbandonPlainButton", _visible_alpha_region(QUEST_ABANDON_PLAIN_128X52, Rect2(1, 4, 126, 42)), _visible_alpha_region(QUEST_ABANDON_PLAIN_128X52_MASK, Rect2(1, 4, 126, 42)), _visible_alpha_region(QUEST_ABANDON_PLAIN_128X52_FRAME, Rect2(1, 4, 126, 42)))
	_offset_button_text_up(result, &"GothicQuestActionGemButton", 2.0)
	_offset_button_text_up(result, &"GothicQuestAbandonPlainButton", 2.0)
	_apply_exact_skill_button(result, &"GothicSystemMenuGemButton", _visible_alpha_region(SYSTEM_MENU_GEM_356X60, Rect2(1, 3, 354, 55)), _visible_alpha_region(SYSTEM_MENU_GEM_356X60_MASK, Rect2(1, 3, 354, 55)), _visible_alpha_region(SYSTEM_MENU_GEM_356X60_FRAME, Rect2(1, 3, 354, 55)))
	_offset_button_text_up(result, &"GothicSystemMenuGemButton", 3.0)
	_apply_exact_skill_button(result, &"GothicSystemSettingsRowGemButton", _visible_alpha_region(SYSTEM_SETTINGS_ROW_GEM_356X68, Rect2(1, 3, 354, 59)), _visible_alpha_region(SYSTEM_SETTINGS_ROW_GEM_356X68_MASK, Rect2(1, 3, 354, 59)), _visible_alpha_region(SYSTEM_SETTINGS_ROW_GEM_356X68_FRAME, Rect2(1, 3, 354, 59)))
	_apply_exact_skill_button(result, &"GothicSystemSettingsBackGemButton", _visible_alpha_region(SYSTEM_SETTINGS_BACK_GEM_356X60, Rect2(1, 3, 354, 55)), _visible_alpha_region(SYSTEM_SETTINGS_BACK_GEM_356X60_MASK, Rect2(1, 3, 354, 55)), _visible_alpha_region(SYSTEM_SETTINGS_BACK_GEM_356X60_FRAME, Rect2(1, 3, 354, 55)))
	_offset_button_text_up(result, &"GothicSystemSettingsBackGemButton", 3.0)
	_apply_exact_skill_button(result, &"GothicDeathRevivalGemButton", _visible_alpha_region(DEATH_REVIVAL_GEM_440X64, Rect2(1, 5, 436, 52)), _visible_alpha_region(DEATH_REVIVAL_GEM_440X64_MASK, Rect2(1, 5, 436, 52)), _visible_alpha_region(DEATH_REVIVAL_GEM_440X64_FRAME, Rect2(1, 5, 436, 52)))
	_apply_exact_skill_button(result, &"GothicDeathRevivalSelectedGemButton", _visible_alpha_region(DEATH_REVIVAL_GEM_440X64, Rect2(1, 5, 436, 52)), _visible_alpha_region(DEATH_REVIVAL_GEM_440X64_MASK, Rect2(1, 5, 436, 52)), _visible_alpha_region(DEATH_REVIVAL_GEM_440X64_FRAME, Rect2(1, 5, 436, 52)), BUTTON_SELECTED_FILL)
	_offset_button_text_up(result, &"GothicDeathRevivalGemButton", 3.0)
	_offset_button_text_up(result, &"GothicDeathRevivalSelectedGemButton", 3.0)
	_apply_exact_skill_button(result, &"GothicConfirmationGemButton", _visible_alpha_region(CONFIRMATION_GEM_202X58, Rect2(1, 5, 199, 46)), _visible_alpha_region(CONFIRMATION_GEM_202X58_MASK, Rect2(1, 5, 199, 46)), _visible_alpha_region(CONFIRMATION_GEM_202X58_FRAME, Rect2(1, 5, 199, 46)))
	_apply_exact_skill_button(result, &"GothicConfirmationSelectedGemButton", _visible_alpha_region(CONFIRMATION_GEM_202X58, Rect2(1, 5, 199, 46)), _visible_alpha_region(CONFIRMATION_GEM_202X58_MASK, Rect2(1, 5, 199, 46)), _visible_alpha_region(CONFIRMATION_GEM_202X58_FRAME, Rect2(1, 5, 199, 46)), BUTTON_SELECTED_FILL)
	_offset_button_text_up(result, &"GothicConfirmationGemButton", 3.0)
	_offset_button_text_up(result, &"GothicConfirmationSelectedGemButton", 3.0)
	_apply_character_hall_exact_buttons(result)
	_apply_character_hall_buttons(result)
	_apply_character_launch_button(result)
	_apply_texture_button_variation(result, "GothicComponentTabButton", COMPONENT_TAB_FRAME, COMPONENT_TAB_FRAME, COMPONENT_TAB_FRAME, Vector4(22, 18, 22, 18), 14)
	_apply_slot_button_variation(result, "GothicComponentSlotButton", false)
	_apply_slot_button_variation(result, "GothicComponentSelectedSlotButton", true)
	_apply_equipment_slot_button_variation(result, "GothicEquipmentSlotButton", false)
	_apply_equipment_slot_button_variation(result, "GothicSelectedEquipmentSlotButton", true)
	# Trading cards deliberately use the same crisp code-drawn border and
	# selected-state contrast as inventory slots.  Their wider rect only changes
	# content layout; it must not weaken the border or selection feedback.
	_apply_slot_button_variation(result, &"GothicComponentShopCard", false)
	_apply_slot_button_variation(result, &"GothicComponentSelectedShopCard", true)
	# Android keeps a synthetic mouse hover at the last touch coordinate.  A
	# shop card's semantic selection is represented by the selected variation,
	# never by hover, so an unselected card must look exactly normal after a
	# swipe or a second tap that cancels selection.
	result.set_stylebox(
		"hover",
		"GothicComponentShopCard",
		result.get_stylebox("normal", "GothicComponentShopCard"),
	)
	# Circular controls keep their source aspect and are never nine-slice stretched.
	_apply_texture_button_variation(result, "GothicComponentCloseButton", COMPONENT_CLOSE_RING, COMPONENT_CLOSE_RING, COMPONENT_CLOSE_RING, Vector4.ZERO, 8)
	_prewarm_action_feedback_styles(result)
	_shared_full_theme = result
	return _shared_full_theme


## Character selection is the first interactive screen and must not pay for
## every in-game panel variation while the brand intro is holding its final
## frame. Keep this contract intentionally limited to the types instantiated by
## character_select.gd; build() creates and caches the complete theme later,
## behind the character launch loading overlay.
static func build_character_hall() -> Theme:
	if _shared_character_hall_theme != null:
		return _shared_character_hall_theme
	var result := _build_base_theme()
	result.set_type_variation("GothicSectionTitle", "Label")
	result.set_color("font_color", "GothicSectionTitle", Color("f0c77f"))
	result.set_font_size("font_size", "GothicSectionTitle", 20)
	result.set_type_variation("GothicMutedLabel", "Label")
	result.set_color("font_color", "GothicMutedLabel", MUTED)
	result.set_font_size("font_size", "GothicMutedLabel", 14)
	result.set_type_variation("GothicSearchField", "LineEdit")
	result.set_stylebox("normal", "GothicSearchField", _flat(Color(0.02, 0.016, 0.014, 0.96), Color(0.42, 0.31, 0.20, 0.92), 2, 8))
	result.set_stylebox("focus", "GothicSearchField", _flat(Color(0.035, 0.024, 0.018, 0.98), BRONZE_BRIGHT, 2, 8))
	result.set_stylebox("read_only", "GothicSearchField", _flat(Color(0.014, 0.012, 0.011, 0.90), Color(0.24, 0.19, 0.15, 0.9), 1, 8))
	result.set_color("font_color", "GothicSearchField", PARCHMENT)
	result.set_color("font_placeholder_color", "GothicSearchField", MUTED.darkened(0.12))
	result.set_color("caret_color", "GothicSearchField", BRONZE_BRIGHT)
	result.set_font_size("font_size", "GothicSearchField", 16)
	result.set_type_variation("GothicContentToggle", "CheckButton")
	result.set_stylebox("normal", "GothicContentToggle", _flat(Color(0.018, 0.015, 0.014, 0.86), Color(0.38, 0.28, 0.19, 0.8), 1, 8))
	result.set_stylebox("hover", "GothicContentToggle", _flat(Color(0.09, 0.055, 0.028, 0.92), BRONZE, 1, 8))
	result.set_stylebox("pressed", "GothicContentToggle", _flat(Color(0.14, 0.065, 0.025, 0.96), BRONZE_BRIGHT, 1, 8))
	result.set_stylebox("focus", "GothicContentToggle", _flat(Color(0.09, 0.055, 0.028, 0.92), BRONZE_BRIGHT, 1, 8))
	result.set_color("font_color", "GothicContentToggle", PARCHMENT)
	result.set_color("font_hover_color", "GothicContentToggle", Color.WHITE)
	result.set_color("font_pressed_color", "GothicContentToggle", Color("ffe2ad"))
	result.set_font_size("font_size", "GothicContentToggle", 14)
	result.set_type_variation("GothicInsetFrame", "Panel")
	result.set_stylebox("panel", "GothicInsetFrame", GothicFrameFactoryScript.create_inset_frame_style_v3())
	_apply_adaptive_button(result, "GothicComponentButton")
	_apply_character_hall_exact_buttons(result)
	_apply_character_hall_buttons(result)
	_apply_character_launch_button(result)
	_shared_character_hall_theme = result
	return _shared_character_hall_theme


static func _build_base_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Label", PARCHMENT)
	result.set_color("font_shadow_color", "Label", Color(0.02, 0.01, 0.01, 0.95))
	result.set_constant("shadow_offset_x", "Label", 2)
	result.set_constant("shadow_offset_y", "Label", 2)
	result.set_color("default_color", "RichTextLabel", PARCHMENT)
	result.set_stylebox("panel", "ScrollContainer", _flat(Color(0.008, 0.007, 0.006, 0.72), Color(0.28, 0.20, 0.13, 0.62), 1, 8))
	_apply_base_button(result)
	return result


static func _apply_base_button(theme: Theme) -> void:
	# Plain Buttons are still part of the public visual system.  Variations below
	# override these states, while editor/utility buttons inherit this baseline.
	var normal := _flat(IRON, BRONZE, 1, 10)
	var hover := _flat(IRON_HOVER, BRONZE_BRIGHT, 2, 10)
	var pressed := _flat(IRON_PRESSED, BUTTON_PRESS_BORDER, 2, 10)
	_apply_flat_press_feedback(pressed)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", hover)
	theme.set_stylebox("disabled", "Button", _flat(Color(0.035, 0.03, 0.028, 0.70), Color(0.27, 0.24, 0.20, 0.72), 1, 10))
	theme.set_color("font_color", "Button", PARCHMENT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color("ffe2ad"))
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.24))
	theme.set_color("font_outline_color", "Button", Color(0.03, 0.015, 0.01, 1.0))
	theme.set_constant("outline_size", "Button", 3)


static func modal_content_safe_rect(panel_size: Vector2) -> Rect2:
	return GothicModalLayoutScript.safe_rect(panel_size)


static func add_modal_frame_overlay(parent: Control) -> Panel:
	var overlay := Panel.new()
	overlay.name = "ModalFrameOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.theme_type_variation = "GothicModalFrameOverlay"
	parent.add_child(overlay)
	return overlay


static func _apply_button_variation(theme: Theme, variation: StringName, normal: StyleBox, hover: StyleBox, pressed: StyleBox) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_stylebox("normal", variation, normal)
	theme.set_stylebox("hover", variation, hover)
	_apply_flat_press_feedback(pressed)
	theme.set_stylebox("pressed", variation, pressed)
	theme.set_stylebox("focus", variation, hover)
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_hover_color", variation, Color.WHITE)
	theme.set_color("font_pressed_color", variation, Color("ffe2ad"))
	theme.set_color("font_outline_color", variation, Color(0.03, 0.015, 0.01, 1.0))
	theme.set_constant("outline_size", variation, 3)


static func _apply_texture_button_variation(theme: Theme, variation: StringName, normal_texture: Texture2D, pressed_texture: Texture2D, disabled_texture: Texture2D, margins: Vector4, content_margin: float) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_stylebox("normal", variation, _texture(normal_texture, margins, content_margin))
	theme.set_stylebox("hover", variation, _texture(normal_texture, margins, content_margin))
	theme.set_stylebox("pressed", variation, _texture(pressed_texture, margins, content_margin, BUTTON_PRESS_MODULATE))
	theme.set_stylebox("focus", variation, _texture(pressed_texture, margins, content_margin, BUTTON_PRESS_MODULATE))
	theme.set_stylebox("disabled", variation, _texture(disabled_texture, margins, content_margin))
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_hover_color", variation, Color.WHITE)
	theme.set_color("font_pressed_color", variation, Color("ffe2ad"))
	theme.set_color("font_disabled_color", variation, MUTED.darkened(0.24))
	theme.set_color("font_outline_color", variation, Color(0.025, 0.012, 0.008, 1.0))
	theme.set_constant("outline_size", variation, 3)


static func _apply_flat_press_feedback(style: StyleBox) -> void:
	if not style is StyleBoxFlat:
		return
	var flat := style as StyleBoxFlat
	if flat.bg_color.a <= 0.0 and flat.border_color.a <= 0.0:
		flat.shadow_color = Color.TRANSPARENT
		flat.shadow_size = 0
		flat.shadow_offset = Vector2.ZERO
		return
	flat.shadow_color = BUTTON_PRESS_SHADOW
	flat.shadow_size = 4
	flat.shadow_offset = Vector2.ZERO


static func feedback_states() -> Array[StringName]:
	return [
		BUTTON_FEEDBACK_NORMAL,
		BUTTON_FEEDBACK_SELECTED,
		BUTTON_FEEDBACK_BUSY,
		BUTTON_FEEDBACK_SUCCESS,
		BUTTON_FEEDBACK_FAILURE,
		BUTTON_FEEDBACK_TRANSITION,
	]


static func feedback_state_is_persistent(state: StringName) -> bool:
	return state == BUTTON_FEEDBACK_SELECTED


static func feedback_state_is_transient(state: StringName) -> bool:
	return state in [BUTTON_FEEDBACK_BUSY, BUTTON_FEEDBACK_SUCCESS, BUTTON_FEEDBACK_FAILURE, BUTTON_FEEDBACK_TRANSITION]


static func set_button_feedback(button: BaseButton, state: StringName, selection_group := "") -> void:
	"""Apply a state cue; the owning panel controls lifetime and group rules.

	`selected` is persistent until the owner calls `clear_button_feedback`.
	`busy`, `success`, `failure`, and `transition` never start a timer here: an
	operation/transition owner must explicitly clear or replace the state.
	"""
	if not is_instance_valid(button):
		return
	if state == BUTTON_FEEDBACK_NORMAL or not feedback_states().has(state):
		clear_button_feedback(button)
		return
	if state != BUTTON_FEEDBACK_TRANSITION:
		_clear_character_transition_font_feedback(button)
	if not button.has_meta(BUTTON_FEEDBACK_META_BACKUP):
		var backup := {"styles": {}}
		for state_name: StringName in [&"normal", &"hover", &"focus", &"disabled"]:
			var key := str(state_name)
			backup["styles"][key] = {
				"overridden": button.has_theme_stylebox_override(state_name),
				"style": button.get_theme_stylebox(state_name),
			}
		button.set_meta(BUTTON_FEEDBACK_META_BACKUP, backup)
	var feedback_style: StyleBox = button.get_theme_stylebox("pressed")
	if feedback_style is AdaptiveButtonStyleBox:
		var adaptive := feedback_style as AdaptiveButtonStyleBox
		if state == BUTTON_FEEDBACK_SUCCESS:
			feedback_style = adaptive.clone_with_feedback(BUTTON_SUCCESS_FILL, BUTTON_SUCCESS_BORDER, BUTTON_SUCCESS_SHADOW, 5, 10, 1)
		elif state == BUTTON_FEEDBACK_FAILURE:
			feedback_style = adaptive.clone_with_feedback(BUTTON_FAILURE_FILL, BUTTON_FAILURE_BORDER, BUTTON_FAILURE_SHADOW, 5, 10, 1)
	elif feedback_style is StyleBoxFlat:
		var flat := (feedback_style as StyleBoxFlat).duplicate() as StyleBoxFlat
		if state == BUTTON_FEEDBACK_SUCCESS:
			flat.bg_color = BUTTON_SUCCESS_FILL
			flat.border_color = BUTTON_SUCCESS_BORDER
			flat.shadow_color = BUTTON_SUCCESS_SHADOW
			flat.shadow_size = 5
		elif state == BUTTON_FEEDBACK_FAILURE:
			flat.bg_color = BUTTON_FAILURE_FILL
			flat.border_color = BUTTON_FAILURE_BORDER
			flat.shadow_color = BUTTON_FAILURE_SHADOW
			flat.shadow_size = 5
		feedback_style = flat
	for state_name: StringName in [&"normal", &"hover", &"focus", &"disabled"]:
		button.add_theme_stylebox_override(state_name, feedback_style)
	button.set_meta(BUTTON_FEEDBACK_META_STATE, state)
	if selection_group.is_empty():
		if button.has_meta(BUTTON_FEEDBACK_META_GROUP):
			button.remove_meta(BUTTON_FEEDBACK_META_GROUP)
	else:
		button.set_meta(BUTTON_FEEDBACK_META_GROUP, selection_group)
	if state == BUTTON_FEEDBACK_TRANSITION:
		_set_character_transition_font_feedback(button)


static func _set_character_transition_font_feedback(button: BaseButton) -> void:
	if button.theme_type_variation not in [
		&"GothicCharacterLaunchButton",
		&"GothicCharacterHallEnterGemButton",
		&"GothicCharacterHallCreateGemButton",
	]:
		return
	if not button.has_meta(BUTTON_FEEDBACK_META_FONT_BACKUP):
		var backup := {"colors": {}, "constants": {}}
		for property_name: String in ["font_color", "font_pressed_color", "font_disabled_color", "font_outline_color", "font_shadow_color"]:
			backup["colors"][property_name] = {
				"overridden": button.has_theme_color_override(property_name),
				"value": button.get_theme_color(property_name),
			}
		for property_name: String in ["outline_size", "shadow_offset_x", "shadow_offset_y"]:
			backup["constants"][property_name] = {
				"overridden": button.has_theme_constant_override(property_name),
				"value": button.get_theme_constant(property_name),
			}
		button.set_meta(BUTTON_FEEDBACK_META_FONT_BACKUP, backup)
	button.add_theme_color_override("font_color", CHARACTER_TRANSITION_FONT)
	button.add_theme_color_override("font_pressed_color", CHARACTER_TRANSITION_FONT)
	button.add_theme_color_override("font_disabled_color", CHARACTER_TRANSITION_FONT)
	button.add_theme_color_override("font_outline_color", CHARACTER_TRANSITION_FONT_OUTLINE)
	button.add_theme_color_override("font_shadow_color", CHARACTER_TRANSITION_FONT_SHADOW)
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_constant_override("shadow_offset_x", 1)
	button.add_theme_constant_override("shadow_offset_y", 1)


static func _clear_character_transition_font_feedback(button: BaseButton) -> void:
	if not is_instance_valid(button) or not button.has_meta(BUTTON_FEEDBACK_META_FONT_BACKUP):
		return
	var backup: Dictionary = button.get_meta(BUTTON_FEEDBACK_META_FONT_BACKUP, {})
	var color_backup: Dictionary = backup.get("colors", {})
	for property_name: String in ["font_color", "font_pressed_color", "font_disabled_color", "font_outline_color", "font_shadow_color"]:
		var entry: Dictionary = color_backup.get(property_name, {})
		if bool(entry.get("overridden", false)):
			button.add_theme_color_override(property_name, entry.get("value", Color.WHITE))
		else:
			button.remove_theme_color_override(property_name)
	var constant_backup: Dictionary = backup.get("constants", {})
	for property_name: String in ["outline_size", "shadow_offset_x", "shadow_offset_y"]:
		var entry: Dictionary = constant_backup.get(property_name, {})
		if bool(entry.get("overridden", false)):
			button.add_theme_constant_override(property_name, int(entry.get("value", 0)))
		else:
			button.remove_theme_constant_override(property_name)
	button.remove_meta(BUTTON_FEEDBACK_META_FONT_BACKUP)


static func clear_button_feedback(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	var backup: Dictionary = button.get_meta(BUTTON_FEEDBACK_META_BACKUP, {})
	var style_backup: Dictionary = backup.get("styles", {})
	for state_name: StringName in [&"normal", &"hover", &"focus", &"disabled"]:
		var key := str(state_name)
		var entry: Dictionary = style_backup.get(key, {})
		if bool(entry.get("overridden", false)):
			button.add_theme_stylebox_override(state_name, entry.get("style"))
		else:
			button.remove_theme_stylebox_override(state_name)
	if button.has_meta(BUTTON_FEEDBACK_META_BACKUP):
		button.remove_meta(BUTTON_FEEDBACK_META_BACKUP)
	if button.has_meta(BUTTON_FEEDBACK_META_STATE):
		button.remove_meta(BUTTON_FEEDBACK_META_STATE)
	if button.has_meta(BUTTON_FEEDBACK_META_GROUP):
		button.remove_meta(BUTTON_FEEDBACK_META_GROUP)
	_clear_character_transition_font_feedback(button)


static func set_character_selection_feedback(
	button: BaseButton,
	selected: bool,
	normal_variation: StringName,
	selected_variation: StringName,
	selection_group := "",
) -> void:
	"""Drive a character-hall selection without a rectangular overlay.

	Character cards use their own irregular-frame Theme variations.  The
	variation owns the alpha-safe inner background; this helper only applies the
	semantic state and keeps the group metadata available to tests/owners.
	"""
	if not is_instance_valid(button):
		return
	if button.has_meta(BUTTON_FEEDBACK_META_BACKUP):
		clear_button_feedback(button)
	button.theme_type_variation = selected_variation if selected else normal_variation
	button.set_pressed_no_signal(selected)
	if selected:
		button.set_meta(BUTTON_FEEDBACK_META_STATE, BUTTON_FEEDBACK_SELECTED)
		if not selection_group.is_empty():
			button.set_meta(BUTTON_FEEDBACK_META_GROUP, selection_group)
	elif button.has_meta(BUTTON_FEEDBACK_META_STATE):
		button.remove_meta(BUTTON_FEEDBACK_META_STATE)
		if button.has_meta(BUTTON_FEEDBACK_META_GROUP):
			button.remove_meta(BUTTON_FEEDBACK_META_GROUP)

static func _apply_adaptive_button(theme: Theme, variation: StringName) -> void:
	theme.set_type_variation(variation, "Button")
	var selected := variation == &"GothicComponentSelectedButton"
	var n_compact := BUTTON_COMPACT_V4
	var n_standard := BUTTON_STANDARD_V4
	var n_wide := BUTTON_WIDE_V4
	var n := AdaptiveButtonStyleBoxScript.new().configure(n_compact, n_standard, n_wide)
	if selected:
		_set_v4_feedback(n, BUTTON_SELECTED_FILL, BUTTON_SELECTED_SHADOW, 6)
	var p := AdaptiveButtonStyleBoxScript.new().configure(BUTTON_COMPACT_V4, BUTTON_STANDARD_V4, BUTTON_WIDE_V4)
	_set_v4_feedback(p, BUTTON_PRESS_FILL, BUTTON_PRESS_SHADOW, 5)
	var d := AdaptiveButtonStyleBoxScript.new().configure(preload(COMPONENT_V3_ROOT + "/button_compact_disabled_v4.png"), preload(COMPONENT_V3_ROOT + "/button_standard_disabled_v4.png"), preload(COMPONENT_V3_ROOT + "/button_wide_disabled_v4.png"))
	theme.set_stylebox("normal", variation, n); theme.set_stylebox("hover", variation, n); theme.set_stylebox("focus", variation, n)
	theme.set_stylebox("pressed", variation, p); theme.set_stylebox("disabled", variation, d)
	theme.set_color("font_color", variation, PARCHMENT); theme.set_color("font_hover_color", variation, Color.WHITE); theme.set_color("font_pressed_color", variation, Color("ffe2ad")); theme.set_color("font_disabled_color", variation, MUTED.darkened(0.24)); theme.set_constant("outline_size", variation, 3)

static func _apply_small_button(theme: Theme, variation: StringName) -> void:
	theme.set_type_variation(variation, "Button")
	var n := AdaptiveButtonStyleBoxScript.new().configure_small(BUTTON_SQUARE_V5, BUTTON_SHORTWIDE_V5, BUTTON_WIDESMALL_V5)
	var p := AdaptiveButtonStyleBoxScript.new().configure_small(BUTTON_SQUARE_V5, BUTTON_SHORTWIDE_V5, BUTTON_WIDESMALL_V5)
	_set_v5_feedback(p, BUTTON_PRESS_FILL, BUTTON_PRESS_SHADOW, 4)
	var d := AdaptiveButtonStyleBoxScript.new().configure_small(preload(COMPONENT_V3_ROOT + "/button_square_disabled_v5.png"), preload(COMPONENT_V3_ROOT + "/button_shortwide_disabled_v5.png"), preload(COMPONENT_V3_ROOT + "/button_widesmall_disabled_v5.png"))
	theme.set_stylebox("normal", variation, n); theme.set_stylebox("hover", variation, n); theme.set_stylebox("focus", variation, n)
	theme.set_stylebox("pressed", variation, p); theme.set_stylebox("disabled", variation, d)
	theme.set_color("font_color", variation, PARCHMENT); theme.set_color("font_hover_color", variation, Color.WHITE); theme.set_color("font_pressed_color", variation, Color("ffe2ad")); theme.set_color("font_disabled_color", variation, MUTED.darkened(0.24)); theme.set_constant("outline_size", variation, 3)


static func _apply_exact_skill_button(theme: Theme, variation: StringName, texture: Texture2D, mask: Texture2D, frame: Texture2D, fill := Color(0.055, 0.035, 0.018, 0.96)) -> void:
	theme.set_type_variation(variation, "Button")
	var normal := _exact_skill_frame_style(texture, mask, frame, fill)
	var pressed := _exact_skill_frame_style(texture, mask, frame, BUTTON_PRESS_FILL)
	theme.set_stylebox("normal", variation, normal)
	theme.set_stylebox("hover", variation, normal)
	theme.set_stylebox("focus", variation, normal)
	theme.set_stylebox("pressed", variation, pressed)
	theme.set_stylebox("disabled", variation, normal)
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_hover_color", variation, Color.WHITE)
	theme.set_color("font_pressed_color", variation, Color("ffe2ad"))
	theme.set_color("font_disabled_color", variation, MUTED.darkened(0.24))
	theme.set_constant("outline_size", variation, 3)


static func _exact_skill_frame_style(texture: Texture2D, mask: Texture2D, frame: Texture2D, fill: Color) -> AdaptiveButtonStyleBox:
	var style := AdaptiveButtonStyleBoxScript.new().configure_small(texture, texture, texture, fill)
	style.set_precomputed_layered_feedback(fill, texture, mask, frame)
	return style


static func _offset_button_text_up(theme: Theme, variation: StringName, pixels: float) -> void:
	for state: StringName in [&"normal", &"hover", &"focus", &"pressed", &"disabled"]:
		var style := theme.get_stylebox(state, variation)
		style.content_margin_top = 0.0
		style.content_margin_bottom = pixels * 2.0


static func _set_button_horizontal_padding(theme: Theme, variation: StringName, pixels: float) -> void:
	for state: StringName in [&"normal", &"hover", &"focus", &"pressed", &"disabled"]:
		var style := theme.get_stylebox(state, variation)
		style.content_margin_left = pixels
		style.content_margin_right = pixels


static func _prewarm_action_feedback_styles(theme: Theme) -> void:
	# Transaction/result feedback is shown immediately after a tap.  Build the
	# two result styles once with the shared Theme so a first transaction does
	# not allocate layered StyleBoxes in the input frame.
	for variation: StringName in [
		&"GothicInventoryActionGemButton",
		&"GothicShopBuyActionGemButton",
		&"GothicShopSellActionGemButton",
		&"GothicQuestActionGemButton",
		&"GothicQuestAbandonPlainButton",
		&"GothicDeathRevivalGemButton",
		&"GothicConfirmationGemButton",
		&"GothicCharacterHallEnterGemButton",
	]:
		var pressed := theme.get_stylebox("pressed", variation) as AdaptiveButtonStyleBox
		if pressed == null:
			continue
		pressed.clone_with_feedback(BUTTON_SUCCESS_FILL, BUTTON_SUCCESS_BORDER, BUTTON_SUCCESS_SHADOW, 5, 10, 1)
		pressed.clone_with_feedback(BUTTON_FAILURE_FILL, BUTTON_FAILURE_BORDER, BUTTON_FAILURE_SHADOW, 5, 10, 1)


static func _visible_alpha_region(texture: Texture2D, region: Rect2) -> Texture2D:
	var visible_texture := AtlasTexture.new()
	visible_texture.atlas = texture
	visible_texture.region = region
	return visible_texture


static func _apply_character_hall_exact_buttons(theme: Theme) -> void:
	_apply_exact_skill_button(theme, &"GothicCharacterHallProfilePlainButton", _visible_alpha_region(CHARACTER_HALL_PROFILE_PLAIN_184X81, Rect2(1, 8, 182, 63)), _visible_alpha_region(CHARACTER_HALL_PROFILE_PLAIN_184X81_MASK, Rect2(1, 8, 182, 63)), _visible_alpha_region(CHARACTER_HALL_PROFILE_PLAIN_184X81_FRAME, Rect2(1, 8, 182, 63)))
	_apply_exact_skill_button(theme, &"GothicCharacterHallSelectedProfilePlainButton", _visible_alpha_region(CHARACTER_HALL_PROFILE_PLAIN_184X81, Rect2(1, 8, 182, 63)), _visible_alpha_region(CHARACTER_HALL_PROFILE_PLAIN_184X81_MASK, Rect2(1, 8, 182, 63)), _visible_alpha_region(CHARACTER_HALL_PROFILE_PLAIN_184X81_FRAME, Rect2(1, 8, 182, 63)), BUTTON_SELECTED_FILL)
	_apply_exact_skill_button(theme, &"GothicCharacterHallAIPlainButton", _visible_alpha_region(CHARACTER_HALL_AI_PLAIN_80X81, Rect2(7, 1, 63, 79)), _visible_alpha_region(CHARACTER_HALL_AI_PLAIN_80X81_MASK, Rect2(7, 1, 63, 79)), _visible_alpha_region(CHARACTER_HALL_AI_PLAIN_80X81_FRAME, Rect2(7, 1, 63, 79)))
	_apply_exact_skill_button(theme, &"GothicCharacterHallProfessionGemButton", _visible_alpha_region(CHARACTER_HALL_PROFESSION_GEM_98X132, Rect2(6, 2, 82, 128)), _visible_alpha_region(CHARACTER_HALL_PROFESSION_GEM_98X132_MASK, Rect2(6, 2, 82, 128)), _visible_alpha_region(CHARACTER_HALL_PROFESSION_GEM_98X132_FRAME, Rect2(6, 2, 82, 128)))
	_apply_exact_skill_button(theme, &"GothicCharacterHallSelectedProfessionGemButton", _visible_alpha_region(CHARACTER_HALL_PROFESSION_GEM_98X132, Rect2(6, 2, 82, 128)), _visible_alpha_region(CHARACTER_HALL_PROFESSION_GEM_98X132_MASK, Rect2(6, 2, 82, 128)), _visible_alpha_region(CHARACTER_HALL_PROFESSION_GEM_98X132_FRAME, Rect2(6, 2, 82, 128)), BUTTON_SELECTED_FILL)
	_apply_exact_skill_button(theme, &"GothicCharacterHallEnterGemButton", _visible_alpha_region(CHARACTER_HALL_ENTER_GEM_286X62, Rect2(1, 3, 284, 54)), _visible_alpha_region(CHARACTER_HALL_ENTER_GEM_286X62_MASK, Rect2(1, 3, 284, 54)), _visible_alpha_region(CHARACTER_HALL_ENTER_GEM_286X62_FRAME, Rect2(1, 3, 284, 54)))
	_apply_exact_skill_button(theme, &"GothicCharacterHallDeleteGemButton", _visible_alpha_region(CHARACTER_HALL_DELETE_GEM_120X62, Rect2(1, 3, 118, 54)), _visible_alpha_region(CHARACTER_HALL_DELETE_GEM_120X62_MASK, Rect2(1, 3, 118, 54)), _visible_alpha_region(CHARACTER_HALL_DELETE_GEM_120X62_FRAME, Rect2(1, 3, 118, 54)))
	_apply_exact_skill_button(theme, &"GothicCharacterHallCreateGemButton", _visible_alpha_region(CHARACTER_HALL_CREATE_GEM_310X58, Rect2(1, 3, 308, 53)), _visible_alpha_region(CHARACTER_HALL_CREATE_GEM_310X58_MASK, Rect2(1, 3, 308, 53)), _visible_alpha_region(CHARACTER_HALL_CREATE_GEM_310X58_FRAME, Rect2(1, 3, 308, 53)))
	for variation: StringName in [
		&"GothicCharacterHallProfilePlainButton",
		&"GothicCharacterHallSelectedProfilePlainButton",
		&"GothicCharacterHallAIPlainButton",
		&"GothicCharacterHallProfessionGemButton",
		&"GothicCharacterHallSelectedProfessionGemButton",
	]:
		_offset_button_text_up(theme, variation, 2.0)
	for variation: StringName in [
		&"GothicCharacterHallProfessionGemButton",
		&"GothicCharacterHallSelectedProfessionGemButton",
	]:
		_set_button_horizontal_padding(theme, variation, 8.0)
	for variation: StringName in [
		&"GothicCharacterHallEnterGemButton",
		&"GothicCharacterHallDeleteGemButton",
		&"GothicCharacterHallCreateGemButton",
	]:
		_offset_button_text_up(theme, variation, 3.0)


static func _apply_warehouse_thin_button(theme: Theme) -> void:
	var variation := &"GothicWarehouseThinButton"
	_apply_exact_skill_button(
		theme,
		variation,
		_visible_alpha_region(SKILL_CONFIG_PLAIN_108X60, Rect2(1, 5, 106, 48)),
		_visible_alpha_region(SKILL_CONFIG_PLAIN_108X60_MASK, Rect2(1, 5, 106, 48)),
		_visible_alpha_region(SKILL_CONFIG_PLAIN_108X60_FRAME, Rect2(1, 5, 106, 48))
	)
	_offset_button_text_up(theme, variation, 2.0)


static func _set_v4_feedback(style: AdaptiveButtonStyleBox, fill: Color, shadow: Color, shadow_size: float) -> void:
	style.set_precomputed_layered_feedback_family(
		fill,
		[BUTTON_COMPACT_V4, BUTTON_STANDARD_V4, BUTTON_WIDE_V4],
		[BUTTON_COMPACT_FEEDBACK_MASK_V1, BUTTON_STANDARD_FEEDBACK_MASK_V1, BUTTON_WIDE_FEEDBACK_MASK_V1],
		[BUTTON_COMPACT_FRAME_ONLY_V1, BUTTON_STANDARD_FRAME_ONLY_V1, BUTTON_WIDE_FRAME_ONLY_V1],
		[BUTTON_ADAPTIVE_PATCH, BUTTON_ADAPTIVE_PATCH, BUTTON_ADAPTIVE_PATCH],
		shadow,
		shadow_size,
	)


static func _set_v5_feedback(style: AdaptiveButtonStyleBox, fill: Color, shadow: Color, shadow_size: float) -> void:
	_ensure_v5_feedback_layers()
	if _button_v5_feedback_masks.size() != 3 or _button_v5_frame_only.size() != 3:
		return
	style.set_precomputed_layered_feedback_family(
		fill,
		[BUTTON_SQUARE_V5, BUTTON_SHORTWIDE_V5, BUTTON_WIDESMALL_V5],
		_button_v5_feedback_masks,
		_button_v5_frame_only,
	)


static func _ensure_v5_feedback_layers() -> void:
	if _button_v5_feedback_masks.size() == 3 and _button_v5_frame_only.size() == 3:
		return
	_button_v5_feedback_masks.clear()
	_button_v5_frame_only.clear()
	for path: String in BUTTON_V5_FEEDBACK_MASK_PATHS:
		var texture := ResourceLoader.load(path) as Texture2D
		if texture == null:
			push_error("按钮反馈遮罩缺失：%s" % path)
			_button_v5_feedback_masks.clear()
			_button_v5_frame_only.clear()
			return
		_button_v5_feedback_masks.append(texture)
	for path: String in BUTTON_V5_FRAME_ONLY_PATHS:
		var texture := ResourceLoader.load(path) as Texture2D
		if texture == null:
			push_error("按钮原框分层缺失：%s" % path)
			_button_v5_feedback_masks.clear()
			_button_v5_frame_only.clear()
			return
		_button_v5_frame_only.append(texture)


static func _character_frame_style(
	texture: Texture2D,
	fill: Color,
	feedback_fill := Color.TRANSPARENT,
	feedback_mask: Texture2D = null,
	frame_only: Texture2D = null,
) -> AdaptiveButtonStyleBox:
	var style := AdaptiveButtonStyleBoxScript.new().configure_small(texture, texture, texture, fill)
	if feedback_fill != Color.TRANSPARENT:
		if feedback_mask != null and frame_only != null:
			style.set_precomputed_layered_feedback(feedback_fill, texture, feedback_mask, frame_only)
		else:
			style.set_feedback(feedback_fill, Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0, true)
	return style


static func _apply_character_choice_variations(
	theme: Theme,
	normal_variation: StringName,
	selected_variation: StringName,
	texture: Texture2D,
	feedback_mask: Texture2D,
	frame_only: Texture2D,
) -> void:
	for variation: StringName in [normal_variation, selected_variation]:
		theme.set_type_variation(variation, "Button")
		var selected := variation == selected_variation
		var normal_fill := CHARACTER_SELECTED_FILL if selected else CHARACTER_FRAME_BASE_FILL
		var hover_fill := CHARACTER_SELECTED_HOVER_FILL if selected else CHARACTER_FRAME_BASE_FILL
		theme.set_stylebox("normal", variation, _character_frame_style(texture, normal_fill, CHARACTER_SELECTED_FILL if selected else Color.TRANSPARENT, feedback_mask, frame_only))
		theme.set_stylebox("hover", variation, _character_frame_style(texture, hover_fill, CHARACTER_SELECTED_HOVER_FILL if selected else Color.TRANSPARENT, feedback_mask, frame_only))
		theme.set_stylebox("focus", variation, _character_frame_style(texture, hover_fill, CHARACTER_SELECTED_HOVER_FILL if selected else Color.TRANSPARENT, feedback_mask, frame_only))
		theme.set_stylebox("pressed", variation, _character_frame_style(texture, CHARACTER_SELECTED_PRESSED_FILL if selected else CHARACTER_FRAME_BASE_FILL, CHARACTER_SELECTED_PRESSED_FILL if selected else CHARACTER_PRESS_FILL, feedback_mask, frame_only))
		theme.set_stylebox("disabled", variation, _character_frame_style(texture, CHARACTER_FRAME_BASE_FILL))
		theme.set_color("font_color", variation, CHARACTER_SELECTED_FONT if selected else PARCHMENT)
		theme.set_color("font_hover_color", variation, CHARACTER_SELECTED_FONT if selected else Color.WHITE)
		theme.set_color("font_pressed_color", variation, CHARACTER_SELECTED_FONT if selected else PARCHMENT)
		theme.set_color("font_disabled_color", variation, MUTED.darkened(0.24))
		theme.set_color("font_outline_color", variation, CHARACTER_SELECTED_FONT_OUTLINE if selected else Color.TRANSPARENT)
		theme.set_color("font_shadow_color", variation, CHARACTER_SELECTED_FONT_SHADOW if selected else Color.TRANSPARENT)
		theme.set_constant("outline_size", variation, 2 if selected else 0)
		theme.set_constant("shadow_offset_x", variation, 1 if selected else 0)
		theme.set_constant("shadow_offset_y", variation, 1 if selected else 0)


static func _apply_character_hall_buttons(theme: Theme) -> void:
	_apply_character_choice_variations(theme, &"GothicCharacterProfileButton", &"GothicCharacterSelectedProfileButton", CHARACTER_PROFILE_FRAME_V7, CHARACTER_PROFILE_FEEDBACK_MASK_V1, CHARACTER_PROFILE_FRAME_ONLY_V1)
	_apply_character_choice_variations(theme, &"GothicCharacterProfessionButton", &"GothicCharacterSelectedProfessionButton", CHARACTER_PROFESSION_FRAME_V7, CHARACTER_PROFESSION_FEEDBACK_MASK_V1, CHARACTER_PROFESSION_FRAME_ONLY_V1)
	var ai_variation := &"GothicCharacterAIStatusButton"
	theme.set_type_variation(ai_variation, "Button")
	var ai_normal := _character_frame_style(CHARACTER_AI_STATUS_FRAME_V7, CHARACTER_FRAME_BASE_FILL)
	var ai_hover := _character_frame_style(CHARACTER_AI_STATUS_FRAME_V7, Color(0.075, 0.038, 0.045, 0.96))
	var ai_pressed := _character_frame_style(CHARACTER_AI_STATUS_FRAME_V7, Color(0.11, 0.045, 0.045, 0.98), CHARACTER_PRESS_FILL, CHARACTER_AI_STATUS_FEEDBACK_MASK_V1, CHARACTER_AI_STATUS_FRAME_ONLY_V1)
	theme.set_stylebox("normal", ai_variation, ai_normal)
	theme.set_stylebox("hover", ai_variation, ai_hover)
	theme.set_stylebox("focus", ai_variation, ai_hover)
	theme.set_stylebox("pressed", ai_variation, ai_pressed)
	theme.set_stylebox("disabled", ai_variation, ai_normal)
	theme.set_color("font_color", ai_variation, PARCHMENT)
	theme.set_color("font_hover_color", ai_variation, Color.WHITE)
	theme.set_color("font_pressed_color", ai_variation, Color("ffe2ad"))
	theme.set_color("font_disabled_color", ai_variation, MUTED.darkened(0.12))
	theme.set_constant("outline_size", ai_variation, 3)


static func _apply_character_launch_button(theme: Theme) -> void:
	var variation := &"GothicCharacterLaunchButton"
	theme.set_type_variation(variation, "Button")
	var normal := AdaptiveButtonStyleBoxScript.new().configure(BUTTON_COMPACT_V4, BUTTON_STANDARD_V4, BUTTON_WIDE_V4)
	var hover := AdaptiveButtonStyleBoxScript.new().configure(BUTTON_COMPACT_V4, BUTTON_STANDARD_V4, BUTTON_WIDE_V4)
	var pressed := AdaptiveButtonStyleBoxScript.new().configure(BUTTON_COMPACT_V4, BUTTON_STANDARD_V4, BUTTON_WIDE_V4)
	_set_v4_feedback(pressed, CHARACTER_TRANSITION_FILL, Color.TRANSPARENT, 0)
	theme.set_stylebox("normal", variation, normal)
	theme.set_stylebox("hover", variation, hover)
	theme.set_stylebox("focus", variation, hover)
	theme.set_stylebox("pressed", variation, pressed)
	theme.set_stylebox("disabled", variation, normal)
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_hover_color", variation, Color.WHITE)
	theme.set_color("font_pressed_color", variation, Color("ffe2ad"))
	theme.set_color("font_disabled_color", variation, MUTED.darkened(0.24))
	theme.set_constant("outline_size", variation, 3)


static func _apply_slot_button_variation(theme: Theme, variation: StringName, selected: bool) -> void:
	theme.set_type_variation(variation, "Button")
	if selected:
		# Semantic multi-selection must dominate transient Button state. Reused
		# slot nodes retain hover/focus after a touch, so different state boxes
		# would make the first and later selected items appear at different
		# brightness. Share one visible full-cell fill for every selected state.
		var selected_box := _slot_box(Color("3b2015"), Color("d39a52"), 1)
		_apply_selected_flat_feedback(selected_box)
		for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
			theme.set_stylebox(state, variation, selected_box)
	else:
		var normal := _slot_box(Color("0c0a09"), Color("594532"), 1)
		var hover := _slot_box(Color("18110c"), Color("9a7044"), 1)
		var pressed := _slot_box(Color("26160c"), Color("d3a15e"), 1)
		_apply_flat_press_feedback(pressed)
		theme.set_stylebox("normal", variation, normal)
		theme.set_stylebox("hover", variation, hover)
		theme.set_stylebox("pressed", variation, pressed)
		theme.set_stylebox("focus", variation, normal)
	theme.set_stylebox("disabled", variation, _slot_box(Color("090807"), Color("332a22"), 1))
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_hover_color", variation, Color.WHITE)
	theme.set_color("font_pressed_color", variation, Color("ffe2ad"))
	theme.set_color("font_outline_color", variation, Color(0.025, 0.012, 0.008, 1.0))
	theme.set_constant("outline_size", variation, 3)


static func _apply_equipment_slot_button_variation(theme: Theme, variation: StringName, selected: bool) -> void:
	theme.set_type_variation(variation, "Button")
	var normal := _equipment_slot_box(Color("21150d"), Color("c18a49"), 1) if selected else _equipment_slot_box(Color("0b0a09"), Color("72583b"), 1)
	var hover := _equipment_slot_box(Color("15100c"), Color("a77a46"), 1)
	var pressed := _equipment_slot_box(Color("25150b"), Color("d8a25b"), 1)
	_apply_flat_press_feedback(pressed)
	if selected:
		_apply_selected_flat_feedback(normal)
	theme.set_stylebox("normal", variation, normal)
	theme.set_stylebox("hover", variation, hover)
	theme.set_stylebox("pressed", variation, pressed)
	# Focus is input navigation state, not semantic selection. Reusing hover here
	# leaves a bright border after a toggle button has been deselected.
	theme.set_stylebox("focus", variation, normal)
	theme.set_stylebox("disabled", variation, _equipment_slot_box(Color("080706"), Color("352b22"), 1))
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_outline_color", variation, Color(0.025, 0.012, 0.008, 1.0))
	theme.set_constant("outline_size", variation, 3)


static func _equipment_slot_box(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _flat(background, border, width, 1)
	style.anti_aliasing = false
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.78)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func _apply_selected_flat_feedback(style: StyleBox) -> void:
	if not style is StyleBoxFlat:
		return
	var flat := style as StyleBoxFlat
	flat.shadow_color = BUTTON_SELECTED_SHADOW
	flat.shadow_size = 5
	flat.shadow_offset = Vector2.ZERO


static func _slot_box(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _flat(background, border, width, 2)
	style.anti_aliasing = false
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func _flat(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


static func _texture(texture: Texture2D, margins: Vector4, content_margin: float, modulate := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = modulate
	style.draw_center = true
	style.set_texture_margin(SIDE_LEFT, margins.x)
	style.set_texture_margin(SIDE_TOP, margins.y)
	style.set_texture_margin(SIDE_RIGHT, margins.z)
	style.set_texture_margin(SIDE_BOTTOM, margins.w)
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style
