extends Node

## R1 MonsterVisual STRUCK queue: a struck is queued while the monster
## finishes its committed action (attack pose / movement step / earlier
## struck), starts once idle, never burns in the background, accelerates at
## 1.5x with a backlog, and is cleared by death.

const MonsterStruckPolicy := preload("res://scripts/monster_struck_policy.gd")

var _checks := 0


class DummyEnemy:
	extends EnemyActor
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass


class StruckVisualFixture:
	extends MonsterVisual
	func _ready() -> void:
		set_process(false)


var _enemy: DummyEnemy
var _visual: StruckVisualFixture


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	assert(condition, "MONSTER_STRUCK_VISUAL_QUEUE: " + label)
	_checks += 1


func _make_fixture(monster_level: int) -> void:
	_enemy = DummyEnemy.new()
	add_child(_enemy)
	_enemy.level = monster_level
	_visual = StruckVisualFixture.new()
	_visual.actor = _enemy
	_enemy.add_child(_visual)
	_visual.sprite = Sprite2D.new()
	_visual.add_child(_visual.sprite)
	_visual.frame_size = Vector2i(8, 8)
	var texture := GradientTexture2D.new()
	texture.width = 48
	texture.height = 64
	# Canonical profile shape: hit resolves to 3 frames per direction.
	_visual.active_resources = {
		"idle": texture, "walk": texture, "attack": texture, "hit": texture, "death": texture,
		"frame_counts": {"idle": 4, "walk": 6, "attack": 6, "hit": 3, "death": 4},
		"direction_mode": "mir2_north_first",
	}


func _dispose_fixture() -> void:
	_enemy.queue_free()
	await get_tree().process_frame


