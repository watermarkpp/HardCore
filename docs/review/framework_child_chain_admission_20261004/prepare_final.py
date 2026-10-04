from pathlib import Path
import json

root = Path.cwd()
assert root == Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
parent_owned = root/'outputs/framework_v2/child_execution_20261004'
owned = root/'outputs/framework_v2/child_chain_admission_20261004'
groups = json.loads((parent_owned/'FINAL_TEST_GROUPS.json').read_text())
groups[0]['label'] = 'child_chain_admission_final_direct'
groups[1]['label'] = 'child_chain_admission_final_world'
groups[0]['tests'] += [
    'tests/framework/feature_child_chain_admission_test.tscn',
    'tests/framework/frame_budget_test.tscn',
    'tests/framework/frame_epoch_test.tscn',
    'tests/framework/budget_producer_admission_test.tscn',
]
assert sum(len(group['tests']) for group in groups) == 42
assert len({test for group in groups for test in group['tests']}) == 42
assert all((root/test).is_file() for group in groups for test in group['tests'])
(owned/'FINAL_TEST_GROUPS.json').write_text(json.dumps(groups, indent=2)+'\n')
(owned/'run_final_groups.py').write_text((parent_owned/'run_final_groups.py').read_text().replace('outputs/framework_v2/child_execution_20261004', 'outputs/framework_v2/child_chain_admission_20261004'))
review = (parent_owned/'prepare_review.py').read_text()
review = review.replace('outputs/framework_v2/child_execution_20261004', 'outputs/framework_v2/child_chain_admission_20261004')
review = review.replace('171bffbb69aa7d59b7f0ab30238e8032d67a6ad7', '1f6ca7a78e2163c3365bbcb38710018e6eee4dbf')
review = review.replace('framework_child_planner_20261004/SOURCE_MANIFEST.json', 'framework_child_execution_20261004/SOURCE_MANIFEST.json')
(owned/'prepare_review.py').write_text(review)
print(json.dumps({'groups': [(group['label'], len(group['tests'])) for group in groups]}))
