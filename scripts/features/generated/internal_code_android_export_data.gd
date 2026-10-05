extends RefCounted

# Code-owned first-export placeholder. No class_name; source/context order stays
# stable across first/final export. The build hook replaces this exact metadata
# file only. It is outside the producer target closure and cannot certify itself.
const AVAILABLE := false
const SEAL_SHA256 := ""
const SEAL_JSON := ""

static func read_bundle() -> Dictionary:
	return {}
