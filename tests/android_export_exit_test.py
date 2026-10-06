"""Real PowerShell native exit identity for the formal export process lane."""
import base64
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

def literal(value):
    return "'" + str(value).replace("'", "''") + "'"

class ExportExit(unittest.TestCase):
    def exercise(self, code):
        shell = shutil.which('powershell.exe')
        if not shell:
            self.skipTest('Windows required')
        source = (ROOT / 'tools/android_seal/bridge/android_two_pass_export_hook.ps1').read_text(encoding='utf-8-sig')
        helper = re.search(r'(?ms)^function Invoke-CodeExportProcess \{.*?^\}', source)
        with tempfile.TemporaryDirectory(prefix='hc export exit ') as directory:
            root = pathlib.Path(directory)
            script = root / 'owned child.py'
            script.write_text('import sys\nprint("native-complete")\nsys.exit(' + str(code) + ')\n')
            stdout, stderr = root/'stdout', root/'stderr'
            command = "$ErrorActionPreference='Stop'; "
            if helper:
                command += helper[0] + '\n'
                command += '$exitCode=Invoke-CodeExportProcess -Executable ' + literal(sys.executable)
                command += ' -Arguments @(' + literal('"' + str(script) + '"') + ')'
                command += ' -Stdout ' + literal(stdout) + ' -Stderr ' + literal(stderr) + '; '
            else:
                command += '$p=Start-Process -FilePath ' + literal(sys.executable)
                command += ' -ArgumentList @(' + literal('"' + str(script) + '"') + ')'
                command += ' -RedirectStandardOutput ' + literal(stdout) + ' -RedirectStandardError ' + literal(stderr)
                command += ' -WindowStyle Hidden -PassThru; if(-not $p.WaitForExit(10000)){throw "owned timeout"}; $exitCode=$p.ExitCode; '
            command += 'Write-Output ("EXACT_NATIVE_EXIT="+$exitCode); exit 0'
            encoded = base64.b64encode(command.encode('utf-16-le')).decode('ascii')
            result = subprocess.run([shell,'-NoProfile','-EncodedCommand',encoded], stdin=subprocess.DEVNULL, capture_output=True, timeout=20)
            self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
            self.assertIn(('EXACT_NATIVE_EXIT='+str(code)).encode(),result.stdout)
            self.assertIn(b'native-complete',stdout.read_bytes())

    def test_zero_is_numeric_not_null(self):
        self.exercise(0)

    def test_nonzero_preserved(self):
        self.exercise(7)

if __name__ == '__main__':
    unittest.main(verbosity=2)
