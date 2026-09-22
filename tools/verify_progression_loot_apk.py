"""Verify payload identity and frozen prior-version assets against the source commit."""
import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def parsed(data):
    return json.loads(data.rstrip(b'\x00').decode('utf-8-sig'))
def digest(data):
    return hashlib.sha256(data).hexdigest()
def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args])

def main():
    p=argparse.ArgumentParser()
    for arg in ['apk','baseline','commit','output']: p.add_argument('--'+arg,required=True)
    p.add_argument('--version-code',type=int,default=80)
    a=p.parse_args()
    with zipfile.ZipFile(a.apk) as current, zipfile.ZipFile(a.baseline) as baseline:
        info=parsed(current.read('assets/assets/generated/build_info.json'))
        old=parsed(baseline.read('assets/assets/generated/build_info.json'))
        assert info['git_head']==a.commit and info['git_dirty'] is False
        assert info['version_code']==a.version_code and old['version_code']==a.version_code-1
        assert info['version_name']=='hardcore 1.0 正式版'
        changed=set(git('diff','--name-only',old['git_head'],a.commit,'--','scripts','assets/data').decode().splitlines())
        script_changes={'assets/'+s[:-3]+'.gdc' for s in changed if s.startswith('scripts/') and s.endswith('.gd')}
        data_changes={'assets/'+s for s in changed if s.startswith('assets/data/')}
        names=set(current.namelist()); old_names=set(baseline.namelist())
        observed=set(); frozen_scripts=0; frozen_data=0
        for name in sorted(old_names):
            if name.startswith('assets/scripts/') and name.endswith('.gdc'):
                assert name in names, 'MISSING_SCRIPT:'+name
                different=current.read(name)!=baseline.read(name)
                assert different==(name in script_changes),'SCRIPT_CHANGE_SCOPE:'+name
                if different: observed.add(name)
                else: frozen_scripts+=1
            if name.startswith('assets/assets/') and name not in data_changes and name!='assets/assets/generated/build_info.json':
                assert name in names and current.read(name)==baseline.read(name),'FROZEN_ASSET:'+name
                frozen_data+=1
        new_scripts={n for n in names-old_names if n.startswith('assets/scripts/') and n.endswith('.gdc')}
        observed.update(new_scripts)
        assert observed==script_changes, 'SCRIPT_INVENTORY:'+str(observed^script_changes)
        for name in data_changes:
            relative=name.removeprefix('assets/')
            expected=git('show',a.commit+':'+relative)
            assert parsed(current.read(name))==parsed(expected), 'DATA_SOURCE_DRIFT:'+name
        assert not any(n.startswith(('assets/tests/','assets/docs/')) for n in names)
        report={'status':'PASS','source_commit':a.commit,'build_info':info,'baseline_commit':old['git_head'],
                'apk':a.apk,'size_bytes':Path(a.apk).stat().st_size,'sha256':digest(Path(a.apk).read_bytes()),
                'changed_scripts':sorted(script_changes),'new_scripts':sorted(new_scripts),'changed_data':sorted(data_changes),
                'unchanged_scripts':frozen_scripts,'unchanged_asset_entries':frozen_data,'device':'NOT_RUN'}
    Path(a.output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'V{a.version_code}_APK_PAYLOAD_PASS',report['sha256'],report['unchanged_asset_entries'])

if __name__=='__main__':main()
