extends RefCounted

const RESOURCE_PATH := "res://assets/art/monsters/effects/monster_target_magic/cow_mage_thunder_magic2.png"

static func acquire_resource() -> Resource:
	return ResourceLoader.load(RESOURCE_PATH)
