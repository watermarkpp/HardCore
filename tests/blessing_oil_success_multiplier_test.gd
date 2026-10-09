extends Node

const Rules := preload("res://scripts/equipment_rules.gd")


func _ready() -> void:
	var joint_hits := 0
	for lower in range(8):
		for upper in range(80):
			if Rules.blessing_luck12_joint_roll_hits(lower, upper, 8, 80):
				joint_hits += 1
	assert(joint_hits == 435, "R=2 total success numerator must be 5*(80+8-1)")
	var r1_hits := 0
	for lower in range(7):
		for upper in range(40):
			if Rules.blessing_luck12_joint_roll_hits(lower, upper, 7, 40):
				r1_hits += 1
	assert(r1_hits == 230, "R=1 total success numerator must be 5*(40+7-1)")
	var r3_hits := 0
	for lower in range(9):
		for upper in range(120):
			if Rules.blessing_luck12_joint_roll_hits(lower, upper, 9, 120):
				r3_hits += 1
	assert(r3_hits == 640, "R=3 total success numerator must be 5*(120+9-1)")
	assert(not Rules.blessing_luck12_joint_roll_hits(-1, 0, 8, 80), "invalid lower draw must fail")
	assert(not Rules.blessing_luck12_joint_roll_hits(0, 80, 8, 80), "invalid upper draw must fail")
	assert(Rules.BLESSING_UNLUCKY_RATE == 20, "unlucky branch denominator must remain 20")
	print("BLESSING_OIL_SUCCESS_MULTIPLIER_PASS multiplier=5 capped=true unlucky=1/20")
	get_tree().quit()
