extends Node2D


## R14-C1/C2/C3/C4/C5: caster skill visual sequence residency test.
## C1: animation_sequence_paths() returns ONLY the selected direction's
##     sequence (laser 6 frames, not the whole 96-frame 16-direction skill).
## C2: refcount lease protects the active sequence from LRU eviction, shares
##     one refcount across multiple instances, and releases on last drop.
## C3: a first-frame miss waits for residency instead of permanently
##     stopping; playback starts from frame 0 once the sequence is resident.
## C4: a mid-sequence miss keeps the current texture, freezes the logical
##     clock and never advances the frame index past an uncommitted texture.
## C5: one-shot completion releases the lease; _exit_tree releases it too.
## Uses laser (playback=once, 16 directions x 6 frames) as the directional
## carrier and drives _process manually so the contract is engine-frame
## independent.
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const SequencePlayer := preload(
	"res://scripts/caster_skill_animation_player.gd"
)

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("R14_C_FAIL: " + message)


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

	_case_1_sequence_paths_are_direction_scoped()
	_case_2_refcount_lease_protects_and_shares()
	await _case_3_first_frame_miss_waits_for_residency()
	await _case_4_mid_sequence_miss_does_not_advance_frame()
	await _case_5_lifecycle_releases_lease()

	Registry.clear_frame_texture_cache()
	Registry.unpin_all_frames()
	Registry.set_loading_window_active(true)
	if _failures == 0:
		print("R14_CASTER_SEQUENCE_LEASE_PASS C1-C5 sequence residency contract")
		get_tree().quit(0)
	else:
		push_error("R14_CASTER_SEQUENCE_LEASE_FAIL failures=" + str(_failures))
		get_tree().quit(1)


## C1: animation_sequence_paths is direction-scoped.
func _case_1_sequence_paths_are_direction_scoped() -> void:
	var laser_all := Registry.animation_frame_paths("wizard.laser")
	_check(
		laser_all.size() == 96,
		"C1 laser whole-skill enumeration is 96 frames, got %d" % laser_all.size(),
	)
	var laser_dir0 := Registry.animation_sequence_paths("wizard.laser", 0)
	_check(
		laser_dir0.size() == 6,
		"C1 laser direction 0 sequence is 6 frames, got %d" % laser_dir0.size(),
	)
	var laser_dir8 := Registry.animation_sequence_paths("wizard.laser", 8)
	_check(
		laser_dir8.size() == 6,
		"C1 laser direction 8 sequence is 6 frames, got %d" % laser_dir8.size(),
	)
	_check(
		laser_dir0[0] != laser_dir8[0],
		"C1 different directions resolve different sequence frame paths",
	)
	_check(
		laser_all.size() == 16 * laser_dir0.size(),
		"C1 one direction is 1/16th of the whole-skill frames",
	)
	# Non-directional skill (fire wall, direction_count==1): unique sequence.
	var fw_all := Registry.animation_frame_paths("wizard.fire_wall")
	var fw_seq := Registry.animation_sequence_paths("wizard.fire_wall", 0)
	_check(
		fw_all.size() == fw_seq.size() and fw_all.size() == 6,
		"C1 fire wall unique sequence equals whole-skill frame set",
	)


## C2: refcount lease. Protect a loaded sequence against eviction, share one
## refcount across two acquires, release drops it only on last holder.
func _case_2_refcount_lease_protects_and_shares() -> void:
	Registry.clear_frame_texture_cache()
	var paths := Registry.animation_sequence_paths("wizard.laser", 4)
	_make_resident(paths)
	Registry.acquire_sequence_lease(paths)
	# Eviction churn must not remove a leased path.
	var churn := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var churn_texture := ImageTexture.create_from_image(churn)
	for index: int in range(128):
		Registry.retain_loaded_texture(
			"ch://c2_%d" % index, churn_texture, 256 * 256 * 4
		)
	_check(
		Registry.sequence_resident(paths),
		"C2 leased sequence survives eviction pressure",
	)
	# Shared refcount: two acquires -> one release still leased.
	Registry.acquire_sequence_lease(paths)
	Registry.release_sequence_lease(paths)
	_check(
		Registry.sequence_resident(paths),
		"C2 shared refcount keeps the sequence leased after one release",
	)
	# After the last release, churn may evict (path is no longer protected).
	Registry.release_sequence_lease(paths)
	for index: int in range(256):
		Registry.retain_loaded_texture(
			"ch://c2b_%d" % index, churn_texture, 256 * 256 * 4
		)
	Registry.unpin_all_frames()


