"""Identity generation invariants; no gameplay copies or name-derived IDs."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "build_entity_registry.py"
spec = importlib.util.spec_from_file_location("entity_registry_builder", MODULE_PATH)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class EntityRegistryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "assets/data/identity/source.json"
        self.table = self.root / "assets/data/table.json"
        self.rows = [{"itemId":85,"name":"显示名称"}]
        self.policy = {"schema_version":1,"contract_id":builder.CONTRACT,"sources":[
            {"kind":"item","path":"assets/data/table.json","records":"records","id_field":"itemId","display_field":"name"}],"explicit":[]}

    def build(self):
        self.source.parent.mkdir(parents=True, exist_ok=True)
        self.source.write_text(json.dumps(self.policy, ensure_ascii=False), encoding="utf-8")
        self.table.write_text(json.dumps({"records":self.rows}, ensure_ascii=False), encoding="utf-8")
        return builder.build(self.source, self.root)

    def test_display_rename_retains_identity(self):
        before = self.build()["records"][0]
        self.rows[0]["name"] = "另一个显示名称"
        after = self.build()["records"][0]
        self.assertEqual(before["id"], "hc.item.000085")
        self.assertEqual(before["id"], after["id"])
        self.assertNotEqual(before["display_name"], after["display_name"])

    def test_duplicate_primary_record_rejects(self):
        self.rows.append(self.rows[0].copy())
        with self.assertRaisesRegex(ValueError, "duplicate primary identity"):
            self.build()

    def test_explicit_alias_projection_preserves_evidence(self):
        self.rows.append(self.rows[0].copy())
        self.policy["sources"][0]["allow_repeated_identity"] = True
        document = self.build()
        self.assertEqual(document["counts"], {"item":1})
        self.assertEqual(len(document["records"][0]["evidence"]), 2)

    def test_conflicting_alias_projection_rejects(self):
        self.rows.append({"itemId":85,"name":"冲突名称"})
        self.policy["sources"][0]["allow_repeated_identity"] = True
        with self.assertRaisesRegex(ValueError, "conflicting registration"):
            self.build()

    def test_missing_id_has_no_name_fallback(self):
        del self.rows[0]["itemId"]
        with self.assertRaises(KeyError):
            self.build()

    def test_numeric_ids_never_coerce(self):
        for value in [85.5, True, "85", -1]:
            with self.subTest(value=value):
                self.rows[0]["itemId"] = value
                with self.assertRaisesRegex(ValueError, "invalid exact numeric identity"):
                    self.build()

    def test_explicit_numeric_mismatch_rejects(self):
        self.policy["explicit"] = [{"id":"hc.item.000086","kind":"item","legacy_id":85,"display_name":"显示名称"}]
        with self.assertRaisesRegex(ValueError, "formal/legacy identity mismatch"):
            self.build()

    def test_unknown_kind_and_transform_reject(self):
        self.policy["sources"][0]["kind"] = "unknown"
        with self.assertRaisesRegex(ValueError, "unknown identity kind"):
            self.build()
        self.policy["sources"][0]["kind"] = "item"
        self.policy["sources"][0]["mode"] = "guess_by_name"
        with self.assertRaisesRegex(ValueError, "unknown identity transformation"):
            self.build()

    def test_exact_generation_matches_checked_in_output(self):
        self.assertEqual(builder.encode(builder.build()), builder.OUTPUT.read_bytes())

    def add_service_alias(self):
        self.rows[0]['serviceIndex'] = 670
        self.policy['sources'].append({'kind':'service_item', 'path':'assets/data/table.json',
            'records':'records', 'id_field':'serviceIndex', 'display_field':'name'})
        self.policy['aliases'] = [{'alias_id':'hc.service_item.000670', 'canonical_id':'hc.item.000085',
            'evidence':[{'path':'res://assets/data/table.json', 'pointer':'/records/0'}]}]

    def test_declared_cross_source_alias_retains_numeric_sources(self):
        self.add_service_alias()
        records = {r['id']:r for r in self.build()['records']}
        self.assertEqual(records['hc.service_item.000670']['canonical_id'], 'hc.item.000085')
        self.assertEqual(records['hc.service_item.000670']['legacy_id'], 670)
        self.assertEqual(records['hc.item.000085']['legacy_id'], 85)

    def test_undeclared_or_cross_kind_alias_fails(self):
        self.add_service_alias()
        for target in ('hc.item.999999', 'hc.service_item.000670'):
            self.policy['aliases'][0]['canonical_id'] = target
            with self.assertRaisesRegex(ValueError, 'invalid or duplicate explicit item alias'):
                self.build()

    def test_duplicate_and_unproven_aliases_fail(self):
        self.add_service_alias()
        self.policy['aliases'].append(self.policy['aliases'][0].copy())
        with self.assertRaisesRegex(ValueError, 'invalid or duplicate explicit item alias'):
            self.build()
        self.policy['aliases'].pop()
        self.policy['aliases'][0]['evidence'][0]['path'] = 'res://assets/data/unregistered.json'
        with self.assertRaisesRegex(ValueError, 'invalid item alias evidence'):
            self.build()


class SkillBookIdentityTests(unittest.TestCase):
    def setUp(self):
        self.authority = {'policies': {'serviceOverridesByIndex': {
            '990': {'learnSkillId': 'hc.skill.wizard.fireball'},
            '995': {'learnSkillId': 'hc.skill.wizard.lightning'},
        }}}
        self.catalog = {'runtimeItems': [
            {'serviceIndex': 990, 'kind': 'skill_book', 'name': '任意展示文字'},
            {'serviceIndex': 995, 'kind': 'skill_book', 'name': '另一展示文字'},
        ]}
        self.records = {
            'hc.skill.wizard.fireball': {'kind': 'skill'},
            'hc.skill.wizard.lightning': {'kind': 'skill'},
            'hc.item.920026': {'kind': 'item'},
            'hc.service_item.000990': {'kind': 'service_item', 'canonical_id': 'hc.item.920026'},
            'hc.service_item.000995': {'kind': 'service_item'},
        }

    def validate(self):
        function = getattr(builder, 'validate_skill_book_bindings', None)
        self.assertTrue(callable(function), 'official generator validates explicit book relations')
        return function(self.authority, self.catalog, self.records)

    def test_registered_relations_ignore_display_and_preserve_declared_alias(self):
        self.assertEqual(self.validate(), {'hc.item.920026': 'hc.skill.wizard.fireball',
            'hc.service_item.000995': 'hc.skill.wizard.lightning'})

    def test_unknown_or_cross_kind_target_fails(self):
        for value in ('hc.skill.wizard.missing', 'hc.item.920026', '火球术'):
            self.authority['policies']['serviceOverridesByIndex']['990']['learnSkillId'] = value
            with self.assertRaisesRegex(ValueError, 'invalid skill book relation'):
                self.validate()

    def test_missing_current_skill_fails(self):
        del self.authority['policies']['serviceOverridesByIndex']['995']
        with self.assertRaisesRegex(ValueError, 'incomplete skill book relations'):
            self.validate()

    def test_duplicate_target_fails(self):
        self.authority['policies']['serviceOverridesByIndex']['995']['learnSkillId'] = 'hc.skill.wizard.fireball'
        with self.assertRaisesRegex(ValueError, 'duplicate skill book relation'):
            self.validate()

    def test_non_book_owner_fails(self):
        self.catalog['runtimeItems'][0]['kind'] = 'consumable'
        with self.assertRaisesRegex(ValueError, 'invalid skill book relation'):
            self.validate()


class RelicIdentityRelationTests(unittest.TestCase):
    def setUp(self):
        self.authority = {'skill_pools': {
            'hc.profession.warrior': ['hc.skill.warrior.thrusting'],
            'hc.profession.wizard': ['hc.skill.wizard.lightning'],
            'hc.profession.taoist': ['hc.skill.taoist.healing'],
        }, 'items': [
            {'item_id': 950101, 'name': '改过显示的圣物'},
            {'item_id': 950201, 'name': '改过显示的徽章', 'skill_profession': '展示标签',
                'skill_profession_id': 'hc.profession.warrior'},
        ]}
        self.skill_source = {'skills': [
            {'skill_id': 'warrior.thrusting', 'class': 'warrior'},
            {'skill_id': 'wizard.lightning', 'class': 'wizard'},
            {'skill_id': 'taoist.healing', 'class': 'taoist'},
        ]}
        self.records = {key: {'kind': 'profession'} for key in self.authority['skill_pools']}
        self.records.update({key: {'kind': 'skill'} for pool in self.authority['skill_pools'].values() for key in pool})
        self.records.update({'hc.item.950101': {'kind': 'item'}, 'hc.item.950201': {'kind': 'item'}})

    def validate(self):
        function = getattr(builder, 'validate_relic_bindings', None)
        self.assertTrue(callable(function), 'official generator validates the primary relic ID relations')
        return function(self.authority, self.skill_source, self.records)

    def test_relations_ignore_display_metadata(self):
        self.assertEqual(self.validate()['pool_skill_count'], 3)

    def test_unknown_cross_kind_or_name_skill_target_rejects(self):
        for target in ('雷电术', 'hc.item.950101', 'hc.skill.wizard.missing'):
            self.authority['skill_pools']['hc.profession.wizard'] = [target]
            with self.assertRaisesRegex(ValueError, 'invalid relic skill relation'):
                self.validate()

    def test_missing_or_duplicate_pool_rejects(self):
        pool = self.authority['skill_pools'].pop('hc.profession.wizard')
        with self.assertRaisesRegex(ValueError, 'incomplete relic profession pools'):
            self.validate()
        self.authority['skill_pools']['hc.profession.wizard'] = pool + pool
        with self.assertRaisesRegex(ValueError, 'duplicate relic skill relation'):
            self.validate()

    def test_cross_class_relation_rejects(self):
        self.authority['skill_pools']['hc.profession.warrior'] = ['hc.skill.wizard.lightning']
        with self.assertRaisesRegex(ValueError, 'cross-class relic skill relation'):
            self.validate()

    def test_badge_missing_or_unknown_profession_rejects(self):
        for target in ('战士', 'hc.skill.warrior.thrusting', 'hc.profession.missing', None):
            self.authority['items'][1]['skill_profession_id'] = target
            with self.assertRaisesRegex(ValueError, 'invalid relic badge profession relation'):
                self.validate()


class ItemCategoryIdentityTests(unittest.TestCase):
    def setUp(self):
        self.document = {'schema_version': 1, 'contract_id': 'hardcore.item_categories.v1', 'records': [
            {'category_id': 'weapon', 'display_name': '武器', 'legacy_categories': ['武器'], 'equipment_slots': ['hc.slot.weapon']},
            {'category_id': 'armor', 'display_name': '盔甲', 'legacy_categories': ['盔甲', '衣服'], 'equipment_slots': ['hc.slot.armor']},
        ]}
        self.records = {'hc.item_category.weapon': {'kind': 'item_category'},
            'hc.item_category.armor': {'kind': 'item_category'},
            'hc.slot.weapon': {'kind': 'slot'}, 'hc.slot.armor': {'kind': 'slot'}}

    def validate(self):
        function = getattr(builder, 'validate_item_categories', None)
        self.assertTrue(callable(function), 'official generator validates the closed category source')
        return function(self.document, self.records)

    def test_category_symbols_have_a_formal_namespace(self):
        self.assertEqual(builder.identity('item_category', 'weapon'), 'hc.item_category.weapon')

    def test_display_rename_does_not_change_legacy_enum_or_identity(self):
        self.document['records'][0]['display_name'] = '装备类型显示'
        self.assertEqual(self.validate()['武器'], 'hc.item_category.weapon')

    def test_duplicate_legacy_enum_rejects(self):
        self.document['records'][1]['legacy_categories'].append('武器')
        with self.assertRaisesRegex(ValueError, 'duplicate category legacy enum'):
            self.validate()

    def test_unknown_slot_target_rejects(self):
        self.document['records'][0]['equipment_slots'] = ['hc.item_category.weapon']
        with self.assertRaisesRegex(ValueError, 'invalid category slot relation'):
            self.validate()

    def test_future_category_source_rejects(self):
        self.document['schema_version'] = 2
        with self.assertRaisesRegex(ValueError, 'unsupported category source'):
            self.validate()


if __name__ == "__main__":
    unittest.main()
