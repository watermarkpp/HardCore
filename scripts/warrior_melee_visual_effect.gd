class_name WarriorMeleeVisualEffect
extends Node2D
## Presentation-only three-layer translucent band for the target-aligned
## warrior melee release. It consumes the same release footprint snapshot as
## gameplay and never computes a second attack range. Without a strict-valid
## snapshot the effect fails closed (no layers, no visible range).
## INTEGRATION_HOOK: game_root instantiates one node per release via
## create_visual(snapshot, mode, hit_info, coordinate_context, anchor_px).

const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const WarriorMeleeGeometryScript := preload(
	"res://scripts/skills/warrior_melee_geometry.gd"
)

const VISUAL_CONTRACT_ID := "skills.warrior.melee.target_aligned_visual.v1"
const GEOMETRY_CONTRACT_ID := (
	"gameplay.warrior.melee.target_aligned_continuous_release.v1"
)
const ACTOR_VISIBILITY_Z_INDEX := -1
const LAYER_ROLE_OUTER := "outer_faint_glow"
const LAYER_ROLE_MID := "mid_blade_pressure"
const LAYER_ROLE_INNER := "inner_bright_line"
const LAYER_COUNT := 3
const LAYER_ROLES: Array[String] = [
	LAYER_ROLE_OUTER,
	LAYER_ROLE_MID,
	LAYER_ROLE_INNER,
]
const LAYER_SCALES: Array[float] = [1.0, 0.62, 0.24]
const LAYER_ALPHAS: Array[float] = [0.10, 0.18, 0.34]
const POLYGON_VERTEX_TOLERANCE_PX := 0.01

var mode := WarriorMeleeGeometryScript.SKILL_NORMAL
var hit_info: Dictionary = {}
var rejection_reason := ""
var _snapshot: Dictionary = {}
var _snapshot_shape_type := ""
var _projected_polygons_screen_offset_px: Array[PackedVector2Array] = []
var _layers: Array[Polygon2D] = []


static func create_visual(
	snapshot: Dictionary,
	mode_value: String,
	hit_info_value: Dictionary,
	coordinate_context: Dictionary,
	anchor_screen_px := Vector2.ZERO
) -> WarriorMeleeVisualEffect:
	## One call per release. Returns null (fail closed) when the snapshot is
	## missing or invalid so integration never presents a guessed attack range.
	var effect := WarriorMeleeVisualEffect.new()
	effect.setup(
		snapshot,
		mode_value,
		hit_info_value,
		coordinate_context,
		anchor_screen_px
	)
	if not effect.rejection_reason.is_empty():
		effect.free()
		return null
	return effect


static func fail_closed_reason(
	snapshot: Dictionary,
	coordinate_context: Dictionary
) -> String:
	## Machine-checkable rejection reason without instantiating a node.
	if snapshot.is_empty():
		return "missing_snapshot"
	if not bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		coordinate_context,
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false)):
		return "invalid_snapshot"
	if SkillFootprintSnapshotScript.projected_polygons_screen_offset_px(
		snapshot
	).is_empty():
		return "missing_projected_polygon"
	return ""


func setup(
	snapshot: Dictionary,
	mode_value: String,
	hit_info_value: Dictionary,
	coordinate_context: Dictionary,
	anchor_screen_px := Vector2.ZERO
) -> void:
	mode = (
		mode_value
		if mode_value in [
			WarriorMeleeGeometryScript.SKILL_NORMAL,
			WarriorMeleeGeometryScript.SKILL_FIRE,
			WarriorMeleeGeometryScript.SKILL_HALF_MOON,
			WarriorMeleeGeometryScript.SKILL_THRUST,
		]
		else WarriorMeleeGeometryScript.SKILL_NORMAL
	)
	hit_info = hit_info_value.duplicate()
	global_position = anchor_screen_px
	if snapshot.is_empty():
		rejection_reason = "missing_snapshot"
		visible = false
		return
	if not bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		coordinate_context,
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false)):
		rejection_reason = "invalid_snapshot"
		visible = false
		return
	_snapshot = snapshot
	_snapshot_shape_type = str(snapshot.get("shape_type", ""))
	_projected_polygons_screen_offset_px = (
		SkillFootprintSnapshotScript.projected_polygons_screen_offset_px(
			snapshot
		)
	)
	if _projected_polygons_screen_offset_px.is_empty():
		rejection_reason = "missing_projected_polygon"
		visible = false
		return
	_install_layers()
	z_as_relative = true
	z_index = ACTOR_VISIBILITY_Z_INDEX
	add_to_group("zone_content")
	set_meta("target_aligned_visual_contract", VISUAL_CONTRACT_ID)
	set_meta("target_aligned_geometry_contract", GEOMETRY_CONTRACT_ID)
	set_meta("snapshot_id", str(snapshot.get("snapshot_id", "")))
	set_meta("snapshot_shape_type", _snapshot_shape_type)


func visual_ready() -> bool:
	return rejection_reason.is_empty() and _layers.size() == LAYER_COUNT


