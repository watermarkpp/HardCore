"""Single-skill metadata synchronization; does not rebuild or touch pixels."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = json.loads((ROOT / 'assets/data/vanilla_176/skills_source_of_truth_v1.json').read_text(encoding='utf-8-sig'))
geometry = next(r['geometry'] for r in source['skills'] if r['skill_id'] == 'wizard.fire_wall')
path = ROOT / 'assets/data/caster_skill_visuals.json'
data = json.loads(path.read_text(encoding='utf-8-sig'))
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
if args.check:
    assert data['skillCoverage']['wizard.fire_wall']['skills_contract']['geometry'] == geometry
else:
    data['skillCoverage']['wizard.fire_wall']['skills_contract']['geometry'] = geometry
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
print('FIRE_WALL_VISUAL_GEOMETRY_SYNC_PASS')
