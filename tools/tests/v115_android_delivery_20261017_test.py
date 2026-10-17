"""Delivery guard unit fixtures only. No Android/Godot build or device proof."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/"outputs/v115_multicore/android_delivery_parallel_20261017/delivery.py"
SPEC=importlib.util.spec_from_file_location("v115_delivery",SOURCE)
DELIVERY=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(DELIVERY)


def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value),encoding="utf-8")
    return {"path":str(path),"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}

class DeliveryBoundaries(unittest.TestCase):
    def test_pinned_input_changes_fail(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"input.json";row=write(p,{"exact":1});self.assertEqual(DELIVERY.pinned(row),p.resolve())
            p.write_text('{"exact":2}')
            with self.assertRaisesRegex(RuntimeError,"differs"):DELIVERY.pinned(row)
            with self.assertRaisesRegex(RuntimeError,"BLOCKED"):DELIVERY.pinned({})

    def test_preflight_cannot_be_substituted_for_actual_template_build(self):
        with tempfile.TemporaryDirectory() as d:
            row=write(Path(d)/"preflight.json",{"status":"PASS","build":"NOT_RUN"})
            with self.assertRaisesRegex(RuntimeError,"not PASS"):DELIVERY.validate_templates(row)

    def test_world_native_exit_and_source_protection_required(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);manifest=write(root/"source.json",[])
            runner={"engine_log_errors":0,"results":[{"test_name":"character_source_full_world_20261016","result":"PASS","effective_exit_code":0,"timeout":False,"framework_receipt_valid":True,"source_content_sha256":manifest["sha256"]}]}
            protection={"source_unchanged":True,"real_index_preserved":True,"native_runner_exit":0}
            gate={"runner_result":write(root/"runner.json",runner),"protection":write(root/"protection.json",protection),"source_manifest":manifest,"source_content_sha256":manifest["sha256"]}
            self.assertEqual(DELIVERY.validate_world(gate)["result"],"PASS")
            for field,value in [("effective_exit_code",1),("timeout",True),("framework_receipt_valid",False),("result","FAIL")]:
                broken=copy.deepcopy(runner);broken["results"][0][field]=value;gate["runner_result"]=write(root/"runner.json",broken)
                with self.assertRaisesRegex(RuntimeError,"BLOCKED"):DELIVERY.validate_world(gate)
            gate["runner_result"]=write(root/"runner.json",runner);protection["source_unchanged"]=False;gate["protection"]=write(root/"protection.json",protection)
            with self.assertRaisesRegex(RuntimeError,"provenance"):DELIVERY.validate_world(gate)

    def test_all_five_actual_command_provenances_required(self):
        source="a"*64;commands=[]
        for target in ("debug","release"):
            for arch in ("arm64","x86_64"):
                commands.append({"argv":["scons",f"target=template_{target}",f"arch={arch}",DELIVERY.NATIVE.native_define(source)],"exit_code":0,"started":1,"finished":2,"inputs_before":{"source_sha256":source},"inputs_after":{"source_sha256":source}})
        commands.append({"argv":["java","-PdoNotStrip=true","generateGodotTemplates"],"exit_code":0,"started":1,"finished":2,"inputs_before":{"source_sha256":source},"inputs_after":{"source_sha256":source}})
        receipt={"native_source_sha256":source,"commands":commands};DELIVERY.validate_template_provenance(receipt)
        for change in ("missing_command","missing_macro","wrong_after","nonzero_exit","wrong_arch"):
            broken=copy.deepcopy(receipt)
            if change=="missing_command":broken["commands"].pop()
            if change=="missing_macro":broken["commands"][0]["argv"].pop()
            if change=="wrong_after":broken["commands"][0]["inputs_after"]["source_sha256"]="b"*64
            if change=="nonzero_exit":broken["commands"][0]["exit_code"]=1
            if change=="wrong_arch":broken["commands"][0]["argv"][2]="arch=arm32"
            with self.assertRaises(RuntimeError):DELIVERY.validate_template_provenance(broken)

    def test_exact_fixed_git_snapshot_must_match_world_and_native_proof(self):
        with tempfile.TemporaryDirectory() as d:
            r=Path(d)/"repo";r.mkdir();subprocess.run(["git","init","-q",str(r)],check=True)
            for name,data in [("scripts/live.gd",b"actual fixed source"),("assets/data/source.json",b"{}"),("native/hardcore_simulation/SCsub",b"fixed Native build input")]:
                p=r/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
            subprocess.run(["git","-C",str(r),"add","."],check=True)
            subprocess.run(["git","-C",str(r),"-c","user.name=Verifier Fixture","-c","user.email=verifier@example.invalid","commit","-qm","temporary verifier fixture"],check=True)
            commit=subprocess.check_output(["git","-C",str(r),"rev-parse","HEAD"],text=True).strip()
            source=[{"path":name,"sha256":hashlib.sha256((r/name).read_bytes()).hexdigest()} for name in ("scripts/live.gd","assets/data/source.json")]
            proof=Path(d)/"source.json";native=Path(d)/"native.json"
            config={"fixed_release_commit":commit,"world_gate":{"source_manifest":write(proof,source)}}
            templates={"manifest":write(native,{"module_inputs":[{"root":"project","relative_path":"native/hardcore_simulation/SCsub","sha256":hashlib.sha256((r/"native/hardcore_simulation/SCsub").read_bytes()).hexdigest()}]})}
            with patch.object(DELIVERY,"ROOT",r):
                self.assertEqual(DELIVERY.verify_release_sources(config,templates)["exact_source_files"],3)
                (r/"scripts/live.gd").write_bytes(b"uncommitted new source")
                self.assertEqual(DELIVERY.verify_release_sources(config,templates)["status"],"PASS")
                source[0]["sha256"]=hashlib.sha256(b"uncommitted new source").hexdigest();config["world_gate"]["source_manifest"]=write(proof,source)
                with self.assertRaisesRegex(RuntimeError,"fixed release differs"):DELIVERY.verify_release_sources(config,templates)

    def test_install_rejects_unbound_original_userdata_before_install_command(self):
        with tempfile.TemporaryDirectory() as d:
            backup=write(Path(d)/"backup.json",{"status":"FAIL","serial":"emulator-5554","package_id":DELIVERY.PACKAGE})
            config={"device_userdata_backup_receipt":backup,"baseline_apk":{"sha256":"a"*64},"output_apk":"not-used.apk"}
            with patch.object(DELIVERY,"verify",return_value={"apk":{}}),patch.object(DELIVERY,"checked_emulator",return_value=(Path("adb.exe"),"emulator-5554")),patch.object(DELIVERY,"run") as execute:
                with self.assertRaisesRegex(RuntimeError,"backup required"):DELIVERY.install(config,Path(d))
                execute.assert_not_called()

    def test_wrong_or_missing_emulator_serial_never_starts_emulator(self):
        for serial in ("", "REA-AN00", "emulator-5554;bad", "emulator-"):
            with patch.object(DELIVERY,"run") as execute:
                with self.assertRaisesRegex(RuntimeError,"already-running"):DELIVERY.checked_emulator({"serial":serial},Path("not-used"))
                execute.assert_not_called()

if __name__=="__main__":unittest.main()
