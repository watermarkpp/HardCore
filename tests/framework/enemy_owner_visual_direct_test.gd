extends Node
const Original := preload("res://scripts/monster_visual.gd")
const Candidate := preload("res://scripts/gameplay/enemy/enemy_owner_visual.gd")
const Timeline := preload("res://scripts/gameplay/actors/monster_action_timeline.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	proof.record(value, label)

func _ready() -> void:
	# Explicit isolated numeric fixture: no actor, resources or S integration
	# is admitted here. Each side has its own test timeline for comparison.
	var old := Original.new()
	var fresh := Candidate.new()
	var owner_timeline := Timeline.new()
	fresh.action_timeline = owner_timeline
	check(fresh.action_timeline == owner_timeline, "candidate uses supplied existing timeline")
	for count in [1, 4, 12, 24]:
		old.active_resources = {"frame_counts": {&"death": count}}
		fresh.active_resources = old.active_resources.duplicate(true)
		check(old.death_animation_duration() == fresh.death_animation_duration(), "source resident death frame duration " + str(count))
	old.play_hit(0.31)
	fresh.play_hit(0.31)
	check(old._hit_remaining == fresh._hit_remaining and fresh._hit_remaining == owner_timeline.hit_remaining, "direct struck primitive mutates existing owner timeline")
	old.action_timeline.enqueue(0, 0.16, -1)
	owner_timeline.enqueue(0, 0.16, -1)
	old.action_timeline.enqueue(0, 0.23, -1)
	owner_timeline.enqueue(0, 0.23, -1)
	check(old._merge_pending_struck_feedback() == fresh._merge_pending_struck_feedback(), "source merge count")
	check(old._pending_struck_count == fresh._pending_struck_count and old._presentation_count == fresh._presentation_count, "source newest struck FIFO state")
	check(old.play_death() == fresh.play_death(), "source death duration result")
	check(old._hit_remaining == fresh._hit_remaining and old._attack_remaining == fresh._attack_remaining and old._presentation_count == fresh._presentation_count, "death cancels same original timeline state")
	check(fresh.action_timeline == owner_timeline, "death never replaces supplied timeline")
	old.free()
	if not proof.write_receipt("enemy_owner_visual_direct_test", checks, failures): failures += 1
	print("ENEMY_OWNER_VISUAL_DIRECT_%s checks=%d scope=isolated numeric source oracle; lifecycle/S NOT_RUN" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
