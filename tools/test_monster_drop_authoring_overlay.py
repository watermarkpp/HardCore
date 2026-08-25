#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest

from monster_drop_authoring_overlay import (
    OVERLAY_AUTHORITY,
    OVERLAY_SCHEMA,
    OverlayValidationError,
    runtime_rows_for_monster,
    validate_overlay,
)


VALID_IDS = {21, 56}


def overlay(
    *,
    global_additions: list[dict] | None = None,
    monster_additions: list[dict] | None = None,
) -> dict:
    return {
        "schema": OVERLAY_SCHEMA,
        "authority": OVERLAY_AUTHORITY,
        "global_additions": global_additions or [],
        "monster_additions": monster_additions or [],
    }


class MonsterDropAuthoringOverlayTest(unittest.TestCase):
    def validate(self, raw: dict) -> dict:
        return validate_overlay(
            raw,
            VALID_IDS,
            "assets/data/canonical_monster_drop_authoring_overrides_v1.json",
        )

    def test_empty_overlay_emits_nothing(self) -> None:
        normalized = self.validate(overlay())
        self.assertEqual(runtime_rows_for_monster(21, normalized), [])
        self.assertEqual(
            normalized["enabled_monster_addition_count"],
            0,
        )

    def test_global_then_monster_order(self) -> None:
        normalized = self.validate(overlay(
            global_additions=[{
                "entry_key": "global.potion",
                "enabled": True,
                "chance": "1/100",
                "item": "金创药(小量)",
                "note": "",
            }],
            monster_additions=[{
                "entry_key": "monster.21.scroll",
                "enabled": True,
                "monster_id": 21,
                "chance": "1/2",
                "item": "回城卷",
                "note": "",
            }],
        ))
        rows = runtime_rows_for_monster(21, normalized)
        self.assertEqual(
            [row["authoring_entry_key"] for row in rows],
            ["global.potion", "monster.21.scroll"],
        )
        self.assertEqual(
            len(runtime_rows_for_monster(56, normalized)),
            1,
        )

    def test_same_item_multiple_slots_are_preserved(self) -> None:
        normalized = self.validate(overlay(
            monster_additions=[
                {
                    "entry_key": "monster.21.potion.a",
                    "enabled": True,
                    "monster_id": 21,
                    "chance": "1/10",
                    "item": "金创药(小量)",
                    "note": "",
                },
                {
                    "entry_key": "monster.21.potion.b",
                    "enabled": True,
                    "monster_id": 21,
                    "chance": "1/100",
                    "item": "金创药(小量)",
                    "note": "",
                },
            ],
        ))
        rows = runtime_rows_for_monster(21, normalized)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["item"], rows[1]["item"])
        self.assertNotEqual(rows[0]["chance"], rows[1]["chance"])

    def test_disabled_entry_is_validated_but_not_emitted(self) -> None:
        normalized = self.validate(overlay(
            global_additions=[{
                "entry_key": "global.disabled",
                "enabled": False,
                "chance": "1/100",
                "item": "金创药(小量)",
                "note": "",
            }],
        ))
        self.assertEqual(runtime_rows_for_monster(21, normalized), [])

    def test_duplicate_entry_key_is_rejected_across_scopes(self) -> None:
        with self.assertRaises(OverlayValidationError):
            self.validate(overlay(
                global_additions=[{
                    "entry_key": "duplicate.key",
                    "enabled": False,
                    "chance": "1/10",
                    "item": "金创药(小量)",
                    "note": "",
                }],
                monster_additions=[{
                    "entry_key": "duplicate.key",
                    "enabled": True,
                    "monster_id": 21,
                    "chance": "1/10",
                    "item": "回城卷",
                    "note": "",
                }],
            ))

    def test_unknown_monster_id_is_rejected(self) -> None:
        with self.assertRaises(OverlayValidationError):
            self.validate(overlay(
                monster_additions=[{
                    "entry_key": "monster.999.invalid",
                    "enabled": True,
                    "monster_id": 999,
                    "chance": "1/10",
                    "item": "回城卷",
                    "note": "",
                }],
            ))

    def test_invalid_chance_tokens_are_rejected(self) -> None:
        for chance in ["0", "1/0", "2/10", "0.1", "1/-1", "1/01"]:
            with self.subTest(chance=chance):
                with self.assertRaises(OverlayValidationError):
                    self.validate(overlay(
                        global_additions=[{
                            "entry_key": "global.invalid",
                            "enabled": True,
                            "chance": chance,
                            "item": "金创药(小量)",
                            "note": "",
                        }],
                    ))

    def test_legacy_or_unknown_fields_are_rejected(self) -> None:
        for field, value in [
            ("monsterId", 21),
            ("itemId", 100),
            ("probability", 0.5),
            ("count", 1),
            ("min_quantity", 1),
        ]:
            with self.subTest(field=field):
                row = {
                    "entry_key": "global.invalid",
                    "enabled": True,
                    "chance": "1/10",
                    "item": "金创药(小量)",
                    "note": "",
                    field: value,
                }
                with self.assertRaises(OverlayValidationError):
                    self.validate(overlay(global_additions=[row]))

    def test_gold_contract_is_strict(self) -> None:
        normalized = self.validate(overlay(
            global_additions=[{
                "entry_key": "global.gold",
                "enabled": True,
                "chance": "1/100",
                "item": "金币",
                "gold": 1000,
                "note": "",
            }],
        ))
        row = runtime_rows_for_monster(21, normalized)[0]
        self.assertEqual(row["gold"], 1000)
        self.assertEqual(row["raw_text"], "1/100 金币 1000")

        with self.assertRaises(OverlayValidationError):
            self.validate(overlay(
                global_additions=[{
                    "entry_key": "global.bad_gold",
                    "enabled": True,
                    "chance": "1/100",
                    "item": "回城卷",
                    "gold": 1000,
                    "note": "",
                }],
            ))

    def test_runtime_projection_is_deterministic(self) -> None:
        normalized = self.validate(overlay(
            global_additions=[{
                "entry_key": "global.potion",
                "enabled": True,
                "chance": "1/100",
                "item": "金创药(小量)",
                "note": "",
            }],
            monster_additions=[{
                "entry_key": "monster.21.scroll",
                "enabled": True,
                "monster_id": 21,
                "chance": "1/2",
                "item": "回城卷",
                "note": "",
            }],
        ))
        first = json.dumps(
            runtime_rows_for_monster(21, normalized),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        second = json.dumps(
            runtime_rows_for_monster(21, normalized),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main(verbosity=2)
