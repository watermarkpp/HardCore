from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,os,subprocess,shutil
BASE=Path(__file__).resolve().parent
ROOT=Path('C:\\Users\\Administrator\\.codex\\worktrees\\multicore-v115\\HardCore')
ENGINE=Path('C:/Users/Administrator/Documents/HardCore-engine-v115/godot')
OUT=BASE/'windows_map_reply_observation_20261017_build';OUT.mkdir(exist_ok=False)
SEAL=BASE/'SOURCE_MANIFEST.map_reply_observation_20261017.json'
expected='0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178'
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
if sha(SEAL)!=expected:raise RuntimeError('Manifest differs')
m=json.loads(SEAL.read_text(encoding='utf-8-sig'))
def verify():
 for x in m['changed_files']+m['module_inputs']:
  p=(ENGINE if x['root']=='engine' else ROOT)/x['relative_path']
  if not p.is_file() or sha(p)!=x['sha256']:raise RuntimeError('Source changed '+str(p))
verify()
cmd=OUT/'build.cmd'
scons=ROOT/'outputs/v115_multicore/build_prep/venv/Scripts/scons.exe'
vs=Path('C:/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/Common7/Tools/VsDevCmd.bat')
cmd.write_text('@echo off\nset "PYTHONHOME="\nset "PYTHONPATH="\ncall "'+str(vs)+'" -arch=x64 -host_arch=x64\nif errorlevel 1 exit /b %errorlevel%\n"'+str(scons)+'" -C "'+str(ENGINE)+'" platform=windows target=editor arch=x86_64 precision=single debug_symbols=no production=yes hardcore_native_source_sha256=58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8 -j2\nexit /b %errorlevel%\n',encoding='utf-8')
r={'status':'RUNNING','started':datetime.now(timezone.utc).isoformat(),'scope':'Actual readonly Map reply observation metadata Native; fixed source/pre-post/actual PE required. Whole game and Android acceptance remain NOT_RUN.','manifest_sha256':expected,'source_sha256':m['source_sha256'],'artifacts':[]}
def save():(OUT/'BUILD_RECEIPT.json').write_text(json.dumps(r,indent=2),encoding='utf-8')
try:
 save()
 with (OUT/'scons.stdout.log').open('wb') as out,(OUT/'scons.stderr.log').open('wb') as err:
  p=subprocess.Popen([os.environ.get('COMSPEC','C:/Windows/System32/cmd.exe'),'/d','/c',str(cmd)],cwd=ENGINE,stdout=out,stderr=err)
  r['pid']=p.pid;save();print(json.dumps({'pid':p.pid,'stage':'windows_native_incremental'}),flush=True);p.wait()
 r['exit_code']=p.returncode
 if p.returncode:raise RuntimeError('SCons failed')
 verify()
 for source_name,target_name in [('godot.windows.editor.x86_64.console.exe','Godot_v115-stable_win64_console.exe'),('godot.windows.editor.x86_64.exe','Godot_v115-stable_win64.exe')]:
  source=ENGINE/'bin'/source_name
  if not source.is_file():raise RuntimeError('Missing '+source_name)
  dest=OUT/target_name;shutil.copy2(source,dest)
  if sha(dest)!=sha(source):raise RuntimeError('Copy mismatch')
  r['artifacts'].append({'path':str(dest),'bytes':dest.stat().st_size,'sha256':sha(dest)})
 r['status']='BUILD_WINDOWS_ONLY_PASS';r['finished']=datetime.now(timezone.utc).isoformat();save();print(json.dumps(r,indent=2),flush=True)
except BaseException as e:
 r.update(status='FAIL',error=repr(e),finished=datetime.now(timezone.utc).isoformat());save();print(json.dumps({'status':'FAIL','error':repr(e)}),flush=True);raise
