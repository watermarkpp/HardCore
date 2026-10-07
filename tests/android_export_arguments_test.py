"""Execute the exact production caller expression; inspect its native arguments."""
import base64
import json
import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ExportArguments(unittest.TestCase):
    def test_runtime_paths_expand_and_remain_quoted(self):
        shell = shutil.which('powershell.exe')
        if not shell:
            self.skipTest('Windows required')
        source = (ROOT/'tools/android_seal/bridge/android_two_pass_export_hook.ps1').read_text(encoding='utf-8-sig')
        calls = [line for line in source.splitlines() if '$NativeExit = Invoke-CodeExportProcess' in line]
        self.assertEqual(len(calls), 1)
        command = r'''
$ErrorActionPreference='Stop'
function Invoke-CodeExportProcess {
 param($Executable,$Arguments,$Stdout,$Stderr)
 $global:Captured = $Arguments
 return 0
}
$GodotConsole='C:\owned engine\godot.exe'
$StageRoot='C:\owned stage with spaces'
$Log='C:\owned logs\first.engine.log'
$Apk='C:\owned output\first.apk'
$Stdout='C:\owned logs\stdout'
$Stderr='C:\owned logs\stderr'
'''
        command += calls[0] + '\nConvertTo-Json -InputObject $global:Captured -Compress\n'
        encoded = base64.b64encode(command.encode('utf-16-le')).decode('ascii')
        result = subprocess.run([shell,'-NoProfile','-NonInteractive','-EncodedCommand',encoded],stdin=subprocess.DEVNULL,capture_output=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
        args = json.loads(result.stdout)
        self.assertEqual(args, ['--headless','--path','"C:\\owned stage with spaces"','--log-file','"C:\\owned logs\\first.engine.log"','--export-debug','Android','"C:\\owned output\\first.apk"'])

if __name__ == '__main__':
    unittest.main(verbosity=2)
