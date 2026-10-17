extends "interactable_actor_model.gd"
const NPCServiceIdentityScript := preload("res://scripts/npc_service_identity.gd")
const ArtSpec := preload("res://scripts/art_spec.gd")
const FACING_DIRECTIONS: Array[Vector2] = [
	Vector2.DOWN, Vector2(-0.70710678, 0.70710678), Vector2.LEFT, Vector2(-0.70710678, -0.70710678),
	Vector2.UP, Vector2(0.70710678, -0.70710678), Vector2.RIGHT, Vector2(0.70710678, 0.70710678),
]

var npc_name := "NPC"
var npc_kind := "shop"
var shop_stock: Array = []
var stock_key := ""
var service_identity_id := ""
var appearance := -1
var facing := Vector2.DOWN
var default_facing := Vector2.DOWN
var map_center := Vector2.ZERO


func setup(display_name: String, kind: String, stock: Array = [], dynamic_stock_key := "", npc_appearance := -1, center := Vector2.ZERO) -> void:
	npc_kind = kind
	shop_stock = stock
	stock_key = dynamic_stock_key
	var service_identity := NPCServiceIdentityScript.resolve(display_name, kind, dynamic_stock_key)
	service_identity_id = str(service_identity.get("id", ""))
	npc_name = str(service_identity.get("display_name", display_name))
	appearance = npc_appearance if npc_appearance >= 0 else _fallback_appearance(display_name, kind, dynamic_stock_key)
	map_center = center

func face_toward(target_position: Vector2, as_default := false) -> void:
	var direction := global_position.direction_to(target_position)
	if direction.length_squared() < 0.0001:
		direction = Vector2.DOWN
	facing = FACING_DIRECTIONS[ArtSpec.direction_index(direction)]
	if as_default:
		default_facing = facing
	_refresh_name_label_anchor()

func reset_to_default_facing() -> void:
	facing = default_facing
	_refresh_name_label_anchor()

func _fallback_appearance(display_name: String, kind: String, dynamic_stock_key: String) -> int:
	# Exact server Image wins when available. These are stable presentation fallbacks.
	if "武器" in display_name or "铁匠" in display_name or dynamic_stock_key in ["starter_gear", "mid_gear"]:
		return 11
	if "书" in display_name or dynamic_stock_key == "books":
		return 8
	if "武馆" in display_name or kind == "trainer":
		return 15
	if "仓库" in display_name or kind == "warehouse":
		return 14
	if "老兵" in display_name or kind == "quest":
		return 0
	if "杂货" in display_name or dynamic_stock_key == "general":
		return 10
	return posmod(display_name.hash(), 23)

func interaction_text() -> String:
	return "与%s交谈" % npc_name

func initialize_gameplay() -> void:
	if _ready_complete: _ports.fail("npc_ready_twice"); return
	add_to_group("interactable")
	add_to_group("zone_content")
	face_toward(map_center, true)
	if not _ports.create_npc_visual(self): _ports.fail("npc_original_visual_admission_failed"); return
	_ready_complete = true

func _refresh_name_label_anchor() -> void:
	_ports.refresh_npc_facing(self)

func interact(game: Object) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if game != null and is_instance_valid(game.player):
		face_toward(game.player.global_position)
	var interaction_succeeded := false
	if npc_kind == "shop":
		var active_stock := shop_stock
		if stock_key == "books":
			active_stock = game._build_skill_book_stock(game._world.profile.profession_id)
		# Keep the merchant identity explicit even when the stock is empty or
		# filtered. ShopPanel must not infer authority from stock[0].
		var merchant_context: Dictionary = game._world.owner_services.GameData.merchant_context(stock_key)
		game.hud.open_shop(npc_name, active_stock, merchant_context)
		interaction_succeeded = true
	elif npc_kind == "trainer":
		game.hud.open_enhancement_vendor(npc_name)
		interaction_succeeded = true
	elif npc_kind == "quest":
		game.hud.open_quest(npc_name)
		interaction_succeeded = true
	elif npc_kind == "guide":
		game.hud.show_message("暗殿真假难辨，沿通道深入后原路返回。", 2.5)
		interaction_succeeded = true
	elif npc_kind == "warehouse":
		game.hud.open_warehouse()
		interaction_succeeded = true
	if interaction_succeeded:
		_notify_interaction_audio(game)

func _notify_interaction_audio(game: Object) -> void:
	if service_identity_id.is_empty() or game == null or not game.has_method("play_npc_interaction_voice"):
		return
	game.call("play_npc_interaction_voice", service_identity_id)

func uses_final_art() -> bool:
	return _visual_bound and _ports.npc_uses_final_art(self)

