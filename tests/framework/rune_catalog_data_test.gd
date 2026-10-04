extends Node
const Rune:=preload("res://scripts/items/rune_item_rules.gd")
const Proof:=preload("res://tests/framework/helpers/check_receipt.gd")
var proof:=Proof.new()
func _ready() -> void:
	var first:=Rune.record_for_id(990002); var second:=Rune.record_for_id(990003)
	var passed: bool=not first.is_empty() and not second.is_empty() and first.itemId!=second.itemId \
		and first.kind=="rune" and second.kind=="rune" and first.category_id==second.category_id
	proof.record(passed,"two primary data-defined rune records resolve without a new GameData branch or a new instance schema")
	var errors:=0 if passed else 1
	var variant:=Rune.create_instance("rune:second-data-only",true,990003)
	passed=not variant.is_empty() and Rune.valid_instance(variant) and GameData.get_item_record(variant).get("itemId")==990003
	proof.record(passed,"second data-defined rune uses the existing creator, identity schema and actual GameData consumer")
	if not passed: errors+=1
	passed=Rune.create_instance("rune:disabled",false,990003).is_empty() and Rune.record_for_id(990999).is_empty()
	proof.record(passed,"disabled fixture creation and undeclared data identities stay unavailable")
	if not passed: errors+=1
	if not proof.write_receipt("rune_catalog_data_test",3,errors): errors+=1
	print("FRAMEWORK_RUNE_CATALOG_"+("PASS" if errors==0 else "FAIL")+" checks=3")
	get_tree().quit(0 if errors==0 else 1)
