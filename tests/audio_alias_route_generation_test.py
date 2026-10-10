"""Focused contract tests for canonical service-item audio aliases."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import pytest

from tools.audio.audio_pipeline import canonical_item_alias_routes


def _fixture(tmp_path: Path, aliases: list[dict], service_records: list[dict] | None = None):
    identity = tmp_path / "assets/data/identity"
    identity.mkdir(parents=True, exist_ok=True)
    (tmp_path / "assets/data").mkdir(parents=True, exist_ok=True)
    records = service_records or [{"serviceIndex": 658, "name": "金创药"}]
    (tmp_path / "assets/data/service_items.json").write_text(
        json.dumps({"runtimeItems": records}), encoding="utf-8"
    )
    (tmp_path / "assets/data/items.json").write_text(
        json.dumps({"records": [{"itemId": 920045, "name": "金创药"}]}), encoding="utf-8"
    )
    registry = {
        "schema_version": 1,
        "contract_id": "hardcore.entity_identity.v1",
        "sources": [
            {"kind": "service_item", "path": "assets/data/service_items.json", "records": "runtimeItems", "id_field": "serviceIndex", "display_field": "name"},
            {"kind": "item", "path": "assets/data/items.json", "records": "records", "id_field": "itemId", "display_field": "name"},
        ],
        "explicit": [],
        "aliases": aliases,
    }
    (identity / "entity_registry_source.json").write_text(
        json.dumps(registry, ensure_ascii=False), encoding="utf-8"
    )
    routes = {"service:658": {"identity_kind": "service_index", "identity_value": 658, "events": {"use_success": "item.use.drug.success"}}}
    return tmp_path, {"runtimeItems": records}, routes


def _alias() -> dict:
    return {
        "alias_id": "hc.service_item.000658",
        "canonical_id": "hc.item.920045",
        "evidence": [
            {"path": "res://assets/data/service_items.json", "pointer": "/runtimeItems/0"},
            {"path": "res://assets/data/items.json", "pointer": "/records/0"},
        ],
    }


def test_alias_adds_canonical_route_without_removing_service_route() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root, services, routes = _fixture(Path(raw), [_alias()])
        summary = canonical_item_alias_routes(root, services, routes)
        assert summary["alias_count"] == 1
        assert routes["service:658"]["events"] == {"use_success": "item.use.drug.success"}
        assert routes["item:920045"]["alias_of"] == "service:658"
        assert routes["item:920045"]["events"] == routes["service:658"]["events"]


def test_alias_generation_is_idempotent_for_exact_generated_route() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root, services, routes = _fixture(Path(raw), [_alias()])
        canonical_item_alias_routes(root, services, routes)
        before = json.loads(json.dumps(routes))
        assert canonical_item_alias_routes(root, services, routes)["alias_count"] == 1
        assert routes == before


def test_alias_conflict_rejects_without_mutating_routes() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root, services, routes = _fixture(Path(raw), [_alias()])
        routes["item:920045"] = {"events": {"use_success": "wrong.event"}}
        before = json.loads(json.dumps(routes))
        with pytest.raises(ValueError, match="conflicting item route"):
            canonical_item_alias_routes(root, services, routes)
        assert routes == before


def test_unregistered_canonical_target_is_rejected_by_formal_registry() -> None:
    with tempfile.TemporaryDirectory() as raw:
        alias = _alias()
        alias["canonical_id"] = "hc.item.999999"
        root, services, routes = _fixture(Path(raw), [alias])
        with pytest.raises(ValueError, match="formal identity registry validation failed"):
            canonical_item_alias_routes(root, services, routes)


def test_duplicate_service_index_is_rejected_explicitly() -> None:
    with tempfile.TemporaryDirectory() as raw:
        duplicate = [{"serviceIndex": 658, "name": "a"}, {"serviceIndex": 658, "name": "b"}]
        root, services, routes = _fixture(Path(raw), [_alias()], duplicate)
        with pytest.raises(ValueError, match="duplicate serviceIndex"):
            canonical_item_alias_routes(root, services, routes)