## C3: configure() with a missing sequence must NOT permanently stop the
## player. P0-1: configure returns TRUE (configuration accepted) even when
## frame 0 is not resident yet; the live visual state is visual_loaded=false
## + _waiting_for_residency=true. It queues the sequence, keeps processing,
## and starts from frame 0 once residency completes.
func _case_3_first_frame_miss_waits_for_residency() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	# Combat mode: no synchronous decode; a miss returns null.
	Registry.set_loading_window_active(false)
	var paths := Registry.animation_sequence_paths("wizard.laser", 8)
	_check(
		not Registry.sequence_resident(paths),
		"C3 setup sequence is not resident",
	)
	var player := SequencePlayer.new()
	add_child(player)
	var configured := player.configure("wizard.laser", Vector2.DOWN)
	_check(
		configured,
		"C3 configure accepts a legal configuration while the sequence warms",
	)
	_check(
		not player.visual_loaded,
		"C3 first-frame miss does not claim a loaded texture",
	)
	_check(
		player._waiting_for_residency,
		"C3 configure arms waiting-for-residency on first-frame miss",
	)
	_check(
		player.is_processing(),
		"C3 waiting player keeps processing (never permanently stops)",
	)
	_check(
		player.current_frame_index == 0,
		"C3 waiting player holds frame index 0",
	)
	# Warm the sequence (the residency source), then drive the next process
	# tick manually so the waiting branch runs deterministically.
	Registry.set_loading_window_active(true)
	_make_resident(paths)
	player._process(0.016)
	_check(
		player._waiting_for_residency == false,
		"C3 residency completion clears waiting flag",
	)
	_check(
		player.visual_loaded,
		"C3 playback starts once the sequence is resident",
	)
	_check(
		player.current_frame_index == 0,
		"C3 playback resumes from frame 0 after first-frame miss",
	)
	player.queue_free()
	await get_tree().process_frame


## C4: a mid-sequence miss must keep the current texture, freeze the logical
## clock and NOT advance the frame index past the uncommitted texture.
func _case_4_mid_sequence_miss_does_not_advance_frame() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	# Combat mode: request_animation_frame_texture returns null for misses
	# instead of synchronously loading, which is the C4 miss precondition.
	Registry.set_loading_window_active(false)
	var paths := Registry.animation_sequence_paths("wizard.laser", 8)
	# Load the base sequence BEFORE closing the window (synchronous warm), so
	# frame 0/1 are resident while the C4 probe path stays missing.
	Registry.set_loading_window_active(true)
	_make_resident(paths)
	Registry.set_loading_window_active(false)
	var player := SequencePlayer.new()
	add_child(player)
	# configure() calls _apply_frame(0) via request_animation_frame_texture;
	# with the window closed but the cache hot, frame 0 is a cache hit.
	_check(
		player.configure("wizard.laser", Vector2.DOWN),
		"C4 configure loads when resident",
	)
	_check(
		player.current_frame_index == 0,
		"C4 configure starts at frame 0",
	)
	# Advance one committed frame: laser frame_time_ms=50 -> one 50ms step.
	player._elapsed = 0.0
	player._process(0.05)
	_check(
		player.current_frame_index == 1,
		"C4 playback advances normally when textures commit, got %d"
		% player.current_frame_index,
	)
	# Replace the NEXT frame with a REAL but NOT-YET-RESIDENT frame path (the
	# same direction's frame 2 of another laser direction is on disk but not
	# loaded), and extend the leased sequence paths so the C4 guard is the
	# active path. In combat mode the miss returns null -> C4 must arm.
	var other_dir_paths := Registry.animation_sequence_paths("wizard.laser", 9)
	var not_yet_resident := other_dir_paths[0]
	_check(
		not Registry.frame_texture_is_resident(not_yet_resident),
		"C4 setup next frame is not resident yet",
	)
	player._frames[2] = {
		"path": not_yet_resident.trim_prefix("res://"),
	}
	var extended: Array[String] = paths.duplicate()
	extended.append(not_yet_resident)
	player._sequence_paths = extended
	# Simulate the formal lease path: configure() succeeded with the base
	# sequence resident and this player holds the lease. The extra probe
	# frame is NOT resident, so the next apply misses - the C4 guard must
	# freeze the index. (P0-4: registry acquire refuses non-resident paths,
	# so the owner flag is set directly to model the pre-miss lease state.)
	player._sequence_lease_held = true
	player._elapsed = 0.0
	var before_index := player.current_frame_index
	player._process(0.05)
	_check(
		player._waiting_for_residency,
		"C4 mid-sequence miss arms waiting-for-residency",
	)
	_check(
		player.current_frame_index == before_index,
		"C4 frame index does not advance past an uncommitted texture",
	)
	# Residency completes -> playback resumes from the last committed frame.
	Registry.set_loading_window_active(true)
	Registry.load_texture_path(not_yet_resident)
	Registry.set_loading_window_active(false)
	player._elapsed = 0.0
	player._process(0.016)
	_check(
		not player._waiting_for_residency,
		"C4 residency resumes playback from the committed frame",
	)
	_check(
		player.current_frame_index == before_index,
		"C4 resume keeps the last committed frame index",
	)
	# The simulated owner releases through the safe path (held flag decides).
	player._release_sequence_lease()
	Registry.set_loading_window_active(true)
	player.queue_free()
	await get_tree().process_frame


