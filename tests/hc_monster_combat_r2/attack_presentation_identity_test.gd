extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")

## HC-MONSTER-COMBAT-R2 T3 counterexamples (R2-02 / R2-03).
##
## 1. Logic clock: a fresh attack presentation must consume its OWN age, not
##    one whole render delta that may predate the attack start. Reproduction
##    of the review clock case: the previous draw was at t=0, the attack
##    starts at t=0.49 with a 0.46 s duration, the next draw happens at
##    t=0.50 with delta 0.50 - the old code subtracted that whole delta and
##    zeroed the fresh attack although it had only aged 0.01 s.
## 2. Parent action identity: the presentation and the audio stream bind to
##    the same serial the enemy allocated at the commit tick.
## 3. Keep the NEWEST struck: merging pending pure-STRUCK feedback keeps the
##    newest item (the R1 loop actually kept the oldest).
## 4. Sustained backpressure: a full presentation ring with waiting struck
##    items collapses them in place on enqueue instead of waiting for the
##    next attack to clean up.
## 5. Audio stages: frame-skip recovery, duplicate consumption rejection and
##    cold/hot recovery, all bound to the parent action serial.


class FakeAudioService extends Node:
	var played: Array = []

	func play_monster_event(monster_id: int, semantic_event: String, _context: Dictionary) -> Dictionary:
		played.append(semantic_event)
		return {"status": "played"}


var _fake_clock_ms := 0


func _clock() -> int:
	return _fake_clock_ms


func _make_enemy(id := 24) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.monster_id = id
	enemy.monster_data = {"monster_id": id}
	enemy.display_name = "测试占位怪"
	# The bare fixture has no catalog setup; a positive HP keeps the audio
	# listenable gate open for the audio-stage scenarios.
	enemy.current_hp = 100
	# HC-MONSTER-COMBAT-R2 T2: an enemy without a valid baked body profile is
	# fail-closed rejected in _ready (combat disabled, no footsole). The audio
	# scenarios need a fighting-capable actor, so bind the REAL baked profile
	# for this identity before the tree enters it.
	enemy.combat_body_profile = MonsterIdentityScript.body_profile(id)
	var visual := MonsterVisual.new()
	visual.setup(enemy)
	enemy.visual = visual
	return enemy


