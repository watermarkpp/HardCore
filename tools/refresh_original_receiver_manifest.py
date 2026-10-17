"""Refresh one reviewed instrumented Main receiver from its actual GDScript AST.
Does not instrument code, alter the method set, or accept unreviewed source drift.
"""
import argparse, hashlib, json, re, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "outputs/v115_multicore/actor_runtime_ports_20261014/parser_runtime"))
from gdtoolkit.parser import parser
sha = lambda data: hashlib.sha256(data).hexdigest()
p = argparse.ArgumentParser()
p.add_argument("--path", required=True)
p.add_argument("--reviewed-sha256", required=True)
p.add_argument("--manifest-before-sha256", required=True)
p.add_argument("--receipt", required=True)
p.add_argument("--reviewed-async-contract", type=Path)
a = p.parse_args()
manifest = root / "scripts/gameplay/source/main_original_receiver_manifest.json"
assert sha(manifest.read_bytes()) == a.manifest_before_sha256, "manifest changed"
d = json.loads(manifest.read_text(encoding="utf-8-sig"))
assert a.path in d and a.path.startswith("res://scripts/") and ".." not in a.path
source = root / a.path.removeprefix("res://")
b = source.read_bytes()
assert sha(b) == a.reviewed_sha256, "reviewed receiver changed"
s = b.decode("utf-8-sig").replace("\r\n", "\n")
tree = parser.parse(s, gather_metadata=True)
functions = {str(n.children[0].children[0]): n for n in tree.children if getattr(n, "data", None) == "func_def"}
lines = s.splitlines(True)
off = [0]
for line in lines: off.append(off[-1] + len(line))
before = d[a.path]
async_review = json.loads(a.reviewed_async_contract.read_text(encoding="utf-8-sig")) if a.reviewed_async_contract else None
if async_review:
    assert async_review["path"] == a.path and async_review["before_script_sha256"] == before["script_sha256"] and async_review["after_script_sha256"] == sha(b), "async review source binding changed"
    assert isinstance(async_review["reason"], str) and async_review["reason"].strip()
    assert set(async_review["methods"]).issubset({m["method"] for m in before["methods"]}), "unknown reviewed async method"
row = json.loads(json.dumps(before))
changes = []
async_changes = []
for m in row["methods"]:
    assert m["method"] in functions and m["retained_method"] in functions, m["method"]
    wrapper = functions[m["method"]]
    target = functions[m["retained_method"]]
    actual_wrapper = s[off[wrapper.meta.line - 1]:off[min(wrapper.meta.end_line - 1, len(off) - 1)]]
    assert m["retained_method"] + "(" in actual_wrapper
    assert actual_wrapper.count('_original_main_callback_ledger["' + m["method"] + '"]') >= 2
    body = s[off[target.children[1].meta.line - 1]:off[min(target.meta.end_line - 1, len(off) - 1)]]
    current_sha = sha(body.encode())
    if current_sha != m["body_sha256"]: changes.append(m["method"])
    m["source_line"] = wrapper.meta.line
    m["body_sha256"] = current_sha
    actual_async = bool(re.search(r"\bawait\s+", body))
    if actual_async != m["await"]:
        assert async_review and m["method"] in async_review["methods"], "async contract changed without exact reviewed binding: " + m["method"]
        reviewed = async_review["methods"][m["method"]]
        assert reviewed == {"before": m["await"], "after": actual_async}, "async review preimage differs"
        assert re.search(r"\bawait\s+" + re.escape(m["retained_method"]) + r"\(", actual_wrapper), "async callback wrapper must retain its original ledger until actual continuation finishes"
        async_changes.append(m["method"])
        m["await"] = actual_async
row["script_sha256"] = sha(b)
d[a.path] = row
for path, item in d.items():
    assert sha((root / path.removeprefix("res://")).read_bytes()) == item["script_sha256"], "unrelated receiver drift: " + path
manifest.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
assert not async_review or set(async_changes) == set(async_review["methods"]), "async review contains unused changes"
receipt = {"status":"SOURCE_REFRESH_ONLY", "path":a.path, "before":before["script_sha256"], "after":sha(b), "manifest_before":a.manifest_before_sha256, "manifest_after":sha(manifest.read_bytes()), "changed_retained_bodies":changes, "reviewed_async_changes":async_changes, "async_review_sha256":sha(a.reviewed_async_contract.read_bytes()) if async_review else None, "method_set_preserved":True, "runtime":"NOT_RUN"}
Path(a.receipt).write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(receipt, ensure_ascii=False))
