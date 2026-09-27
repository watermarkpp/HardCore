"""Check real committed/materialized terminal receipts; keep bounded-ledger scope explicit."""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "overhead_frame_pairs_aoe30"
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
execution = read(root / "exact_execution_check.json")
assert execution["status"] == "PASS"
rows = []
for run in read(root / "runs.json"):
    sample = read(root / run["label"] / "load.json")
    keys = {d["fixed_key"] for d in sample["random_inputs"]["death_identity_inputs"]}
    queue = sample["death_queue_at_end"]
    terminals = queue["terminal"]
    visible_nodes = 0
    for terminal in terminals:
        assert terminal["death_key"] in keys
        assert terminal["state"] == "COMMITTED"
        assert terminal["transaction_result"]["success"] is True
        assert terminal["drop_plan"]["materialized"] is True
        count = terminal["materialized_node_count"]
        assert isinstance(count, int) and count >= 0
        assert count == len(terminal["drop_plan"]["requests"])
        visible_nodes += count
    assert visible_nodes > 0
    assert sample["native_loot_nodes_created"] >= visible_nodes
    assert len(terminals) <= queue["terminal_ledger_limit"]
    rows.append(dict(label=run["label"], source_head=sample["source_head"],
                     terminal_receipts=len(terminals), materialized_nodes_in_retained_receipts=visible_nodes,
                     native_nodes_created=sample["native_loot_nodes_created"],
                     terminal_count=queue["terminal_count"], pending_at_end=len(queue["pending"])))
result = dict(status="PASS", runs=rows,
              scope="Real terminal transaction acknowledgement and native materialization verified. The terminal ledger is bounded; retained receipts are a subset, not all historical deaths. Pending work at sampling end is retained and is not declared settled.")
(root / "native_receipt_check.json").write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=False))
