extends Node

const Migrator := preload(
	"res://tools/map_editor/formal_runtime_collision_contract_migrator.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var parsed := Migrator.parse_cli_args(OS.get_cmdline_user_args())
	if not bool(parsed.get("ok", false)):
		push_error(
			"FORMAL_RUNTIME_COLLISION_CONTRACT_MIGRATION_REFUSED %s"
			% str(parsed.get("error", "unknown"))
		)
		get_tree().quit(2)
		return
	var result := Migrator.new().migrate(parsed.selection)
	if not bool(result.get("ok", false)):
		push_error(
			"FORMAL_RUNTIME_COLLISION_CONTRACT_MIGRATION_FAILED %s"
			% str(result.get("error", "unknown"))
		)
		get_tree().quit(1)
		return
	print(
		"FORMAL_RUNTIME_COLLISION_CONTRACT_MIGRATION_PASS maps=%d contract=%s"
		% [
			int(result.get("changed_count", 0)),
			str(result.get("target_contract_id", "")),
		]
	)
	get_tree().quit(0)
