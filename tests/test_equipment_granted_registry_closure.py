"""Unknown grants must not escape the ordinary skill-book closure by prefix."""
import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('registry_builder', ROOT / 'tools/build_entity_registry.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class RegistryGrantClosure(unittest.TestCase):
    def setUp(self):
        self.records = {row['id']: row for row in builder.read(ROOT / 'assets/data/runtime/entity_registry_v1.json')['records']}
        self.authority = builder.read(ROOT / 'assets/data/item_runtime_authority_v1.json')
        self.catalog = builder.read(ROOT / 'assets/data/service_item_catalog.json')

    def test_exact_three_grants_leave_all_33_book_targets_required(self):
        relations = builder.validate_skill_book_bindings(self.authority, self.catalog, self.records)
        self.assertEqual(len(relations), 33)
        self.assertEqual(builder.validate_equipment_granted_bindings(ROOT, self.records)['skill_count'], 3)

    def test_unknown_equipment_prefix_does_not_bypass_book_closure(self):
        records = copy.deepcopy(self.records)
        records['hc.skill.equipment.unknown'] = {'kind': 'skill'}
        with self.assertRaisesRegex(ValueError, 'incomplete skill book relations'):
            builder.validate_skill_book_bindings(self.authority, self.catalog, records)


if __name__ == '__main__':
    unittest.main()
