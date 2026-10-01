extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const O := preload("res://tests/source176_r3/helpers/case_oracle.gd")
var errors: Array[String] = []
var checks := 0
var rows: Array = []

func _ready() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value and errors.size() < 64:
		errors.append(label)

func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var inputs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/source176_r3/cases/boundary_expected.json"))
	var cases: Array = inputs.rows.duplicate(true)
	# Reuse the independent 72-point geometry oracle for real zombie/member
	# and high-level ordinary identities; identity resolution remains runtime.
	for id: int in [24,81,238]:
		for template: Dictionary in inputs.rows:
			if int(template.monster_id)!=64:
				continue
			var input: Dictionary = template.duplicate(true)
			input.monster_id = id
			input.case_id = "identity_"+str(id)+"/"+str(template.case_id)
			cases.append(input)
	for input: Dictionary in cases:
		var phase := Vector2(float(input.phase[0]),float(input.phase[1]))
		var origin := Vector2(20,20)+phase
		var offset := Vector2(float(input.relative_ground_gu[0]),float(input.relative_ground_gu[1]))
		var victim := F.player(self,origin+offset)
		var actor := F.enemy(self,int(input.monster_id),origin,victim)
		# This is a deterministic admission/consumer test, not natural
		# pursuit. Undo spawn hygiene once BEFORE invoking the gate; log and
		# verify the actual landed pose and unchanged physical radii.
		actor.set_combat_position(F.to_screen(origin),&"r3_boundary_fixture")
		var actual_origin := F.to_ground(actor.global_position)
		var actual_offset := F.to_ground(victim.global_position)-actual_origin
		var overlap := actual_offset.length() < actor.combat_radius_gu+actor._target_combat_radius_gu(victim)-.0001
		check(actual_origin.distance_to(origin)<.0001,"landed source pose")
		check(actual_offset.distance_to(offset)<.0001,"landed target offset")
		check(not overlap,"boundary fixture has legal bodies")
		check(actor._source176_ordinary_melee(),"canonical ordinary route")
		var expected: bool = bool(input.expected)
		check(O.in_box(actual_offset)==expected,"independent expectation remains valid at actual pose")
		actor._attack_timer = 0.0
		var hp := victim.current_hp
		var rng_state: int = actor._rng.state
		var parent_id: int = actor._attack_logic_serial
		var admitted := actor._hc_try_start(victim)
		check(admitted==expected,"strict admission "+str(input.case_id))
		if not expected:
			check(actor._rng.state==rng_state,"rejected admission spends no RNG")
			check(actor._attack_timer==0.0,"rejected admission spends no cooldown")
			check(actor._attack_logic_serial==parent_id,"rejected admission allocates no parent")
			check(victim.current_hp==hp,"rejected admission deals no damage")
		rows.append({"case_id":input.case_id,"accepted":admitted,
			"actual_pose_verified":actual_origin.distance_to(origin)<.0001 and actual_offset.distance_to(offset)<.0001,
			"body_overlap":overlap,"expected_from_independent_oracle":true,
			"source_radius":actor.combat_radius_gu,"target_radius":actor._target_combat_radius_gu(victim)})
		F.dispose(actor,victim)
	check(rows.size()==360,"five exact 72 member boundary sets")
	check(F.write_evidence("eight_direction_admission",{"schema":"source176.r3.boundary_observation.v1","rows":rows,"checks":checks,"errors":errors}),"write boundary evidence")
	print(("R3_BOUNDARY_PASS" if errors.is_empty() else "R3_BOUNDARY_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
