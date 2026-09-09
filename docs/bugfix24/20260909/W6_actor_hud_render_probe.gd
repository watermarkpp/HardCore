extends Node2D

## Controlled OpenGL evidence scene. It instantiates the real EnemyActor and
## GameHUD classes, then freezes the selected poses for one deterministic frame.
## It is a probe only; no production scene or GameRoot wiring is changed.

const VIEW_SIZE := Vector2(1598.0, 720.0)
const ORDINARY_ID := 28
const ELITE_ID := 41
const BOSS_ID := 199
const DIRECTIONS: Array[Vector2] = [
	Vector2.UP,
	Vector2(1.0, -1.0),
	Vector2.RIGHT,
	Vector2(1.0, 1.0),
	Vector2.DOWN,
	Vector2(-1.0, 1.0),
	Vector2.LEFT,
	Vector2(-1.0, -1.0),
]
const DIRECTION_LABELS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const STATE_LABELS := ["idle", "walk", "attack", "hit", "death"]

var _actors: Array[EnemyActor] = []
var _player: PlayerCharacter


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.set_synchronous_loading_for_tests(true)
	_make_background()
	_player = PlayerCharacter.new()
	_player.name = "RenderProbePlayer"
	_player.global_position = Vector2(780.0, 700.0)
	_player.set_physics_process(false)
	add_child(_player)

	# Eight directions: one real ordinary EnemyActor per column.
	for index in range(DIRECTIONS.size()):
		var enemy := _make_enemy(ORDINARY_ID, Vector2(100.0 + index * 198.0, 160.0))
		enemy.facing = DIRECTIONS[index]
		enemy.movement_facing = DIRECTIONS[index]
		_add_caption(Vector2(70.0 + index * 198.0, 235.0), DIRECTION_LABELS[index], Color("d8c79e"))

	# Five real ordinary actors cover the state row. Walk gets a nonzero
	# velocity; action poses are entered through the actual MonsterVisual API.
	for index in range(STATE_LABELS.size()):
		var enemy := _make_enemy(ORDINARY_ID, Vector2(210.0 + index * 292.0, 365.0))
		var visual: MonsterVisual = enemy.get_node("MonsterVisual")
		match STATE_LABELS[index]:
			"walk":
				enemy.velocity = Vector2.RIGHT * 32.0
			"attack":
				visual.play_attack()
			"hit":
				visual.play_hit()
			"death":
				enemy._dying = true
				visual.play_death()
		visual.set_process(false)
		_add_caption(Vector2(160.0 + index * 292.0, 440.0), STATE_LABELS[index], Color("d8c79e"))

	# Exact rank samples use real EnemyActor identity and real overhead nodes.
	var elite := _make_enemy(ELITE_ID, Vector2(560.0, 565.0))
	var boss := _make_enemy(BOSS_ID, Vector2(1030.0, 565.0))
	_add_caption(Vector2(500.0, 655.0), "elite: 41", Color("e8edf2"))
	_add_caption(Vector2(950.0, 655.0), "boss: 199", Color("f1c45a"))

	var hud := GameHUD.new()
	hud.name = "RenderProbeHUD"
	hud.layer = 20
	add_child(hud)
	await get_tree().process_frame
	# Keep the production target panel and its real target label visible while
	# hiding unrelated controls that would obscure the evidence matrix.
	_hide_unrelated_hud(hud)
	# Use the real elite actor so this capture proves the exact-ID variant label
	# boundary at the same time as the overhead marker.
	var target_actor := elite
	hud.update_target(
		target_actor.display_name,
		target_actor.current_hp,
		target_actor.max_hp,
		false,
		true,
		target_actor.monster_id,
	)

	# Allow all actual EnemyActor children and their final client textures to
	# enter the tree. The proof records the real node contracts before capture.
	for _frame in range(8):
		await get_tree().process_frame
	for actor in _actors:
		var overhead := actor.get_node("MonsterOverhead")
		assert(overhead is MonsterOverhead, "real actor overhead missing")
	assert(str(elite.overhead.marker_rank()) == "elite", "elite marker rank missing")
	assert(str(boss.overhead.marker_rank()) == "boss", "boss marker rank missing")
	assert(hud.target_label.text.contains("半兽勇士"), "HUD target label did not render")
	assert(not hud.target_label.text.contains("9"), "HUD retained a confirmed variant suffix")
	var image := get_viewport().get_texture().get_image()
	var path := "res://outputs/test_logs/w6_actor_hud_render.png"
	assert(image.save_png(path) == OK, "failed to save actor/HUD render")
	print("W6_ACTOR_HUD_RENDER_SAVED path=%s target_id=%d target_text=%s elite_marker=%s boss_marker=%s" % [
		path,
		target_actor.monster_id,
		hud.target_label.text,
		elite.overhead.marker_texture_path(),
		boss.overhead.marker_texture_path(),
	])
	get_tree().quit(0)


func _make_background() -> void:
	var background := ColorRect.new()
	background.name = "RenderProbeBackground"
	background.position = Vector2.ZERO
	background.size = VIEW_SIZE
	background.color = Color("17131e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -20
	add_child(background)
	_add_caption(Vector2(24.0, 105.0), "真实 EnemyActor：8方向", Color("d8c79e"), 20)
	_add_caption(Vector2(24.0, 315.0), "真实 MonsterVisual 状态", Color("d8c79e"), 20)
	_add_caption(Vector2(24.0, 515.0), "真实 MonsterOverhead rank marker", Color("d8c79e"), 20)


func _add_caption(at: Vector2, text_value: String, color: Color, font_size := 16) -> void:
	var label := Label.new()
	label.position = at
	label.text = text_value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.z_index = 10
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _make_enemy(monster_id: int, at: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.name = "RenderProbeEnemy_%d_%d" % [monster_id, _actors.size()]
	enemy.setup(GameData.get_monster_by_id(monster_id), _player, false)
	enemy.global_position = at
	enemy.set_physics_process(false)
	add_child(enemy)
	_actors.append(enemy)
	return enemy


func _hide_unrelated_hud(hud: GameHUD) -> void:
	for child in hud.get_children():
		if child.name == "MobileSafeRoot":
			for nested in child.get_children():
				if nested.name != "TargetPanel" and nested is CanvasItem:
					nested.hide()