func presentation_descriptor() -> Dictionary:
	var layer_specs: Array[Dictionary] = []
	var palette := _palette(mode)
	for layer_index: int in range(LAYER_COUNT):
		layer_specs.append({
			"role": LAYER_ROLES[layer_index],
			"color": _layer_color(palette, layer_index),
			"alpha": LAYER_ALPHAS[layer_index],
			"scale": LAYER_SCALES[layer_index],
		})
	var descriptor := {
		"contract_id": VISUAL_CONTRACT_ID,
		"geometry_contract_id": GEOMETRY_CONTRACT_ID,
		"mode": mode,
		"snapshot_id": str(_snapshot.get("snapshot_id", "")),
		"snapshot_shape_type": _snapshot_shape_type,
		"same_snapshot_source": true,
		"projected_polygon_count": (
			_projected_polygons_screen_offset_px.size()
		),
		"layer_count": layer_specs.size(),
		"layer_specs": layer_specs,
		"rejection_reason": rejection_reason,
		"hit_info": hit_info.duplicate(),
	}
	descriptor.make_read_only()
	return descriptor


func layer_polygons_screen_offset_px() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for layer: Polygon2D in _layers:
		result.append(layer.polygon.duplicate())
	return result


func snapshot_id() -> String:
	return str(_snapshot.get("snapshot_id", ""))


func _install_layers() -> void:
	var palette := _palette(mode)
	for polygon_screen_offset_px: PackedVector2Array in (
		_projected_polygons_screen_offset_px
	):
		if polygon_screen_offset_px.size() < 3:
			continue
		for layer_index: int in range(LAYER_COUNT):
			var layer_polygon := _scaled_layer_polygon(
				polygon_screen_offset_px,
				LAYER_SCALES[layer_index]
			)
			if layer_polygon.size() < 3:
				continue
			var layer := Polygon2D.new()
			layer.polygon = layer_polygon
			layer.color = _layer_color(palette, layer_index)
			layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			layer.set_meta(
				"target_aligned_visual_layer_role",
				LAYER_ROLES[layer_index]
			)
			layer.set_meta(
				"target_aligned_visual_layer_scale",
				LAYER_SCALES[layer_index]
			)
			add_child(layer)
			_layers.append(layer)


func _scaled_layer_polygon(
	polygon_screen_offset_px: PackedVector2Array,
	scale: float
) -> PackedVector2Array:
	var safe_scale := clampf(scale, 0.0, 1.0)
	if _snapshot_shape_type == (
		SkillFootprintSnapshotScript.SHAPE_DIRECTED_RECTANGLE
	):
		return _inset_directed_quad(polygon_screen_offset_px, safe_scale)
	# Sector fan: scale radially about the fan apex (first projected vertex,
	# which is the release origin). Inner layers become nested arc bands.
	if polygon_screen_offset_px.is_empty():
		return PackedVector2Array()
	var apex_screen_offset_px := polygon_screen_offset_px[0]
	var result := PackedVector2Array()
	for point_screen_offset_px: Vector2 in polygon_screen_offset_px:
		result.append(
			apex_screen_offset_px
			+ (point_screen_offset_px - apex_screen_offset_px) * safe_scale
		)
	return result


func _inset_directed_quad(
	quad_screen_offset_px: PackedVector2Array,
	lateral_scale: float
) -> PackedVector2Array:
	## Lateral-only inset of a directed quad, matching the caster line-layer
	## convention: at scale 1.0 the returned quad equals the snapshot polygon.
	if quad_screen_offset_px.size() != 4:
		return PackedVector2Array()
	var safe_scale := clampf(lateral_scale, 0.0, 1.0)
	var start_center_px := (
		quad_screen_offset_px[0] + quad_screen_offset_px[3]
	) * 0.5
	var end_center_px := (
		quad_screen_offset_px[1] + quad_screen_offset_px[2]
	) * 0.5
	return PackedVector2Array([
		start_center_px.lerp(quad_screen_offset_px[0], safe_scale),
		end_center_px.lerp(quad_screen_offset_px[1], safe_scale),
		end_center_px.lerp(quad_screen_offset_px[2], safe_scale),
		start_center_px.lerp(quad_screen_offset_px[3], safe_scale),
	])


func _palette(mode_value: String) -> Dictionary:
	match mode_value:
		WarriorMeleeGeometryScript.SKILL_THRUST:
			return {
				"outer": Color(0.32, 0.72, 1.0, LAYER_ALPHAS[0]),
				"mid": Color(0.55, 0.88, 1.0, LAYER_ALPHAS[1]),
				"inner": Color(0.90, 0.98, 1.0, LAYER_ALPHAS[2]),
			}
		WarriorMeleeGeometryScript.SKILL_HALF_MOON:
			return {
				"outer": Color(1.0, 0.78, 0.30, LAYER_ALPHAS[0]),
				"mid": Color(1.0, 0.84, 0.42, LAYER_ALPHAS[1]),
				"inner": Color(1.0, 0.94, 0.62, LAYER_ALPHAS[2]),
			}
		_:
			return {
				"outer": Color(1.0, 0.45, 0.12, LAYER_ALPHAS[0]),
				"mid": Color(1.0, 0.62, 0.18, LAYER_ALPHAS[1]),
				"inner": Color(1.0, 0.88, 0.42, LAYER_ALPHAS[2]),
			}


func _layer_color(palette: Dictionary, layer_index: int) -> Color:
	return palette.get(
		[
			"outer",
			"mid",
			"inner",
		][layer_index],
		Color.WHITE
	) as Color
