"""Actual private Git objects/archive tests, explicitly NOT World evidence."""
from pathlib import Path
import json, os, shutil, sys, traceback
import fixed_release_objects as F
from isolated_git import GitSandbox, IsolationError

OUT=Path(__file__).resolve().parent
RUN=OUT/'component_run'
checks=[]
def check(name,condition):
    checks.append({'name':name,'status':'PASS' if condition else 'FAIL'})
def rejects(name,fn):
    try:fn()
    except Exception:check(name,True)
    else:check(name,False)

def owned_box(name):
    box=GitSandbox(RUN/name,OUT)
    box.workspace.mkdir(parents=True)
    for rel in ('objects/info','refs'):(box.git_dir/rel).mkdir(parents=True,exist_ok=True)
    (box.git_dir/'HEAD').write_text('0'*40+'\n')
    (box.git_dir/'config').write_text('[core]\nrepositoryformatversion = 0\nbare = false\nfilemode = false\nautocrlf = true\nlogallrefupdates = false\n')
    (box.git_dir/'codex-isolated.json').write_text(json.dumps({'workspace':str(box.workspace),'git_dir':str(box.git_dir),'index':str(box.index),'ceiling':str(box.root)}))
    box.verify()
    tree=F.object_write(box,'tree',b'')
    base=F.object_write(box,'commit',('tree '+tree+'\nauthor Component <test@invalid.local> 0 +0000\ncommitter Component <test@invalid.local> 0 +0000\n\nComponent bootstrap\n').encode())
    (box.git_dir/'HEAD').write_text(base+'\n')
    box.mutate(['read-tree',base]);box.verify()
    return box,base

def put(root,rel,data):
    p=root/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)

