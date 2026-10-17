"""Native policy/mailbox component only; not a Godot World or APK result."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    allowed = root / 'outputs' / 'v115_multicore'
    if allowed not in output.parents or output.exists():
        raise RuntimeError('A fresh component evidence directory inside this tree is required')
    output.mkdir(parents=True)
    inputs = [root / 'tests/caster_close_cleanup_policy_20261018_test.cpp',
              root / 'native/hardcore_simulation/source_caster_cleanup_policy.h',
              root / 'native/hardcore_simulation/source_event_reply_mailbox.h',
              root / 'native/hardcore_simulation/source_event_reply_mailbox.cpp',
              root / 'native/hardcore_simulation/source_event_issued_claim_attachment.cpp']
    def fingerprints():
        return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    before = fingerprints()
    vs = Path('C:/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/Common7/Tools/VsDevCmd.bat')
    exe = output / 'caster_cleanup.exe'
    cmd = output / 'run.cmd'
    cmd.write_text('@echo off\ncall "' + str(vs) + '" -arch=x64 -host_arch=x64 >nul\n'
                   'if errorlevel 1 exit /b 90\n'
                   'cl /nologo /std:c++17 /EHsc /W4 /I"' + str(inputs[1].parent) + '" "' + str(inputs[0]) + '" "' + str(inputs[3]) + '" "' + str(inputs[4]) + '" /Fo:"' + output.as_posix() + '/" /Fe:"' + str(exe) + '" >"' + str(output / 'compile.log') + '" 2>&1\n'
                   'if errorlevel 1 exit /b 91\n"' + str(exe) + '" >"' + str(output / 'native.log') + '" 2>&1\nexit /b %errorlevel%\n', encoding='utf-8')
    result = subprocess.run([os.environ.get('COMSPEC', 'C:/Windows/System32/cmd.exe'), '/d', '/c', str(cmd)], cwd=output, timeout=30)
    after = fingerprints()
    log = (output / 'native.log').read_text(encoding='utf-8', errors='replace') if (output / 'native.log').exists() else ''
    receipt = {'status': 'PASS' if result.returncode == 0 and before == after and 'CASTER_CLOSE_CLEANUP_POLICY_PASS' in log else 'FAIL',
               'scope': 'Actual Native cleanup policy and real two-owner SourceEventReplyMailbox only',
               'command': str(cmd), 'native_exit': result.returncode, 'source_unchanged': before == after,
               'inputs': before, 'native_output': log, 'World': 'NOT_RUN', 'APK': 'NOT_RUN'}
    (output / 'RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
