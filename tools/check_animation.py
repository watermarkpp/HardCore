import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

with open(REPO / "assets/data/runtime/monster_animation_catalog.json", 'r', encoding='utf-8') as f:
    d = json.load(f)

monsters = d.get('monsters', [])
print('Monsters count:', len(monsters))

if monsters:
    print('First monster keys:', list(monsters[0].keys())[:10])
    print('First monster ID:', monsters[0].get('monsterId', 'N/A'))

# Check summary
summary = d.get('summary', {})
print('\nSummary:', summary)
