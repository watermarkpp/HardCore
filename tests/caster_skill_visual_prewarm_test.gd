extends Node

## FW-COLD contract (GPT audit 2026-09-16): the first real cast of a learned
## skill must not synchronously load animation frames on the main thread.
## prewarm_animation() resolves the manifest animation and loads every frame
## of every direction sequence; a full production-style playback afterwards
## must be a pure cache hit (zero new loads). GameRoot must run the learned
## skill prewarm inside the loading window, before the loading cover lifts.

const Registry := preload(
	"res://scripts/caster_skill_visual_registry.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# 1) Cold cache: clear, then prewarm the fire wall animation.
	Registry.clear_frame_texture_cache()
	var prewarm: Dictionary = Registry.prewarm_animation("wizard.fire_wall")
	assert(
		bool(prewarm.get("ready", false)),
		"fire wall prewarm must resolve a runtime-ready animation"
	)
	assert(
		int(prewarm.get("frames", 0)) == 6,
		"fire wall manifest declares 6 visible frames: %s" % [prewarm]
	)
	assert(
		int(prewarm.get("sequences", 0)) >= 1,
		"prewarm must cover every direction sequence"
	)
	var after_prewarm: Dictionary = Registry.frame_texture_cache_diagnostics()
	var loads_after_prewarm := int(after_prewarm.get("loads", 0))
	assert(
		loads_after_prewarm >= 6,
		"prewarm itself must have performed the synchronous loads: %s"
		% [after_prewarm]
	)

	# 2) Production-style playback right after prewarm: pure cache hits only.
	var player := CasterSkillAnimationPlayer.new()
	add_child(player)
	assert(
		player.configure("wizard.fire_wall", Vector2.DOWN),
		"the fire wall animation must configure from the prewarmed cache"
	)
	assert(
		player.visual_loaded,
		"configure must resolve frame 0 from the cache"
	)
	for frame_index: int in 6:
		assert(
			player._apply_frame(frame_index),
			"frame %d must resolve during playback" % frame_index
		)
	var after_playback: Dictionary = Registry.frame_texture_cache_diagnostics()
	assert(
		int(after_playback.get("loads", 0)) == loads_after_prewarm,
		"playback must not perform new texture loads after prewarm: %s vs %s"
		% [after_playback, loads_after_prewarm]
	)
	assert(
		int(after_playback.get("hits", 0)) > int(after_prewarm.get("hits", 0)),
		"playback must be served from the prewarmed cache"
	)

	# 3) A second cast direction (fresh player, cache warm) stays a pure hit.
	var second := CasterSkillAnimationPlayer.new()
	add_child(second)
	assert(second.configure("wizard.fire_wall", Vector2.RIGHT))
	for frame_index: int in 6:
		assert(second._apply_frame(frame_index))
	var after_second: Dictionary = Registry.frame_texture_cache_diagnostics()
	assert(
		int(after_second.get("loads", 0)) == loads_after_prewarm,
		"the second cast must stay a pure cache hit: %s" % [after_second]
	)

	# 4) Unknown / non-runtime skills must prewarm as a visible no-op.
	var missing: Dictionary = Registry.prewarm_animation("wizard.does_not_exist")
	assert(
		not bool(missing.get("ready", true)),
		"an unknown skill must report a non-ready prewarm"
	)

	# 5) Source discipline: GameRoot prewarms learned skills inside the
	# loading window (after FINALIZE, before the loading cover lifts). The
	# call site is matched with its two-tab indentation so the function
	# definition earlier in the file cannot satisfy this gate. The first-
	# combat extension (weapon swing audio + fallback action textures) must
	# warm inside the same window; the presentation cache must therefore be
	# populated by the hook call, not by the first real attack.
	var source := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	assert(
		source.contains("func _prewarm_learned_skill_visuals()"),
		"GameRoot must define the learned-skill prewarm"
	)
	var finalize_index := source.find(
		"WorldBootstrapCoordinator.Stage.FINALIZE"
	)
	var prewarm_index := source.find(
		"\t\t_prewarm_learned_skill_visuals()"
	)
	var finish_index := source.find("hud.finish_loading_transition()")
	var prewarm_def_index := source.find(
		"func _prewarm_learned_skill_visuals()"
	)
	assert(
		finalize_index >= 0 and prewarm_index > finalize_index
		and finish_index > prewarm_index,
		"the prewarm must run inside the loading window, before the cover lifts"
	)
	# The first-combat warming calls must live inside the prewarm function
	# body, so they execute wherever the (window-gated) call site runs.
	for warming_call: String in [
		'PresentationAssets.audio(audio_id)',
		'PresentationAssets.player_texture(action_key)',
	]:
		var body_index := source.find(warming_call, prewarm_def_index)
		assert(
			prewarm_def_index >= 0 and body_index >= 0,
			"first-combat presentation warming must sit in the prewarm body: %s"
			% warming_call
		)
	print(
		"CASTER_SKILL_VISUAL_PREWARM_PASS frames=%d loads=%d hits=%d"
		% [
			int(prewarm.get("frames", 0)),
			int(after_second.get("loads", 0)),
			int(after_second.get("hits", 0)),
		]
	)
	get_tree().quit(0)
