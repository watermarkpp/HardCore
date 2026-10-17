"""Fail-closed v115 delivery orchestrator. Default is read-only preflight.
No build/export/emulator launch is performed by preflight. No uninstall/clear.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import tarfile
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("native_templates", ROOT / "tools/build_hardcore_android_templates.py")
NATIVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NATIVE)
PACKAGE = "com.personal.mafaoffline"


def sha(path): return NATIVE.sha(Path(path))
def fact(path): return NATIVE.fact(Path(path))
def load(path): return json.loads(Path(path).read_text(encoding="utf-8-sig"))
def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
def pinned(row):
    if not isinstance(row, dict) or not row.get("path") or re.fullmatch("[0-9a-f]{64}", row.get("sha256", "")) is None:
        raise RuntimeError("BLOCKED: missing exact path/SHA256 input")
    p=Path(row["path"]).resolve(strict=True)
    if sha(p) != row["sha256"]: raise RuntimeError("Pinned input differs: " + str(p))
    return p

def validate_world(gate):
    if not isinstance(gate,dict) or not gate.get("runner_result") or not gate.get("protection"):
        raise RuntimeError("BLOCKED: pinned real full-world runner result and source protection receipt required")
    runner=load(pinned(gate["runner_result"]))
    protection=load(pinned(gate["protection"]))
    source_manifest=pinned(gate["source_manifest"])
    if sha(source_manifest)!=gate.get("source_content_sha256"):
        raise RuntimeError("BLOCKED: full-world source manifest hash differs")
    matches=[row for row in runner["results"] if row.get("test_name")=="character_source_full_world_20261016"]
    if len(matches)!=1: raise RuntimeError("BLOCKED: one actual full-world producer required")
    row=matches[0]
    if row.get("result")!="PASS" or row.get("effective_exit_code")!=0 or row.get("timeout") is not False or row.get("framework_receipt_valid") is not True or runner.get("engine_log_errors")!=0:
        raise RuntimeError("BLOCKED: full-world native start/world/exit is not PASS")
    if protection.get("source_unchanged") is not True or protection.get("real_index_preserved") is not True or protection.get("native_runner_exit")!=0:
        raise RuntimeError("BLOCKED: full-world source/exit provenance missing")
    if row.get("source_content_sha256") != gate.get("source_content_sha256"):
        raise RuntimeError("BLOCKED: full-world source identity differs")
    return row

def validate_template_provenance(receipt):
    source=receipt["native_source_sha256"];commands=receipt.get("commands",[])
    if "reused_native_receipt" in receipt:
        prior=load(pinned(receipt["reused_native_receipt"]))
        reused=receipt.get("reused_native_builds",[])
        if (len(commands)!=1 or len(reused)!=4
                or prior.get("status") not in ("PASS","FAIL","BLOCKED")
                or prior.get("native_source_sha256")!=source
                or prior.get("manifest")!=receipt.get("manifest")
                or prior.get("tools")!=receipt.get("tools")
                or prior.get("jni")!=receipt.get("jni")):
            raise RuntimeError("Verified JNI resume source/tools/artifacts provenance differs")
        originals=[]
        for row in reused:
            command=row.get("original_command",{})
            matches=[old for old in prior.get("commands",[]) if old.get("argv")==command.get("argv")]
            if (len(matches)!=1 or matches[0]!=command
                    or row.get("verified_inputs")!=command.get("inputs_before")
                    or row.get("verified_inputs")!=command.get("inputs_after")
                    or row.get("verified_inputs")!=receipt.get("preflight")
                    or row.get("verified_inputs")!=receipt.get("postflight")
                    or pinned(row.get("original_log"))!=Path(command["log"]).resolve()):
                raise RuntimeError("Exact original successful JNI execution evidence required")
            argv=command["argv"]
            target=next((a.removeprefix("target=template_") for a in argv if a.startswith("target=template_")),"")
            arch=next((a.removeprefix("arch=") for a in argv if a.startswith("arch=")),"")
            if target not in ("debug","release") or arch not in NATIVE.ARCHES:
                raise RuntimeError("Original JNI target/ABI differs")
            abi=NATIVE.ARCHES[arch][0]
            artifact=receipt["jni"][target][abi]["libgodot_android.so"]
            actual=NATIVE.verify_fresh(pinned(artifact),command["started_ns"])
            if actual["mtime_ns"]!=artifact.get("mtime_ns") or artifact.get("produced_after_ns")!=command["started_ns"]:
                raise RuntimeError("Original successful JNI timestamp provenance differs")
            originals.append(command)
        # Local validation view only. The receipt continues distinguishing
        # genuine prior SCons executions from the new Gradle execution.
        commands=originals+commands
    elif receipt.get("reused_native_builds"):
        raise RuntimeError("Pinned original JNI execution receipt required")
    if len(commands)!=5: raise RuntimeError("Missing actual four SCons builds plus Gradle command provenance")
    for command in commands:
        if command.get("exit_code")!=0 or command.get("finished",0)<command.get("started",1):
            raise RuntimeError("Actual template command did not finish successfully")
        for field in ("inputs_before","inputs_after"):
            if command.get(field,{}).get("source_sha256")!=source:
                raise RuntimeError("Per-command Native source provenance differs")
    expected={(target,arch) for target in ("debug","release") for arch in ("arm64","x86_64")}
    actual=set()
    for command in commands[:4]:
        argv=command["argv"]
        if NATIVE.native_define(source) not in argv or any(a.startswith("cppdefines=") for a in argv):
            raise RuntimeError("Actual compiler command omitted module-local Native identity")
        target=next((a.removeprefix("target=template_") for a in argv if a.startswith("target=template_")),"")
        arch=next((a.removeprefix("arch=") for a in argv if a.startswith("arch=")),"")
        actual.add((target,arch))
    if actual!=expected: raise RuntimeError("Actual Native target/ABI command set differs")
    if "generateGodotTemplates" not in commands[-1]["argv"] or "-PdoNotStrip=true" not in commands[-1]["argv"]:
        raise RuntimeError("Actual Gradle template generation provenance differs")

def validate_templates(row):
    receipt=load(pinned(row))
    if receipt.get("status")!="PASS" or receipt.get("build")!="PASS": raise RuntimeError("BLOCKED: actual Native template build is not PASS")
    source=receipt["native_source_sha256"]
    validate_template_provenance(receipt)
    NATIVE.native_define(source)
    if receipt["preflight"]["source_sha256"]!=source or receipt["postflight"]["source_sha256"]!=source:
        raise RuntimeError("Native pre/post provenance differs")
    for target in ("debug","release"):
        if set(receipt["jni"][target])!={"arm64-v8a","x86_64"}: raise RuntimeError("Native template ABI set differs")
        p=pinned(receipt["artifacts"][target]["file"])
        NATIVE.verify_jni_zip(p,receipt["jni"][target],"lib")
        for abi, libraries in receipt["jni"][target].items():
            machine=183 if abi=="arm64-v8a" else 62
            NATIVE.verify_elf(pinned(libraries["libgodot_android.so"]),machine,source)
    source_zip=pinned(receipt["artifacts"]["source_zip"])
    with zipfile.ZipFile(source_zip) as package:
        names=package.namelist()
        if len(names)!=len(set(names)): raise RuntimeError("Duplicate source ZIP members")
        for target in ("debug","release"):
            raw=package.read(f"libs/{target}/godot-lib.template_{target}.aar")
            expected=receipt["artifacts"]["source_"+target]["file"]
            if hashlib.sha256(raw).hexdigest()!=expected["sha256"]: raise RuntimeError("Nested AAR bytes differ")
            NATIVE.verify_jni_zip(io.BytesIO(raw),receipt["jni"][target],"jni")
    return receipt

def run(argv, evidence, label, env=None):
    evidence=Path(evidence);evidence.mkdir(parents=True,exist_ok=True)
    record={"argv":[str(a) for a in argv],"started_ns":time.time_ns(),"stdout":str(evidence/(label+".stdout.log")),"stderr":str(evidence/(label+".stderr.log"))}
    save(evidence/(label+".command.json"),record)
    with open(record["stdout"],"wb") as out,open(record["stderr"],"wb") as err:
        result=subprocess.run(record["argv"],cwd=ROOT,stdout=out,stderr=err,env=env)
    record["exit_code"]=result.returncode;record["finished_ns"]=time.time_ns();save(evidence/(label+".command.json"),record)
    if result.returncode: raise RuntimeError("Actual command failed: "+label+" exit="+str(result.returncode))
    return record

def clone_native(config, destination):
    source=pinned(config["native_manifest"]);manifest=load(source)
    NATIVE.verify_inputs(manifest,Path(config["engine_root"]))
    manifest["build_config"]["android_archs"]=["arm64","x86_64"]
    manifest["build_config"]["android_abis"]=["arm64-v8a","x86_64"]
    if Path(destination).exists(): raise RuntimeError("Immutable manifest output already exists")
    save(destination,manifest)
    return {"status":"PASS","scope":"dual ABI config clone only; build NOT_RUN","original_manifest":fact(source),"clone":fact(destination),"native_source_sha256":manifest["source_sha256"]}

def preflight(config):
    checks=[]
    def inspect(label, action):
        try: checks.append({"check":label,"status":"PASS","evidence":action()})
        except Exception as error: checks.append({"check":label,"status":"BLOCKED","reason":str(error)})
    inspect("exact Native inputs",lambda:NATIVE.verify_inputs(load(pinned(config["native_manifest"])),Path(config["engine_root"])))
    inspect("compiled identity candidate installed",lambda:NATIVE.verify_identity_source(Path(config["engine_root"])))
    inspect("actual full-world native/source gate",lambda:validate_world(config["world_gate"]))
    inspect("actual fresh dual-ABI template receipt",lambda:validate_templates(config["templates_receipt"]))
    inspect("existing baseline APK",lambda:fact(pinned(config["baseline_apk"])))
    inspect("formal export candidate installed",lambda:export_ready(config))
    return {"status":"PASS" if all(row["status"]=="PASS" for row in checks) else "BLOCKED","scope":"preflight only; no build/export/install","checks":checks,"game_APK115":"NOT_RUN","device":"NOT_RUN"}

def export_ready(config):
    source=(ROOT/"tools/build_android_isolated.ps1").read_text(encoding="utf-8-sig")
    if "$NativeTemplateReceipt" not in source or "-GodotExecutable $GodotConsole" not in source:
        raise RuntimeError("BLOCKED: reviewed formal export parameter candidate must be applied")
    commit=config.get("fixed_release_commit","")
    if re.fullmatch("[0-9a-f]{40}",commit) is None: raise RuntimeError("BLOCKED: final fixed release commit required; dirty HEAD is not a release snapshot")
    return {"status":"PASS","fixed_release_commit":commit}

def verify_release_sources(config, templates):
    expected={row["path"]:row["sha256"] for row in load(pinned(config["world_gate"]["source_manifest"]))
              if row["path"]=="project.godot" or row["path"].startswith(("scripts/","scenes/","assets/data/"))}
    native=load(pinned(templates["manifest"]))
    for row in native["module_inputs"]:
        if row["root"]=="project": expected[row["relative_path"]]=row["sha256"]
    if not expected: raise RuntimeError("BLOCKED: empty fixed release source binding")
    # Read immutable Git blobs, not the dirty checkout. No commit/index mutation.
    archive_roots=sorted({path.split("/",1)[0] for path in expected})
    process=subprocess.Popen(["git","-c","core.autocrlf=false","-C",str(ROOT),"archive",config["fixed_release_commit"],*archive_roots],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    observed={}
    try:
        with tarfile.open(fileobj=process.stdout,mode="r|") as archive:
            for member in archive:
                if not member.isfile() or member.name not in expected: continue
                value=hashlib.sha256();stream=archive.extractfile(member)
                for block in iter(lambda:stream.read(1<<20),b""): value.update(block)
                observed[member.name]=value.hexdigest()
        error=process.stderr.read();code=process.wait()
    finally:
        process.stdout.close();process.stderr.close()
    if code: raise RuntimeError("Fixed release Git archive failed: "+error.decode("utf-8",errors="replace"))
    different=[path for path,wanted in expected.items() if observed.get(path)!=wanted]
    if different: raise RuntimeError("BLOCKED: fixed release differs from actual World/Native source proof: "+repr(different[:20]))
    return {"status":"PASS","commit":config["fixed_release_commit"],"exact_source_files":len(expected)}

def prepare_private_editor(config, receipt, destination):
    destination=Path(destination);destination.mkdir(parents=True,exist_ok=False)
    for row in config["windows_binaries"]:
        source=pinned(row);shutil.copy2(source,destination/source.name)
    (destination/"_sc_").write_bytes(b"")
    data=destination/"editor_data";data.mkdir()
    def path(value): return str(value).replace("\\","/")
    settings='[gd_resource type="EditorSettings" format=3]\n[resource]\n'
    settings+='export/android/java_sdk_path = '+json.dumps(path(config["java_home"]))+'\n'
    settings+='export/android/android_sdk_path = '+json.dumps(path(config["compile_sdk"]))+'\n'
    settings+='export/android/debug_keystore = '+json.dumps(path(Path(config["signing_tool_root"])/"tools/godot-4.7/editor_data/keystores/debug.keystore"))+'\n'
    (data/"editor_settings-4.7.tres").write_text(settings,encoding="utf-8")
    templates=data/"export_templates/4.7.stable";templates.mkdir(parents=True)
    for row in [receipt["artifacts"]["debug"]["file"],receipt["artifacts"]["release"]["file"],receipt["artifacts"]["source_zip"]]:
        source=pinned(row);shutil.copy2(source,templates/source.name)
    return destination / next(Path(row["path"]).name for row in config["windows_binaries"] if "_console.exe" in row["path"])

def export(config, evidence):
    export_ready(config);validate_world(config["world_gate"])
    templates=validate_templates(config["templates_receipt"])
    source_binding=verify_release_sources(config,templates)
    save(Path(evidence)/"FIXED_RELEASE_SOURCE_BINDING.json",source_binding)
    capability=load(pinned(config["windows_native_capability"]))
    NATIVE.verify_capability(capability["capabilities"],templates["native_source_sha256"])
    main=next(row for row in config["windows_binaries"] if "_console.exe" not in row["path"])
    if capability.get("status")!="PASS" or capability.get("engine_binary_sha256")!=main["sha256"]: raise RuntimeError("Runtime capability belongs to another Windows binary")
    editor=prepare_private_editor(config,templates,Path(evidence)/"private_editor")
    output=Path(config["output_apk"])
    if output.exists(): raise RuntimeError("Final APK path already exists; preserve it")
    argv=[config["powershell"],"-NoProfile","-File",str(ROOT/"tools/build_android_isolated.ps1"),"-Commit",config["fixed_release_commit"],"-OutputApk",str(output),"-GodotConsole",str(editor),"-AndroidRoot",str(Path(config["compile_sdk"]).parent),"-BaselineApkPath",str(pinned(config["baseline_apk"])),"-VersionCode","115","-ExpectedVersionCode","115","-ExpectedVersionName",config["version_name"],"-NativeTemplateReceipt",str(pinned(config["templates_receipt"])),"-ExpectedNativeTemplateReceiptSha256",config["templates_receipt"]["sha256"],"-SigningToolRoot",config["signing_tool_root"],"-KeepStage"]
    run(argv,evidence,"official_two_pass_export")
    return verify(config,evidence)

def verify(config,evidence):
    validate_world(config["world_gate"])
    templates=validate_templates(config["templates_receipt"]);verify_release_sources(config,templates);apk=Path(config["output_apk"])
    NATIVE.verify_jni_zip(apk,templates["jni"]["debug"],"lib")
    run([config["powershell"],"-NoProfile","-File",str(ROOT/"tools/verify_android_build.ps1"),"-ApkPath",str(apk),"-AndroidRoot",str(Path(config["compile_sdk"]).parent),"-BaselineApkPath",str(pinned(config["baseline_apk"])),"-ExpectedVersionCode","115","-ExpectedVersionName",config["version_name"],"-ExpectedCommit",config["fixed_release_commit"]],evidence,"official_package_signature_version_contents")
    result={"status":"PASS","scope":"official final APK static verification ONLY","apk":fact(apk),"package_id":PACKAGE,"version_code":115,"device":"NOT_RUN","native_source_sha256":templates["native_source_sha256"]}
    save(Path(evidence)/"FINAL_APK_STATIC_RECEIPT.json",result)
    return result

def checked_emulator(config, evidence):
    serial=config.get("serial","")
    if not re.fullmatch(r"emulator-[0-9]+",serial): raise RuntimeError("BLOCKED: exact already-running emulator serial required")
    adb=Path(config["device_sdk"])/"platform-tools/adb.exe"
    record=run([str(adb),"-s",serial,"emu","avd","name"],evidence,"exact_avd_identity")
    name=Path(record["stdout"]).read_text(encoding="utf-8").splitlines()[0].strip()
    if name!="HONOR_REA_AN00_Clone": raise RuntimeError("BLOCKED: selected emulator is not the preserved HONOR clone")
    return adb,serial

def backup_userdata(config,evidence):
    adb,serial=checked_emulator(config,evidence)
    pid=subprocess.run([str(adb),"-s",serial,"shell","pidof",PACKAGE],capture_output=True)
    save(Path(evidence)/"before_backup_process.json",{"argv":[str(adb),"-s",serial,"shell","pidof",PACKAGE],"exit_code":pid.returncode,"stdout":pid.stdout.decode("utf-8",errors="replace"),"stderr":pid.stderr.decode("utf-8",errors="replace")})
    if pid.returncode not in (0,1) or pid.stdout.strip(): raise RuntimeError("BLOCKED: exit the game normally before copying its save files")
    path_record=run([str(adb),"-s",serial,"shell","pm","path",PACKAGE],evidence,"installed_apk_path")
    paths=[line.removeprefix("package:").strip() for line in Path(path_record["stdout"]).read_text().splitlines() if line.startswith("package:")]
    if len(paths)!=1 or not paths[0].startswith("/data/app/") or not paths[0].endswith(".apk"): raise RuntimeError("BLOCKED: single installed original APK required for exact baseline binding")
    installed=Path(evidence)/"installed_original.apk"
    run([str(adb),"-s",serial,"pull",paths[0],str(installed)],evidence,"installed_original_apk_readonly_copy")
    if sha(installed)!=config.get("installed_apk",config["baseline_apk"])["sha256"]: raise RuntimeError("BLOCKED: installed APK differs from preserved baseline; do not overwrite an unidentified install")
    capture=run([str(adb),"-s",serial,"exec-out","run-as",PACKAGE,"tar","-cf","-","."],evidence,"original_userdata_readonly_tar")
    archive=Path(capture["stdout"]);rows=[]
    with tarfile.open(archive,"r:") as source:
        for entry in source:
            if entry.isfile():
                stream=source.extractfile(entry);value=hashlib.sha256()
                for block in iter(lambda:stream.read(1<<20),b""): value.update(block)
                rows.append({"path":entry.name,"bytes":entry.size,"sha256":value.hexdigest()})
    result={"status":"PASS","scope":"read-only stopped-app private-data archive; no install or gameplay acceptance","serial":serial,"avd":"HONOR_REA_AN00_Clone","package_id":PACKAGE,"files":[fact(archive),fact(installed)],"original_file_manifest":rows,"profile_files":[row for row in rows if "/characters/" in row["path"] and row["path"].endswith(".json")],"installed_apk_sha256":sha(installed),"original_runtime":"NOT_RUN"}
    save(Path(evidence)/"USERDATA_BACKUP_RECEIPT.json",result);return result

def install(config,evidence):
    static=verify(config,evidence);adb,serial=checked_emulator(config,evidence)
    if not re.fullmatch(r"emulator-[0-9]+",serial): raise RuntimeError("BLOCKED: exact running emulator serial required; this script never launches an emulator")
    capture=load(pinned(config["device_userdata_backup_receipt"]))
    if capture.get("status")!="PASS" or capture.get("serial")!=serial or capture.get("package_id")!=PACKAGE:
        raise RuntimeError("BLOCKED: original emulator userdata verified backup required before overwrite install")
    if capture.get("installed_apk_sha256")!=config["baseline_apk"]["sha256"]:
        raise RuntimeError("BLOCKED: original backup belongs to another installed APK")
    for row in capture["files"]: pinned(row)
    run([str(adb),"-s",serial,"install","-r",config["output_apk"]],evidence,"overwrite_install_same_signature")
    launch=run([str(adb),"-s",serial,"shell","am","start","-W","-n",PACKAGE+"/com.godot.game.GodotApp"],evidence,"normal_launcher_start")
    if re.search(r"(?m)^Status:\s*ok\s*$",Path(launch["stdout"]).read_text(encoding="utf-8")) is None:
        raise RuntimeError("Launcher did not report actual Status: ok")
    package=run([str(adb),"-s",serial,"shell","dumpsys","package",PACKAGE],evidence,"installed_package")
    text=Path(package["stdout"]).read_text(encoding="utf-8")
    if re.search(r"versionCode=115(?:\s|$)",text) is None or "primaryCpuAbi=x86_64" not in text:
        raise RuntimeError("Installed versionCode/actual emulator ABI differs")
    run([str(adb),"-s",serial,"exec-out","screencap","-p"],evidence,"launcher_screen_png")
    return {"status":"PASS","scope":"overwrite install and launcher command only","apk":static["apk"],"serial":serial,"gameplay":"NOT_RUN","normal_game_exit":"NOT_RUN","warehouse_equipment":"NOT_RUN","physical_phone_performance":"NOT_RUN"}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode",nargs="?",default="preflight",choices=["preflight","bind-gates","clone-native-manifest","templates","export","verify","backup-userdata","install"])
    parser.add_argument("--config",type=Path,required=True)
    parser.add_argument("--evidence",type=Path,required=True)
    parser.add_argument("--output",type=Path)
    for name in ("world-runner","world-protection","world-source-manifest","native-template-receipt","windows-capability","backup-receipt","installed-apk"):
        parser.add_argument("--"+name,type=Path)
    parser.add_argument("--fixed-release-commit")
    parser.add_argument("--serial")
    args=parser.parse_args()
    if args.mode in ("templates","clone-native-manifest","bind-gates") and args.output is None:
        parser.error("--output is required for templates/clone-native-manifest")
    config=load(args.config)
    if args.evidence.exists(): raise RuntimeError("Evidence directory already exists; do not overwrite")
    args.evidence.mkdir(parents=True)
    try:
        if args.mode=="preflight": result=preflight(config)
        elif args.mode=="bind-gates":
            if args.output.exists(): raise RuntimeError("Pinned config output already exists")
            world=[args.world_runner,args.world_protection,args.world_source_manifest]
            if any(world):
                if not all(world): raise RuntimeError("All three actual World evidence paths required together")
                config["world_gate"]={"runner_result":fact(args.world_runner),"protection":fact(args.world_protection),"source_manifest":fact(args.world_source_manifest),"source_content_sha256":sha(args.world_source_manifest)}
                validate_world(config["world_gate"])
            for arg,key in [(args.native_template_receipt,"templates_receipt"),(args.windows_capability,"windows_native_capability"),(args.backup_receipt,"device_userdata_backup_receipt"),(args.installed_apk,"installed_apk")]:
                if arg is not None: config[key]=fact(arg)
            if args.fixed_release_commit is not None:
                if re.fullmatch("[0-9a-f]{40}",args.fixed_release_commit) is None: raise RuntimeError("Exact fixed release commit required")
                config["fixed_release_commit"]=args.fixed_release_commit
            if args.serial is not None: config["serial"]=args.serial
            save(args.output,config)
            result={"status":"PASS","scope":"exact input facts bound only; build/export/device NOT_RUN","config":fact(args.output)}
        elif args.mode=="clone-native-manifest": result=clone_native(config,args.output)
        elif args.mode=="templates":
            m=pinned(config["native_manifest"])
            argv=[sys.executable,"-B",str(ROOT/"tools/build_hardcore_android_templates.py"),"--manifest",str(m),"--manifest-sha256",config["native_manifest"]["sha256"],"--engine",config["engine_root"],"--sdk",config["compile_sdk"],"--java-home",config["java_home"],"--scons",config["scons"],"--output",str(args.output),"--jobs","2","--build"]
            run(argv,args.evidence,"actual_native_templates");result={"status":"PASS","scope":"actual Native templates only; game NOT_RUN","receipt":fact(args.output/"ANDROID_TEMPLATE_RECEIPT.json")}
        else: result={"export":export,"verify":verify,"backup-userdata":backup_userdata,"install":install}[args.mode](config,args.evidence)
        save(args.evidence/"RESULT.json",result);print(json.dumps(result,ensure_ascii=False))
        return 2 if result["status"]=="BLOCKED" else 0
    except Exception as error:
        save(args.evidence/"RESULT.json",{"status":"BLOCKED" if str(error).startswith("BLOCKED:") else "FAIL","error":str(error),"game_APK115":"NOT_RUN","device":"NOT_RUN"})
        raise

if __name__=="__main__": sys.exit(main())
