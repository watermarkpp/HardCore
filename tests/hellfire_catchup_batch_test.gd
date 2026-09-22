extends Node

const EffectScript := preload("res://scripts/caster_skill_visual_effect.gd")
const WorldRender := preload("res://scripts/world_effect_render_order.gd")
const SKILL_ID := "wizard.hellfire"


class HellfireSpy extends EffectScript:
	var visual_commit_count := 0

	func _update_hellfire_sprites() -> void:
		visual_commit_count += 1
		super._update_hellfire_sprites()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	# Use the real authored animation and real texture/lease path. This test
	# isolates catch-up submission, so cold-resource waiting is warmed first.
	CasterSkillVisualRegistry.set_loading_window_active(false)
	var direction_index := CasterSkillVisualRegistry.direction_index(Vector2.RIGHT)
	var paths: Array[String] = CasterSkillVisualRegistry.animation_sequence_paths(SKILL_ID, direction_index, "")
	assert(paths.size() == 6, "hellfire catch-up fixture requires the formal six-frame sequence")
	for path: String in paths:
		var texture := load(path) as Texture2D
		assert(texture != null, "missing real hellfire frame: " + path)
		CasterSkillVisualRegistry.retain_loaded_texture(path, texture)

	var small := _make_effect()
	var batched := _make_effect()
	_assert_logical_parity(small, batched)
	_assert_sprite_parity(small, batched)
	small.visual_commit_count = 0
	batched.visual_commit_count = 0
	for _step: int in range(4):
		small._process_hellfire(0.05)
	batched._process_hellfire(0.20)
	# All four logical steps still happen. The oldest live record is four
	# frames old; it must not disappear just to meet the submission budget.
	_assert_logical_parity(small, batched)
	assert(batched._hellfire_emissions == 5, "initial emission plus four catch-up steps must remain")
	assert(batched._hellfire_records.size() == 5)
	assert(int(batched._hellfire_records.back().get("age", -1)) == 4)
	assert(not batched._hellfire_finished)
	_assert_sprite_parity(small, batched)
	_assert_visible_sprites_match_records(batched)
	assert(small.visual_commit_count == 4, "four separate render calls each commit their final state")
	assert(
		batched.visual_commit_count == 1,
		"one 200ms render call must submit only its final trail state; actual=%d" % batched.visual_commit_count,
	)

	var substep := _make_effect()
	var records_before := substep._hellfire_records.duplicate(true)
	var emissions_before := substep._hellfire_emissions
	substep.visual_commit_count = 0
	substep._process_hellfire(0.02)
	assert(substep.visual_commit_count == 0, "below one logical step there is no visual commit")
	assert(substep._hellfire_records == records_before)
	assert(substep._hellfire_emissions == emissions_before)
	substep._process_hellfire(0.03)
	assert(substep.visual_commit_count == 1, "fractional deltas must accumulate to one logical step")
	assert(substep._hellfire_emissions == emissions_before + 1)
	_assert_visible_sprites_match_records(substep)

	var completed := _make_effect()
	completed.visual_commit_count = 0
	completed._process_hellfire(4.0)
	assert(completed._hellfire_finished, "large delta must finish all remaining emissions and ages")
	assert(completed._hellfire_emissions == completed._hellfire_total_emissions)
	assert(completed._hellfire_records.is_empty())
	for sprite: Sprite2D in completed._sprites:
		assert(not sprite.visible, "completion commit must hide every real trail sprite")
	assert(completed.visual_commit_count == 1, "even a completion catch-up performs one final hide commit")
	completed.visual_commit_count = 0
	completed._process_hellfire(0.20)
	assert(completed.visual_commit_count == 0, "finished trail has no further visible state changes")

	small.free()
	batched.free()
	substep.free()
	completed.free()
	print("HELLFIRE_CATCHUP_BATCH_PASS logical_steps=4 batched_commits=1 real_sprite_parity=1 finish_hide=1 substep=1")
	get_tree().quit(0)


func _make_effect() -> HellfireSpy:
	var effect := HellfireSpy.new()
	# The production installer creates the six actual animation players,
	# chooses its real 50ms trajectory step, and performs the initial commit.
	effect.setup(Vector2(20.0, 40.0), SKILL_ID, 320.0, 0.8, Vector2.RIGHT)
	add_child(effect)
	effect.set_process(false)
	assert(effect.rejection_reason.is_empty(), effect.rejection_reason)
	assert(effect._playback_strategy == "firegun_trail")
	assert(is_equal_approx(effect._hellfire_step_seconds, 0.05))
	assert(effect._hellfire_total_emissions > 5, "four-step fixture must remain mid-flight")
	assert(effect._hellfire_frame_count == 6 and effect._sprites.size() == 6)
	assert(effect._hellfire_emissions == 1 and effect._hellfire_records.size() == 1)
	assert(effect.visual_commit_count == 1, "installation must retain its immediate initial submission")
	for sprite: CasterSkillAnimationPlayer in effect._sprites:
		sprite.set_process(false)
		assert(sprite.visual_loaded and sprite.texture != null, "fixture must use resident real textures")
		assert(sprite._sequence_lease_held, "fixture must retain the real active sequence lease")
	_assert_visible_sprites_match_records(effect)
	return effect


func _assert_logical_parity(left: HellfireSpy, right: HellfireSpy) -> void:
	assert(left._hellfire_records == right._hellfire_records, "catch-up changed positions/ages/order")
	assert(left._hellfire_emissions == right._hellfire_emissions)
	assert(left._hellfire_total_emissions == right._hellfire_total_emissions)
	assert(left._hellfire_finished == right._hellfire_finished)
	assert(is_equal_approx(left._hellfire_tick_elapsed, right._hellfire_tick_elapsed))


func _assert_sprite_parity(left: HellfireSpy, right: HellfireSpy) -> void:
	assert(left._sprites.size() == right._sprites.size())
	for index: int in range(left._sprites.size()):
		var a := left._sprites[index] as CasterSkillAnimationPlayer
		var b := right._sprites[index] as CasterSkillAnimationPlayer
		assert(a.visible == b.visible, "catch-up changed sprite visibility")
		assert(a.position.is_equal_approx(b.position), "catch-up changed sprite position")
		assert(a.current_frame_index == b.current_frame_index, "catch-up changed committed animation frame")
		assert(a.texture == b.texture, "catch-up changed the actual bound frame texture")
		assert(a.offset.is_equal_approx(b.offset), "catch-up changed authored frame anchor")


func _assert_visible_sprites_match_records(effect: HellfireSpy) -> void:
	for index: int in range(effect._sprites.size()):
		var sprite := effect._sprites[index] as CasterSkillAnimationPlayer
		if index >= effect._hellfire_records.size():
			assert(not sprite.visible)
			continue
		var record: Dictionary = effect._hellfire_records[index]
		var position: Vector2 = record.get("position", Vector2.ZERO)
		assert(sprite.visible)
		assert(sprite.current_frame_index == int(record.get("age", -1)))
		assert(sprite.position.is_equal_approx(position.round() + Vector2(0.0, WorldRender.SORT_EPSILON_PX)))
