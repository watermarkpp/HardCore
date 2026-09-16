class_name HUDChassisDesigns
extends RefCounted

## Bottom chassis design registry for the HUD (主界面下方框体).
##
## v2_demon is the shipped 2026-09 baseline (1009x336 source). The v3_* designs
## are the user-authored 2172x724 candidate frames from 2026-09-14 with the
## slot wells pre-cut as alpha holes; their geometry was measured from those
## holes by tools/build_chassis_design_v3_assets_20260914.py and is recorded in
## assets/ui/gothic_hud/v3/gothic_hud_frame_geometry_v3.json.
##
## All geometry is stored in source pixel space and mapped to the display rect
## with the same aspect fit as GameHUD._chassis_source_to_local. Switching the
## active design is a one-line change of ACTIVE_DESIGN_ID.

const DISPLAY_SIZE := Vector2(820, 273)

## Candidate presentation order used by the UI workbench compare windows.
## 2026-09-16 user decision: adopt v3_dragon; the other candidates are closed.
const COMPARE_DESIGN_IDS: Array[String] = [
	"v3_dragon",
]

const ACTIVE_DESIGN_ID := "v3_dragon"

const DESIGNS := {
	"v2_demon": {
		"id": "v2_demon",
		"display_name": "经典恶魔",
		"texture_path": "res://assets/ui/gothic_hud/v2/runtime/bottom_chassis_v2.png",
		"source_size": Vector2(1009, 336),
		"health_orb_center_source": Vector2(223.5, 230.5),
		"mana_orb_center_source": Vector2(785.5, 230.5),
		"orb_display_size": 110.0,
		"item_slot_centers_source": [
			Vector2(349.5, 235.0),
			Vector2(452.0, 234.5),
			Vector2(558.5, 234.5),
			Vector2(662.0, 234.5),
		],
		"item_slot_fill_display_size": Vector2(72, 72),
		"experience_bar_policy": "item_quick_slot_outer_frame_union.v1",
		"experience_slot_source_rect": Rect2(),
		"chassis_stable_id": "ui.hud.gothic.v2.bottom_chassis",
		"sanitize_policy": "v2_legacy_skill_mask.v1",
		"center_peak_source": Vector2(505, 115),
	},
	"v3_dragon": {
		"id": "v3_dragon",
		"display_name": "魔龙",
		"texture_path": "res://assets/ui/gothic_hud/v3/runtime/bottom_chassis_v3_dragon.png",
		"source_size": Vector2(2172, 724),
		# 2026-09-16 user review: orbs/fills must fill the cut wells completely.
		# Wells are drawn under the frame art and oversized so the opaque rim
		# masks the anti-aliased well edge (BFS alpha<200 re-measure supersedes
		# the generator bbox for render coverage).
		"health_orb_center_source": Vector2(532.0, 410.0),
		"mana_orb_center_source": Vector2(1640.0, 410.0),
		"orb_display_size": 93.0,
		"item_slot_centers_source": [
			Vector2(785.0, 412.5),
			Vector2(981.0, 412.5),
			Vector2(1190.5, 412.5),
			Vector2(1388.0, 412.5),
		],
		"item_slot_fill_display_size": Vector2(50, 51),
		"item_slot_fill_render_size": Vector2(56, 57),
		"experience_bar_policy": "chassis_design_xp_slot.v1",
		"experience_slot_source_rect": Rect2(675, 560, 821, 35),
		"experience_slot_render_bleed": Vector2(16, 8),
		"chassis_stable_id": "ui.hud.gothic.v3.bottom_chassis",
		"sanitize_policy": "none",
		"center_peak_source": Vector2(1086, 139),
	},
	"v3_lion": {
		"id": "v3_lion",
		"display_name": "雄狮",
		"texture_path": "res://assets/ui/gothic_hud/v3/runtime/bottom_chassis_v3_lion.png",
		"source_size": Vector2(2172, 724),
		"health_orb_center_source": Vector2(493.0, 411.5),
		"mana_orb_center_source": Vector2(1679.0, 411.5),
		"orb_display_size": 90.0,
		"item_slot_centers_source": [
			Vector2(753.5, 415.0),
			Vector2(971.5, 415.0),
			Vector2(1201.0, 414.5),
			Vector2(1420.0, 415.0),
		],
		"item_slot_fill_display_size": Vector2(56, 55),
		"experience_bar_policy": "chassis_design_xp_slot.v1",
		"experience_slot_source_rect": Rect2(652, 561, 869, 32),
		"chassis_stable_id": "ui.hud.gothic.v3.bottom_chassis",
		"sanitize_policy": "none",
		"center_peak_source": Vector2(1086, 159),
	},
	"v3_winged_lion": {
		"id": "v3_winged_lion",
		"display_name": "飞狮",
		"texture_path": "res://assets/ui/gothic_hud/v3/runtime/bottom_chassis_v3_winged_lion.png",
		"source_size": Vector2(2172, 724),
		"health_orb_center_source": Vector2(527.5, 412.0),
		"mana_orb_center_source": Vector2(1643.5, 412.0),
		"orb_display_size": 91.0,
		"item_slot_centers_source": [
			Vector2(781.5, 415.5),
			Vector2(981.5, 415.0),
			Vector2(1189.0, 415.0),
			Vector2(1390.5, 415.5),
		],
		"item_slot_fill_display_size": Vector2(50, 52),
		"experience_bar_policy": "chassis_design_xp_slot.v1",
		"experience_slot_source_rect": Rect2(677, 566, 817, 28),
		"chassis_stable_id": "ui.hud.gothic.v3.bottom_chassis",
		"sanitize_policy": "none",
		"center_peak_source": Vector2(1086, 144),
	},
	"v3_demon": {
		"id": "v3_demon",
		"display_name": "恶魔",
		"texture_path": "res://assets/ui/gothic_hud/v3/runtime/bottom_chassis_v3_demon.png",
		"source_size": Vector2(2172, 724),
		"health_orb_center_source": Vector2(530.5, 410.5),
		"mana_orb_center_source": Vector2(1640.5, 410.5),
		"orb_display_size": 89.0,
		"item_slot_centers_source": [
			Vector2(783.5, 412.0),
			Vector2(980.5, 412.0),
			Vector2(1190.0, 412.5),
			Vector2(1387.5, 412.0),
		],
		"item_slot_fill_display_size": Vector2(51, 52),
		"experience_bar_policy": "chassis_design_xp_slot.v1",
		"experience_slot_source_rect": Rect2(679, 561, 813, 31),
		"chassis_stable_id": "ui.hud.gothic.v3.bottom_chassis",
		"sanitize_policy": "none",
		"center_peak_source": Vector2(1086, 148),
	},
}

