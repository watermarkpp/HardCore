from pathlib import Path
import json
r=Path.cwd();prior=r/'outputs/framework_v2/child_planner_20261004';o=r/'outputs/framework_v2/child_execution_20261004'
g=json.loads((prior/'FINAL_TEST_GROUPS.json').read_text())
g[0]['label']='child_execution_final_direct'
g[0]['tests']+=['tests/framework/feature_child_execution_test.tscn','tests/framework/feature_producing_death_reentry_test.tscn','tests/framework/feature_resource_accepted_lifetime_test.tscn','tests/framework/feature_lifesteal_runtime_test.tscn']
g[1]['label']='child_execution_final_world'
assert sum(len(x['tests']) for x in g)==38
(o/'FINAL_TEST_GROUPS.json').write_text(json.dumps(g,indent=2)+'\n')
(o/'run_final_groups.py').write_text((prior/'run_final_groups.py').read_text().replace('outputs/framework_v2/child_planner_20261004','outputs/framework_v2/child_execution_20261004'))
source=(prior/'prepare_review.py').read_text().replace('child_planner_20261004','child_execution_20261004').replace('5b8288f773d0659b2d1e45538f93fc9a2556dfba','171bffbb69aa7d59b7f0ab30238e8032d67a6ad7').replace('framework_child_commit_20261004/SOURCE_MANIFEST.json','framework_child_planner_20261004/SOURCE_MANIFEST.json')
(o/'prepare_review.py').write_text(source)
print(json.dumps({'groups':[(x['label'],len(x['tests'])) for x in g]}))
