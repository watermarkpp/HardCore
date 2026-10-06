"""Windows native import logging: warning output is not an exit failure.

Uses the actual production function when present; the old branch is the actual
PowerShell direct invocation shape. No Godot/gameplay success is inferred.
"""
import base64
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

def ps_literal(value):
    return "'" + str(value).replace("'", "''") + "'"

class NativeImportProcess(unittest.TestCase):
    def exercise(self, exit_code):
        powershell = shutil.which('powershell.exe')
        if not powershell:
            self.skipTest('Real Windows PowerShell required')
        source = (ROOT / 'tools/build_android_isolated.ps1').read_text(encoding='utf-8-sig')
        helper = re.search(r'(?ms)^function Invoke-AndroidNativeCommand \{.*?^\}', source)
        with tempfile.TemporaryDirectory(prefix='hc native import ') as directory:
            root = pathlib.Path(directory)
            native = root / 'native input.py'
            stdout = root / 'native.stdout'
            stderr = root / 'native.stderr'
            native.write_text('import sys\nsys.stdout.buffer.write("completed 中文\\n".encode("utf-8"))\nsys.stderr.buffer.write(b"WARNING: owned import warning\\n")\nsys.exit(' + str(exit_code) + ')\n', encoding='utf-8')
            command = "$ErrorActionPreference='Stop'; "
            if helper:
                command += helper.group(0) + '\n'
                command += '$code=Invoke-AndroidNativeCommand -FilePath ' + ps_literal(sys.executable)
                command += ' -ArgumentList @(' + ps_literal('"' + str(native) + '"') + ')'
                command += ' -StdoutPath ' + ps_literal(stdout) + ' -StderrPath ' + ps_literal(stderr) + '; '
            else:
                command += '& ' + ps_literal(sys.executable) + ' ' + ps_literal(native)
                command += ' > ' + ps_literal(stdout) + ' 2> ' + ps_literal(stderr) + '; $code=$LASTEXITCODE; '
            command += 'Write-Output ("NATIVE_EXIT="+$code); exit 0'
            encoded = base64.b64encode(command.encode('utf-16-le')).decode('ascii')
            completed = subprocess.run([powershell, '-NoProfile', '-EncodedCommand', encoded], capture_output=True, timeout=30)
            self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors='replace'))
            self.assertIn(('NATIVE_EXIT=' + str(exit_code)).encode(), completed.stdout)
            self.assertEqual(stdout.read_bytes(), 'completed 中文\n'.encode('utf-8'))
            self.assertEqual(stderr.read_bytes(), b'WARNING: owned import warning\n')

    def test_warning_keeps_actual_zero_exit_and_raw_streams(self):
        self.exercise(0)

    def test_nonzero_exit_is_not_relabelled_success(self):
        self.exercise(7)

if __name__ == '__main__':
    unittest.main(verbosity=2)
