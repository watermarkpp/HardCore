"""Host-only tests of source fingerprints; never exports APKs or touches saves."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, sys, tempfile, unittest, zipfile

def digest(data):
    return hashlib.sha256(data).hexdigest()

def load(path):
    spec = importlib.util.spec_from_file_location('seal_source_contract_collector', path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module

class SourceBytesContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='owned_seal_source_', dir=SCRATCH)
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def source_plan(self, data, expected=None, kind='script', type_name='GDScript', path='res://scripts/example.gd', context=False):
        if expected is None:
            expected = data.replace(b'\r\n', b'\n') if not context else data
        target = self.root / path.removeprefix('res://')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        record = {'sha256': digest(expected), 'bytes': len(expected)}
        if not context:
            record.update(kind=kind, type=type_name)
        plan = {'nodes': {} if context else {path: record}, 'source_fingerprints': {'source_context': {path: record} if context else {}}}
        return plan, target

    def test_lf_script_exact(self):
        plan, _ = self.source_plan(b'extends RefCounted\nconst V = 3\n')
        self.assertEqual(len(C.verify_source_files(plan, self.root)), 64)

    def test_crlf_script_uses_producer_lf_contract(self):
        plan, _ = self.source_plan(b'extends RefCounted\r\nconst V = 3\r\n')
        self.assertEqual(len(C.verify_source_files(plan, self.root)), 64)

    def test_crlf_resident_uses_same_contract(self):
        plan, _ = self.source_plan(b'extends Node\r\nconst V = 3\r\n', kind='resident_script')
        self.assertEqual(len(C.verify_source_files(plan, self.root)), 64)

    def test_shader_source_uses_producer_lf_contract(self):
        plan, _ = self.source_plan(b'shader_type canvas_item;\r\n', kind='asset', type_name='Shader', path='res://shaders/example.gdshader')
        self.assertEqual(len(C.verify_source_files(plan, self.root)), 64)

    def test_semantic_edit_rejected_even_with_equal_length(self):
        plan, _ = self.source_plan(b'extends Node\r\nconst V = 4\r\n', expected=b'extends Node\nconst V = 3\n')
        with self.assertRaises(C.Refusal):
            C.verify_source_files(plan, self.root)

    def test_wrong_hash_rejected(self):
        plan, _ = self.source_plan(b'extends Node\n')
        plan['nodes']['res://scripts/example.gd']['sha256'] = '0' * 64
        with self.assertRaises(C.Refusal):
            C.verify_source_files(plan, self.root)

    def test_wrong_length_rejected(self):
        plan, _ = self.source_plan(b'extends Node\n')
        plan['nodes']['res://scripts/example.gd']['bytes'] += 1
        with self.assertRaises(C.Refusal):
            C.verify_source_files(plan, self.root)

    def test_project_context_remains_raw_exact(self):
        plan, _ = self.source_plan(b'[application]\r\n', expected=b'[application]\n', path='res://project.godot', context=True)
        with self.assertRaises(C.Refusal):
            C.verify_source_files(plan, self.root)

    def test_class_cache_remains_raw_exact(self):
        plan, _ = self.source_plan(b'list=[]\r\n', expected=b'list=[]\n', path='res://.godot/global_script_class_cache.cfg', context=True)
        with self.assertRaises(C.Refusal):
            C.verify_source_files(plan, self.root)

    def test_json_is_not_normalized(self):
        plan, _ = self.source_plan(b'{"v":3}\r\n', expected=b'{"v":3}\n', path='res://assets/data/example.json', context=True)
        with self.assertRaises(C.Refusal):
            C.verify_source_files(plan, self.root)

    def test_lone_cr_is_not_removed(self):
        plan, _ = self.source_plan(b'extends Node\rconst V = 3\n', expected=b'extends Node\nconst V = 3\n')
        with self.assertRaises(C.Refusal):
            C.verify_source_files(plan, self.root)

    def test_raw_snapshot_detects_eol_drift_between_reads(self):
        data=b'extends Node\r\nconst V = 3\r\n'
        plan, target = self.source_plan(data)
        first = C.verify_source_files(plan, self.root)
        target.write_bytes(data.replace(b'\r\n', b'\n'))
        second = C.verify_source_files(plan, self.root)
        self.assertNotEqual(first, second)

    def test_shader_zip_maps_real_raw_export_and_canonical_source(self):
        raw = b'shader_type canvas_item;\r\n'
        plan, _ = self.source_plan(raw, kind='asset', type_name='Shader', path='res://shaders/example.gdshader')
        apk = self.root/'fixture.zip'
        with zipfile.ZipFile(apk, 'w') as z:
            z.writestr('assets/shaders/example.gdshader', raw)
        with C.ZipView(apk) as z:
            result=C.map_node(z,'res://shaders/example.gdshader',plan['nodes']['res://shaders/example.gdshader'])
        self.assertEqual(result['export']['sha256'], digest(raw))
        self.assertEqual(result['source']['sha256'], digest(raw.replace(b'\r\n',b'\n')))

    def test_shader_semantic_export_edit_rejected(self):
        plan, _ = self.source_plan(b'shader_type canvas_item;\n', kind='asset', type_name='Shader', path='res://shaders/example.gdshader')
        apk=self.root/'fixture.zip'
        with zipfile.ZipFile(apk,'w') as z:
            z.writestr('assets/shaders/example.gdshader', b'shader_type particles;\r\n')
        with C.ZipView(apk) as z, self.assertRaises(C.Refusal):
            C.map_node(z,'res://shaders/example.gdshader',plan['nodes']['res://shaders/example.gdshader'])

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2])
    parser.add_argument('--collector',type=Path)
    parser.add_argument('--scratch',type=Path,required=True)
    args=parser.parse_args();SCRATCH=args.scratch;SCRATCH.mkdir(parents=True,exist_ok=True)
    C=load(args.collector or args.root/'tools/android_seal/export_identity_tool/collector.py')
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SourceBytesContract))
    print(json.dumps({'status':'PASS' if result.wasSuccessful() else 'FAIL','checks':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'scope':'host component and synthetic ZIP contracts; not APK/game acceptance'}))
    sys.exit(0 if result.wasSuccessful() else 1)