static var _texture_cache: Dictionary = {}


static func design(design_id: String) -> Dictionary:
	assert(DESIGNS.has(design_id), "unknown chassis design id: %s" % design_id)
	return DESIGNS[design_id]


static func active_design() -> Dictionary:
	return design(ACTIVE_DESIGN_ID)


static func load_texture(design: Dictionary) -> Texture2D:
	var path: String = design["texture_path"]
	if not _texture_cache.has(path):
		var texture: Texture2D = load(path) as Texture2D
		assert(texture != null, "chassis design texture missing: %s" % path)
		_texture_cache[path] = texture
	return _texture_cache[path]


static func source_to_local(design: Dictionary, source_point: Vector2) -> Vector2:
	var source_size: Vector2 = design["source_size"]
	var scale := minf(DISPLAY_SIZE.x / source_size.x, DISPLAY_SIZE.y / source_size.y)
	var render_size := source_size * scale
	var render_origin := (DISPLAY_SIZE - render_size) * 0.5
	return render_origin + source_point * scale


static func source_rect_to_local(design: Dictionary, source_rect: Rect2) -> Rect2:
	return Rect2(source_to_local(design, source_rect.position), source_rect.size * _source_scale(design))


static func _source_scale(design: Dictionary) -> float:
	var source_size: Vector2 = design["source_size"]
	return minf(DISPLAY_SIZE.x / source_size.x, DISPLAY_SIZE.y / source_size.y)
