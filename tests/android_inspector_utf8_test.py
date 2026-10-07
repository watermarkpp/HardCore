"""Exercise production native-tool decoding under Windows PowerShell's GBK locale."""
import base64
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class AndroidInspectorUtf8(unittest.TestCase):
    def run_probe(self, native_exit):
        shell = shutil.which('powershell.exe')
        if not shell:
            self.skipTest('Windows PowerShell required')
        source = (ROOT / 'tools/verify_android_build.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('function Read-AndroidToolUtf8', source)
        function = source[source.index('function Read-AndroidToolUtf8'):source.index('$ProjectRoot =')]
        with tempfile.TemporaryDirectory(prefix='hc inspector utf8 ') as directory:
            probe = pathlib.Path(directory) / 'native utf8 probe.py'
            probe.write_text('import sys\nsys.stdout.buffer.write("正式版".encode("utf-8"))\nsys.stderr.buffer.write(b"owned diagnostic")\nsys.exit(' + str(native_exit) + ')\n', encoding='utf-8')
            quote = lambda value: "'" + str(value).replace("'", "''") + "'"
            command = "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::GetEncoding(936);\n" + function
            command += '\ntry { $value=Read-AndroidToolUtf8 -Executable ' + quote(__import__('sys').executable) + ' -Arguments ' + quote('"' + str(probe) + '"') + '; $result=@{success=$true;value=$value} } catch { $result=@{success=$false;error=$_.Exception.Message} };'
            command += '$json=$result|ConvertTo-Json -Compress; [Console]::WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))'
            encoded = base64.b64encode(command.encode('utf-16-le')).decode('ascii')
            completed = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded], stdin=subprocess.DEVNULL, capture_output=True, timeout=20)
            self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors='replace'))
            return json.loads(base64.b64decode(completed.stdout.strip()))

    def test_utf8_version_survives_gbk_console(self):
        result = self.run_probe(0)
        self.assertTrue(result['success'], result)
        self.assertEqual(result['value'], '正式版')

    def test_actual_nonzero_exit_still_fails(self):
        result = self.run_probe(7)
        self.assertFalse(result['success'], result)
        self.assertIn('exit=7', result['error'])
        self.assertIn('owned diagnostic', result['error'])

    def test_all_apk_inspection_calls_use_explicit_decoder(self):
        source = (ROOT / 'tools/verify_android_build.ps1').read_text(encoding='utf-8-sig')
        for variable in ('$Badging', '$BaselineBadging', '$Manifest'):
            self.assertIn(variable + ' = Read-AndroidToolUtf8', source)

if __name__ == '__main__':
    unittest.main(verbosity=2)
