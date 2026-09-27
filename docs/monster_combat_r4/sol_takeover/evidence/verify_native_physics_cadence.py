"""Check actual sample tick identities, separate from the historical >=600 contract."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("matrix", type=Path)
args = parser.parse_args()
root = args.matrix.resolve()
read = lambda path: json.loads(path.read_text(encoding="utf-8-sig"))
runs = read(root / "runs.json")
rows = []
for run in runs:
    if run["exit_code"] != 0:
        continue
    sample = read(root / run["label"] / "load.json")
    ticks = [int(frame["tick"]) for frame in sample["frames"]]
    gaps = [{"index": i, "previous_tick": ticks[i - 1], "tick": ticks[i]}
            for i in range(1, len(ticks)) if ticks[i] != ticks[i - 1] + 1]
    valid = len(ticks) == 600 and not gaps and ticks[-1] - ticks[0] + 1 == 600
    rows.append(dict(label=run["label"], source_head=sample["source_head"],
                     status="PASS" if valid else "FAIL", samples=len(ticks),
                     actual_physics_tick_span=ticks[-1] - ticks[0] + 1,
                     skipped_physics_tick_count=sum(max(0, item["tick"] - item["previous_tick"] - 1) for item in gaps),
                     nonconsecutive_boundaries=gaps))
result = dict(status="PASS" if rows and all(row["status"] == "PASS" for row in rows) else "FAIL",
              scope="Consecutive native physics identities; historical collection and performance verdicts remain unchanged.",
              actual_samples=len(rows), failures=sum(row["status"] == "FAIL" for row in rows), rows=rows)
output = root / "native_physics_cadence_check.json"
if output.exists():
    raise SystemExit("refuse to overwrite existing cadence evidence")
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: value for key, value in result.items() if key != "rows"}, ensure_ascii=False))
raise SystemExit(0 if result["status"] == "PASS" else 1)
