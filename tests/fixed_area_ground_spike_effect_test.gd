extends Node

## Fixed-area monster release contract: gameplay settles once per valid target,
## then emits one presentation descriptor carrying the shared immutable
## snapshot. The visual consumes no damage API and expires after its eight
## authored frames.

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const MonsterGroundSpikeEffectScript := preload(
	"res://scripts/monster_ground_spike_effect.gd"
)

var _descriptors: Array[Dictionary] = []
var _attacker: EnemyActor
var _players: Array[PlayerCharacter] = []


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_attacker = EnemyActor.new()
	_attacker.global_position = Vector2.ZERO
	var primary := _make_player(Vector2(128.0, 0.0), 10000)
	_attacker.setup(GameData.get_monster_by_id(180), primary, true)
	_attacker.configure_runtime_map_projection(
		180,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	_attacker.fixed_area_ground_spike_requested.connect(
		_capture_descriptor
	)
	add_child(_attacker)
	await get_tree().process_frame
	_attacker.set_physics_process(false)
	_attacker.attack_min = 7
	_attacker.attack_max = 7
	_attacker._attack_animation_duration = 0.62

	var second := _make_player(Vector2(-128.0, 0.0), 10000)
	var out_of_range := _make_player(Vector2(1200.0, 0.0), 10000)
	var dead := _make_player(Vector2(192.0, 0.0), 0)
	var queued := _make_player(Vector2(224.0, 0.0), 10000)
	var safe := _make_player(Vector2(256.0, 0.0), 10000)
	await get_tree().process_frame
	for player: PlayerCharacter in _players:
		_configure_player(player, 10000)
	_configure_player(dead, 0)
	_attacker.set_meta(
		"safe_zones",
		[
			{
				"shape": "circle",
				"center": safe.global_position,
				"center_ground_gu": _screen_to_ground(safe.global_position),
				"radius_gu": 0.25,
			}
		],
	)
	queued.queue_free()
	_attacker._area_attack_warning = 0.0
	_attacker._area_attack_cooldown = 0.0

	var primary_hp_before := primary.current_hp
	var second_hp_before := second.current_hp
	_attacker._physics_process(0.05)
	assert(_descriptors.is_empty(), "fixed area warning must not emit a spike early")
	assert(primary.current_hp == primary_hp_before)
	_attacker._physics_process(0.14)
	assert(_descriptors.is_empty(), "fixed area warning must remain visual-free before settlement")
	_attacker._physics_process(0.07)

	assert(_descriptors.size() == 2, "N valid victims must produce N spike descriptors")
	assert(primary.current_hp < primary_hp_before)
	assert(second.current_hp < second_hp_before)
	assert(out_of_range.current_hp == out_of_range.max_hp)
	assert(dead.current_hp == 0)
	assert(safe.current_hp == safe.max_hp)
	var expected_release_id := str(_descriptors[0].get("release_id", ""))
	assert(not expected_release_id.is_empty(), "release_id must be present")
	var snapshot: Dictionary = _descriptors[0].get("footprint_snapshot", {})
	assert(snapshot.is_read_only(), "descriptor footprint snapshot must be immutable")
	for descriptor: Dictionary in _descriptors:
		assert(
			str(descriptor.get("effect_id", ""))
			== MonsterGroundSpikeEffectScript.EFFECT_ID,
			"effect id must be stable",
		)
		assert(str(descriptor.get("release_id", "")) == expected_release_id)
		assert(int(descriptor.get("source_monster_id", -1)) == 180)
		assert(int(descriptor.get("source_instance_id", 0)) == _attacker.get_instance_id())
		var target_instance_id := int(descriptor.get("target_instance_id", 0))
		var target: Dictionary = descriptor.get("target", {})
		assert(target_instance_id == int(target.get("instance_id", 0)))
		assert(target.get("world_px", Vector2.INF) is Vector2)
		assert(target.get("ground_gu", Vector2.INF) is Vector2)
		assert(descriptor.get("footprint_snapshot", {}) == snapshot)

	var first_descriptor := _descriptors[0]
	var first_target_id := int(first_descriptor.get("target_instance_id", 0))
	var first_target: PlayerCharacter = null
	for player: PlayerCharacter in _players:
		if player.get_instance_id() == first_target_id:
			first_target = player
			break
	assert(first_target != null)
	assert(
		first_descriptor.get("target_world_px", Vector2.INF)
		.is_equal_approx(first_target.rendered_footpoint_world_px()),
		"spike presentation must use the APK-derived rendered shoe point",
	)
	assert(
		first_descriptor.get("target_actor_origin_world_px", Vector2.INF)
		.is_equal_approx(first_target.global_position),
		"authoritative actor origin must remain unchanged",
	)
	assert(
		first_descriptor.get("target_ground_gu", Vector2.INF)
		.is_equal_approx(_screen_to_ground(first_target.global_position)),
		"damage footprint must remain on the authoritative actor origin",
	)
	assert(
		first_target.rendered_footpoint_local_px().is_equal_approx(
			ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION
		),
		"APK-derived visible footpoint offset must be (7.5, 12.5)",
	)
	var effect := MonsterGroundSpikeEffectScript.new()
	effect.setup(first_descriptor)
	add_child(effect)
	await get_tree().process_frame
	assert(effect.frame_count() == 8)
	assert(not effect.has_method("take_damage"), "visual effect must not own damage")
	assert(effect.source_texture_path().ends_with("fixed_area_ground_spike_rgba_v1.png"))
	assert(
		is_equal_approx(
			float(effect.visual_descriptor().get("display_scale", 0.0)),
			0.18,
		),
		"source-sized atlas must be scaled to a player-footpoint effect",
	)
	assert(
		effect.frame_anchor_offset_px(0).is_equal_approx(
			Vector2(14.5, -146.0) * 0.18
		),
		"opening crack center must be aligned to the target footpoint",
	)
	await get_tree().create_timer(0.75).timeout
	assert(not is_instance_valid(effect), "eight-frame effect must self-release")

	_cleanup()
	await get_tree().process_frame
	print("FIXED_AREA_GROUND_SPIKE_EFFECT_PASS descriptors=%d release_id=%s" % [_descriptors.size(), expected_release_id])
	get_tree().quit(0)


func _make_player(position_px: Vector2, hp: int) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.global_position = position_px
	player.set_physics_process(false)
	add_child(player)
	_players.append(player)
	return player


func _configure_player(player: PlayerCharacter, hp: int) -> void:
	player.max_hp = maxi(1, hp)
	player.current_hp = hp
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0


func _capture_descriptor(descriptor: Dictionary) -> void:
	_descriptors.append(descriptor)


func _cleanup() -> void:
	if is_instance_valid(_attacker):
		_attacker.queue_free()
	for player: PlayerCharacter in _players:
		if is_instance_valid(player):
			player.queue_free()
	_players.clear()
