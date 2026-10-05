extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Identity := preload("res://scripts/monster_identity.gd")
var checks := 0
var errors: Array[String] = []
var rows: Array = []

func _ready() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)

func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	# ID33 is a real canonical four-frame attack; do not invent an eight
	# frame monster. Ordinary 64/89 cover the six-frame identities.
	for id: int in [33,64,89]:
		var victim := F.player(self,Vector2(25,20))
		var actor := F.enemy(self,id,Vector2(20,20),victim)
		var profile := Identity.appearance_profile(id)
		var count := int(profile.get("actions",{}).get("attack",{}).get("framesPerDirection",0))
		check(count>0,"formal attack metadata exists")
		check(actor._canonical_attack_frame_count(1)==count,"owner uses canonical count")
		actor.visual.visible = false
		actor.visual.set_process(false)
		var duration := 1.2
		actor.visual.active_resources = {}
		actor.visual._start_attack_visual(duration)
		var cold_phase: float = actor.visual._attack_strike_threshold_s
		actor.visual.active_resources = {"frame_counts":{&"attack":count}}
		actor.visual._start_attack_visual(duration)
		var hot_phase: float = actor.visual._attack_strike_threshold_s
		check(absf(cold_phase-hot_phase)<.000001,"cold and hot phase identical")
		check(absf(cold_phase-duration*2.0/float(maxi(count,4)))<.000001,"phase from independent canonical metadata")
		rows.append({"monster_id":id,"frames":count,"cold_phase":cold_phase,"hot_phase":hot_phase})
		F.dispose(actor,victim)
	# Fixed-area actions must use metadata captured by this actor's setup.
	# A catalog cache replacement models a later reload; it must not mutate
	# an already accepted actor's action duration or cause a hot deep copy.
	for id: int in [124,180,195]:
		var victim := F.player(self,Vector2(25,20))
		var actor := F.enemy(self,id,Vector2(20,20),victim)
		var action: Dictionary = Identity.appearance_profile(id).get("actions",{}).get("attack",{})
		var frames := int(action.get("framesPerDirection",0))
		var frame_ms := int(action.get("frameMs",0))
		check(frames>0 and frame_ms>0,"formal fixed-area action metadata exists")
		var expected := maxf(actor._attack_animation_duration,float(frames*frame_ms)/1000.0)
		var original: Dictionary = Identity._appearance_cache[str(id)]
		Identity._appearance_cache[str(id)] = {"actions":{"attack":{"framesPerDirection":99,"frameMs":999}}}
		actor.visual.active_resources = {}
		var cold_duration := actor._area_attack_visual_duration()
		actor.visual.active_resources = {"frame_counts":{&"attack":frames}}
		var hot_duration := actor._area_attack_visual_duration()
		Identity._appearance_cache[str(id)] = original
		check(absf(cold_duration-expected)<.000001,"area duration is frozen at setup")
		check(absf(hot_duration-cold_duration)<.000001,"area cold/hot duration is identical")
		rows.append({"monster_id":id,"frames":frames,"frame_ms":frame_ms,
			"expected_duration":expected,"cold_duration":cold_duration,"hot_duration":hot_duration})
		F.dispose(actor,victim)
	check(F.write_evidence("cold_hot_action_phase",{"checks":checks,"errors":errors,"rows":rows}),"write metadata evidence")
	print(("R3_COLD_HOT_PASS" if errors.is_empty() else "R3_COLD_HOT_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