## C5: one-shot completion releases the lease; _exit_tree releases it too.
func _case_5_lifecycle_releases_lease() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)
	var paths := Registry.animation_sequence_paths("wizard.laser", 8)
	_make_resident(paths)
	var player := SequencePlayer.new()
	add_child(player)
	_check(
		player.configure("wizard.laser", Vector2.DOWN),
		"C5 configure loads when resident",
	)
	_check(
		Registry.sequence_resident(paths),
		"C5 lease protects the active sequence",
	)
	# Run the full one-shot to completion (6 frames at 50ms).
	for step: int in range(20):
		player._process(1.0 / 60.0)
	_check(
		player.playback_complete,
		"C5 one-shot completes",
	)
	_check(
		player._sequence_paths.is_empty(),
		"C5 one-shot completion releases the sequence lease",
	)
	# The one-shot release must drop the lease refcount to zero; eviction
	# pressure may then remove its frames.
	var churn := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var churn_texture := ImageTexture.create_from_image(churn)
	for index: int in range(256):
		Registry.retain_loaded_texture(
			"ch://c5_%d" % index, churn_texture, 256 * 256 * 4
		)
	_check(
		not Registry.sequence_resident(paths),
		"C5 one-shot completion releases the lease (frames evictable)",
	)
	player.queue_free()
	await get_tree().process_frame
	# A looping/persistent effect holds the lease until _exit_tree. Use fire
	# wall (playback=loop, direction_count=1): it never self-completes, so
	# the lease must survive its whole life and drop at teardown.
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)
	var fw_paths := Registry.animation_sequence_paths("wizard.fire_wall", 0)
	_make_resident(fw_paths)
	var loop_player := SequencePlayer.new()
	add_child(loop_player)
	_check(
		loop_player.configure("wizard.fire_wall", Vector2.DOWN),
		"C5 loop configure loads when resident",
	)
	_check(
		Registry.sequence_resident(fw_paths),
		"C5 loop player holds the lease",
	)
	var diag_before := Registry.frame_texture_cache_diagnostics()
	_check(
		int(diag_before.get("leased_sequence_paths", -1)) >= fw_paths.size(),
		"C5 loop lease is counted in diagnostics",
	)
	loop_player.queue_free()
	await get_tree().process_frame
	# The loop player is freed; verify the lease actually left the registry.
	var diag_after := Registry.frame_texture_cache_diagnostics()
	_check(
		int(diag_after.get("leased_sequence_paths", -1)) < fw_paths.size(),
		"C5 _exit_tree releases the looping lease (registry refcount dropped)",
	)
