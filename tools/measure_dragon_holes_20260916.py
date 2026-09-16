# Measure the dragon chassis art hollow features precisely.
from PIL import Image
import json
import sys
from collections import deque

SRC = r'assets/ui/gothic_hud/v3/runtime/bottom_chassis_v3_dragon.png'
img = Image.open(SRC).convert('RGBA')
w, h = img.size
px = img.load()
ALPHA_T = 200

def hole_component(seed, limit=400000):
    """BFS the transparent region from seed, return bbox + pixel count."""
    seen = set()
    q = deque([seed])
    seen.add(seed)
    minx = miny = 10**9
    maxx = maxy = -1
    while q:
        x, y = q.popleft()
        minx = min(minx, x); maxx = max(maxx, x)
        miny = min(miny, y); maxy = max(maxy, y)
        if len(seen) > limit:
            break
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx, ny = x+dx, y+dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen:
                if px[nx, ny][3] < ALPHA_T:
                    seen.add((nx, ny))
                    q.append((nx, ny))
    return {'bbox': [minx, miny, maxx, maxy], 'w': maxx-minx+1, 'h': maxy-miny+1, 'pixels': len(seen)}

report = {}
# Orb holes: seed near registry centers
for name, (cx, cy) in (('health_orb', (532, 410)), ('mana_orb', (1640, 410))):
    seed = (int(cx), int(cy))
    if px[seed[0], seed[1]][3] >= ALPHA_T:
        # nudge until transparent
        found = None
        for r in range(1, 40):
            for dx in range(-r, r+1):
                for dy in (-r, r):
                    p = (seed[0]+dx, seed[1]+dy)
                    if 0 <= p[0] < w and 0 <= p[1] < h and px[p[0], p[1]][3] < ALPHA_T:
                        found = p; break
                if found: break
            if found: break
        seed = found
    report[name] = hole_component(seed)

# Slot holes: seeds from registry centers (already source pixels)
for i, (cx, cy) in enumerate(((785.0, 412.5), (981.0, 412.5), (1190.5, 412.5), (1388.0, 412.5))):
    sx, sy = int(cx), int(cy)
    seed = (sx, sy)
    if px[sx, sy][3] >= ALPHA_T:
        found = None
        for r in range(1, 30):
            for dx in range(-r, r+1):
                for dy in (-r, r):
                    p = (sx+dx, sy+dy)
                    if 0 <= p[0] < w and 0 <= p[1] < h and px[p[0], p[1]][3] < ALPHA_T:
                        found = p; break
                if found: break
            if found: break
        seed = found
    report['slot_%d' % (i+1)] = hole_component(seed)

# XP slot: seed center of measured rect (678,563,815,29)
sx, sy = 678 + 815 // 2, 563 + 29 // 2
report['xp_slot'] = hole_component((sx, sy))

# Opacity band around XP slot: check rows above/below for opaque coverage
x0, y0, x1, y1 = report['xp_slot']['bbox']
band = {}
for dy in (-14, -10, -6, -3, 3, 6, 10, 14):
    y = y0 + (0 if dy < 0 else y1 - y0) + dy
    opaque = sum(1 for x in range(max(0, x0-60), min(w, x1+60)) if px[x, y][3] >= ALPHA_T)
    total = min(w, x1+60) - max(0, x0-60)
    band['row_offset_%+d' % dy] = {'y': y, 'opaque_ratio': round(opaque / max(1, total), 3)}
report['xp_surrounding_opacity'] = band

# Opacity ring around orb hole: sample ring at radius +2..+10 outside bbox
ob = report['health_orb']['bbox']
ring = {}
for pad in (2, 4, 6, 8, 12):
    cx, cy = (ob[0]+ob[2])//2, (ob[1]+ob[3])//2
    rx = (ob[2]-ob[0])//2 + pad
    ry = (ob[3]-ob[1])//2 + pad
    total = opaque = 0
    import math
    for a in range(0, 360, 3):
        x = int(cx + rx * math.cos(math.radians(a)))
        y = int(cy + ry * math.sin(math.radians(a)))
        if 0 <= x < w and 0 <= y < h:
            total += 1
            if px[x, y][3] >= ALPHA_T:
                opaque += 1
    ring['pad_%d' % pad] = round(opaque / max(1, total), 3)
report['orb_surrounding_opacity'] = ring

print(json.dumps(report, indent=1))
