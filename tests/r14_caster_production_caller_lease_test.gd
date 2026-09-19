extends Node2D


## R14-C-R1 P0-3/P0-9/P0-10: production-caller first-frame miss + shared
## refcount ownership + never-acquired release safety.
##
## P0-3: a REAL production caller (CasterSkillVisualEffect) in combat mode
## with a legal but not-yet-resident sequence must KEEP its sprite child
## (configure()==true, visual_loaded==false, waiting_for_residency==true),
## not queue_free it. After residency completes the child starts from frame 0.
##
## P0-9: two players on the same resident sequence share one refcount per
## path; releasing one player drops the total by exactly one sequence, LRU
## pressure still cannot evict the survivor's sequence, and the last release
## returns the total to zero (frames evictable again).
##
## P0-10 (hard gate): a never-acquired waiter sharing the same _sequence_paths
## must NOT decrement the registry refcount of a real owner when destroyed.
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const SequencePlayer := preload(
	"res://scripts/caster_skill_animation_player.gd"
)
const VisualEffectScript := preload(
	"res://scripts/caster_skill_visual_effect.gd"
)

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("R14_C_R1_FAIL: " + message)


func _ready() -> void:
	_run.call_deferred()


func _make_resident(paths: Array[String]) -> void:
	for path: String in paths:
		if not Registry.frame_texture_is_resident(path):
			Registry.load_texture_path(path)


func _run() -> void:
	Registry.clear_frame_texture_cache()
	Registry.unpin_all_frames()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)

	await _case_1_production_caller_keeps_sprite_on_first_frame_miss()
	_case_2_shared_refcount_ownership()
	_case_3_never_acquired_waiter_never_releases_owner()

	Registry.clear_frame_texture_cache()
	Registry.unpin_all_frames()
	Registry.set_loading_window_active(true)
	if _failures == 0:
		print("R14_CASTER_PRODUCTION_CALLER_LEASE_PASS P0-3/P0-9/P0-10")
		get_tree().quit(0)
	else:
		push_error(
			"R14_CASTER_PRODUCTION_CALLER_LEASE_FAIL failures=" + str(_failures)
		)
		get_tree().quit(1)


## P0-3: CasterSkillVisualEffect (production caller) in combat mode with a
## legal directional skill whose sequence is NOT resident.
func _case_1_production_caller_keeps_sprite_on_first_frame_miss() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(false)
	var paths := Registry.animation_sequence_paths("wizard.laser", 8)
	_check(
		not Registry.sequence_resident(paths),
		"P0-3 setup sequence is not resident",
	)
	var effect := VisualEffectScript.new()
	# Production order (see laser_direction_visual_extent_test): setup() first,
	# then add_child - the visual install runs in _ready().
	effect.setup(
		Vector2(320.0, 240.0),
		"wizard.laser",
		72.0,
		0.8,
		Vector2.DOWN,
		null,
		"",
		{"visual_type": "beam", "enable_beam_visual": true},
	)
	add_child(effect)
	_check(
		effect._sprites.size() == 1,
		"P0-3 production caller keeps ONE sprite on first-frame miss",
	)
	var sprite := effect._sprites[0] as SequencePlayer
	_check(
		is_instance_valid(sprite) and not sprite.is_queued_for_deletion(),
		"P0-3 sprite child is NOT queue_free'd by the production caller",
	)
	_check(
		sprite._waiting_for_residency,
		"P0-3 sprite waits for residency",
	)
	_check(
		not sprite.visual_loaded,
		"P0-3 sprite has no loaded texture yet",
	)
	_check(
		sprite.current_frame_index == 0,
		"P0-3 sprite holds frame index 0",
	)
	# Warm the sequence, then drive the sprite process ticks so the waiting
	# branch runs deterministically.
	Registry.set_loading_window_active(true)
	_make_resident(paths)
	sprite._process(0.016)
	_check(
		sprite.visual_loaded,
		"P0-3 sprite starts once residency completes",
	)
	_check(
		not sprite._waiting_for_residency,
		"P0-3 waiting clears after residency",
	)
	_check(
		sprite.current_frame_index == 0,
		"P0-3 playback resumes from frame 0",
	)
	effect.queue_free()
	await get_tree().process_frame


