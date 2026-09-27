"""Verify preserved native outcomes; earlier failed attempts remain failures."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
expected = {
    "scoped_sampler_catalog_55f_20260928_0547": (3, 2, 1),
    "scoped_sampler_warehouse_red_55f_20260928_0548": (2, 1, 1),
    "warehouse_receipt_red_55f_20260928_0550": (1, 0, 1),
    "warehouse_receipt_green_55f_20260928_0551": (1, 1, 0),
    "warehouse_receipt_regression_55f_20260928_0552": (9, 9, 0),
}
raw = []
rows = []
for name, counts in expected.items():
    root = ROOT / name
    completion = read(root / "completion.json")
    runners = list((root / "runner").glob("runner_results_*.json"))
    assert len(runners) == 1, name
    result = read(runners[0])
    assert (result["total"], result["passed"], result["failed"]) == counts, name
    assert completion["exit_code"] == (1 if counts[2] else 0), name
    assert len({r["test_path"] for r in result["results"]}) == counts[0], name
    for row in result["results"]:
        if row["result"] == "PASS":
            assert row["pass_marker_found"] and row["process_exited"] and row["effective_exit_code"] == 0
            assert not row["timeout"] and not row["reason"]
            assert row["stdout_failure_count"] + row["stderr_failure_count"] + row["engine_log_failure_count"] == 0
        for suffix in ("stdout.log", "stderr.log", "godot.log"):
            path = root / "runner" / (row["test_name"] + "." + suffix)
            data = path.read_bytes()
            raw.append({"path": path.relative_to(ROOT).as_posix(), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    if name == "warehouse_receipt_red_55f_20260928_0550":
        assert result["engine_log_errors"] == 0 and result["results"][0]["process_exited"]
        assert result["results"][0]["effective_exit_code"] == 1 and not result["results"][0]["timeout"]
    rows.append({"directory": name, "total": counts[0], "passed": counts[1], "failed": counts[2], "engine_log_errors": result["engine_log_errors"]})
red = read(ROOT / "warehouse_receipt_red_55f_20260928_0550/warehouse.json")
green = read(ROOT / "warehouse_receipt_regression_55f_20260928_0552/warehouse.json")
assert len(red["observations"]) == len(green["observations"]) == 4
assert len(red["failures"]) == 6 and not green["failures"]
assert {r["label"] for r in red["observations"]} == {r["label"] for r in green["observations"]}
for row in green["observations"]:
    assert row["result"]["success"] and row["receipt"]["success"] and row["gold"] == row["disk_gold"] == 17
    assert row["inventory_ids"] == row["disk_inventory_ids"] and row["warehouse_ids"] == row["disk_warehouse_ids"]
    assert len(row["inventory_ids"]) + len(row["warehouse_ids"]) == 1
result = {"status": "PASS", "rows": rows, "raw": raw,
          "scope": "Scoped native outcomes and real warehouse RED/GREEN only; whole-project and performance acceptance remain separate."}
output = ROOT / "scoped_closure_receipt.json"
assert not output.exists(), "refuse existing verdict"
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: v for k, v in result.items() if k != "raw"}))
