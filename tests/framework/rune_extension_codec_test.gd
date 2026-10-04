extends Node

const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String]=[]
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks+=1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	var base:=Drop.create_instance(GameData.get_item_record({"item_id":85}),"rune:base")
	var rune: Dictionary={"rune_instance_contract_id":"hc.runes.fixture.rune.v1","item_id":990002,
		"name":"验证符文","count":1,"instance_id":"rune:asset"}
	var gem:=Gem.create_instance("rune:gem",true)
	var extensions: Dictionary={"hc.socketing":{"schema_version":1,"sockets":[{"socket_id":Codec.SOCKET_ID,"item":gem}]},
		"hc.runes":{"schema_version":1,"runes":[{"rune_slot_id":"hc.runes.primary","item":rune}]}}
	var made:=Codec.with_extensions(base,extensions)
	check(made.status==Codec.KNOWN_VALID,"registered rune and original socket namespaces coexist on one unchanged authoritative base")
	if made.status!=Codec.KNOWN_VALID:
		print("RUNE_EXTENSION_RED_REASON="+str(made.reason)); _finish(); return
	check(Codec.base_record(made.item)==base,"adding a rune never rerolls the historical drop")
	check(Codec.ownership_ids(made.item)==[base.instance_id,gem.instance_id,rune.instance_id],"all three original instances have explicit independent ownership")
	check(not Codec.can_release_ownership(made.item),"destruction or sale cannot discard either embedded asset")
	var encoded:=Codec.encode_runtime(made.item)
	check(encoded.status==Codec.KNOWN_VALID and Codec.decode_wire(encoded.item).item==made.item,"complete two-namespace wire roundtrip retains all original fields")
	check(PlayerState._validate_extended_item_ownership({"inventory":[made.item]}),"single owner aggregate accepts both original assets")
	check(not PlayerState._validate_extended_item_ownership({"inventory":[made.item,rune]}),"an accessible copy of the embedded rune is rejected")
	var future: Dictionary=encoded.item.duplicate(true)
	future.extensions["hc.runes"].schema_version=2; future.base["unknown_base_field"]=1
	check(Codec.decode_wire(future).status==Codec.OPAQUE_UNSUPPORTED,"future rune ownership wins before known-base corruption")
	future=encoded.item.duplicate(true)
	future.extensions["hc.runes"].runes[0].item.rune_instance_contract_id="hc.runes.fixture.rune.v2"
	future.base["unknown_base_field"]=1
	check(Codec.decode_wire(future).status==Codec.OPAQUE_UNSUPPORTED,"future embedded rune instance remains opaque even beside a corrupted old base")
	var unknown: Dictionary=rune.duplicate(true); unknown.item_id=990999
	check(Codec.decode_wire(unknown).status==Codec.OPAQUE_UNSUPPORTED,"an unregistered future rune identity is not recoverable known corruption")
	future=encoded.item.duplicate(true); future.extensions["hc.runes"].runes[0].item=unknown
	future.base["unknown_base_field"]=1
	check(Codec.decode_wire(future).status==Codec.OPAQUE_UNSUPPORTED,"unknown embedded rune identity takes priority over a corrupted known base")
	var collision: Dictionary=encoded.item.duplicate(true)
	collision.extensions["hc.runes"].runes[0].item.instance_id=gem.instance_id
	check(Codec.decode_wire(collision).status==Codec.INVALID,"one instance identity cannot be owned by both registered namespaces")
	var invalid: Dictionary=encoded.item.duplicate(true)
	invalid.extensions["hc.runes"].runes[0].item.count=2
	check(Codec.decode_wire(invalid).status==Codec.INVALID,"known rune instances cannot stack an independently owned asset")
	invalid=encoded.item.duplicate(true); invalid.extensions["hc.runes"].runes[0].item["extra"]=1
	check(Codec.decode_wire(invalid).status==Codec.INVALID,"registered rune contract keeps its exact field whitelist")
	_finish()
func _finish() -> void:
	if not proof.write_receipt("rune_extension_codec_test",checks,failures.size()): failures.append("receipt")
	print(("FRAMEWORK_RUNE_EXTENSION_PASS" if failures.is_empty() else "FRAMEWORK_RUNE_EXTENSION_FAIL")+" checks="+str(checks)+" errors="+str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
