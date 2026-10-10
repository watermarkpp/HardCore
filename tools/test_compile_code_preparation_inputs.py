"""Offline direct counterexamples; test-owned symbols are never engine evidence."""
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("compile_code_preparation_inputs.py")
SPEC = importlib.util.spec_from_file_location("code_preparation_candidate", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

OWNED = Path(__file__).resolve().parents[1] / "outputs/test_logs/code_preparation_producer"
OWNER = "res://scripts/entry.gd"
ASSET = "res://assets/shaders/example.gdshader"
NATIVE = {"RefCounted", "Sprite2D", "Vector2", "Shader", "String", "Array", "Dictionary", "Variant"}


class ProducerCases(unittest.TestCase):
    def inspect(self, source, classes=None):
        return MODULE.extract(source, OWNER, classes or {}, NATIVE, {})

    def asset_paths(self, source, classes=None):
        result = self.inspect(source, classes)
        self.assertEqual(result["refusals"], [])
        return [edge["to"] for edge in result["edges"]]

    def refused(self, source, error):
        result = self.inspect(source)
        self.assertTrue(any(error in refusal for refusal in result["refusals"]), result)

    def test_literal_preload(self):
        self.assertEqual(self.asset_paths(f'extends RefCounted\nconst Asset = preload("{ASSET}")\n'), [ASSET])

    def test_comment_is_not_code(self):
        self.assertEqual(self.asset_paths(f'# preload("res://wrong.gd")\nconst Asset=preload("{ASSET}") # preload("res://wrong2.gd")'), [ASSET])

    def test_single_string_is_not_code(self):
        self.assertEqual(self.asset_paths("const Message='preload(\"res://wrong.gd\")'\n"), [])

    def test_double_escaped_string_is_not_code(self):
        self.assertEqual(self.asset_paths('const Message="preload(\\\"res://wrong.gd\\\")"\n'), [])

    def test_triple_string_is_not_code(self):
        self.assertEqual(self.asset_paths("const Message=\"\"\"\npreload('res://wrong.gd')\n# extends Unknown\n\"\"\"\n"), [])

    def test_string_hash_is_not_comment(self):
        self.assertEqual(self.asset_paths('const Message="# preload(ignored)"\n'), [])

    def test_unicode_escape_decodes_path(self):
        self.assertEqual(self.asset_paths('const Asset=preload("res://assets/shaders/exampl\\u0065.gdshader")'), [ASSET])

    def test_escaped_quote_decodes_not_truncates(self):
        self.assertEqual(self.asset_paths('const Asset=preload("res://assets/shaders/a\\\"b.gdshader")'), ['res://assets/shaders/a"b.gdshader'])

    def test_unknown_escape_is_refused(self):
        with self.assertRaisesRegex(MODULE.Refusal, "unsupported_string_escape"):
            MODULE.lex('const Asset=preload("res://a\\q.gdshader")')

    def test_raw_string_is_refused(self):
        with self.assertRaisesRegex(MODULE.Refusal, "unsupported_raw_string"):
            MODULE.lex('const Asset=preload(r"res://a.gdshader")')

    def test_multiline_and_trailing_comma(self):
        self.assertEqual(self.asset_paths(f'const Asset=preload(\n "{ASSET}",\n)\n'), [ASSET])

    def test_line_continuation(self):
        self.assertEqual(self.asset_paths('const Root="res://assets/"\nconst Asset=preload(Root + \\\n"shaders/example.gdshader")'), [ASSET])

    def test_string_constant_combination(self):
        source = 'const PREFIX="res://assets/"\nconst STEM=("shaders/"+"example")\nconst Asset=preload(PREFIX+(STEM+".gdshader"))'
        self.assertEqual(self.asset_paths(source), [ASSET])

    def test_forward_constant_is_resolved(self):
        self.assertEqual(self.asset_paths('const Asset=preload(Path)\nconst Path="res://assets/shaders/example.gdshader"'), [ASSET])

    def test_typed_constant_is_resolved(self):
        self.assertEqual(self.asset_paths('const Path:String="res://assets/shaders/example.gdshader"\nconst Asset=preload(Path)'), [ASSET])

    def test_constant_cycle_is_refused(self):
        self.refused('const A=B\nconst B=A\nconst Asset=preload(A)', "cyclic_path_constant")

    def test_variable_argument_is_refused(self):
        self.refused('var path="res://x.gdshader"\nconst Asset=preload(path)', "unresolved_path_constant")

    def test_eager_constant_helper_call_is_refused(self):
        self.refused('const Asset = make_asset()\nfunc make_asset():\n return load("res://hidden.tres")\n', "unsupported_eager_constant_call")

    def test_indirect_constant_call_is_refused(self):
        self.refused('const Asset = [make_asset][0]()\n', "unsupported_indirect_constant_call")

    def test_only_exact_source_bound_numeric_fold_case_is_accepted(self):
        source = 'const Value = example_math(64.0 * 32.0)\n'
        approved = {OWNER + "#Value": {"expression_tokens": ["example_math", "(", "64.0", "*", "32.0", ")"], "native_functions": ["example_math"]}}
        value = MODULE.extract(source, OWNER, {}, NATIVE | {"example_math"}, {}, approved)
        self.assertEqual(value["refusals"], [])
        changed = MODULE.extract(source.replace("32.0", "33.0"), OWNER, {}, NATIVE | {"example_math"}, {}, approved)
        self.assertTrue(any("unsupported_eager_constant_call" in e for e in changed["refusals"]))
        wrong_owner = MODULE.extract(source, "res://scripts/other.gd", {}, NATIVE | {"example_math"}, {}, approved)
        self.assertTrue(any("unsupported_eager_constant_call" in e for e in wrong_owner["refusals"]))

    def test_bare_math_registration_does_not_authorize_eager_calls(self):
        value = MODULE.extract('const Value = example_math(1.0)\n', OWNER, {}, NATIVE | {"example_math"}, {})
        self.assertTrue(any("unsupported_eager_constant_call" in e for e in value["refusals"]))

    def test_method_computed_path_is_refused(self):
        self.refused('const Asset=preload("res://x.gdshader".replace("x","y"))', "unsupported_preload_path_expression")

    def test_global_function_computed_path_is_refused(self):
        self.refused('const Asset=preload(make_path())', "unresolved_path_constant")

    def test_conditional_path_is_refused(self):
        self.refused('const Asset=preload("res://a.gdshader" if true else "res://b.gdshader")', "unsupported_preload_path_expression")

    def test_stringname_argument_is_refused(self):
        self.refused('const Asset=preload(&"res://a.gdshader")', "unsupported_preload_path_expression")

    def test_relative_path_is_canonical(self):
        self.assertEqual(self.asset_paths('const Asset=preload("neighbor.gd")'), ['res://scripts/neighbor.gd'])

    def test_parent_relative_is_refused(self):
        self.refused('const Asset=preload("../neighbor.gd")', "noncanonical_resource_path")

    def test_uid_is_refused(self):
        self.refused('const Asset=preload("uid://unresolved")', "unsupported_resource_namespace")

    def test_control_character_path_is_refused(self):
        self.refused('const Asset=preload("res://bad\\npath.gd")', "invalid_resource_path")

    def test_literal_extends(self):
        self.assertEqual(self.asset_paths('extends "parent.gd"\n'), ['res://scripts/parent.gd'])

    def test_native_extends(self):
        self.assertEqual(self.asset_paths('extends RefCounted\n'), [])

    def test_unknown_extends_is_refused(self):
        self.refused('extends UnknownBase\n', "unresolved_extends_identity")

    def test_qualified_extends_is_refused(self):
        self.refused('extends "parent.gd".Inner\n', "unsupported_qualified_extends")

    def test_named_class_edge(self):
        self.assertEqual(self.asset_paths('extends RefCounted\nfunc action():\n\tPeer.work()\n', {"Peer":"res://scripts/peer.gd"}), ['res://scripts/peer.gd'])

    def test_named_class_in_type_is_edge(self):
        self.assertEqual(self.asset_paths('func action(value:Peer):\n\tpass', {"Peer":"res://scripts/peer.gd"}), ['res://scripts/peer.gd'])

    def test_autoload_is_residency_requirement_not_fake_cold_recursion(self):
        result = MODULE.extract('func later():\n\tGameData.lookup()',OWNER,{},NATIVE,{"GameData":"res://scripts/game_data.gd"})
        self.assertEqual(result["refusals"],[])
        self.assertEqual(result["edges"][0]["kind"],"autoload_symbol")

    def test_member_name_does_not_become_global(self):
        self.assertEqual(self.asset_paths('func action(value):\n\tvalue.Peer()\n', {"Peer":"res://scripts/peer.gd"}), [])

    def test_class_name_shadowing_is_refused(self):
        result = self.inspect('func action(Peer):\n\tPeer.work()\n', {"Peer":"res://scripts/peer.gd"})
        self.assertTrue(any("global_class_shadowing" in value for value in result["refusals"]))

    def test_exact_registered_preload_alias_is_eager_edge(self):
        path = "res://scripts/example.gd"
        result = self.inspect(f'const Example = preload("{path}")\nfunc f():\n return Example.new()\n', {"Example": path})
        self.assertEqual(result["refusals"], [])
        self.assertEqual([(edge["kind"], edge["to"]) for edge in result["edges"]], [("preload", path)])

    def test_wrong_registered_preload_alias_is_refused(self):
        result = self.inspect('const Example = preload("res://scripts/wrong.gd")\n', {"Example": "res://scripts/example.gd"})
        self.assertTrue(any("global_class_shadowing" in value for value in result["refusals"]))

    def test_native_constructor_shadowing_is_refused(self):
        self.refused('func Vector2():\n\tpass\nvar position=Vector2()', "engine_symbol_shadowing")

    def test_uppercase_local_cannot_hide_global_miss(self):
        self.refused('func first():\n\tvar MissingClass=1\nfunc second():\n\tMissingClass.work()', "unsupported_uppercase_scoped_binding")

    def test_nested_class_is_refused(self):
        self.refused('class Inner:\n\tpass', "unsupported_nested_class_or_enum")

    def test_annotation_is_refused(self):
        self.refused('@tool\nextends RefCounted', "unsupported_annotation")

    def test_dynamic_load_is_explicit(self):
        result = self.inspect('func later(path):\n\treturn load(path)')
        self.assertEqual(result["refusals"], [])
        self.assertEqual(result["deferred_observations"][0]["phase"], "runtime_method")
        self.assertEqual(result["deferred_observations"][0]["runtime_resource_contract"], "MISSING")

    def test_preload_inside_method_still_eager(self):
        self.assertEqual(self.asset_paths(f'func later():\n\treturn preload("{ASSET}")'), [ASSET])

    def test_static_init_does_not_hide_dynamic_load(self):
        self.refused('static func _static_init():\n\tload("res://a.gdshader")', "unsupported_eager_static_init")

    def test_static_var_dynamic_load_is_eager_rejected(self):
        self.refused('static var texture=load("res://a.gdshader")', "unproven_eager_dynamic_execution")

    def test_instance_var_load_is_deferred(self):
        result = self.inspect('var texture=load("res://a.gdshader")')
        self.assertEqual(result["refusals"], [])
        self.assertEqual(result["deferred_observations"][0]["phase"], "runtime_instance_initializer")

    def test_multiline_signature_does_not_leak_method_scope(self):
        result = self.inspect('func later(\n path\n):\n\tload(path)\nstatic var texture=load("res://a.gdshader")')
        self.assertEqual([o["phase"] for o in result["deferred_observations"]], ["runtime_method", "eager_static_initializer"])
        self.assertTrue(any("unproven_eager_dynamic_execution" in error for error in result["refusals"]))

    def test_static_initializer_helper_escape_is_refused(self):
        self.refused('static var ready=helper()\nfunc helper():\n\treturn 1', "unsupported_member_initializer_call")

    def test_indirect_static_initializer_escape_is_refused(self):
        self.refused('static var ready=ResourceLoader["load"]("res://dynamic.gdshader")', "unsupported_indirect_initializer_call")

    def test_static_getter_escape_is_refused(self):
        self.refused('static var ready=Factory.asset', "unsupported_member_initializer_access")

    def test_dynamic_runtime_code_is_refused(self):
        result = self.inspect('func action():\n\tGDScript.new()')
        self.assertTrue(any(o["operation"] == "GDScript" and o["phase"] == "runtime_method" for o in result["deferred_observations"]))
        self.assertFalse(any("unsupported_eager_code_construction" in error for error in result["refusals"]))

    def test_duplicate_constant_is_refused(self):
        self.refused('const Path="a"\nconst Path="b"\nconst Asset=preload(Path)', "duplicate_constant")

    def test_scoped_constant_is_refused(self):
        self.refused('func action():\n\tconst Path="res://a.gdshader"\n\tpreload(Path)', "unsupported_scoped_constant")

    def test_unterminated_string_is_refused(self):
        with self.assertRaisesRegex(MODULE.Refusal, "unterminated_string"):
            MODULE.lex('const X="unterminated')

    def test_unbalanced_delimiter_is_refused(self):
        with self.assertRaisesRegex(MODULE.Refusal, "unclosed_delimiter"):
            self.inspect('const X=preload("res://a.gdshader"')

    def test_class_cache_conflict_is_refused(self):
        data = b'list=[{"class": &"Peer", "path":"res://a.gd", "language":&"GDScript"},{"class":&"Peer", "path":"res://b.gd", "language":&"GDScript"}]'
        with self.assertRaisesRegex(MODULE.Refusal, "conflicting_global_class_path"):
            MODULE.read_class_map(data)

    def test_class_cache_not_arbitrary_eval(self):
        with self.assertRaises(MODULE.Refusal):
            MODULE.read_class_map(b'list=execute("arbitrary")')

    def test_engine_identity_mismatch_is_refused(self):
        with self.assertRaisesRegex(MODULE.Refusal, "fingerprint"):
            MODULE.native_namespace({"schema_version":1,"engine":{"binary_sha256":"wrong"}}, "actual")

    def test_no_namespace_is_missing(self):
        names, errors = MODULE.native_namespace(None, None)
        self.assertEqual(names, set())
        self.assertEqual(errors, ["MISSING:engine_namespace_capture"])

    def test_classdb_json_cannot_self_grant_global_symbols(self):
        env = {"schema_version":1,"engine":{"binary_sha256":"TEST_ONLY"},"run_id":"T","invocation_id":"T","source_content_sha256":"T",
               "object_classes":["RefCounted"],"variant_type_names":[],"singletons":[],"global_constants":{"status":"PASS","names":["PretendGlobal"]}}
        names, errors = MODULE.native_namespace(env, "TEST_ONLY")
        self.assertNotIn("PretendGlobal", names)
        self.assertEqual(errors, [])

    def test_global_symbols_need_matching_engine_source_artifact(self):
        env = {"schema_version":1,"engine":{"binary_sha256":"TEST_ONLY","version":{"hash":"COMMIT_A"}},"run_id":"T","invocation_id":"T","source_content_sha256":"T",
               "object_classes":["RefCounted"],"variant_type_names":[],"singletons":[]}
        utility = {"schema_version":1,"engine_commit":"COMMIT_B","authority":{"kind":"fixed_engine_source_generated","source_files":[{"path":"test.cpp","commit":"COMMIT_A","sha256":"0" * 64}],"extractor_sha256":"0" * 64},"global_constants":["TestConstant"],"global_functions":[],
                   "producer_id":"hc.code_preparation.native_symbols.compile_probe.candidate.v1","binary_availability":"PASS","engine":{"binary_sha256":"TEST_ONLY"},"run_id":"TEST_ONLY","invocation_id":"TEST_ONLY","source_content_sha256":"TEST_ONLY","candidate_artifact_sha256":"0" * 64,
                   "probe_results":[{"name":"TestConstant","kind":"global_constant","status":"PASS","reload_error":0,"method_invocations":0}]}
        with self.assertRaisesRegex(MODULE.Refusal,"version_mismatch"):
            MODULE.native_namespace(env,"TEST_ONLY",utility)
        utility["engine_commit"] = "COMMIT_A"
        names, _ = MODULE.native_namespace(env,"TEST_ONLY",utility)
        self.assertIn("TestConstant",names)
        utility["binary_availability"] = "NOT_RUN"
        with self.assertRaisesRegex(MODULE.Refusal,"binary_proof_missing"):
            MODULE.native_namespace(env,"TEST_ONLY",utility)
        utility["binary_availability"] = "PASS"
        utility["probe_results"][0]["reload_error"] = 1
        with self.assertRaisesRegex(MODULE.Refusal,"probe_failed"):
            MODULE.native_namespace(env,"TEST_ONLY",utility)

    def test_full_owned_graph_success_and_missing_leaf_refusal(self):
        # This namespace is test-owned grammar input, explicitly not fixed-engine metadata.
        with tempfile.TemporaryDirectory(prefix="producer_cases_", dir=OWNED) as directory:
            root = Path(directory)
            self.assertTrue(root.resolve().is_relative_to(OWNED.resolve()))
            (root / "scripts").mkdir()
            (root / "assets/shaders").mkdir(parents=True)
            (root / "project.godot").write_text('[autoload]\n', encoding="utf-8")
            cache = root / "class_cache.cfg"
            cache.write_text('list=[{"class":&"Peer","path":"res://scripts/peer.gd","language":&"GDScript"}]', encoding="utf-8")
            (root / "scripts/entry.gd").write_text('extends RefCounted\nconst Asset=preload("res://assets/shaders/example.gdshader")\nfunc action():\n\tPeer.work()\n', encoding="utf-8")
            (root / "scripts/peer.gd").write_text('class_name Peer\nextends RefCounted\n', encoding="utf-8")
            (root / "assets/shaders/example.gdshader").write_text('shader_type canvas_item;\n', encoding="utf-8")
            env = {"schema_version":1,"engine":{"binary_sha256":"TEST_ONLY"},"run_id":"TEST_ONLY","invocation_id":"TEST_ONLY", "source_content_sha256":"TEST_ONLY", "object_classes":["RefCounted"],"variant_type_names":[],"singletons":[]}
            env["global_script_class_cache_sha256"] = MODULE.sha(cache.read_bytes())
            env["project_godot_sha256"] = MODULE.sha((root / "project.godot").read_bytes())
            result = MODULE.compile_entry(root, OWNER, cache, env, "TEST_ONLY", 8)
            self.assertEqual(result["status"], "PASS", result)
            self.assertEqual(result["prepared_inputs"], [ASSET])
            (root / "assets/shaders/example.gdshader").unlink()
            result = MODULE.compile_entry(root, OWNER, cache, env, "TEST_ONLY", 8)
            self.assertEqual(result["status"], "FAIL")
            self.assertEqual(result["prepared_inputs"], [])
            self.assertTrue(any("missing_exact_dependency" in error for error in result["errors"]))

    def test_fold_owner_evidence_keeps_exact_probe_bytes(self):
        lf = b"const Value = 64.0 * 32.0\n"
        crlf = lf.replace(b"\n", b"\r\n")
        approved_raw = MODULE.sha(crlf)
        self.assertTrue(MODULE.fold_owner_matches_source(approved_raw, crlf))
        self.assertFalse(MODULE.fold_owner_matches_source(approved_raw, lf))
        self.assertFalse(MODULE.fold_owner_matches_source(approved_raw, crlf.replace(b"32.0", b"33.0")))

    def test_crlf_checkout_has_same_canonical_source_fingerprints(self):
        with tempfile.TemporaryDirectory(prefix="producer_eol_", dir=OWNED) as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "assets/shaders").mkdir(parents=True)
            (root / "project.godot").write_bytes(b"[autoload]\nGameData=\"res://scripts/peer.gd\"\n")
            cache = root / "class_cache.cfg"
            cache.write_bytes(b"list=[{\"class\":&\"Peer\",\"path\":\"res://scripts/peer.gd\",\"language\":&\"GDScript\"}]\n")
            entry = root / "scripts/entry.gd"
            peer = root / "scripts/peer.gd"
            shader = root / "assets/shaders/example.gdshader"
            lf_entry = b"extends RefCounted\nconst Asset=preload(\"res://assets/shaders/example.gdshader\")\nfunc action():\n\tGameData.lookup()\n\tPeer.work()\n"
            lf_peer = b"class_name Peer\nextends RefCounted\nfunc work():\n\tpass\n"
            lf_shader = b"shader_type canvas_item;\n"
            entry.write_bytes(lf_entry)
            peer.write_bytes(lf_peer)
            shader.write_bytes(lf_shader)
            env = {"schema_version": 1, "engine": {"binary_sha256": "TEST_ONLY"}, "run_id": "TEST_ONLY", "invocation_id": "TEST_ONLY", "source_content_sha256": "TEST_ONLY", "object_classes": ["RefCounted"], "variant_type_names": [], "singletons": []}
            env["global_script_class_cache_sha256"] = MODULE.sha(cache.read_bytes())
            env["project_godot_sha256"] = MODULE.sha((root / "project.godot").read_bytes())
            lf_result = MODULE.compile_entry(root, OWNER, cache, env, "TEST_ONLY", 8)
            self.assertEqual(lf_result["status"], "PASS", lf_result)
            entry.write_bytes(lf_entry.replace(b"\n", b"\r\n"))
            peer.write_bytes(lf_peer.replace(b"\n", b"\r\n"))
            shader.write_bytes(lf_shader.replace(b"\n", b"\r\n"))
            crlf_result = MODULE.compile_entry(root, OWNER, cache, env, "TEST_ONLY", 8)
            self.assertEqual(crlf_result["status"], "PASS", crlf_result)
            self.assertEqual(crlf_result["nodes"], lf_result["nodes"])
            self.assertEqual(crlf_result["source_fingerprints"], lf_result["source_fingerprints"])


if __name__ == "__main__":
    OWNED.mkdir(parents=True, exist_ok=True)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ProducerCases)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    artifact = {"schema_version":1,"producer_id":MODULE.PRODUCER,"mode":"offline_test_owned_grammar", "tests":result.testsRun,
                "failures":len(result.failures),"errors":len(result.errors),"status":"PASS" if result.wasSuccessful() else "FAIL",
                "native_execution":"NOT_RUN", "gpu":"NOT_RUN", "production_publication":"NOT_RUN"}
    (OWNED / "OFFLINE_TEST_RESULT.json").write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if result.wasSuccessful() else 1)
