from __future__ import annotations
import json
from pathlib import Path
from PIL import Image
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/data/map_editor/asset_catalog.json"

def image_template(path: Path) -> dict:
    with Image.open(path) as image:
        width, height = image.size
    rel = path.relative_to(ROOT).as_posix()
    name = path.stem
    template_id = rel.rsplit(".", 1)[0].replace("/", "__")
    layer = "base_ground" if "ground" in name else ("foreground" if any(x in name for x in ("canopy", "roof")) else "obstacle")
    return {"id": template_id, "name": name, "category": path.parent.name, "image": rel, "width": width, "height": height,
            "pivot": {"x": width // 2, "y": max(0, height - 4)}, "footprint": {"gridWidth": 1, "gridHeight": 1},
            "blockMove": layer == "obstacle", "blockProjectile": False, "occlusion": layer == "foreground", "layer": layer,
            "metadataSource": "generated_default", "editable": True}

def image_templates(path: Path) -> list[dict]:
    base = image_template(path)
    if "gothic_bich_camp/sprites" in base["image"]:
        with Image.open(path).convert("RGBA") as image:
            alpha = np.array(image.getchannel("A"))
            mask = (alpha > 12).astype(np.uint8)
            joined = cv2.dilate(mask, np.ones((7, 7), np.uint8), iterations=1)
            count, labels, stats, _ = cv2.connectedComponentsWithStats(joined, 8)
            groups = []
            for label in range(1, count):
                x, y, width, height, _ = stats[label]
                real_pixels = int(mask[y:y+height, x:x+width].sum())
                if width >= 10 and height >= 10 and real_pixels >= 80:
                    ys, xs = np.where(mask[y:y+height, x:x+width] > 0)
                    groups.append(tuple(int(value) for value in (x + int(xs.min()), y + int(ys.min()), x + int(xs.max()) + 1, y + int(ys.max()) + 1)))
            if len(groups) > 1:
                result = []
                for index, (left, top, right, bottom) in enumerate(sorted(groups)):
                    result.append({**base, "id": f"{base['id']}__part_{index}", "name": f"{base['name']} 部件 {index + 1}",
                                   "region": {"x": left, "y": top, "width": right-left, "height": bottom-top},
                                   "width": right-left, "height": bottom-top, "pivot": {"x": (right-left)//2, "y": bottom-top}})
                if len(result) > 1: return result
    if base["height"] in (24, 32) and base["width"] >= 64 and base["width"] % 64 == 0:
        return [{**base, "id": f"{base['id']}__tile_{index}", "name": f"{base['name']} {index + 1}",
                 "region": {"x": index * 64, "y": 0, "width": 64, "height": base["height"]},
                 "width": 64, "layer": "base_ground", "blockMove": False}
                for index in range(base["width"] // 64)]
    if base["height"] == 128 and base["width"] >= 96 and base["width"] % 96 == 0:
        return [{**base, "id": f"{base['id']}__prop_{index}", "name": f"{base['name']} 物件 {index + 1}",
                 "region": {"x": index * 96, "y": 0, "width": 96, "height": 128},
                 "width": 96, "height": 128, "pivot": {"x": 48, "y": 118}, "layer": "obstacle"}
                for index in range(base["width"] // 96)]
    return [base]

def named_records(path: Path, key: str) -> list[dict]:
    if not path.exists(): return []
    data = json.loads(path.read_text(encoding="utf-8"))
    records = data.get(key, data if isinstance(data, list) else [])
    flat: list[dict] = []
    def visit(value):
        if isinstance(value, list):
            for child in value: visit(child)
        elif isinstance(value, dict):
            if value.get("name"): flat.append(value)
            for child_key in ("records", "npcs"): 
                if child_key in value: visit(value[child_key])
    visit(records)
    return [{"id": str(x.get("id", x.get("monsterId", x.get("name", "")))), "name": x.get("name", ""), "template": x} for x in flat]

def main() -> None:
    roots = [ROOT / "assets/presentation", ROOT / "assets/art/maps"]
    images = sorted({p for root in roots if root.exists() for p in root.rglob("*.png")})
    catalog = {"schemaVersion": 1, "generated": True, "objects": [item for p in images for item in image_templates(p)],
               "monsters": named_records(ROOT / "assets/data/vanilla_176/monsters.json", "records"),
               "npcs": named_records(ROOT / "assets/data/vanilla_176/npcs.json", "records")}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"MAP_EDITOR_CATALOG_PASS objects={len(catalog['objects'])} monsters={len(catalog['monsters'])} npcs={len(catalog['npcs'])}")

if __name__ == "__main__": main()
