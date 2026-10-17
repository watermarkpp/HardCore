"""Run only after real upstream full-world proof; never fabricates Source readiness."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, sys
from isolated_git import GitSandbox, physical, input_rows
TOOL_ROOT=Path(__file__).resolve().parent
O=TOOL_ROOT.parent if TOOL_ROOT.name=="candidate" else TOOL_ROOT
R=O.parents[2]
LEGACY=R/"outputs/v115_multicore/source_save_roundtrip_parallel_20261017"
AGGREGATE="58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8"
CONSOLE="1b69c0d26f54df88301791e5f3dbd43f7e20aad30a727addfff3287ea9d11c91"
MAIN="7f54a5090cfde94a7d2fcf37c22c14ecd23e00eefcc0bf5e23d1c0326bc7b8de"
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path):return json.loads(Path(path).read_text(encoding="utf-8-sig"))
def require(ok,reason):
 if not ok:raise RuntimeError(reason)
def within(path,root):return path==root or root in path.parents
def verify_upstream(receipt_path,runner_path,manifest_path,snapshot):
 proof=read(receipt_path);runner=read(runner_path)
 require(proof.get("status")=="PASS" and proof.get("scene_id")=="character_source_full_world_20261016" and proof.get("failed")==0,"BLOCKED: actual full-world launch/exit proof required")
 matches=[x for x in runner.get("results",[]) if x.get("test_name")=="character_source_full_world_20261016"]
 require(len(matches)==1 and matches[0].get("effective_exit_code")==0 and matches[0].get("framework_receipt_valid")==True and not matches[0].get("timeout") and runner.get("engine_log_errors")==0 and runner.get("source_content_sha256")==proof.get("source_content_sha256") and matches[0].get("framework_run_id")==proof.get("run_id"),"BLOCKED: same real upstream native exit/engine result required")
 manifest=read(manifest_path);require(sum(x.get("path")=="project.godot" for x in manifest)==1,"upstream full-project configuration missing");input_rows(snapshot,[x for x in manifest if x["path"].startswith(("scripts/","scenes/","assets/",".godot/","tools/")) or x["path"]=="project.godot"]);require(sha(manifest_path)==proof.get("source_content_sha256"),"upstream source-manifest hash does not match receipt")
 for row in manifest:
  rel=row["path"]
  if rel.startswith(("scripts/","scenes/","assets/",".godot/","tools/")) or rel=="project.godot":
   current=snapshot/rel
   # This one reviewed command-router fix is covered by this block's exact binding.
   expected=sha(LEGACY/"candidate"/rel) if rel=="scripts/gameplay/source/main_root_checkpoint_router.gd" else row["sha256"]
   require(current.is_file() and sha(current)==expected,"upstream dependency differs: "+rel)
 return proof

def main():
 p=argparse.ArgumentParser();p.add_argument("--snapshot",type=Path,required=True);p.add_argument("--profile",choices=["warrior","wizard","taoist"],required=True);p.add_argument("--phase",choices=["deposit","withdraw"],required=True);p.add_argument("--label",required=True);p.add_argument("--engine",type=Path,required=True);p.add_argument("--upstream-receipt",type=Path,required=True);p.add_argument("--upstream-runner",type=Path,required=True);p.add_argument("--upstream-source-manifest",type=Path,required=True);p.add_argument("--prior-stage",type=Path);p.add_argument("--native-manifest",type=Path,default=R/"outputs/v115_multicore/codex_resume_20261015_182255/SOURCE_MANIFEST.map_reply_observation_20261017.json");p.add_argument("--native-manifest-sha256",default="0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178");p.add_argument("--native-source-sha256",default=AGGREGATE);p.add_argument("--console-sha256",default=CONSOLE);p.add_argument("--main-sha256",default=MAIN);a=p.parse_args()
 tool_binding=read(O/"CANDIDATE_BINDING.json")
 for tool in tool_binding["files"]:require(sha(TOOL_ROOT/tool["path"])==tool["candidate_sha256"],"reviewed runner guard changed:"+tool["path"])
 s=physical(a.snapshot,O);GitSandbox(s,O).verify();require(within(s,O) and s!=O and (s/"project.godot").is_file(),"snapshot must be a separate physical project inside authorized output")
 require(not s.is_symlink(),"physical original project required")
 require(a.label.replace("_","").replace("-","").isalnum(),"invalid unique runner label")
 require(sha(a.engine)==a.console_sha256 and sha(a.engine.with_name(a.engine.name.replace("_console.exe",".exe")))==a.main_sha256,"actual fixed console and PE hashes required")
 require(sha(a.native_manifest)==a.native_manifest_sha256,"immutable Native manifest digest mismatch")
 manifest=read(a.native_manifest)
 input_rows(s,[x for x in manifest["module_inputs"] if x["root"]=="project"])
 require(manifest["source_sha256"]==a.native_source_sha256 and len(a.native_source_sha256)==64,"actual pinned Native aggregate required")
 require(a.native_source_sha256.encode() in a.engine.with_name(a.engine.name.replace("_console.exe",".exe")).read_bytes(),"actual PE lacks complete pinned Native identity")
 for row in manifest["module_inputs"]:
  if row["root"]=="project":require(sha(s/row["relative_path"])==row["sha256"],"snapshot Native mismatch: "+row["relative_path"])
 for row in manifest["reviewed_gd_seals"]:require(sha(s/row["path"])==row["after"],"five-role seal mismatch: "+row["path"])
 # Install only this block's authorized candidate files, after parent has already
 # integrated the router fix and created/frozen the matching full project.
 require(sha(s/"scripts/gameplay/source/main_root_checkpoint_router.gd")==sha(LEGACY/"candidate/scripts/gameplay/source/main_root_checkpoint_router.gd"),"reviewed router hunk must already be integrated in snapshot")
 upstream=verify_upstream(a.upstream_receipt,a.upstream_runner,a.upstream_source_manifest,s)
 # Exact human authorization is functional-only and belongs to this one scene.
 budget_gate=read(O/"STAGE_BUDGET_GATE.json")
 require(budget_gate.get("status")=="PASS" and budget_gate.get("scene")=="tests/framework/source_save_roundtrip_20261017.tscn" and budget_gate.get("timeout_seconds")==180 and budget_gate.get("authorization_id")=="human_source_save_six_stages_180_20261017","BLOCKED: exact Source save/warehouse stage180 authorization required")
 input_rows(s,read(O/"SOURCE_SAVE_FIXTURE_BINDING.json")["files"])
 require({a.console_sha256,a.main_sha256}.issubset({x["sha256"] for x in read(a.upstream_runner).get("engine_fingerprints",[])}),"actual upstream proof used a different engine pair")
 for row in read(LEGACY/"DELIVERY_SHA256.json"):
  if row["path"].startswith(("candidate/","corpus/")) or row["path"]=="EXPECTED_CASES.json":require(sha(LEGACY/row["path"])==row["sha256"],"frozen candidate/corpus input changed: "+row["path"])
 expected=next(x for x in read(LEGACY/"EXPECTED_CASES.json")["cases"] if x["profession_id"]=="hc.profession."+a.profile)
 control=O/"stages"/a.label;require(not control.exists(),"label evidence already exists");control.mkdir(parents=True)
 inp=s/"outputs/source_save_inputs"/a.label;require(not inp.exists(),"input path already exists")
 prior_witness=None
 if a.phase=="deposit":shutil.copytree(LEGACY/"corpus"/expected["profile_id"],inp)
 else:
  require(a.prior_stage is not None,"withdraw requires actual prior deposit native stage receipt")
  require(within(a.prior_stage.resolve(),O),"prior evidence must be inside this authorized output")
  prior=read(a.prior_stage/"STAGE_RESULT.json")
  require(prior.get("runner_guard_binding_sha256")==sha(O/"CANDIDATE_BINDING.json"),"prior stage used a different reviewed runner guard")
  require(prior.get("native_source_sha256")==a.native_source_sha256 and prior.get("main_sha256")==a.main_sha256 and prior.get("candidate_binding_sha256")==sha(LEGACY/"CANDIDATE_BINDING.json"),"prior phase has a different frozen candidate/Native build")
  for row in read(a.prior_stage/"SOURCE_MANIFEST.json"):
   if row["path"].startswith(("scripts/","scenes/","assets/",".godot/","tools/")) or row["path"]=="project.godot":require(sha(s/row["path"])==row["sha256"],"production input differs between real phases: "+row["path"])
  for row in prior["evidence_files"]:require(sha(a.prior_stage/row["path"])==row["sha256"],"prior actual proof file changed")
  actual_prior=read(a.prior_stage/"runner_results.json");prior_framework=read(a.prior_stage/"source_save_roundtrip_20261017.result.json");actual_row=actual_prior["results"][0]
  require(prior_framework.get("status")=="PASS" and prior_framework.get("scene_id")=="source_save_roundtrip_20261017" and prior_framework.get("failed")==0 and actual_row.get("framework_receipt_valid")==True and actual_row.get("framework_run_id")==prior_framework.get("run_id") and actual_row.get("effective_exit_code")==0 and not actual_row.get("timeout") and actual_prior.get("engine_log_errors")==0 and actual_prior.get("source_content_sha256")==prior_framework.get("source_content_sha256")==prior.get("source_content_sha256"),"prior stage actual native/framework/source correlation required")
  prior_protection=read(a.prior_stage/"PROTECTION.json");require(prior_protection.get("source_unchanged")==True and prior_protection.get("real_index_preserved")==True,"prior stage source/index freeze violated")
  require(prior.get("status")=="PASS" and prior.get("phase")=="deposit" and prior.get("profile_id")==expected["profile_id"],"same-profile successful Source deposit required")
  cp=a.prior_stage/"checkpoint";require(cp.is_dir(),"actual Source disk checkpoint missing")
  for row in prior["checkpoint_files"]:require(sha(cp/row["path"])==row["sha256"],"prior disk checkpoint changed")
  shutil.copytree(cp,inp);prior_witness=inp.parent/(a.label+"_prior_witness.bin");shutil.copy2(a.prior_stage/"source_save_roundtrip_witness_20261017.bin",prior_witness);require(sha(prior_witness)==prior["witness_sha256"],"prior binary witness changed")
 spec={"contract_id":"hardcore.test.Source_save_scenario.v1","phase":a.phase,"timeout_seconds":180,"expected":expected,"native_source_sha256":a.native_source_sha256,"main_sha256":a.main_sha256,"input_directory":"res://"+inp.relative_to(s).as_posix(),"upstream_source_content_sha256":upstream["source_content_sha256"]}
 if prior_witness:spec.update(prior_witness="res://"+prior_witness.relative_to(s).as_posix(),prior_witness_sha256=sha(prior_witness))
 spec_path=s/"tests/framework/source_save_scenario_20261017.json";spec_path.write_text(json.dumps(spec,ensure_ascii=False,indent=2),encoding="utf-8")
 external=[spec_path.relative_to(s).as_posix()]+[x.relative_to(s).as_posix() for x in inp.rglob("*") if x.is_file()]
 if prior_witness:external.append(prior_witness.relative_to(s).as_posix())
 if (s/"override.cfg").is_file():external.append("override.cfg")
 config=control/"runner_config.json";config.write_text(json.dumps({"snapshot":str(s),"engine":str(a.engine.resolve()),"label":a.label,"external_inputs":external,"authorized_root":str(O),"git_dir":str(s/".git"),"git_work_tree":str(s),"git_index":str(s/".git/private.index"),"git_ceiling":str(O)},indent=2))
 command=["pwsh","-NoProfile","-ExecutionPolicy","Bypass","-File",str(TOOL_ROOT/"runner_bridge.ps1"),"-Config",str(config)]
 with (control/"runner.log").open("w",encoding="utf-8") as out:run=subprocess.run(command,stdout=out,stderr=subprocess.STDOUT)
 input_rows(s,[x for x in manifest["module_inputs"] if x["root"]=="project"])
 inv=s/"outputs/v115_multicore/invocations"/a.label;protection=read(inv/"PROTECTION.json");results=read(next((inv/"logs").glob("runner_results*.json")));r=results["results"][0]
 require(run.returncode==0 and r["effective_exit_code"]==0 and r.get("framework_receipt_valid")==True and not r["timeout"] and results["engine_log_errors"]==0 and protection["source_unchanged"] and protection["real_index_preserved"],"actual stage failed; raw failure retained")
 require({a.console_sha256,a.main_sha256}.issubset({x["sha256"] for x in r.get("engine_fingerprints",[])}),"actual runner engine bytes differ from fixed Native169 pair")
 require(r.get("cleanup_warning_evidence",{}).get("status")=="PASS" and r["cleanup_warning_evidence"].get("objectdb_leak_warning_count")==0,"actual cleanup warning is not accepted")
 user=Path(r["runtime_appdata"])/"Godot/app_userdata/HardCore";export=read(user/"source_save_stage_export_20261017.json")
 require(export.get("status")=="PASS" and export.get("phase")==a.phase and export.get("profile_id")==expected["profile_id"] and export.get("source_content_sha256")==results.get("source_content_sha256") and export.get("invocation_id")==results.get("invocation_id"),"actual native phase witness/profile identity mismatch")
 witness=Path(export["witness_path"]);require(within(witness.resolve(),user.resolve()) and sha(witness)==export["witness_sha256"],"actual private witness hash/path mismatch")
 checkpoint=Path(export["checkpoint_directory"]);require(checkpoint.resolve()==(user/"Source_roundtrip_case").resolve(),"actual private checkpoint identity mismatch")
 shutil.copytree(checkpoint,control/"checkpoint");shutil.copy2(witness,control/witness.name)
 shutil.copy2(next((inv/"logs").glob("runner_results*.json")),control/"runner_results.json")
 for f in [inv/"PROTECTION.json",inv/"SOURCE_MANIFEST.json",inv/"SOURCE_BINDING.json",s/"outputs/test_logs/framework/source_save_roundtrip_20261017.result.json"]:shutil.copy2(f,control/f.name)
 checkpoint_files=[{"path":x.relative_to(checkpoint).as_posix(),"sha256":sha(x)} for x in checkpoint.rglob("*") if x.is_file()]
 evidence_files=[{"path":f.name,"sha256":sha(f)} for f in control.glob("*.json")]
 result={"runner_guard_binding_sha256":sha(O/"CANDIDATE_BINDING.json"),"stage_budget_gate_sha256":sha(O/"STAGE_BUDGET_GATE.json"),"native_source_sha256":a.native_source_sha256,"main_sha256":a.main_sha256,"candidate_binding_sha256":sha(LEGACY/"CANDIDATE_BINDING.json"),"evidence_files":evidence_files,"status":"PASS","phase":a.phase,"profile_id":expected["profile_id"],"native_exit":r["effective_exit_code"],"engine_log_errors":results["engine_log_errors"],"source_content_sha256":export["source_content_sha256"],"witness_sha256":sha(witness),"checkpoint_files":checkpoint_files,"invocation":str(inv),"command":command,"upstream_receipt_sha256":sha(a.upstream_receipt)}
 (control/"STAGE_RESULT.json").write_text(json.dumps(result,indent=2)+"\n");print(json.dumps(result,indent=2))
if __name__=="__main__":
 try:main()
 except Exception as e:print("BLOCKED/FAIL: "+str(e),file=sys.stderr);sys.exit(1)
