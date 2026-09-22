extends Node

const Projectile := preload("res://scripts/skill_projectile.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const MAP_ID := 1
const FIXTURE_MONSTER_ID := 19


class AudioProbe extends Node:
	var calls: Array[Dictionary] = []

	func _ready() -> void:
		add_to_group(&"audio_runtime_service")

	func play_event(event_id: String, context: Dictionary = {}) -> Dictionary:
		calls.append({
			"event_id": event_id,
			"context": context.duplicate(true),
		})
		return {"status": "played"}

	func play_monster_event(
		_monster_id: int,
		_semantic_event: String,
		_context: Dictionary = {},
	) -> Dictionary:
		return {"status": "played"}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var probe := AudioProbe.new()
	add_child(probe)
	await get_tree().process_frame

	var terminal := _make_projectile(
		"audio-terminal",
		Vector2.ZERO,
		Vector2.RIGHT,
		0.25,
		10.0,
		null,
	)
	assert(_count(probe, "audio-terminal", "skill.wizard.fireball.launch") == 1)
	terminal._emit_projectile_audio_phase("launch", "duplicate_probe")
	assert(
		_count(probe, "audio-terminal", "skill.wizard.fireball.launch") == 1,
		"ready-success launch must be one-shot",
	)
	terminal._physics_process(0.1)
	assert(
		_count(probe, "audio-terminal", "skill.wizard.fireball.impact") == 1,
		"valid maximum-distance terminal must emit impact once",
	)
	assert(_reason(probe, "audio-terminal", "skill.wizard.fireball.impact") == "path_terminal")
	terminal._emit_projectile_audio_phase("impact", "duplicate_probe")
	assert(
		_count(probe, "audio-terminal", "skill.wizard.fireball.impact") == 1,
		"terminal impact latch must reject duplicates",
	)

	var index := SpatialIndexScript.new()
	var enemy := _make_enemy(index, Vector2(0.5, 0.0), 8001)
	var contact := _make_projectile(
		"audio-contact",
		Vector2.ZERO,
		Vector2.RIGHT,
		2.0,
		10.0,
		index,
	)
	var hp_before := enemy.current_hp
	contact._physics_process(0.1)
	assert(enemy.current_hp < hp_before, "contact fixture must prove a real target hit")
	assert(
		_count(probe, "audio-contact", "skill.wizard.fireball.impact") == 1,
		"actual target contact must emit impact once",
	)
	assert(_reason(probe, "audio-contact", "skill.wizard.fireball.impact") == "target_contact")

	var invalid := Projectile.new()
	invalid.setup_ground_unit_projectile(
		Vector2.ZERO,
		Vector2.RIGHT,
		2.0,
		5,
		10.0,
		0.2,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"audio-invalid-projection",
	)
	invalid.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
	)
	add_child(invalid)
	assert(
		_count(probe, "audio-invalid-projection", "skill.wizard.fireball.launch") == 0,
		"projection-rejected ready must not emit launch",
	)
	invalid._physics_process(0.1)
	await get_tree().process_frame
	assert(
		_count(probe, "audio-invalid-projection", "skill.wizard.fireball.impact") == 0,
		"projection rejection cleanup must not masquerade as impact",
	)

	var cancelled := _make_projectile(
		"audio-cancelled",
		Vector2.ZERO,
		Vector2.RIGHT,
		2.0,
		1.0,
		null,
	)
	assert(_count(probe, "audio-cancelled", "skill.wizard.fireball.launch") == 1)
	cancelled.queue_free()
	await get_tree().process_frame
	assert(
		_count(probe, "audio-cancelled", "skill.wizard.fireball.impact") == 0,
		"external expiry/map cleanup must not emit impact",
	)

	if is_instance_valid(enemy):
		enemy.queue_free()
	await get_tree().process_frame
	print(
		"PROJECTILE_AUDIO_LIFECYCLE_PASS: ready launch/target and path impact "
		+ "one-shot; rejection and external cleanup silent",
	)
	get_tree().quit(0)


func _make_projectile(
	release_id: String,
	start_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	maximum_distance_gu: float,
	speed_gu: float,
	index: Variant,
) -> SkillProjectile:
	var projectile := Projectile.new()
	projectile.setup_ground_unit_projectile(
		GroundUnit.ground_delta_gu_to_screen_delta_px(start_ground_gu),
		direction_ground_gu,
		maximum_distance_gu,
		25,
		speed_gu,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		release_id,
	)
	projectile.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
		GroundUnit.screen_delta_px_to_ground_delta_gu,
	)
	if index != null:
		projectile.configure_spatial_index(index)
	add_child(projectile)
	return projectile


func _make_enemy(
	index: SpatialIndexScript,
	center_ground_gu: Vector2,
	serial: int,
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(FIXTURE_MONSTER_ID), null, false)
	enemy.max_hp = 1000
	enemy.current_hp = 1000
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
		GroundUnit.screen_delta_px_to_ground_delta_gu,
	)
	enemy.configure_spatial_index(index, serial)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = 0.25
	add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	index.register(
		serial,
		MAP_ID,
		center_ground_gu,
		0.25,
		serial,
		enemy,
	)
	return enemy


func _count(probe: AudioProbe, release_id: String, event_id: String) -> int:
	var count := 0
	for call: Dictionary in probe.calls:
		if (
			str(call.get("event_id", "")) == event_id
			and str(call.get("context", {}).get("release_id", "")) == release_id
		):
			count += 1
	return count


func _reason(probe: AudioProbe, release_id: String, event_id: String) -> String:
	for call: Dictionary in probe.calls:
		if (
			str(call.get("event_id", "")) == event_id
			and str(call.get("context", {}).get("release_id", "")) == release_id
		):
			return str(call.get("context", {}).get("terminal_reason", ""))
	return ""


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
