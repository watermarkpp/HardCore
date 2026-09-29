"""Read alpha extents; do not rewrite artwork or generate replacement textures."""
import json
from pathlib import Path
import re
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEST = Path(__file__).parent / 'evidence/icon_pixel_footprints.json'

def extent(resource):
    path = ROOT / resource.removeprefix('res://')
    if path.suffix == '.tres':
        text = path.read_text(encoding='utf-8-sig')
        source = re.search(r'path="(res://[^\"]+)"', text).group(1)
        rect = [int(float(n)) for n in re.search(r'region = Rect2\(([^)]+)\)', text).group(1).split(',')]
        x, y, w, h = rect
        with Image.open(ROOT / source.removeprefix('res://')) as image:
            alpha = image.convert('RGBA').getchannel('A').crop((x, y, x+w, y+h))
    else:
        with Image.open(path) as image:
            alpha = image.convert('RGBA').getchannel('A')
    box = alpha.getbbox()
    assert box, resource
    return alpha.size, (box[2]-box[0], box[3]-box[1])

fragment = json.loads((ROOT / 'assets/data/ancient_relic_fragment_v1.json').read_text(encoding='utf-8-sig'))
relics = json.loads((ROOT / 'assets/data/relic_synthesis_v1.json').read_text(encoding='utf-8-sig'))['items']
rows = []
for item in [fragment, *relics]:
    row = {'item_id': item['item_id'], 'name': item['name']}
    for field, maximum in [('inventory_icon', 32), ('ground_icon', 36)]:
        canvas, visible = extent(item[field])
        scale = maximum / max(canvas)
        shown = [round(n * scale, 3) for n in visible]
        assert 0 < min(shown) <= max(shown) <= maximum
        assert max(shown) >= maximum * .75, 'transparent padding shrinks the visible art'
        row[field] = {'canvas': canvas, 'alpha_bounds': visible, 'visible_display_pixels': shown}
    rows.append(row)
DEST.write_text(json.dumps({'result': 'PASS', 'items': rows}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('ICON_PIXEL_FOOTPRINTS_PASS items=7 assets_modified=0')
