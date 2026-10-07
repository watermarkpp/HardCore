"""Run the full production two-pass function with owned native-tool fixtures.

Only APK exporter/signer and tool internals are fixtures. This checks orchestration
return/exit/evidence contracts, NOT APK signing, seal validity or device behavior.
"""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / 'tools/android_seal/bridge/android_two_pass_export_hook.ps1'

class TwoPassResult(unittest.TestCase):
    def probe(self, fail=''):
        shell = shutil.which('powershell.exe')
        if not shell:
            self.skipTest('Windows PowerShell required')
        with tempfile.TemporaryDirectory(prefix='hc owned full export ') as directory:
            root = Path(directory)
            bridge = root/'bridge'; bridge.mkdir()
            collector = root/'export_identity_tool'; collector.mkdir()
            (collector/'collector.py').write_text('# owned fixture\n', encoding='utf-8')
            shutil.copyfile(HOOK, bridge/HOOK.name)
            # The real Python process emits JSON stdout, as both production
            # tools do. A requested nonzero exit must reach the outer caller.
            native = '''import json, os, pathlib, sys
name=pathlib.Path(__file__).stem
print(json.dumps({"owned_tool":name,"status":"PASS"}),flush=True)
if os.environ.get("HC_OWNED_EXPORT_FAIL")==name:
    print("owned tool failure",file=sys.stderr,flush=True)
    raise SystemExit(7)
args=sys.argv[1:]
for option in ("--output-gd","--output-json","--output"):
    if option in args:
        target=pathlib.Path(args[args.index(option)+1])
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text("extends RefCounted\\nconst AVAILABLE := true\\n" if option=="--output-gd" else "{}",encoding="utf-8")
'''
            for name in ('build_android_seal.py','verify_final_export.py'):
                (bridge/name).write_text(native,encoding='utf-8')
            stage=root/'stage with spaces'; stage.mkdir()
            inputs=root/'inputs'; inputs.mkdir()
            evidence=root/'evidence'
            for path in ('project.godot','.godot/global_script_class_cache.cfg','export_presets.cfg','assets/generated/build_info.json',
                         'assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png',
                         'assets/audio/sfx/client/137__M26-3.wav','assets/audio/sfx/client/10332__M33-3.wav'):
                target=stage/path; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(b'owned')
            metadata=stage/'scripts/features/generated/internal_code_android_export_data.gd'
            metadata.parent.mkdir(parents=True); metadata.write_text('extends RefCounted\nconst AVAILABLE := false\n',encoding='utf-8')
            for name in ('catalogue.gd','plan.json','producer.py','template.apk','baseline.apk','signer.cmd'):
                (inputs/name).write_bytes(b'owned')
            (bridge/'inject_sources_resign.ps1').write_text('# export fixture owns no signing\n',encoding='utf-8')
            quote=lambda value: "'"+str(value).replace("'","''")+"'"
            command="$ErrorActionPreference='Stop'; Set-StrictMode -Version 2.0\n"
            command+=' . '+quote(bridge/HOOK.name)+'\n'
            command+='$Stage='+quote(stage)+'; $InputsDir='+quote(inputs)+'; $Evidence='+quote(evidence)+'; $PythonExe='+quote(sys.executable)+'\n'
            command+=r'''
function Invoke-CodeOfficialExport([string]$GodotConsole,[string]$StageRoot,[string]$Apk,[string]$EvidenceRoot,[string]$Name) {
    [IO.File]::WriteAllBytes($Apk,[Text.Encoding]::UTF8.GetBytes('owned-'+$Name))
    return @{native_exit=0;apk=$Apk;apk_sha256=(Get-CodeExportHash $Apk)}
}
function Assert-CodeExportSigner([string]$Apk,[string]$BaselineApk,[string]$ApkSigner) {
    return @{status='OWNED_TEST_STUB';certificate_sha256=@('owned')}
}
$Generate={ param($StageRoot,$EvidenceRoot)
    $namespace=Join-Path $InputsDir 'namespace.json'
    @{engine=@{binary_sha256=(Get-CodeExportHash $PythonExe)};project_godot_sha256=(Get-CodeExportHash (Join-Path $StageRoot 'project.godot'));global_script_class_cache_sha256=(Get-CodeExportHash (Join-Path $StageRoot '.godot/global_script_class_cache.cfg'))} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $namespace -Encoding UTF8
    return @{SourceCatalogue=(Join-Path $InputsDir 'catalogue.gd');SourcePlan=(Join-Path $InputsDir 'plan.json');Producer=(Join-Path $InputsDir 'producer.py');Namespace=$namespace;EntryId='owned'}
}
$Verify={param($Apk,$Commit) Write-Output 'OWNED_PACKAGE_VERIFY'}
try {
    $value=Invoke-TwoPassAndroidCodeExport -StageRoot $Stage -GodotConsole $PythonExe -Python $PythonExe -OutputApk (Join-Path $Evidence 'final.apk') -EvidenceRoot $Evidence -SourceCommit 'owned-commit' -TemplateApk (Join-Path $InputsDir 'template.apk') -ExpectedTemplateSha256 (Get-CodeExportHash (Join-Path $InputsDir 'template.apk')) -BaselineApk (Join-Path $InputsDir 'baseline.apk') -ApkSigner (Join-Path $InputsDir 'signer.cmd') -RegenerateStageCatalogue $Generate -VerifyProductionBuild $Verify
    $result=@{success=$true;type=$value.GetType().FullName;apk_sha256=$value.apk_sha256}
} catch { $result=@{success=$false;error=$_.Exception.Message} }
$json=$result|ConvertTo-Json -Compress
[Console]::WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))
'''
            encoded=base64.b64encode(command.encode('utf-16-le')).decode('ascii')
            env=os.environ.copy(); env['HC_OWNED_EXPORT_FAIL']=fail
            run=subprocess.run([shell,'-NoProfile','-NonInteractive','-EncodedCommand',encoded],stdin=subprocess.DEVNULL,capture_output=True,env=env,timeout=30)
            self.assertEqual(run.returncode,0,run.stderr.decode(errors='replace'))
            result=json.loads(base64.b64decode(run.stdout.strip().splitlines()[-1]))
            logs={p.name:p.read_bytes() for p in evidence.glob('*.log')} if evidence.exists() else {}
            return result,logs

    def test_full_function_returns_only_one_apk_record(self):
        result,logs=self.probe()
        self.assertTrue(result['success'],result)
        self.assertEqual(result['type'],'System.Collections.Hashtable')
        self.assertEqual(len(result['apk_sha256']),64)
        self.assertIn(b'build_android_seal',logs.get('build-seal.stdout.log',b''))
        self.assertIn(b'verify_final_export',logs.get('final-verify.stdout.log',b''))

    def test_seal_native_failure_is_not_success(self):
        result,logs=self.probe('build_android_seal')
        self.assertFalse(result['success'],result)
        self.assertIn(b'owned tool failure',logs.get('build-seal.stderr.log',b''))

    def test_final_verifier_native_failure_is_not_success(self):
        result,logs=self.probe('verify_final_export')
        self.assertFalse(result['success'],result)
        self.assertIn(b'owned tool failure',logs.get('final-verify.stderr.log',b''))

if __name__=='__main__': unittest.main(verbosity=2)
