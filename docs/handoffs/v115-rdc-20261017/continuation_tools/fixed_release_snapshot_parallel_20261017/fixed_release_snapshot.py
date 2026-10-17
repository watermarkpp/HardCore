"""Formal gated CLI. This module has no component/mock/force gate override."""
from pathlib import Path
import argparse, json, re, sys
from fixed_release_objects import *
from isolated_git import input_rows

R=Path('C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore')
E=Path('C:/Users/Administrator/Documents/HardCore-engine-v115/godot')
OUT=Path(__file__).resolve().parent
HEAD='45170d0eaf4d2c642d4a03de392f64fa2b1e25bf'
INDEX_SHA='3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22'
AGG='58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8'
NATIVE_SHA='0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178'
CONSOLE_SHA='1b69c0d26f54df88301791e5f3dbd43f7e20aad30a727addfff3287ea9d11c91'
MAIN_SHA='7f54a5090cfde94a7d2fcf37c22c14ecd23e00eefcc0bf5e23d1c0326bc7b8de'
load=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
file_sha=lambda p:sha(Path(p).read_bytes())

def real_layout(root):
    root=Path(root).absolute();require(root==R,'wrong production root');physical(root,root)
    line=(root/'.git').read_text().strip()
    require(line.startswith('gitdir: '),'exact managed-worktree gitfile required')
    gd=Path(line.removeprefix('gitdir: ')).absolute()
    expected=Path('C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore1')
    require(gd==expected and gd.is_dir(),'wrong real Git directory')
    common=(gd/(gd/'commondir').read_text().strip()).resolve(strict=True)
    require(common==Path('C:/Users/Administrator/Documents/HardCore/.git'),'wrong common Git directory')
    physical(gd,common);require((gd/'HEAD').read_text().strip()==HEAD,'actual detached HEAD differs')
    require(file_sha(gd/'index')==INDEX_SHA,'actual protected index differs')
    return gd,common

def real_custody(root):
    gd,common=real_layout(root);facts={}
    paths=[gd/'index',gd/'HEAD',common/'HEAD',common/'config',common/'packed-refs']
    for folder in (common/'refs',gd/'refs'):
        if folder.exists():paths.extend(p for p in folder.rglob('*') if p.is_file())
    for p in paths:
        physical(p,common);facts[str(p)]=file_sha(p) if p.exists() else None
    return facts

def pinned(row):
    require(isinstance(row,dict) and isinstance(row.get('path'),str) and re.fullmatch('[0-9a-f]{64}',row.get('sha256',''))!=None,'pinned file path/SHA required')
    p=physical(Path(row['path']).absolute(),R)
    require(p.is_file() and file_sha(p)==row['sha256'],'pinned file drift: '+str(p))
    return p

def validate_world(gate,source):
    require(source==R,'wrong World source root')
    runner_path=pinned(gate.get('runner_result'));protection_path=pinned(gate.get('protection'));manifest_path=pinned(gate.get('source_manifest'))
    runner=load(runner_path);protection=load(protection_path);rows=load(manifest_path)
    require(isinstance(rows,list) and rows,'World source manifest missing')
    matches=[r for r in runner.get('results',[]) if r.get('test_name')=='character_source_full_world_20261016']
    require(len(matches)==1,'one actual World start/normal-exit scene required');test=matches[0]
    require(test.get('result')=='PASS' and test.get('effective_exit_code')==0 and test.get('timeout') is False and test.get('framework_receipt_valid') is True and runner.get('engine_log_errors')==0,'BLOCKED: real World/native/engine PASS missing')
    require(protection.get('source_unchanged') is True and protection.get('real_index_preserved') is True and protection.get('native_runner_exit')==0,'BLOCKED: real World source/index/native protection missing')
    require(test.get('source_content_sha256')==file_sha(manifest_path),'World source receipt/manifest mismatch')
    warning=test.get('cleanup_warning_evidence',{})
    require(warning.get('status')=='PASS' and warning.get('objectdb_leak_warning_count')==0,'World cleanup leak evidence missing')
    fingerprints={r.get('sha256') for r in test.get('engine_fingerprints',[])+runner.get('engine_fingerprints',[])}
    require({CONSOLE_SHA,MAIN_SHA}<=fingerprints,'World used a different actual Windows pair')
    paths=set()
    for row in rows:
        rel=relative(row['path']);require(rel.casefold() not in paths,'duplicate World source path');paths.add(rel.casefold())
    input_rows(source,rows) # Includes .godot/outputs/override witness inputs, though these are not shipped.
    require(any(r['path']=='project.godot' for r in rows) and any(r['path'].startswith('scripts/') for r in rows) and any(r['path'].startswith('assets/') for r in rows),'incomplete World source manifest')
    return {'runner':str(runner_path),'protection':str(protection_path),'manifest':str(manifest_path),'manifest_sha256':file_sha(manifest_path),'files':rows,'run_id':test.get('framework_run_id')}