func _ready() -> void:
	# --- 1. Logic clock: the review's cross-frame counterexample ---
	var s1 := _make_enemy()
	var visual1: MonsterVisual = s1.visual
	visual1._clock_ms = Callable(self, "_clock")
	_fake_clock_ms = 490
	assert(
		visual1.begin_attack_presentation(0.46, 7, 490, Vector2.RIGHT),
		"fixture: the attack presentation must start"
	)
	assert(
		is_equal_approx(visual1._attack_remaining, 0.46),
		"fixture: a fresh attack keeps its full declared duration"
	)
	_fake_clock_ms = 500
	visual1._advance_action_timers(0.50)
	assert(
		visual1._attack_remaining > 0.40,
		(
			"the render delta that spans the attack start must not zero the "
			+ "fresh attack (aged 0.01 s of 0.46 s; got %f)"
		)
			% visual1._attack_remaining
	)
	_fake_clock_ms = 950
	visual1._advance_action_timers(0.10)
	assert(
		visual1._attack_remaining == 0.0,
		"the attack must finish once its own age reaches the duration"
	)
	assert(
		visual1.current_attack_action_id() == -1,
		"a finished presentation no longer owns a parent action id"
	)
	s1.free()

	# --- 1b. The same clock defect through the version-stable direct API ---
	# `_start_attack_visual` exists in both R1 and R2 with the same signature,
	# so this is a behavioral RED on the R1 code, not a parse error: starting
	# a fresh 0.46 s attack and then advancing one 0.50 s render delta used to
	# zero the fresh action although it had barely aged.
	var s1b := _make_enemy()
	var visual1b: MonsterVisual = s1b.visual
	visual1b._start_attack_visual(0.46)
	visual1b._advance_action_timers(0.50)
	assert(
		visual1b._attack_remaining > 0.40,
		(
			"one spanning render delta must not consume a fresh attack's whole "
			+ "duration (got %f)"
		)
			% visual1b._attack_remaining
	)
	s1b.free()

	# --- 2. Parent action identity binding ---
	var s2 := _make_enemy()
	s2._play_attack_animation(0.46)
	assert(
		s2._attack_logic_serial > 0,
		"the attack commit must allocate a parent action serial"
	)
	assert(
		s2.visual.current_attack_action_id() == s2._attack_logic_serial,
		"the presentation must replay the exact parent action"
	)
	assert(
		s2._audio_attack_sequence == s2._attack_logic_serial,
		"the audio stream must bind to the same parent action serial"
	)
	var previous_serial: int = s2._attack_logic_serial
	s2._play_attack_animation(0.46)
	assert(
		s2._attack_logic_serial == previous_serial + 1,
		"each attack commit allocates the next serial"
	)
	s2.free()

	# --- 3. Keep the NEWEST struck (level 50 -> 0.16 s, level 1 -> 0.39 s) ---
	var s3 := _make_enemy()
	s3.visual.queue_struck(50)
	s3.visual.queue_struck(1)
	assert(s3.visual.pending_struck_count() == 2, "fixture: two struck items pending")
	var merged: int = s3.visual._merge_pending_struck_feedback()
	assert(merged == 2, "both waiting struck items were merged")
	assert(
		s3.visual.pending_struck_count() == 1,
		"the merge keeps exactly one bounded struck feedback"
	)
	var kept_duration: float = s3.visual._presentation_duration[s3.visual._presentation_head]
	assert(
		is_equal_approx(kept_duration, 0.39),
		(
			"the kept struck must be the NEWEST one (level 1: 2 x 195 ms = "
			+ "0.39 s), not the oldest (level 50: 0.16 s was enqueued first); "
			+ "kept %f"
		)
			% kept_duration
	)
	s3.free()

	# --- 4. Sustained backpressure collapses in place on enqueue ---
	var s4 := _make_enemy()
	for i in MonsterVisual.PRESENTATION_QUEUE_CAPACITY:
		s4.visual.queue_struck(50)
	assert(
		s4.visual._presentation_count == MonsterVisual.PRESENTATION_QUEUE_CAPACITY,
		"fixture: backlog is full"
	)
	s4.visual.queue_struck(1)
	assert(
		s4.visual._presentation_count <= MonsterVisual.PRESENTATION_QUEUE_CAPACITY,
		"the ring must stay within capacity"
	)
	assert(
		s4.visual.pending_struck_count() == 2,
		(
			"the enqueue-time collapse keeps the newest waiting struck and "
			+ "admits the new one without dropping it (got %d)"
		)
			% s4.visual.pending_struck_count()
	)
	s4.free()

	# --- 5. Audio stages on the parent action serial ---
	var s5 := _make_enemy()
	var fake_audio := FakeAudioService.new()
	fake_audio.name = "FakeAudioService"
	add_child(fake_audio)
	fake_audio.add_to_group(&"audio_runtime_service")
	s5.add_child(s5.visual)
	add_child(s5)
	# The bare non-boss fixture enters background deep sleep in _ready, which
	# closes the audio listenable gate; wake it for the audio-stage scenarios.
	s5._background_deep_sleeping = false
	s5.set_physics_process(true)

	s5._play_attack_animation(0.46)
	var serial: int = s5._audio_attack_sequence
	assert(
		s5.combat_enabled,
		"fixture: the valid baked profile must keep combat enabled"
	)
	assert(
		s5._audio_attack_start_accepted,
		"fixture: the fake service must accept the attack-start audio"
	)
	assert(
		fake_audio.played.size() == 1 and str(fake_audio.played[0]) == "attack_start",
		"fixture: attack-start played once"
	)

	# Frame-skip: the visual jumps straight to frame 3 in one draw.
	s5.visual.current_state = "attack"
	s5.visual.current_frame = 3
	s5._audio_observe_visual_state()
	assert(
		fake_audio.played.size() == 2 and str(fake_audio.played[1]) == "attack_frame",
		"a jumped frame must still fire the frame sound exactly once (got %s)"
			% str(fake_audio.played)
	)
	# Duplicate consumption: observing the same sequence again emits nothing.
	s5._audio_observe_visual_state()
	assert(
		fake_audio.played.size() == 2,
		"the frame sound must be consumed once per parent action (got %s)"
			% str(fake_audio.played)
	)

	# Cold/hot recovery: a NEW action whose frames stream in too late.
	s5._play_attack_animation(0.46)
	var serial2: int = s5._audio_attack_sequence
	assert(
		serial2 == serial + 1,
		"the next attack binds the next serial (identity chain)"
	)
	s5.visual.current_state = "attack"
	s5.visual.current_frame = 0
	s5._audio_observe_visual_state()
	# Frames observed at 0, then the streaming consumes frames 1..3 between
	# observations: the next draw sees the attack already over.
	s5.visual.current_state = "idle"
	s5.visual.current_frame = 0
	s5.visual._attack_remaining = 0.0
	s5._audio_observe_visual_state()
	assert(
		fake_audio.played.size() == 4,
		"cold/hot recovery fires the missed frame sound once (got %s)"
			% str(fake_audio.played)
	)
	s5._audio_observe_visual_state()
	assert(
		fake_audio.played.size() == 4,
		"the recovered frame sound is never duplicated"
	)

	s5.queue_free()
	print("HC_MCR2_ATTACK_IDENTITY_PASS")
	get_tree().quit()
