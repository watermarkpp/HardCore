extends Node

## Release-gate regression (v74 closure): loads bytecode extracted from the
## signed APK inside the full project context (runner boot = autoloads and all
## production preloads registered) and asserts the AIA2 ownership contract:
## five ownership methods exist, contract id and buffered-ticket constant match.
## Env: V74_GDC_DIR = res:// directory holding extracted .gdc files.
## Extraction procedure is documented in docs/closure/20260910/最终交付报告.md.

const FIVE_METHODS := [
	"_process_ordinary_attack_input",
	"_reconcile_ordinary_attack_button_owners",
	"_refresh_mobile_attack_held",
	"_try_ordinary_attack_intent",
	"_ordinary_attack_owner_matches",
]
const EXPECTED_CONTRACT := "combat.input.ordinary_attack.live_owner_no_debt.v2"
const EXPECTED_BUFFERED := 0


func _ready() -> void:
	var gdc_dir := OS.get_environment("V74_GDC_DIR").strip_edges()
	assert(not gdc_dir.is_empty(), "V74_GDC_DIR not set")
	var game_root_script: GDScript = load(gdc_dir + "/game_root.gdc")
	assert(
		game_root_script != null,
		"extracted game_root.gdc failed to load in full project context",
	)
	var methods := {}
	for method_info in game_root_script.get_script_method_list():
		methods[method_info["name"]] = true
	var missing: Array[String] = []
	for method_name in FIVE_METHODS:
		if not methods.has(method_name):
			missing.append(method_name)
	assert(
		missing.is_empty(),
		"AIA2 ownership methods missing from packaged bytecode: %s" % [missing],
	)
	var constants: Dictionary = game_root_script.get_script_constant_map()
	var contract_id := str(constants.get("ATTACK_INPUT_TICKET_CONTRACT_ID", ""))
	assert(
		contract_id == EXPECTED_CONTRACT,
		"packaged contract id mismatch: %s" % contract_id,
	)
	var buffered := int(constants.get("MAX_BUFFERED_MOBILE_ATTACK_TICKETS", -1))
	assert(
		buffered == EXPECTED_BUFFERED,
		"packaged MAX_BUFFERED_MOBILE_ATTACK_TICKETS mismatch: %d" % buffered,
	)
	# Companion scripts that declare a global class_name (hud, guard, enemy)
	# cannot be re-loaded beside the project's own registrations; their
	# presence is proven by the byte-level APK comparison and the resource
	# closure verifier. Scripts without a global class load cleanly here.
	for companion in [
		"combat_runtime_service.gdc",
		"audio_preferences.gdc",
		"player_state.gdc",
	]:
		var script: GDScript = load(gdc_dir + "/" + companion)
		assert(
			script != null,
			"packaged script failed to load in full project context: %s" % companion,
		)
	print(
		"PACKAGED_BYTECODE_CONTRACT_PASS five_methods=%d contract=%s buffered_tickets=%d"
		% [FIVE_METHODS.size(), EXPECTED_CONTRACT, EXPECTED_BUFFERED]
	)
	get_tree().quit(0)