def validate_native():
    base=R/'outputs/v115_multicore/codex_resume_20261015_182255'
    manifest=base/'SOURCE_MANIFEST.map_reply_observation_20261017.json'
    require(file_sha(manifest)==NATIVE_SHA,'fixed Native manifest differs');m=load(manifest)
    require(m.get('source_sha256')==AGG and len(m.get('module_inputs',[]))==74 and len(m.get('changed_files',[]))==95 and len(m.get('reviewed_gd_seals',[]))==5,'fixed Native169/five-role schema differs')
    for row in m['module_inputs']+m['changed_files']:
        root=R if row['root']=='project' else E if row['root']=='engine' else None
        require(root is not None,'unknown Native input root');input_rows(root,[row])
    for row in m['reviewed_gd_seals']:input_rows(R,[{'path':row['path'],'sha256':row['after']}])
    console=base/'windows_map_reply_observation_20261017_build/Godot_v115-stable_win64_console.exe'
    main=console.with_name('Godot_v115-stable_win64.exe')
    require(file_sha(console)==CONSOLE_SHA and file_sha(main)==MAIN_SHA and AGG.encode() in main.read_bytes(),'fixed actual PE pair/embedded Native identity differs')
    return {'manifest_sha256':NATIVE_SHA,'native_source_sha256':AGG,'inputs':169,'sealed_roles':5,'console_sha256':CONSOLE_SHA,'main_sha256':MAIN_SHA}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world-gate',type=Path,required=True,help='JSON with pinned runner_result/protection/source_manifest facts')
    parser.add_argument('--output',type=Path,required=True,help='New physical child directory inside this exclusive delivery')
    parser.add_argument('--publish-common-objects',action='store_true',help='After all gates, add verified immutable loose objects to the real common objects DB; no refs/index changes')
    args=parser.parse_args()
    output=physical(args.output.absolute(),OUT);require(output!=OUT and not output.exists(),'new exclusive output required')
    real_before=real_custody(R);gate=load(args.world_gate);world=validate_world(gate,R);native=validate_native()
    gd,common=real_layout(R)
    rows=inventory(R);require({'project.godot','export_presets.cfg'}<={r['path'] for r in rows},'formal project/export inputs missing')
    # Every measured source asset is included, not merely assets/data.
    shipped={r['path']:r['sha256'] for r in rows}
    for row in world['files']:
        if row['path']=='project.godot' or row['path'].startswith(('scripts/','scenes/','assets/','tools/','tests/')):
            require(shipped.get(row['path'])==row['sha256'],'measured input excluded or changed: '+row['path'])
    output.mkdir(parents=True)
    box=GitSandbox(output/'objects_workspace',OUT);box.initialize(HEAD,common/'objects')
    built=build_from_rows(box,R,rows,HEAD)
    built['archive']=verify_archive(box,built['commit'],rows)
    require(inventory(R)==rows,'source changed before final approval/publication')
    validate_world(gate,R);validate_native();require(real_custody(R)==real_before,'real index/HEAD/refs changed')
    publication={'status':'NOT_RUN'}
    if args.publish_common_objects:
        publication=publish_additive(box,common/'objects',common/'objects')
        require(real_custody(R)==real_before,'real custody changed during additive object publication')
    result={'status':'PASS','scope':'FIXED_RAW_BUILD_OBJECT','production_commit_object_created_in_private_db':True,'common_object_publication':publication,'world':world,'native':native,'build':built,'real_custody_before':real_before,'real_custody_after':real_custody(R),'build_command_after_publication':['pwsh','-NoProfile','-File',str(R/'tools/build_android_isolated.ps1'),'-Commit',built['commit']]}
    (output/'FIXED_RELEASE_RESULT.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'PASS','commit':built['commit'],'common_objects':publication['status'],'receipt':str(output/'FIXED_RELEASE_RESULT.json')}))

if __name__=='__main__':
    try:main()
    except Exception as exc:print('BLOCKED/FAIL: '+str(exc),file=sys.stderr);sys.exit(1)