## P0-9: two players on the same sequence share one refcount per path.
func _case_2_shared_refcount_ownership() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)
	# Registry direction_index: 0=N(UP), 4=E(RIGHT), 8=S(DOWN), 12=W(LEFT).
	# Direction 4 is Vector2.RIGHT.
	var paths := Registry.animation_sequence_paths("wizard.laser", 4)
	_make_resident(paths)
	var player_a := SequencePlayer.new()
	add_child(player_a)
	_check(
		player_a.configure("wizard.laser", Vector2.RIGHT),
		"P0-9 player A configure accepts",
	)
	var player_b := SequencePlayer.new()
	add_child(player_b)
	_check(
		player_b.configure("wizard.laser", Vector2.RIGHT),
		"P0-9 player B configure accepts",
	)
	_check(
		player_a._sequence_lease_held and player_b._sequence_lease_held,
		"P0-9 both resident players hold the lease",
	)
	var diag_two := Registry.frame_texture_cache_diagnostics()
	_check(
		int(diag_two.get("leased_sequence_paths", -1)) == paths.size(),
		"P0-9 unique leased paths == sequence path count (%d, got %d)"
		% [paths.size(), int(diag_two.get("leased_sequence_paths", -1))],
	)
	_check(
		int(diag_two.get("leased_sequence_refcount_total", -1))
		== paths.size() * 2,
		"P0-9 total refcount == path count x 2 (%d, got %d)"
		% [paths.size() * 2, int(diag_two.get("leased_sequence_refcount_total", -1))],
	)
	# Release player A -> one full sequence worth of refcounts drops.
	player_a._release_sequence_lease()
	var diag_one := Registry.frame_texture_cache_diagnostics()
	_check(
		int(diag_one.get("leased_sequence_refcount_total", -1)) == paths.size(),
		"P0-9 releasing one player drops total refcount to path count (%d)"
		% paths.size(),
	)
	# LRU pressure must not evict player B's still-leased sequence.
	var churn := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var churn_texture := ImageTexture.create_from_image(churn)
	for index: int in range(128):
		Registry.retain_loaded_texture(
			"ch://p09_%d" % index, churn_texture, 256 * 256 * 4
		)
	_check(
		Registry.sequence_resident(paths),
		"P0-9 survivor B's sequence survives LRU pressure",
	)
	# Release player B -> total refcount 0; LRU pressure may then evict.
	player_b._release_sequence_lease()
	var diag_zero := Registry.frame_texture_cache_diagnostics()
	_check(
		int(diag_zero.get("leased_sequence_refcount_total", -1)) == 0,
		"P0-9 last release returns total refcount to 0",
	)
	for index: int in range(256):
		Registry.retain_loaded_texture(
			"ch://p09b_%d" % index, churn_texture, 256 * 256 * 4
		)
	_check(
		not Registry.sequence_resident(paths),
		"P0-9 unleased sequence is evictable again",
	)
	player_a.queue_free()
	player_b.queue_free()
	await get_tree().process_frame


## P0-10 hard gate: a never-acquired waiter sharing _sequence_paths must not
## decrement the real owner's registry refcount when destroyed.
func _case_3_never_acquired_waiter_never_releases_owner() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)
	var paths := Registry.animation_sequence_paths("wizard.fire_wall", 0)
	_make_resident(paths)
	# Owner: resident configure -> acquires the lease (held=true).
	var owner := SequencePlayer.new()
	add_child(owner)
	_check(
		owner.configure("wizard.fire_wall", Vector2.DOWN),
		"P0-10 owner configure accepts",
	)
	_check(
		owner._sequence_lease_held,
		"P0-10 owner holds the lease",
	)
	var owner_total := int(
		Registry.frame_texture_cache_diagnostics().get(
			"leased_sequence_refcount_total", -1
		)
	)
	_check(
		owner_total == paths.size(),
		"P0-10 owner refcount total is one sequence (%d)" % owner_total,
	)
	# Waiter: same _sequence_paths, but NEVER acquired (held stays false).
	# A waiter that never acquired must not decrement the owner's refcount
	# when it is destroyed - this is the P0-10 hard gate.
	var waiter := SequencePlayer.new()
	add_child(waiter)
	waiter._sequence_paths = paths.duplicate()
	waiter._sequence_lease_held = false
	_check(
		int(Registry.frame_texture_cache_diagnostics().get(
			"leased_sequence_refcount_total", -1
		)) == owner_total,
		"P0-10 waiter construction does not touch the registry",
	)
	waiter.queue_free()
	await get_tree().process_frame
	_check(
		int(Registry.frame_texture_cache_diagnostics().get(
			"leased_sequence_refcount_total", -1
		)) == owner_total,
		"P0-10 never-acquired waiter destroy does NOT change owner refcount (%d)"
		% owner_total,
	)
	owner.queue_free()
	await get_tree().process_frame
	_check(
		int(Registry.frame_texture_cache_diagnostics().get(
			"leased_sequence_refcount_total", -1
		)) == 0,
		"P0-10 owner teardown releases to 0",
	)
