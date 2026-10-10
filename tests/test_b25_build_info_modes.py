import json, os, shutil, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'tools/generate_build_info.ps1'

def fixture(tmp_path):
    def git(*args,input=None):
        return subprocess.check_output(['git',*args],cwd=tmp_path,input=input).decode().strip()
    git('init','-q');git('config','user.name','Scratch');git('config','user.email','scratch@example.invalid')
    git('config','core.filemode','false');git('config','core.autocrlf','false')
    (tmp_path/'project.godot').write_text('config/version="1.0"\n')
    (tmp_path/'export_presets.cfg').write_text('version/code=109\n')
    (tmp_path/'sample.txt').write_bytes(b'same\r\n')
    git('add','.');git('commit','-qm','fixture')
    return git

def invoke(tmp_path,allow=True):
    command=[shutil.which('pwsh'),'-NoProfile','-File',str(SCRIPT),'-StageRoot',str(tmp_path)]
    if allow:command.append('-AllowDirty')
    result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8')
    output=tmp_path/'assets/generated/build_info.json'
    return result,json.loads(output.read_bytes()) if output.exists() else None

def test_raw_equal_content_exemption_preserves_unchanged_mode(tmp_path):
    git=fixture(tmp_path)
    # HEAD stores CRLF, while the clean filter now maps working CRLF to LF.
    git('config','core.autocrlf','true')
    (tmp_path/'.git/info/attributes').write_text('sample.txt text\n')
    stamp=(tmp_path/'sample.txt').stat().st_mtime+5
    os.utime(tmp_path/'sample.txt',(stamp,stamp))
    assert subprocess.run(['git','diff-index','--quiet','HEAD','--'],cwd=tmp_path).returncode==1
    result,info=invoke(tmp_path,False)
    assert result.returncode==0,result.stderr
    assert info['git_dirty'] is False

def test_equal_bytes_mode_only_change_stays_dirty(tmp_path):
    git=fixture(tmp_path)
    git('update-index','--chmod=+x','sample.txt')
    result,info=invoke(tmp_path)
    assert result.returncode==0,result.stderr
    assert info['git_dirty'] is True

def test_mode_change_default_build_is_rejected_before_publication(tmp_path):
    git=fixture(tmp_path);git('update-index','--chmod=+x','sample.txt')
    result,info=invoke(tmp_path,False)
    assert result.returncode!=0
    assert info is None
    assert 'Working tree is dirty' in result.stderr

def test_content_change_stays_dirty(tmp_path):
    fixture(tmp_path);(tmp_path/'sample.txt').write_text('changed\n')
    result,info=invoke(tmp_path)
    assert result.returncode==0,result.stderr
    assert info['git_dirty'] is True
