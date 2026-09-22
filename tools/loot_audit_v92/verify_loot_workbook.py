"""Read-only OOXML verification of the finished loot workbook and montage creation."""
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile
import xml.etree.ElementTree as ET

NS = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}


def verify(root):
    exact = json.loads((root / "exact_ground_probabilities.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "workbook_manifest.json").read_text(encoding="utf-8"))
    book = root / manifest.get("outputFilename", "HardCore_当前地图怪物真实掉率_20260922.xlsx")
    assert exact["source_sha256"] == manifest["sourceSha256"]
    source = Path(exact["source_path"])
    assert hashlib.sha256(source.read_bytes()).hexdigest() == exact["source_sha256"]
    with ZipFile(book) as archive:
        wb = ET.fromstring(archive.read("xl/workbook.xml"))
        relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        targets = {node.attrib["Id"]: node.attrib["Target"] for node in relationships}
        shared = []
        if "xl/sharedStrings.xml" in archive.namelist():
            for si in ET.fromstring(archive.read("xl/sharedStrings.xml")):
                shared.append("".join(si.itertext()))
        styles = ET.fromstring(archive.read("xl/styles.xml"))
        xfs = styles.find("s:cellXfs", NS)
        formats = {int(n.attrib["numFmtId"]): n.attrib["formatCode"] for n in styles.findall("s:numFmts/s:numFmt", NS)}
        formats[49] = "@"
        cells_by_sheet = {}
        sheets = wb.findall("s:sheets/s:sheet", NS)
        assert [s.attrib["name"] for s in sheets] == [s["name"] for s in manifest["sheets"]]
        assert len(sheets) == 121
        def value(cell):
            kind = cell.attrib.get("t", "n")
            v = cell.find("s:v", NS)
            text = "" if v is None else v.text or ""
            if kind == "s":
                return shared[int(text)]
            if kind == "inlineStr":
                return "".join(cell.find("s:is", NS).itertext())
            return text
        for sheet in sheets:
            target = targets[sheet.attrib[f"{{{NS['r']}}}id"]]
            entry = target.lstrip("/") if target.startswith("/") else "xl/" + target
            document = ET.fromstring(archive.read(entry))
            cells = {cell.attrib["r"]: cell for cell in document.findall("s:sheetData/s:row/s:c", NS)}
            assert not any(c.attrib.get("t") == "e" for c in cells.values()), sheet.attrib["name"]
            assert document.find("s:sheetViews/s:sheetView/s:pane", NS) is not None
            cells_by_sheet[sheet.attrib["name"]] = cells
        for record in manifest["probabilityCells"]:
            cell = cells_by_sheet[record["sheet"]][record["address"]]
            assert cell.attrib.get("t") in ("s", "inlineStr", "str"), record
            format_id = int(xfs[int(cell.attrib.get("s", 0))].attrib.get("numFmtId", 0))
            assert formats.get(format_id) == "@", (record, format_id)
            actual = value(cell)
            assert actual == record["value"] and re.fullmatch(r"\d+/[1-9]\d*", actual), record
            assert 0 <= Fraction(actual) <= 1, record
        lookup = {m["monster_id"]: m for m in exact["monsters"]}
        assert {s["monsterId"] for s in manifest["sheets"] if s["monsterId"] is not None} == set(lookup)
        overview = cells_by_sheet["总览"]
        assert value(overview["D3"]) == str(exact["map_count"])
        assert value(overview["F3"]) == str(exact["spawn_points"])
        assert value(overview["B4"]) == str(exact["summary"]["monster_count"])
        assert value(overview["D4"]) == str(exact["slot_count"])
        assert value(overview["F4"]) == str(exact["summary"]["output_rows"])
        if manifest.get("armorRevision"):
            assert "衣服单槽修正版" in value(overview["A2"])
            assert "保留单槽原概率" in value(overview["A11"])
        for i, m in enumerate(exact["monsters"]):
            expected = [str(m["monster_id"]), m["name"], m["classification_label"], str(m["spawn_points"]), str(len(m["slots"])), manifest["sheets"][i + 1]["name"]]
            assert [value(overview[f"{col}{i + 15}"]) for col in "ABCDEF"] == expected
        for entry in manifest["sheets"][1:]:
            m = lookup[entry["monsterId"]]
            cells = cells_by_sheet[entry["name"]]
            assert value(cells["A2"]) == f"{m['name']}（{m['monster_id']}）"
            assert value(cells["A3"]) == f"正式分类：{m['classification_label']}"
            for i, r in enumerate(m["outputs"]):
                row = entry["mainStart"] + i
                expected = [r["name"], str(r["item_id"]), r["actual_probability"], str(r["slot_count"]), r["slot_probabilities"], r["groups"]]
                assert [value(cells[f"{col}{row}"]) for col in "ABCDEF"] == expected
            for i, r in enumerate(m["slots"]):
                row = entry["detailStart"] + i
                expected = [r["slot_uid"], str(r["item_id"]), r["probability"], "保护" if r["protected"] else "常规", str(r["priority"]), r["name"]]
                assert [value(cells[f"{col}{row}"]) for col in "ABCDEF"] == expected
            for i, r in enumerate(m["maps"]):
                row = entry["mapsStart"] + i
                assert value(cells[f"A{row}"]) == str(r["map_id"])
                assert value(cells[f"C{row}"]) == r["name"]
            if entry["empty"]:
                assert value(cells[f"A{entry['mainStart']}"]) == "正式空掉落表"
    assert len(manifest["renders"]) == 121
    for render in manifest["renders"]:
        assert (root / "previews" / render["file"]).is_file()
    report = {"status": "PASS", "xlsx": str(book.resolve()), "size_bytes": book.stat().st_size,
              "sha256": hashlib.sha256(book.read_bytes()).hexdigest(), "source_sha256": exact["source_sha256"],
              "sheets": 121, "monster_sheets": 120, "probability_text_cells": len(manifest["probabilityCells"]),
              "probability_types": "All are OOXML text and Excel number format @; zero date/numeric probability cells",
              "probability_cells_by_kind": dict(Counter(r["kind"] for r in manifest["probabilityCells"])),
              "full_cell_comparison": "All output, slot, map, classification, and empty-table rows match the exact snapshot",
              "render_count": len(manifest["renders"]), "math_tests": exact["math_tests"], "summary": exact["summary"]}
    (root / "verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


def montage(root):
    from PIL import Image, ImageOps, ImageDraw, ImageFont
    manifest = json.loads((root / "workbook_manifest.json").read_text(encoding="utf-8"))
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
    renders = manifest["renders"]
    for offset in range(0, len(renders), 12):
        chunk = renders[offset:offset + 12]
        tiles = []
        for entry in chunk:
            img = Image.open(root / "previews" / entry["file"]).convert("RGB")
            img.thumbnail((800, 380))
            tile = Image.new("RGB", (810, 414), "#DFE5EA")
            ImageDraw.Draw(tile).text((8, 5), entry["sheet"], fill="#152836", font=font)
            tile.paste(img, (5, 30))
            tiles.append(tile)
        canvas = Image.new("RGB", (1620, 414 * ((len(tiles) + 1) // 2)), "white")
        for i, tile in enumerate(tiles):
            canvas.paste(tile, (810 * (i % 2), 414 * (i // 2)))
        canvas.save(root / "previews" / f"montage_{offset // 12:02}.png")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("outputs/repair_v92/excel"))
    args = parser.parse_args()
    verify(args.root)
    montage(args.root)
