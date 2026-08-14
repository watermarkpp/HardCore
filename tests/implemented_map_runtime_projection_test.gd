extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const EPSILON := 0.01


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for map_id: int in [4, 217, 268]:
		assert(
			Bridge.is_runtime_built(map_id),
			"map %d must be runtime-built" % map_id
		)
		assert(
			Bridge.is_formal_playable(map_id),
			"map %d must be formally playable" % map_id
		)
		var profile: Dictionary = Mapper.resolve_formal_runtime_projection_profile(
			map_id
		)
		assert(
			bool(profile.get("success", false)),
			"map %d formal profile must succeed" % map_id
		)
		assert(
			str(profile.get("policy", ""))
			== str(Mapper.PROJECTION_POLICY_MAP_EDITOR_RUNTIME_ABSOLUTE),
			"map %d must be map_editor_runtime_absolute" % map_id
		)
		assert(
			profile.get("source_size", Vector2i.ZERO) != Vector2i.ZERO,
			"map %d formal profile must carry a runtime design size" % map_id
		)
		var ground := Vector2(10.5, 8.25)
		var screen: Vector2 = (
			(profile.get("ground_to_screen", Callable()) as Callable)
			.call(ground)
		)
		var back: Vector2 = (
			(profile.get("screen_to_ground", Callable()) as Callable)
			.call(screen)
		)
		assert(
			back.distance_to(ground) <= EPSILON,
			"map %d runtime profile roundtrip must be identity" % map_id
		)
	# Formal GameRoot spawn on the live runtime map 4.
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for _wait in range(300):
		if not bool(game.get("_world_bootstrap_in_progress")):
			break
		await get_tree().process_frame
	await get_tree().process_frame
	assert(int(game.current_map_id) == 4, "game must boot on runtime map 4")
	var pharmacist: NPCActor = null
	for candidate: Node in get_tree().get_nodes_in_group("interactable"):
		if candidate is NPCActor and str((candidate as NPCActor).stock_key) == "medicine":
			pharmacist = candidate as NPCActor
			break
	assert(pharmacist != null, "runtime map 4 must spawn the Bichon pharmacist")
	assert(not pharmacist.shop_stock.is_empty(), "Bichon pharmacist must receive the primary medicine stock")
	game.hud.open_shop("比奇药剂商", [], GameData.merchant_context("medicine"))
	assert(
		str(game.hud.shop_panel._active_merchant_context().get("merchant_id", ""))
		== str(GameData.merchant_context("medicine").get("merchant_id", "")),
		"shop sell authority must survive an empty stock via explicit context"
	)
	var monster := GameData.get_monster_by_id(21)
	assert(not monster.is_empty(), "monster 21 must exist")
	var enemy: EnemyActor = game._spawn_enemy(
		monster,
		Vector2(0.0, 80.0),
		false
	)
	assert(enemy != null, "runtime map 4 enemy spawn must succeed")
	assert(
		enemy.spatial_index_position().is_finite(),
		"runtime map 4 enemy provider must be finite"
	)
	var candidates: Array = game._combat_spatial_index.query_aabb_candidates(
		4,
		Rect2(
			enemy.spatial_index_position() - Vector2(2, 2),
			Vector2(4, 4)
		),
		0.05
	)
	assert(
		not candidates.is_empty(),
		"runtime map 4 spatial index must contain the enemy"
	)
	game.queue_free()
	await get_tree().process_frame
	print("IMPLEMENTED_MAP_RUNTIME_PROJECTION_PASS maps=4,217,268")
	get_tree().quit(0)
