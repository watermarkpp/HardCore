"""Run the real build-info generator against an isolated Git repository."""
import base64
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class BuildInfoUtf8(unittest.TestCase):
    def generate(self, version_line, override=0):
        shell = shutil.which('powershell.exe')
        if not shell:
            self.skipTest('Windows PowerShell required')
        with tempfile.TemporaryDirectory(prefix='hc owned build-info ') as directory:
            root = pathlib.Path(directory)
            (root / 'project.godot').write_text('[application]\n' + version_line + '\n', encoding='utf-8')
            (root / 'export_presets.cfg').write_text('[preset.0.options]\nversion/code=82\n', encoding='utf-8')
            for args in (['init','-q'], ['add','.'], ['-c','user.name=OwnedTest','-c','user.email=owned@example.invalid','-c','core.hooksPath=none','commit','-q','--no-gpg-sign','-m','owned fixture']):
                subprocess.run(['git', *args], cwd=root, check=True, capture_output=True)
            script = ROOT / 'tools/generate_build_info.ps1'
            quote = lambda value: "'" + str(value).replace("'", "''") + "'"
            command = "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::GetEncoding(936); & " + quote(script) + ' -StageRoot ' + quote(root) + ' -VersionCodeOverride ' + str(override)
            encoded = base64.b64encode(command.encode('utf-16-le')).decode('ascii')
            completed = subprocess.run([shell,'-NoProfile','-NonInteractive','-EncodedCommand',encoded], stdin=subprocess.DEVNULL,capture_output=True,timeout=30)
            output = root / 'assets/generated/build_info.json'
            value = json.loads(output.read_bytes()) if output.exists() else None
            return completed, value

    def test_chinese_version_and_override_remain_exact(self):
        result, value = self.generate('config/version="hardcore 1.0 正式版"', 103)
        self.assertEqual(result.returncode, 0, result.stderr.decode('gbk', errors='replace'))
        self.assertEqual(value['version_name'], 'hardcore 1.0 正式版')
        self.assertEqual(value['version_code'], 103)
        self.assertFalse(value['git_dirty'])

    def test_ascii_version_and_preset_code_remain_compatible(self):
        result, value = self.generate('config/version="owned-alpha"')
        self.assertEqual(result.returncode, 0, result.stderr.decode('gbk', errors='replace'))
        self.assertEqual(value['version_name'], 'owned-alpha')
        self.assertEqual(value['version_code'], 82)

    def test_missing_version_refuses_instead_of_writing_partial_info(self):
        result, value = self.generate('config/name="owned"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(value)

if __name__ == '__main__':
    unittest.main(verbosity=2)
