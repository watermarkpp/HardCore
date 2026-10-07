"""Exercise the exact final verification call's PowerShell output contract.

This proves result/exception propagation, not APK correctness or a new export.
"""
import base64
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ExportReturnValue(unittest.TestCase):
    def probe(self, fail):
        shell = shutil.which('powershell.exe')
        if not shell:
            self.skipTest('Windows PowerShell required')
        source = (ROOT/'tools/android_seal/bridge/android_two_pass_export_hook.ps1').read_text(encoding='utf-8-sig')
        lines = [line for line in source.splitlines() if line.strip().startswith('& $VerifyProductionBuild ')]
        self.assertEqual(len(lines), 1)
        with tempfile.TemporaryDirectory(prefix='hc owned export result ') as directory:
            quoted = "'" + directory.replace("'", "''") + "'"
            callback = "throw 'owned verification failure'" if fail else "Write-Output 'APK_VERIFY_OWNED'; Write-Output 'HASH_OWNED'"
            command = "$ErrorActionPreference='Stop'; Set-StrictMode -Version 2.0; $EvidenceRoot=" + quoted + "; $OutputApk='owned.apk'; $SourceCommit='owned'; $VerifyProductionBuild={param($Apk,$Commit) " + callback + "};\n"
            command += "function Invoke-OwnedResult {\n" + lines[0] + "\nreturn @{apk_sha256='owned-hash';native_exit=0}\n}\n"
            command += "try {$value=Invoke-OwnedResult;$result=@{success=$true;result_type=$value.GetType().FullName;value=$value}} catch {$result=@{success=$false;error=$_.Exception.Message}}; $json=$result|ConvertTo-Json -Depth 5 -Compress; [Console]::WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))"
            encoded = base64.b64encode(command.encode('utf-16-le')).decode('ascii')
            native = subprocess.run([shell,'-NoProfile','-NonInteractive','-EncodedCommand',encoded],stdin=subprocess.DEVNULL,capture_output=True,timeout=20)
            self.assertEqual(native.returncode,0,native.stderr.decode(errors='replace'))
            result = json.loads(base64.b64decode(native.stdout.strip()))
            logs = ''.join(p.read_text(encoding='utf-16',errors='replace') for p in pathlib.Path(directory).glob('*.log'))
            return result, logs

    def test_verifier_messages_do_not_replace_final_result(self):
        result, logs = self.probe(False)
        self.assertTrue(result['success'],result)
        self.assertEqual(result['result_type'],'System.Collections.Hashtable')
        self.assertEqual(result['value']['apk_sha256'],'owned-hash')
        self.assertIn('APK_VERIFY_OWNED',logs)
        self.assertIn('HASH_OWNED',logs)

    def test_real_verification_exception_still_fails(self):
        result, _ = self.probe(True)
        self.assertFalse(result['success'],result)
        self.assertIn('owned verification failure',result['error'])

if __name__ == '__main__':
    unittest.main(verbosity=2)
