import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

with open(REPO / "assets/data/monster_behavior_profiles.json", 'r', encoding='utf-8') as f:
    d = json.load(f)

profiles = d.get('profiles', {})
print('Profiles type:', type(profiles))
print('Profiles count:', len(profiles))

if profiles:
    first_key = list(profiles.keys())[0]
    print(f'First profile key: {first_key}')
    print(f'First profile value type: {type(profiles[first_key])}')
    print(f'First profile value: {profiles[first_key]}')

# Check profileByMonsterId
pbm = d.get('profileByMonsterId', {})
print(f'\nprofileByMonsterId count: {len(pbm)}')
if pbm:
    print(f'Sample: {dict(list(pbm.items())[:5])}')
