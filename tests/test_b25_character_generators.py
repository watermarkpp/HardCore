"""B25 character-generator source-domain regressions."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_primary_weapon_mapping_contracts_match_formal_records() -> None:
    module = load("warrior_b25", "tools/build_warrior_wear_assets.py")
    compatibility = json.loads(
        (ROOT / "assets/data/equipment_primary_weapon_compatibility.json").read_text(
            encoding="utf-8"
        )
    )
    visual = json.loads(
        (ROOT / "assets/data/equipment_visual_catalog.json").read_text(
            encoding="utf-8"
        )
    )
    by_name = {
        str(value["itemName"]): value
        for value in compatibility["itemsById"].values()
    }
    mappings = visual["runtimeMappings"]
    expected = {"炼狱": 22, "屠龙": 52, "命运之刃": 58}
    for name, feature in expected.items():
        module.validate_user_confirmed_primary_mapping(
            name,
            by_name[name],
            mappings[name],
            feature,
        )

    wrong_type = dict(by_name["炼狱"])
    wrong_type["mappingType"] = (
        "user_confirmed_semantic_primary_weapon_feature"
    )
    try:
        module.validate_user_confirmed_primary_mapping(
            "炼狱", wrong_type, mappings["炼狱"], 22
        )
    except ValueError as error:
        assert "炼狱" in str(error)
    else:
        raise AssertionError("炼狱 accepted the semantic mapping contract")

    unconfirmed = dict(by_name["炼狱"])
    unconfirmed["userAtlasReviewEvidence"] = {"confirmed": False}
    try:
        module.validate_user_confirmed_primary_mapping(
            "炼狱", unconfirmed, mappings["炼狱"], 22
        )
    except ValueError as error:
        assert "炼狱" in str(error)
    else:
        raise AssertionError("炼狱 accepted an unconfirmed atlas mapping")

    wrong_feature = dict(by_name["屠龙"])
    wrong_feature["maleFeature"] = 51
    try:
        module.validate_user_confirmed_primary_mapping(
            "屠龙", wrong_feature, mappings["屠龙"], 52
        )
    except ValueError as error:
        assert "屠龙" in str(error)
    else:
        raise AssertionError("屠龙 accepted the wrong feature")


def test_original_paper_doll_rejects_final_calibration_domain(tmp_path, monkeypatch) -> None:
    module = load(
        "paper_doll_b25", "tools/build_original_client_paper_doll_stage.py"
    )
    catalog = json.loads(
        (ROOT / "assets/data/equipment_visual_catalog.json").read_text(
            encoding="utf-8"
        )
    )
    selected = module.selected_male_items(catalog)
    helmet = next(row for row in selected if row[0] == 146)
    try:
        module.validate_original_source_mapping(helmet[0], helmet[2])
    except ValueError as error:
        assert "user_final_helmet_calibration" in str(error)
    else:
        raise AssertionError("final calibration record crossed the WIL boundary")

    exact = {
        "status": "exact_client_record",
        "source": "stateitem.wil",
        "sourceIndex": 146,
        "rawDrawOffset": [77, 42],
    }
    module.validate_original_source_mapping(146, exact)

    fractional = dict(exact)
    fractional["rawDrawOffset"] = [77.262, 42.262]
    try:
        module.validate_original_source_mapping(146, fractional)
    except ValueError as error:
        assert "integer rawDrawOffset" in str(error)
    else:
        raise AssertionError("fractional calibration offset accepted as WIL Hot")

    # Exercise the real main entry with existing formal JSON and empty scratch
    # WIL paths. It must fail at the source-domain gate before decoding or any
    # output write; no decode success is mocked here.
    prguse = tmp_path / "Prguse.wil"
    stateitem = tmp_path / "StateItem.wil"
    prguse.write_bytes(b"")
    stateitem.write_bytes(b"")
    output = tmp_path / "output"
    monkeypatch.setattr(module, "PRGUSE", prguse)
    monkeypatch.setattr(module, "STATE_ITEM", stateitem)
    monkeypatch.setattr(module, "OUTPUT", output)
    monkeypatch.setattr(module, "STATE_OUTPUT", output / "stateitem")
    monkeypatch.setattr(module, "MANIFEST", tmp_path / "manifest.json")
    try:
        module.main()
    except ValueError as error:
        assert "user_final_helmet_calibration" in str(error)
    else:
        raise AssertionError("main crossed final calibration into WIL decode")
    assert not output.exists()
    assert not (tmp_path / "manifest.json").exists()
