"""Extract only declared, ID-addressed primary item frames; preserve other art."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from PIL import Image
from vendor.extract_wil import read_library, decode_sprite

ROOT = Path(__file__).resolve().parents[1]

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def extract(item_ids: list[int], source_root: Path, check: bool = False) -> list[dict]:
    authority = json.loads((ROOT / "assets/data/item_runtime_authority_v1.json").read_text(encoding="utf-8"))
    policy = json.loads((ROOT / "assets/data/source_priority_policy.json").read_text(encoding="utf-8"))
    primary = [s for s in policy["lanes"]["client_assets"]["sources"] if s["tier"] == "primary" and s["eligible"]]
    if len(primary) != 1:
        raise ValueError("client_assets requires exactly one primary source")
    records = {int(row["itemId"]): row for row in authority["newItems"]}
    if len(set(item_ids)) != len(item_ids) or any(i not in records for i in item_ids):
        raise ValueError("target IDs must be unique, existing authority newItems")
    source_root = source_root.resolve(strict=True)
    libraries, images, receipts = {}, {}, []
    output_root = (ROOT / "assets/art/items/service").resolve()
    for item_id in item_ids:
        for field in ("inventoryIcon", "stateIcon", "groundIcon"):
            art = records[item_id]["art"][field]
            if art.get("distribution") != primary[0]["distribution"]:
                raise ValueError(f"{item_id}/{field}: undeclared primary client")
            relative = art["sourceLibrary"]
            prefix = "dev_art_sources/" + primary[0]["rootPrefix"] + "/"
            if not relative.startswith(prefix):
                raise ValueError(f"{item_id}/{field}: source outside declared primary")
            library_path = (source_root / relative.removeprefix("dev_art_sources/")).resolve(strict=True)
            if not library_path.is_relative_to(source_root):
                raise ValueError("source escaped source root")
            if library_path not in libraries:
                data, palette, offsets, info = read_library(library_path)
                wix = next(p for p in (library_path.with_suffix(".WIX"), library_path.with_suffix(".wix")) if p.exists())
                libraries[library_path] = (data, palette, offsets, {"wil_sha256": sha(library_path), "wix_sha256": sha(wix), **info})
            data, palette, offsets, info = libraries[library_path]
            index = int(art["sourceIndex"])
            if index < 0 or index >= len(offsets):
                raise ValueError("primary source frame missing")
            pixels, metadata = decode_sprite(data, offsets[index], palette)
            if not pixels.getchannel("A").getbbox():
                raise ValueError("primary source frame is empty")
            path = art["path"]
            if not path.startswith("res://assets/art/items/service/"):
                raise ValueError("target outside runtime service item art")
            target = (ROOT / path.removeprefix("res://")).resolve()
            if not target.is_relative_to(output_root):
                raise ValueError("target escaped item art root")
            before_hash = ""
            if target.exists():
                before_hash = sha(target)
                with Image.open(target) as existing:
                    if existing.size != pixels.size or existing.convert("RGBA").tobytes() != pixels.tobytes():
                        raise ValueError(f"refusing to overwrite existing differing art: {target}")
            elif check:
                raise ValueError(f"runtime art missing: {target}")
            previous = images.get(target)
            if previous is not None and previous.tobytes() != pixels.tobytes():
                raise ValueError("conflicting target frame declarations")
            images[target] = pixels
            receipts.append({"item_id": item_id, "field": field, "path": path, "source_library": relative,
                             "source_index": index, "source": info, "metadata": metadata, "before_sha256": before_hash})
    # Admission above checks the whole explicit target set before the first write.
    for target, pixels in images.items():
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            pixels.save(target)
    for row in receipts:
        row["after_sha256"] = sha(ROOT / row["path"].removeprefix("res://"))
        row["status"] = "PASS"
    return receipts

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--item-id", type=int, nargs="+", required=True)
    ap.add_argument("--source-root", type=Path, default=ROOT / "dev_art_sources")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--receipt", type=Path, required=True)
    args = ap.parse_args()
    rows = extract(args.item_id, args.source_root, args.check)
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps({"status": "PASS", "targets": args.item_id, "frames": rows}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"AUTHORITY_ITEM_ART_PASS target_items={len(args.item_id)} fields={len(rows)}")

if __name__ == "__main__":
    main()
