extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Authority := preload("res://scripts/features/adapters/feature_authority.gd")
var proof := Proof.new()
var errors: Array[String] = []
var checks := 0
func check(value: bool, label: String) -> void:
 proof.record(value, label)
 checks += 1
 if not value: errors.append(label)
func _ready() -> void:
 var owner: Variant = load("res://scripts/features/compilation/feature_loadout.gd").new()
 var authority: Dictionary = Authority.build()
 var module: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/numeric_fixture.json"))
 var compiled: Dictionary = Compiler.compile_catalog([module], authority)
 check(compiled.success and owner.synchronize(compiled.catalog, [], authority), "empty bundle publishes without stat inputs")
 var previous: Dictionary = owner.bundle()
 var before_count: int = owner.compile_count
 module.mechanics = [{"mechanic_id":"hc.fixture_inverted_range", "kind":"stat", "tags":[], "operations":[{"stat":"magic_min", "op":"add", "value":1000}]}]
 var bad: Dictionary = Compiler.compile_catalog([module], authority)
 var source := {"source":{"slot":"hc.slot.rule", "instance_id":"rule:atomic.range", "mechanic_id":"hc.fixture_inverted_range"},"mechanic_id":"hc.fixture_inverted_range"}
 check(bad.success, "numeric schema alone cannot prove actual actor range invariant")
 check(not owner.synchronize(bad.catalog, [source], authority) and is_same(previous, owner.bundle()) and owner.compile_count == before_count, "stat candidate cannot publish without actual base validation")
 var support := false
 for method: Dictionary in owner.get_script().get_script_method_list():
  if method.name == "synchronize" and method.args.size() == 4: support = true
 if support:
  var base := {"accuracy":2,"attack_min":2,"attack_max":3,"magic_min":2,"magic_max":3,"tao_min":2,"tao_max":3}
  check(not owner.call("synchronize", bad.catalog, [source], authority, base) and is_same(previous, owner.bundle()), "actual inverted range rejects and preserves previous bundle")
  module.mechanics[0].operations[0].value = 1
  var good: Dictionary = Compiler.compile_catalog([module], authority)
  check(owner.call("synchronize", good.catalog, [source], authority, base), "valid boundary stat candidate publishes atomically")
  check(owner.apply_stats(base).stats.magic_min == 3 and owner.compile_count == before_count + 1, "valid contribution applies once after validation")
 if not proof.write_receipt("feature_loadout_atomic_test", checks, errors.size()): errors.append("receipt")
 print(("FRAMEWORK_FEATURE_LOADOUT_ATOMIC_PASS" if errors.is_empty() else "FRAMEWORK_FEATURE_LOADOUT_ATOMIC_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
 get_tree().quit(0 if errors.is_empty() else 1)
