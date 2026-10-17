extends RefCounted

## Owner-local proof. Candidate data is Main-canonical, recursively frozen
## values; never a Main Node, Callable, Resource or accepted actor identity.
var owner: WeakRef
var expected_expansions: Dictionary = {}
var database_revision := 0
var database_loaded := false
var layer_revision := 0
var requested_expansions: Dictionary = {}
var merged_database: Dictionary = {}
var merge_diagnostics: Array = []
var database_candidate: Dictionary = {}
var consumed := false
