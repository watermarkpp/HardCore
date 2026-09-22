class_name GroundSkillVisualCell
extends GroundSkillEffect


## Q2-C: explicit ownership contract. FireWallFieldController owns every
## damage/claim/enemy-query decision; a cell is a pure animation/presentation
## node. It may keep a read-only canonical snapshot copy and its local offsets,
## never a damage geometry truth.
const DAMAGE_OWNER := &"fire_wall_controller"

var damage_owner := DAMAGE_OWNER
var visual_only := true
var cell_index := -1
var canonical_snapshot_id := ""
var cell_ground_offset := Vector2.ZERO
var cell_screen_offset_px := Vector2.ZERO
var _controller_owned_lifetime := false


func set_controller_owned_lifetime() -> void:
	_controller_owned_lifetime = true
	set_physics_process(false)


func _ready() -> void:
	super._ready()


func _physics_process(delta: float) -> void:
	if _controller_owned_lifetime:
		return
	# Visual cells are pure presentation objects. All damage logic,
	# enemy iteration, and tick claims live exclusively in
	# FireWallFieldController.  Bypassing the parent's combat loop
	# guarantees one enemy-group scan per tick per fire-wall field.
	duration -= delta
	if duration <= 0.0:
		queue_free()
		return
	if _sprite == null:
		queue_redraw()


## SOT same_caster_same_tile_refreshes_duration: a same-tile recast re-arms
## the cell lifetime from the refreshed field duration so presentation nodes
## never outlive (or die before) their controller.
func refresh_lifetime(new_duration: float) -> void:
	duration = maxf(0.1, new_duration)


func runtime_diagnostics() -> Dictionary:
	return {
		"enemy_group_queries": 0,
		"damage_ticks": 0,
	}
