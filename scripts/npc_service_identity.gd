class_name NPCServiceIdentity
extends RefCounted

const GENERAL_VENDOR_ID := "npc.service.general_vendor.v1"
const BLACKSMITH_ID := "npc.service.blacksmith.v1"
const BOOK_VENDOR_ID := "npc.service.book_vendor.v1"
const PHARMACIST_ID := "npc.service.pharmacist.v1"
const ENHANCEMENT_VENDOR_ID := "npc.service.enhancement_vendor.v1"
const VETERAN_ID := "npc.service.veteran.v1"
const WAREHOUSE_ID := "npc.service.warehouse.v1"

const STOCK_IDENTITIES := {
	"general": {"id": GENERAL_VENDOR_ID, "display_name": "杂货商"},
	"starter_gear": {"id": BLACKSMITH_ID, "display_name": "铁匠"},
	"mid_gear": {"id": BLACKSMITH_ID, "display_name": "铁匠"},
	"books": {"id": BOOK_VENDOR_ID, "display_name": "书店老板"},
	"medicine": {"id": PHARMACIST_ID, "display_name": "药剂商"},
}


static func resolve(legacy_display_name: String, kind: String, stock_key: String) -> Dictionary:
	var normalized_stock := stock_key.strip_edges()
	if STOCK_IDENTITIES.has(normalized_stock):
		return (STOCK_IDENTITIES[normalized_stock] as Dictionary).duplicate(true)
	var normalized_kind := kind.strip_edges()
	match normalized_kind:
		"repair":
			return {"id": BLACKSMITH_ID, "display_name": "铁匠"}
		"trainer":
			return {"id": ENHANCEMENT_VENDOR_ID, "display_name": "强化商人"}
		"quest":
			return {"id": VETERAN_ID, "display_name": "老兵"}
		"warehouse":
			return {"id": WAREHOUSE_ID, "display_name": "仓库管理员"}
	var legacy_name := legacy_display_name.strip_edges()
	if "药剂商" in legacy_name:
		return {"id": PHARMACIST_ID, "display_name": "药剂商"}
	if "杂货商" in legacy_name:
		return {"id": GENERAL_VENDOR_ID, "display_name": "杂货商"}
	if "铁匠" in legacy_name or "武器店" in legacy_name or "装备店" in legacy_name:
		return {"id": BLACKSMITH_ID, "display_name": "铁匠"}
	if "书店" in legacy_name:
		return {"id": BOOK_VENDOR_ID, "display_name": "书店老板"}
	if "武馆教头" in legacy_name:
		return {"id": ENHANCEMENT_VENDOR_ID, "display_name": "强化商人"}
	if "老兵" in legacy_name:
		return {"id": VETERAN_ID, "display_name": "老兵"}
	if "仓库管理员" in legacy_name:
		return {"id": WAREHOUSE_ID, "display_name": "仓库管理员"}
	return {"id": "", "display_name": legacy_name if not legacy_name.is_empty() else "NPC"}
