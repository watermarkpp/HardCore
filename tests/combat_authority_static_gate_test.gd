extends Node

## Combat authority static gate (GPT audit R1-P0 close-out).
## Locks the production combat candidate/delivery authority contract:
##   1. GroundSkillEffect must not scan the enemies group and must not call
##      take_damage directly (candidates: RuntimeCombatSpatialIndex,
##      delivery: injected runtime_tick_adapter only).
##   2. FireWallFieldController must not scan the enemies group and must not
##      call take_damage directly (delivery: runtime_tick_callback only).
##   3. The fire wall runtime must keep the explicit fail-closed cap policy
##      (evict_oldest only via configured data, never implicit).
## If a future change needs to touch these invariants, it must do so through
## a reviewed contract change, not by silently reintroducing the old paths.

const _GROUND_EFFECT_SOURCE := "res://scripts/ground_effect.gd"
const _CONTROLLER_SOURCE := "res://scripts/fire_wall_field_controller.gd"
const _GAME_ROOT_SOURCE := "res://scripts/game_root.gd"
const _QUERY_SERVICE_SOURCE := (
	"res://scripts/layers/runtime/combat_target_query_service.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ground_effect_source := _read(_GROUND_EFFECT_SOURCE)
	assert(
		not ground_effect_source.contains('get_nodes_in_group("enemies")'),
		"GroundSkillEffect must not scan the enemies group (R1-P0 item 3)"
	)
	assert(
		not ground_effect_source.contains("take_damage("),
		"GroundSkillEffect must not deliver damage via take_damage "
		+ "(R1-P0 item 5)"
	)
	assert(
		ground_effect_source.contains(
			"_combat_spatial_index.query_aabb_candidates("
		),
		"GroundSkillEffect self-managed tick must use the shared spatial index"
	)
	var controller_source := _read(_CONTROLLER_SOURCE)
	assert(
		not controller_source.contains('get_nodes_in_group("enemies")'),
		"FireWallFieldController must not scan the enemies group"
	)
	assert(
		not controller_source.contains("take_damage("),
		"FireWallFieldController must not deliver damage via take_damage"
	)
	var game_root_source := _read(_GAME_ROOT_SOURCE)
	assert(
		game_root_source.contains("FIRE_WALL_CAP_POLICY_REJECT_NEW"),
		"fire wall cap policy must stay explicit and fail-closed"
	)
	assert(
		game_root_source.contains("_fire_wall_registry_key("),
		"fire wall registry key must stay source-aware"
	)
	var query_service_source := _read(_QUERY_SERVICE_SOURCE)
	assert(
		not query_service_source.contains("get_nodes_in_group("),
		"CombatTargetQueryService must never scan scene-tree groups"
	)
	assert(
		not query_service_source.contains("take_damage("),
		"CombatTargetQueryService must never deliver damage"
	)
	print("COMBAT_AUTHORITY_STATIC_GATE_PASS")
	get_tree().quit(0)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "cannot read source for static gate: %s" % path)
	return file.get_as_text()
