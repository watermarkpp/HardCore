extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const O := preload("res://tests/source176_r3/helpers/case_oracle.gd")
const Poly := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Step := preload("res://scripts/monster_source176/source_step_plan.gd")
var errors: Array[String] = []
var checks := 0
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
	var directions := [Vector2(1,0), Vector2(1,1), Vector2(0,1), Vector2(-1,1),
		Vector2(-1,0), Vector2(-1,-1), Vector2(0,-1), Vector2(1,-1)]
	for phase: Vector2 in [Vector2.ZERO, Vector2(.125,.875), Vector2(.875,.125), Vector2(.5,.5)]:
		for direction: Vector2 in directions:
			var start := Vector2(20,20) + phase
			var goal := start + direction * 7
			var victim := F.player(self, goal)
			var actor := F.enemy(self, 64, start, victim)
			actor._hc_owned_movement_call = true
			var accepted := actor._begin_autonomous_step_without_cadence(direction, 1.0, false, &"pursuit", victim)
			var expected := O.next_leg(start, goal)
			var actual := actor._movement_step_target_ground_gu
			check(accepted, "open leg admitted")
			check(actual.distance_to(expected) <= .0001, "actual committed endpoint matches independent oracle")
			check(O.parallel_forward(actual-start, expected-start), "strict direction has no 45 degree error")
			rows.append({"start": [start.x,start.y], "goal": [goal.x,goal.y],
				"actual": [actual.x,actual.y], "expected": [expected.x,expected.y]})
			F.dispose(actor, victim)
	# Pure source plan: negative coordinates and complete octile length are
	# separate from a published map whose coordinates must remain nonnegative.
	for sx: float in [-1.0,1.0]:
		for sy: float in [-1.0,1.0]:
			var origin := Vector2(-5.125,-5.875)
			var goal := origin + Vector2(12*sx,5*sy)
			var position := origin
			var length := 0.0
			var turns := 0
			var previous := Vector2.ZERO
			for n in range(32):
				if position.distance_to(goal) < .0001:
					break
				var endpoint := Step.next_leg(position, goal)
				check(endpoint.distance_to(O.next_leg(position,goal)) < .0001, "negative phase oracle")
				var leg := endpoint-position
				length += leg.length()
				if previous != Vector2.ZERO and not O.parallel_forward(leg,previous):
					turns += 1
				previous = leg
				position = endpoint
			check(position.distance_to(goal) < .0001, "whole path ends at goal")
			check(absf(length-(7+5*sqrt(2.0))) < .0001, "full octile distance")
			check(turns == 1, "single principal turn")
	var victim := F.player(self, Vector2(12,.875))
	var actor := F.enemy(self,64,Vector2(5.125,.875),victim)
	var radius := actor.combat_radius_gu
	var bottom := .75-radius
	var top := 1.0+radius
	var context := F.polygon_context([[[0,0],[16,0],[16,bottom],[0,bottom]],
		[[0,top],[16,top],[16,16],[0,16]]],radius)
	check(not context.is_empty(), "real polygon fixture constructed")
	if not context.is_empty():
		actor.configure_terrain_navigation_context(context)
		var start := Vector2(5.125,.875)
		var endpoint := Vector2(6.125,.875)
		check(Poly.segment_walkable(context,start,endpoint,radius), "actual narrow-band leg is legal")
		check(not Poly.segment_walkable(context,start,Vector2(6.5,.5),radius), "cell proxy genuinely blocked")
		actor._hc_owned_movement_call = true
		check(actor._begin_autonomous_step_without_cadence(Vector2.RIGHT,1.0,false,&"pursuit",victim), "legal corridor admitted")
		check(actor._movement_step_target_ground_gu.distance_to(endpoint) < .0001, "corridor keeps true endpoint")
		check(actor._hc_polygon_neighbor_clear(start,Vector2(5.25,.875),Vector2i(5,0),Vector2i(5,0)), "same-cell segment accepted")
		check(not actor._hc_polygon_neighbor_clear(start,Vector2(6.125,.5),Vector2i(5,0),Vector2i(6,0)), "actual wall intersection rejected")
		# An axial goal makes the old arbitrary-angle fallback accidentally
		# identical. A tiny lawful goal offset exposes the lost short leg.
		actor._clear_autonomous_step_state()
		victim.global_position = F.to_screen(Vector2(12,.9))
		actor._hc_damage_dirty = true
		var short_endpoint := O.next_leg(start,Vector2(12,.9))
		check(Poly.segment_walkable(context,start,short_endpoint,radius), "short same-cell source leg legal")
		check(actor._begin_autonomous_step_without_cadence(Vector2.RIGHT,1.0,false,&"pursuit",victim), "short corridor leg admitted")
		check(actor._movement_step_target_ground_gu.distance_to(short_endpoint) < .0001, "blocked proxy cannot replace lawful fractional leg")
	F.dispose(actor,victim)
	check(F.write_evidence("exact_leg_and_corridor",{"checks":checks,"errors":errors,"rows":rows}),"evidence written")
	print(("R3_EXACT_LEG_PASS" if errors.is_empty() else "R3_EXACT_LEG_FAIL") + " checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
