"""B26 map design catalog preservation and identity-contract checks."""
from __future__ import annotations

import importlib.util
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "assets/data/map_design"


def load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_current_catalog_rejects_missing_formal_template_coverage() -> None:
    module = load("map_validator_b26", "tools/map_design/validate_map_design_catalog.py")
    # The current authoring snapshot has five catalog entries without a
    # corresponding blank-template identity; fail closed until that source
    # gap is resolved by the formal authoring chain.
    assert module.main() == 1


def _run(module, capsys):
    result = module.main()
    report = capsys.readouterr().out
    return result, report


def test_validator_rejects_unknown_and_duplicate_ids(tmp_path, monkeypatch, capsys) -> None:
    module, scratch = _scratch_validator(tmp_path, monkeypatch)

    catalog_path = scratch / "map_design_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    catalog["maps"][0]["map_id"] = "unknown_map_id"
    catalog_path.write_text(json.dumps(catalog), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "unknown canonical/authoring map_id" in report

    module, scratch = _scratch_validator(tmp_path / "duplicate_case", monkeypatch)
    catalog_path = scratch / "map_design_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    catalog["maps"][1]["map_id"] = catalog["maps"][0]["map_id"]
    catalog_path.write_text(json.dumps(catalog), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "duplicate/missing map_id" in report

    module, scratch = _scratch_validator(tmp_path / "template_identity_case", monkeypatch)
    blank_path = scratch / "map_blank_templates.json"
    blank = json.loads(blank_path.read_text(encoding="utf-8"))
    blank["templates"][0]["map_id"] = "not_a_legacy_map"
    blank_path.write_text(json.dumps(blank), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "unknown legacy/canonical map_id" in report


def test_builder_refuses_to_overwrite_unmigrated_templates(tmp_path, monkeypatch) -> None:
    module = load("map_builder_b26", "tools/map_design/build_map_design_catalog.py")
    scratch = tmp_path / "map_design"
    scratch.mkdir(parents=True)
    (scratch / "map_size_templates.json").write_text(
        json.dumps({
            "templates": [{
                "id": "outdoor_province",
                "default_size": [10, 10],
                "max_size": [100, 100],
            }],
            "coordinate_system": [],
        }),
        encoding="utf-8",
    )
    (scratch / "map_scale_overrides.json").write_text(
        json.dumps({
            "scale_policy": {"factor": 1, "rounding": "half_up"},
            "overrides": [{
                "map_id": "canonical_test",
                "runtime_map_id": 1,
                "name": "test",
                "map_type": "outdoor_province",
                "design_size": [10, 10],
                "strategy": "preserve_function",
            }],
        }),
        encoding="utf-8",
    )
    (scratch / "source_map_audit.json").write_text(
        json.dumps({"records": []}), encoding="utf-8"
    )
    blank_path = scratch / "map_blank_templates.json"
    original_blank = {
        "templates": [{"template_id": "blank.legacy_test", "map_id": "legacy_test"}]
    }
    blank_path.write_text(json.dumps(original_blank), encoding="utf-8")
    monkeypatch.setattr(module, "DATA", scratch)
    try:
        module.main()
    except RuntimeError as error:
        assert "before explicit template migration" in str(error)
    else:
        raise AssertionError("builder overwrote unmigrated legacy templates")
    assert json.loads(blank_path.read_text(encoding="utf-8")) == original_blank
    assert not (scratch / "map_design_catalog.json").exists()


def _scratch_validator(tmp_path, monkeypatch):
    module = load(f"map_validator_b26_{tmp_path.name}", "tools/map_design/validate_map_design_catalog.py")
    scratch = tmp_path / "map_design"
    scratch.mkdir(parents=True)
    for name in (
        "map_design_catalog.json",
        "map_blank_templates.json",
        "map_identity_registry.json",
        "map_scale_overrides.json",
    ):
        shutil.copy2(DATA / name, scratch / name)
    monkeypatch.setattr(module, "DATA", scratch)
    return module, scratch


def test_validator_preserves_authoring_size_clone_and_source_contracts(tmp_path, monkeypatch, capsys) -> None:
    module, scratch = _scratch_validator(tmp_path, monkeypatch)
    catalog_path = scratch / "map_design_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    catalog["maps"][0]["design_size"][0] += 1
    catalog_path.write_text(json.dumps(catalog), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "design_size differs from authoring override" in report

    module, scratch = _scratch_validator(tmp_path / "clone_case", monkeypatch)
    catalog_path = scratch / "map_design_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    clone = next(row for row in catalog["maps"] if "clone_source_map_id" in row)
    clone["clone_source_map_id"] = "wrong_source"
    catalog_path.write_text(json.dumps(catalog), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "clone_source_map_id differs from authoring override" in report

    module, scratch = _scratch_validator(tmp_path / "source_case", monkeypatch)
    catalog_path = scratch / "map_design_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    sourced = next(row for row in catalog["maps"] if "source_distribution" in row)
    sourced["source_distribution"] = "tampered_source"
    catalog_path.write_text(json.dumps(catalog), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "source_distribution differs from authoring override" in report


def test_validator_preserves_template_policy_and_size_contract(tmp_path, monkeypatch, capsys) -> None:
    module, scratch = _scratch_validator(tmp_path, monkeypatch)
    blank_path = scratch / "map_blank_templates.json"
    blank = json.loads(blank_path.read_text(encoding="utf-8"))
    blank["templates"][0]["content_policy"] = "empty_layers"
    blank_path.write_text(json.dumps(blank), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "content_policy disagrees with template_kind" in report

    module, scratch = _scratch_validator(tmp_path / "template_size_case", monkeypatch)
    blank_path = scratch / "map_blank_templates.json"
    blank = json.loads(blank_path.read_text(encoding="utf-8"))
    blank["templates"][0]["design_size"] = [0, 80]
    blank_path.write_text(json.dumps(blank), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "invalid design_size" in report


def test_validator_rejects_missing_catalog_and_template_coverage(tmp_path, monkeypatch, capsys) -> None:
    module, scratch = _scratch_validator(tmp_path, monkeypatch)
    catalog_path = scratch / "map_design_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    catalog["maps"].pop()
    catalog_path.write_text(json.dumps(catalog), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "missing catalog map for authoring override" in report

    module, scratch = _scratch_validator(tmp_path / "template_case", monkeypatch)
    blank_path = scratch / "map_blank_templates.json"
    blank = json.loads(blank_path.read_text(encoding="utf-8"))
    removed = blank["templates"].pop(0)
    blank_path.write_text(json.dumps(blank), encoding="utf-8")
    result, report = _run(module, capsys)
    expected = "missing legal blank template coverage"
    assert result == 1 and removed["map_id"] in report and expected in report

    module, scratch = _scratch_validator(tmp_path / "policy_case", monkeypatch)
    blank_path = scratch / "map_blank_templates.json"
    blank = json.loads(blank_path.read_text(encoding="utf-8"))
    first = blank["templates"][0]
    first["template_kind"] = "empty_map"
    first["content_policy"] = "empty_layers"
    blank_path.write_text(json.dumps(blank), encoding="utf-8")
    result, report = _run(module, capsys)
    assert result == 1 and "structure_reference_only requires existing workspace policy" in report