func _run() -> void:
	await _test_idle_struck_starts_fully()
	await _test_struck_during_attack_waits_then_plays_fully()
	await _test_struck_during_committed_step_waits()
	await _test_struck_during_visible_movement_waits()
	await _test_backlog_acceleration_and_drain()
	await _test_attack_presentation_waits_for_started_struck()
	await _test_backlog_drains_before_pending_attack_starts()
	await _test_fifo_attack_between_strucks()
	await _test_multiple_attack_requests_keep_order()
	await _test_walk_grant_does_not_flip_playing_struck()
	await _test_death_clears_pending()
	await _test_queue_is_counter_only_and_capped()
	print("MONSTER_STRUCK_VISUAL_QUEUE_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _test_idle_struck_starts_fully() -> void:
	await _make_fixture(43)
	_visual.queue_struck(43)
	_check(_visual.pending_struck_count() == 1, "idle queue increments pending")
	_check(_visual._hit_remaining == 0.0, "queued struck must not burn before start")
	_visual._advance_action_timers(0.016)
	_check(_visual.pending_struck_count() == 0, "started struck consumes one pending")
	# Lv43 => 80ms/frame, hit has 3 frames => 0.24s total. The start tick
	# assigns the full duration; the countdown begins on the next tick.
	_check(
		is_equal_approx(_visual._hit_remaining, 0.24),
		"struck duration is ActStruck frames x struck_frame_ms"
	)
	_visual._update_animation_frame(0.0)
	_check(_visual.current_state == "hit", "idle struck becomes the visible action")
	_check(_visual.current_frame == 0, "struck starts at hit frame 0")
	await _dispose_fixture()


func _test_struck_during_attack_waits_then_plays_fully() -> void:
	await _make_fixture(43)
	_visual.play_attack(0.5)
	_visual.queue_struck(43)
	_visual._advance_action_timers(0.1)
	_check(_visual._attack_remaining > 0.0, "attack still playing")
	_check(_visual.pending_struck_count() == 1, "struck during attack stays queued")
	_check(_visual._hit_remaining == 0.0, "queued struck must not burn while attacking")
	_visual._update_animation_frame(0.0)
	_check(_visual.current_state == "attack", "attack priority is preserved")
	# Finish the attack: the queued struck starts on the very tick the attack
	# clock reaches zero, with its FULL duration.
	_visual._advance_action_timers(0.45)
	_check(_visual._attack_remaining <= 0.0, "attack finished")
	_check(_visual.pending_struck_count() == 0, "queued struck starts as the attack ends")
	_check(
		is_equal_approx(_visual._hit_remaining, 0.24),
		"post-attack struck plays the complete duration, not a leftover"
	)
	_visual._advance_action_timers(0.016)
	_visual._update_animation_frame(0.0)
	_check(_visual.current_state == "hit", "struck becomes visible after attack")
	_check(_visual.current_frame == 0, "post-attack struck starts at frame 0")
	await _dispose_fixture()


func _test_struck_during_committed_step_waits() -> void:
	await _make_fixture(43)
	_enemy._movement_step_active = true
	_visual.queue_struck(43)
	_visual._advance_action_timers(0.05)
	_check(_visual.pending_struck_count() == 1, "committed step keeps the struck queued")
	_check(_visual._hit_remaining == 0.0, "no background burn during a committed step")
	# The step completes normally; the struck then plays from frame 0.
	_enemy._movement_step_active = false
	_visual._advance_action_timers(0.016)
	_check(_visual.pending_struck_count() == 0, "struck starts after the step completes")
	_visual._update_animation_frame(0.0)
	_check(_visual.current_state == "hit", "no recoil-while-sliding: struck plays after arrival")
	await _dispose_fixture()


func _test_struck_during_visible_movement_waits() -> void:
	await _make_fixture(43)
	_enemy.velocity = Vector2(120.0, 0.0)
	_visual.queue_struck(43)
	_visual._advance_action_timers(0.05)
	_check(_visual.pending_struck_count() == 1, "moving monster keeps the struck queued")
	_enemy.velocity = Vector2.ZERO
	_visual._advance_action_timers(0.016)
	_check(_visual.pending_struck_count() == 0, "struck starts once movement stops")
	await _dispose_fixture()


func _test_backlog_acceleration_and_drain() -> void:
	await _make_fixture(43)
	for _i: int in range(5):
		_visual.queue_struck(43)
	_visual._advance_action_timers(0.016)
	_check(_visual.pending_struck_count() == 4, "one struck started, four queued")
	# With a backlog >= 2 the countdown runs at 1.5x: 0.1s delta burns 0.15s.
	var before := _visual._hit_remaining
	_visual._advance_action_timers(0.1)
	_check(
		is_equal_approx(_visual._hit_remaining, before - 0.15),
		"backlog countdown runs at 1.5x (frame time x 2/3)"
	)
	# Drain the whole backlog without any stuck state.
	for _i: int in range(40):
		_visual._advance_action_timers(0.05)
	_check(_visual.pending_struck_count() == 0, "backlog drains fully")
	_check(_visual._hit_remaining <= 0.0, "last struck finished")
	await _dispose_fixture()


func _test_death_clears_pending() -> void:
	await _make_fixture(43)
	for _i: int in range(3):
		_visual.queue_struck(43)
	_visual.play_death()
	_check(_visual.pending_struck_count() == 0, "death clears the struck backlog")
	_visual._advance_action_timers(0.05)
	_visual._update_animation_frame(0.0)
	_check(_visual.current_state == "death", "death keeps the highest priority")
	_check(_visual.pending_struck_count() == 0, "no struck starts after death")
	await _dispose_fixture()


## R1.1 review P1 closure (reverse direction): a started STRUCK is the current
## vanilla action; the next attack presentation must wait in its O(1) slot
## instead of covering the struck and letting `_hit_remaining` burn away in
## the background. Gameplay authority is untouched by the waiting.
func _test_attack_presentation_waits_for_started_struck() -> void:
	await _make_fixture(43)
	_visual.queue_struck(43)
	_visual._advance_action_timers(0.016)
	_check(is_equal_approx(_visual._hit_remaining, 0.24), "struck is the current action")
	_visual.play_attack(0.5)
	_check(_visual._attack_remaining == 0.0, "attack presentation must not preempt a playing struck")
	_visual._advance_action_timers(0.1)
	_check(is_equal_approx(_visual._hit_remaining, 0.14), "struck keeps burning while the attack waits")
	_check(_visual._attack_remaining == 0.0, "attack presentation stays parked during the struck")
	# The struck drains; the parked attack presentation starts on that tick
	# with its FULL duration (same start-tick rule as a struck start).
	_visual._advance_action_timers(0.2)
	_check(_visual._hit_remaining == 0.0, "struck finished completely (no background loss)")
	_check(is_equal_approx(_visual._attack_remaining, 0.5), "attack presentation starts after the struck with full duration")
	_visual._update_animation_frame(0.0)
	_check(_visual.current_state == "attack", "attack becomes the visible action after the struck")
	await _dispose_fixture()


## Vanilla FIFO: a struck backlog that arrived BEFORE the attack request
## finishes before the parked attack presentation starts.
func _test_backlog_drains_before_pending_attack_starts() -> void:
	await _make_fixture(43)
	_visual.queue_struck(43)
	_visual._advance_action_timers(0.016)
	_visual.queue_struck(43)
	_visual.queue_struck(43)
	_check(_visual.pending_struck_count() == 2, "two struck queued behind the playing one")
	_visual.play_attack(0.5)
	_visual._advance_action_timers(0.3)
	_check(_visual.pending_struck_count() == 1, "backlog struck started instead of the parked attack")
	_check(_visual._attack_remaining == 0.0, "attack presentation still waits behind the backlog")
	_visual._advance_action_timers(0.5)
	_check(_visual.pending_struck_count() == 0, "backlog drained")
	# The last queued struck only started on the previous tick; give it its
	# full duration before the parked attack presentation may start.
	_visual._advance_action_timers(0.3)
	_check(_visual._hit_remaining == 0.0, "last struck finished")
	_check(_visual._attack_remaining > 0.0, "parked attack presentation starts after the backlog drains")
	await _dispose_fixture()


## R1.2 review P1 closure, Test A (true FIFO across a later struck): with a
## struck playing, an attack request arriving BEFORE a further struck must
## play between them - A -> B(attack) -> C, never A -> C -> B.
func _test_fifo_attack_between_strucks() -> void:
	await _make_fixture(43)
	_visual.queue_struck(43)
	_visual._advance_action_timers(0.016)
	_check(is_equal_approx(_visual._hit_remaining, 0.24), "struck A is the current action")
	_visual.play_attack(0.5)
	_visual.queue_struck(43)
	_check(_visual.pending_struck_count() == 1, "struck C queued behind attack B")
	_visual._advance_action_timers(0.3)
	_check(_visual._hit_remaining == 0.0, "struck A finished")
	_check(is_equal_approx(_visual._attack_remaining, 0.5), "attack B starts before the later struck C")
	_visual._update_animation_frame(0.0)
	_check(_visual.current_state == "attack", "FIFO: attack B plays, struck C waits")
	_visual._advance_action_timers(0.6)
	_check(_visual._attack_remaining == 0.0, "attack B finished")
	_check(_visual._hit_remaining > 0.0, "struck C starts after attack B")
	_visual._update_animation_frame(0.0)
	_check(_visual.current_state == "hit", "FIFO order A -> B -> C holds")
	await _dispose_fixture()


## R1.2 review P1 closure, Test B: multiple attack requests during a struck
## backlog stay separate FIFO events with their own durations - never merged
## into the last one.
func _test_multiple_attack_requests_keep_order() -> void:
	await _make_fixture(43)
	_visual.queue_struck(43)
	_visual._advance_action_timers(0.016)
	_visual.play_attack(0.3)
	_visual.play_attack(0.2)
	_visual._advance_action_timers(0.3)
	_check(_visual._hit_remaining == 0.0, "struck A finished")
	_check(is_equal_approx(_visual._attack_remaining, 0.3), "attack B starts with its own duration")
	_visual._advance_action_timers(0.35)
	_check(is_equal_approx(_visual._attack_remaining, 0.2), "attack C keeps its own duration (no merge)")
	_visual._advance_action_timers(0.3)
	_check(_visual._attack_remaining == 0.0 and _visual._hit_remaining == 0.0, "presentation FIFO drained fully")
	await _dispose_fixture()


## P1 verification item (presentation layer ONLY): the walk cadence granting
## the next step while a struck plays must not flip the presentation away
## from the struck, and the struck clock must keep its own duration. The
## gameplay position move stays authoritative and untouched - no WalkTick
## penalty, no movement hard-stun.
func _test_walk_grant_does_not_flip_playing_struck() -> void:
	await _make_fixture(43)
	_visual.queue_struck(43)
	_visual._advance_action_timers(0.016)
	_check(is_equal_approx(_visual._hit_remaining, 0.24), "struck started before the walk grant")
	_enemy.velocity = Vector2(120.0, 0.0)
	_visual._advance_action_timers(0.05)
	_visual._update_animation_frame(0.0)
	_check(_visual.current_state == "hit", "walk grant does not flip the presentation away from the struck")
	_check(is_equal_approx(_visual._hit_remaining, 0.19), "walk grant neither cancels nor accelerates the struck clock")
	_enemy.velocity = Vector2.ZERO
	await _dispose_fixture()


func _test_queue_is_counter_only_and_capped() -> void:
	await _make_fixture(43)
	for _i: int in range(300):
		_visual.queue_struck(43)
	_check(
		_visual.pending_struck_count() == MonsterVisual.PRESENTATION_QUEUE_CAPACITY,
		"malformed-input guard caps the presentation FIFO at its fixed capacity"
	)
	_check(_visual._hit_remaining == 0.0, "mass queueing still does not start a burn")
	await _dispose_fixture()