def main():
    F.require(not RUN.exists(),'component evidence already exists')
    RUN.mkdir()
    real_index=Path('C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore1/index')
    index_before=F.sha(real_index.read_bytes())
    box,bootstrap=owned_box('source')
    source=RUN/'raw_source';source.mkdir()
    initial={'project.godot':b'[application]\r\nconfig/name="Component"\r\n','export_presets.cfg':b'[preset.0]\r\nname="Android"\r\n','scripts/deleted.gd':b'extends RefCounted\n'}
    for path,data in initial.items():put(source,path,data)
    baseline=F.build_from_rows(box,source,F.inventory(source),bootstrap)
    (box.git_dir/'HEAD').write_text(baseline['commit']+'\n');box.mutate(['read-tree',baseline['commit']])
    (source/'scripts/deleted.gd').unlink()
    expected={**{k:v for k,v in initial.items() if k!='scripts/deleted.gd'},'scripts/LF.gd':b'extends RefCounted\n# LF\n','scripts/CRLF.gd':b'extends RefCounted\r\n# CRLF\r\n','scenes/example.tscn':b'[gd_scene format=3]\n[node name="Example" type="Node"]\n','assets/ui/icon.png':b'\x89PNG\r\n\x1a\n\x00\xff\x00raw\r\n','tools/fresh.ps1':b'Write-Output "new untracked"\r\n','tests/component.gd':b'extends RefCounted\n'}
    for path,data in expected.items():put(source,path,data)
    for rel in ('outputs/ignored.txt','.godot/cache.bin','tools/godot-4.7/private.exe','tools/signing.jks','.env','tools/credentials.json'):
        put(source,rel,b'component excluded data')
    before=F.custody(box);rows=F.inventory(source)
    check('current inventory includes all allowed dirty/untracked bytes',set(r['path'] for r in rows)==set(expected))
    built=F.build_from_rows(box,source,rows,baseline['commit'])
    archive=F.verify_archive(box,built['commit'],rows)
    check('actual Git archive validates all raw byte SHA including PNG and scene/project',archive['raw_bytes_verified'] and archive['files']==len(expected))
    for path,data in expected.items():
        blob=F.run(box,['cat-file','blob',built['commit']+':'+path])
        check('actual Git blob raw bytes '+path,blob==data)
    rejects('tracked deletion absent from fixed commit',lambda:F.run(box,['cat-file','blob',built['commit']+':scripts/deleted.gd']))
    check('parent identity retained',F.run(box,['cat-file','-p',built['commit']]).splitlines()[1]==('parent '+baseline['commit']).encode())
    check('private HEAD/index/config/refs unchanged',F.custody(box)==before)
    again=F.build_from_rows(box,source,rows,baseline['commit'])
    check('identical raw snapshot deterministic commit',again['commit']==built['commit'])
    check('source raw bytes unchanged',all((source/p).read_bytes()==v for p,v in expected.items()))
    put(source,'scripts/LF.gd',b'changed\n')
    rejects('content drift rejected before fixed snapshot accepted',lambda:F.build_from_rows(box,source,rows,baseline['commit']))
    put(source,'scripts/LF.gd',expected['scripts/LF.gd'])
    put(source,'scripts/late.gd',b'late\n')
    rejects('roster drift rejected',lambda:F.build_from_rows(box,source,rows,baseline['commit']))
    (source/'scripts/late.gd').unlink()
    rejects('path escape rejected',lambda:F.build_from_rows(box,source,[{'path':'../escape','bytes':0,'sha256':'0'*64}],baseline['commit']))
    rejects('absolute path rejected',lambda:F.relative('C:/escape'))
    rejects('backslash path rejected',lambda:F.relative('assets\\escape'))
    rejects('duplicate source path rejected',lambda:F.build_from_rows(box,source,rows+rows[:1],baseline['commit']))
    rejects('excluded credential input rejected',lambda:F.build_from_rows(box,source,[{'path':'tools/key.jks','bytes':0,'sha256':'0'*64}],baseline['commit']))
    put(source,'tools/embedded.txt',b'-----BEGIN PRIVATE KEY-----\ncomponent\n')
    rejects('embedded private key refused',lambda:F.inventory(source));(source/'tools/embedded.txt').unlink()
    put(source,'export_presets.cfg',b'keystore/release_password="component-secret"\n')
    rejects('embedded export password refused',lambda:F.inventory(source));put(source,'export_presets.cfg',expected['export_presets.cfg'])
    link=source/'assets/foreign'
    try:
        link.symlink_to(RUN/'raw_source/scripts',target_is_directory=True)
    except OSError as exc:checks.append({'name':'actual symlink source negative','status':'NOT_RUN','reason':str(exc)})
    else:
        rejects('actual symlink source rejected',lambda:F.inventory(source));link.unlink()
    marker=box.git_dir/'codex-isolated.json';original=marker.read_bytes();marker.write_text('{}')
    rejects('wrong private root marker rejected',box.verify);marker.write_bytes(original)
    (box.git_dir/'refs/heads').mkdir();ref=box.git_dir/'refs/heads/component';ref.write_text(bootstrap+'\n')
    check('refs mutation visible to custody guard',F.custody(box)!=before);ref.unlink()
    raw_index=box.index.read_bytes();box.index.write_bytes(raw_index+b'wrong')
    check('index mutation visible to custody guard',F.custody(box)!=before);box.index.write_bytes(raw_index)
    old=os.environ.get('GIT_DIR');os.environ['GIT_DIR']='C:/definitely-wrong-real-git'
    old_obj=os.environ.get('GIT_OBJECT_DIRECTORY');os.environ['GIT_OBJECT_DIRECTORY']='C:/foreign-objects'
    try:
        env=box.environment();box.verify()
        check('ambient Git redirection discarded',env['GIT_DIR']==str(box.git_dir) and 'GIT_OBJECT_DIRECTORY' not in env and env['GIT_WORK_TREE']==str(box.workspace) and env['GIT_INDEX_FILE']==str(box.index) and env['GIT_CEILING_DIRECTORIES']==str(OUT))
    finally:
        if old is None:os.environ.pop('GIT_DIR',None)
        else:os.environ['GIT_DIR']=old
        if old_obj is None:os.environ.pop('GIT_OBJECT_DIRECTORY',None)
        else:os.environ['GIT_OBJECT_DIRECTORY']=old_obj
    target,target_base=owned_box('destination');target_before=F.custody(target)
    objects_before={p.relative_to(target.git_dir/'objects').as_posix():F.sha(p.read_bytes()) for p in (target.git_dir/'objects').rglob('*') if p.is_file()}
    published=F.publish_additive(box,target.git_dir/'objects',target.git_dir/'objects')
    check('actual publication added immutable objects',len(published['added_objects'])>0)
    check('publication preserves destination old object bytes',all(F.sha((target.git_dir/'objects'/p).read_bytes())==v for p,v in objects_before.items()))
    check('publication preserves destination HEAD/index/config/refs',F.custody(target)==target_before)
    check('destination actual Git archive resolves published commit without source alternates',F.verify_archive(target,built['commit'],rows)['status']=='PASS')
    check('repeat publication adds no duplicate objects',F.publish_additive(box,target.git_dir/'objects',target.git_dir/'objects')['added_objects']==[])
    rejects('wrong publication object root rejected',lambda:F.publish_additive(box,target.git_dir/'objects',RUN/'wrong-objects'))
    oid=next(iter(published['added_objects']));dst=target.git_dir/'objects'/oid[:2]/oid[2:];good=dst.read_bytes();dst.write_bytes(b'corrupt')
    rejects('corrupt existing object refused without overwrite',lambda:F.publish_additive(box,target.git_dir/'objects',target.git_dir/'objects'))
    check('corrupt existing destination not overwritten',dst.read_bytes()==b'corrupt');dst.write_bytes(good)
    check('original source custody still unchanged',F.custody(box)==before)
    check('real index read-only hash preserved',F.sha(real_index.read_bytes())==index_before)
    # Formal CLI negative uses no fabricated positive World artifacts.
    import fixed_release_snapshot as CLI
    rejects('formal CLI wrong production root rejected',lambda:CLI.real_layout(source))
    rejects('formal World gate requires pinned actual three evidence files',lambda:CLI.validate_world({},CLI.R))
    report={'status':'PASS' if all(x['status']!='FAIL' for x in checks) else 'FAIL','scope':'PRIVATE_GIT_COMPONENT_ONLY_NOT_WORLD','checks':len(checks),'failed':sum(x['status']=='FAIL' for x in checks),'not_run':sum(x['status']=='NOT_RUN' for x in checks),'details':checks,'baseline_commit':baseline['commit'],'fixed_commit':built['commit'],'archive':archive,'publication':published,'real_index_before':index_before,'real_index_after':F.sha(real_index.read_bytes()),'production_snapshot':'NOT_RUN','production_publication':'NOT_RUN','command':sys.executable+' '+str(Path(__file__).resolve())}
    (OUT/'COMPONENT_RESULT.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':report['status'],'checks':report['checks'],'failed':report['failed'],'not_run':report['not_run']}))
    return 0 if report['status']=='PASS' else 1

if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception:traceback.print_exc();raise
