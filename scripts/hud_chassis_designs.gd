class_name HUDChassisDesigns
extends RefCounted

## Bottom chassis design registry for the HUD (主界面下方框体).
##
## 2026-09-16 user decision: adopt the v3_dragon frame (2172x724 user-authored
## art with slot wells pre-cut as alpha holes) and ship ONLY that version. The
## legacy v2 chassis and the other three v3 candidates were removed from the
## asset tree; their measurements remain recorded in
## assets/ui/gothic_hud/v3/gothic_hud_frame_geometry_v3.json for provenance.
##
## All geometry is stored in source pixel space and mapped to the display rect
## with the same aspect fit as GameHUD._chassis_source_to_local.

## 2026-09-20 user order: shrink the whole chassis 20% (820x273 -> 656x218.4),
## anchored at the bottom spike tip (source ~(1085, 705), measured by alpha
## scan). Internal wells (orbs, item slots, experience slot) scale through the
## same source_to_local mapping; item icons intentionally stay at native
## texture size (user decision, icon art must not shrink).
const LEGACY_DISPLAY_SIZE := Vector2(820, 273)
const DISPLAY_SIZE := Vector2(656, 218.4)
## Display-pixel sizes authored for the legacy 820x273 mapping must shrink by
## the same ratio so wells keep filling their cutouts.
const DISPLAY_SCALE_RATIO := DISPLAY_SIZE.x / LEGACY_DISPLAY_SIZE.x

const COMPARE_DESIGN_IDS: Array[String] = [
	"v3_dragon",
]

const ACTIVE_DESIGN_ID := "v3_dragon"

const DESIGNS := {
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
		"orb_display_size": 93.0 * DISPLAY_SCALE_RATIO,
		"item_slot_centers_source": [
			Vector2(785.0, 412.5),
			Vector2(981.0, 412.5),
			Vector2(1190.5, 412.5),
			Vector2(1388.0, 412.5),
		],
		"item_slot_fill_display_size": Vector2(50, 51) * DISPLAY_SCALE_RATIO,
		"item_slot_fill_render_size": Vector2(56, 57) * DISPLAY_SCALE_RATIO,
		"experience_bar_policy": "chassis_design_xp_slot.v1",
		"experience_slot_source_rect": Rect2(675, 560, 821, 35),
		"experience_slot_render_bleed": Vector2(16, 8) * DISPLAY_SCALE_RATIO,
		"chassis_stable_id": "ui.hud.gothic.v3.bottom_chassis",
		"sanitize_policy": "none",
		"center_peak_source": Vector2(1086, 139),
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
