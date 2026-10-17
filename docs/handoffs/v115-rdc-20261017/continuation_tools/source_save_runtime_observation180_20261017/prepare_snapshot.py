from pathlib import Path
import argparse, hashlib, json, os, shutil, stat
from isolated_git import GitSandbox, physical, input_rows
TOOL_ROOT=Path(__file__).resolve().parent
O=TOOL_ROOT.parent if TOOL_ROOT.name=="candidate" else TOOL_ROOT
R=O.parents[2]
LEGACY=R/"outputs/v115_multicore/source_save_roundtrip_parallel_20261017"
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def physical_files(root):
 for current,dirs,files in os.walk(root,followlinks=False):
  for name in dirs+files:
   p=Path(current)/name
   if getattr(p.lstat(),"st_file_attributes",0)&stat.FILE_ATTRIBUTE_REPARSE_POINT:raise RuntimeError("physical snapshot cannot copy reparse path: "+str(p))
  for name in files:yield Path(current)/name
p=argparse.ArgumentParser();p.add_argument("--destination",type=Path,required=True);p.add_argument("--upstream-source-manifest",type=Path,required=True);p.add_argument("--native-manifest",type=Path,default=R/"outputs/v115_multicore/codex_resume_20261015_182255/SOURCE_MANIFEST.map_reply_observation_20261017.json");a=p.parse_args();dest=physical(a.destination,O)
if O not in dest.parents or dest.exists():raise SystemExit("new snapshot directory must be inside this authorized output; never overwrite a prior snapshot")
manifest=json.loads(a.upstream_source_manifest.read_text(encoding="utf-8-sig"))
input_rows(R,[x for x in manifest if x["path"].startswith(("scripts/","scenes/","assets/",".godot/","tools/")) or x["path"]=="project.godot"])
if sha(a.native_manifest)!="0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178":raise SystemExit("fixed58a1 Native manifest digest required")
native=json.loads(a.native_manifest.read_text(encoding="utf-8-sig"))
if native.get("source_sha256")!="58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8":raise SystemExit("fixed58a1 Native aggregate required")
native_project=[x for x in native["module_inputs"] if x["root"]=="project"]
input_rows(R,native_project)
input_rows(R,[{"path":x["path"],"sha256":x["after"]} for x in native["reviewed_gd_seals"]])
for row in manifest:
 if row["path"].startswith(("scripts/","scenes/","assets/",".godot/","tools/")) or row["path"]=="project.godot":
  if sha(R/row["path"])!=row["sha256"]:raise SystemExit("upstream/current source drift: "+row["path"])
files=[R/x["relative_path"] for x in native_project]
for folder in ["scripts","assets","scenes","tests",".godot/imported"]:
 files.extend(physical_files(R/folder))
files.extend(x for x in (R/"tools").glob("*.ps1") if x.is_file())
for rel in ["project.godot","override.cfg",".godot/global_script_class_cache.cfg",".godot/uid_cache.bin"]:
 f=R/rel
 if f.is_file():files.append(f)
rows=[]
for f in sorted(set(files)):
 rel=f.relative_to(R);before=sha(f);q=dest/rel;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,q)
 if sha(q)!=before or sha(f)!=before:raise SystemExit("copy source drift: "+str(rel))
 rows.append({"path":rel.as_posix(),"sha256":before,"bytes":q.stat().st_size})
# Global freeze check closes cross-file time-of-copy races, not only each file.
for row in rows:
 if sha(R/row["path"])!=row["sha256"]:raise SystemExit("source changed during snapshot: "+row["path"])
router="scripts/gameplay/source/main_root_checkpoint_router.gd"
binding=json.loads((LEGACY/"ROUTER_ARITY_BINDING.json").read_text())
if sha(dest/router) not in [binding["preimage_sha256"],binding["candidate_sha256"]]:raise SystemExit("router parent drift requires exact hunk review")
input_rows(dest,json.loads((O/"SOURCE_SAVE_FIXTURE_BINDING.json").read_text(encoding="utf-8"))["files"])
git=GitSandbox(dest,O)
git_paths=git.initialize()
input_rows(dest,native_project)
input_rows(dest,[{"path":x["path"],"sha256":x["after"]} for x in native["reviewed_gd_seals"]])
(dest/"SNAPSHOT_BINDING.json").write_text(json.dumps({"status":"PASS","scope":"copy/freeze only; no Source World execution","snapshot":str(dest),"HEAD":"45170d0eaf4d2c642d4a03de392f64fa2b1e25bf","upstream_manifest_sha256":sha(a.upstream_source_manifest),"native_manifest_sha256":sha(a.native_manifest),"copied_original_inputs":rows,"candidate_overlay":str(LEGACY/"CANDIDATE_BINDING.json"),"git_paths":git_paths},indent=2)+"\n")
print(str(dest))
