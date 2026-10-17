"""Build sealed Native templates only; game export/signing is a separate gate.

Default is a read-only Native/tool preflight. --build compiles both Android
architectures and packages the official Gradle templates, then verifies the
actual APK/AAR JNI bytes. Never searches for or accepts an arbitrary old APK.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import time
import zipfile

ARCHES = {"arm64": ("arm64-v8a", 183), "x86_64": ("x86_64", 62)}
ROOT = Path(__file__).resolve().parents[1]
FINGERPRINT_ALGORITHM = "sha256(utf8(sorted root/relative_path:sha256 rows joined with LF, including final LF))"


def sha(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            value.update(block)
    return value.hexdigest()


def fact(path: Path) -> dict:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha(path)}


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True,
                                   encoding="utf-8", env={**os.environ, "GIT_OPTIONAL_LOCKS": "0"}).strip()


def bounded_input(root: Path, relative: str) -> Path:
    path = (root / relative).resolve(strict=True)
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise RuntimeError("Native input escapes declared root: " + relative)
    return path


def native_define(fingerprint: str) -> str:
    if not isinstance(fingerprint, str) or re.fullmatch(r"[0-9a-f]{64}", fingerprint) is None:
        raise RuntimeError("Native source fingerprint must be a full lowercase SHA256")
    return "hardcore_native_source_sha256=" + fingerprint


def verify_capability(capability: dict, fingerprint: str) -> dict:
    native_define(fingerprint)
    if capability.get("native_source_identity_injected") is not True:
        raise RuntimeError("Native source identity macro was not injected")
    if capability.get("native_source_sha256") != fingerprint:
        raise RuntimeError("Runtime Native source fingerprint mismatch")
    return {"status": "PASS", "native_source_sha256": fingerprint}


def verify_fresh(path: Path, started_ns: int) -> dict:
    if not path.is_file() or path.stat().st_size == 0 or path.stat().st_mtime_ns < started_ns:
        raise RuntimeError("Missing or stale artifact from before this actual build: " + str(path))
    return {**fact(path), "mtime_ns": path.stat().st_mtime_ns,
            "produced_after_ns": started_ns}


def verify_identity_source(engine: Path) -> dict:
    source = engine / "modules/hardcore_simulation/simulation_host_original_primitives.cpp"
    text = source.read_text(encoding="utf-8")
    for token in ("#ifdef HARDCORE_NATIVE_SOURCE_SHA256", "#define HARDCORE_NATIVE_STRINGIFY_INNER(value) #value",
                  "#define HARDCORE_NATIVE_STRINGIFY(value) HARDCORE_NATIVE_STRINGIFY_INNER(value)",
                  'caps["native_source_sha256"]', 'caps["native_source_identity_injected"]'):
        if token not in text:
            raise RuntimeError("BLOCKED: compiled Native identity candidate not applied: " + token)
    config = engine / "modules/hardcore_simulation/config.py"
    scsub = engine / "modules/hardcore_simulation/SCsub"
    if "hardcore_native_source_sha256" not in config.read_text(encoding="utf-8") or "env.Clone()" not in scsub.read_text(encoding="utf-8"):
        raise RuntimeError("BLOCKED: module-local identity option/Clone candidate not applied")
    return {"status": "PASS", "source": fact(source), "config": fact(config), "SCsub": fact(scsub), "runtime_capability": "NOT_RUN"}


def verify_inputs(manifest: dict, engine: Path) -> dict:
    if manifest.get("schema") != "hardcore.v115.source_manifest.v1":
        raise RuntimeError("Unknown Native source manifest schema")
    native_define(manifest["source_sha256"])
    if git(ROOT, "rev-parse", "HEAD") != manifest["project_head"]:
        raise RuntimeError("Native project HEAD drift")
    if git(engine, "rev-parse", "HEAD") != manifest["engine_commit"]:
        raise RuntimeError("Native engine HEAD drift")
    rows = manifest["changed_files"] + manifest["module_inputs"]
    identities = [(r["root"], r["relative_path"]) for r in rows]
    for module_input in ("SCsub", "config.py", "simulation_host_original_primitives.cpp"):
        for root, prefix in (("engine", "modules/hardcore_simulation/"), ("project", "native/hardcore_simulation/")):
            if (root, prefix + module_input) not in identities:
                raise RuntimeError("Unsealed Native compile identity input: " + root + "/" + prefix + module_input)
    if len(set(identities)) != len(identities):
        raise RuntimeError("Duplicate sealed Native input")
    for row in rows:
        if re.fullmatch(r"[0-9a-f]{64}", row.get("sha256", "")) is None:
            raise RuntimeError("Invalid Native input SHA256")
    pairs = sorted(r["root"] + "/" + r["relative_path"] + ":" + r["sha256"] for r in rows)
    aggregate = hashlib.sha256(("\n".join(pairs) + "\n").encode("utf-8")).hexdigest()
    if manifest.get("source_fingerprint_algorithm") != FINGERPRINT_ALGORITHM or aggregate != manifest["source_sha256"]:
        raise RuntimeError("Native aggregate fingerprint or its declared algorithm differs")
    for row in rows:
        if row["root"] not in ("engine", "project"):
            raise RuntimeError("Unknown Native input root")
        path = bounded_input(engine if row["root"] == "engine" else ROOT, row["relative_path"])
        if sha(path) != row["sha256"]:
            raise RuntimeError("Sealed Native input drift: " + row["relative_path"])
    # Engine dirtiness is wholly declared. Project GDS/game dirtiness belongs
    # to the separate APK source freeze; only Native module mirrors and the
    # actual five compiled GDS seals are inputs to this Native-only build.
    declared = {r["relative_path"] for r in manifest["changed_files"] if r["root"] == "engine"}
    actual = set(git(engine, "diff", "--name-only", "HEAD").splitlines())
    actual.update(git(engine, "ls-files", "--others", "--exclude-standard").splitlines())
    if actual != declared:
        raise RuntimeError("Undeclared/missing dirty Native engine inputs: " + repr(sorted(actual ^ declared)))
    seals = manifest.get("reviewed_gd_seals", [])
    if len(seals) != 5:
        raise RuntimeError("Exactly five reviewed Native GDS seals required")
    for row in seals:
        if sha(bounded_input(ROOT, row["path"])) != row["after"]:
            raise RuntimeError("Compiled GDS seal drift: " + row["name"])
    return {"status": "PASS", "inputs": len(rows), "gd_seals": len(seals), "engine_head": manifest["engine_commit"], "source_sha256": aggregate}


def verify_elf(path: Path, machine: int, fingerprint: str | None) -> dict:
    with path.open("rb") as stream:
        header = stream.read(64)
    if len(header) != 64 or header[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", header, 18)[0] != machine:
        raise RuntimeError("Wrong Android ELF architecture: " + str(path))
    if fingerprint is None:
        return fact(path)
    native_define(fingerprint)
    needle = fingerprint.encode("ascii")
    found = False
    tail = b""
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            if needle in tail + block:
                found = True
                break
            tail = block[-len(needle):]
    if not found:
        raise RuntimeError("Expected Native fingerprint absent from actual JNI: " + str(path))
    return fact(path)


def verify_jni_zip(path: Path, expected: dict, prefix: str) -> dict:
    found = {}
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise RuntimeError("Duplicate ZIP members in actual packaged JNI: " + str(path))
        wanted_members = {f"{prefix}/{abi}/{name}" for abi, files in expected.items() for name in files}
        actual_members = {name for name in names if name.startswith(prefix + "/") and name.endswith(".so")}
        if actual_members != wanted_members:
            raise RuntimeError("Actual packaged JNI ABI set or library set mismatch: " + str(path))
        for abi, files in expected.items():
            found[abi] = {}
            for name, wanted in files.items():
                member = f"{prefix}/{abi}/{name}"
                if "bytes" in wanted and archive.getinfo(member).file_size != wanted["bytes"]:
                    raise RuntimeError("Packaged JNI byte size differs: " + member)
                value = hashlib.sha256()
                with archive.open(member) as stream:
                    for block in iter(lambda: stream.read(1 << 20), b""):
                        value.update(block)
                if value.hexdigest() != wanted["sha256"]:
                    raise RuntimeError("Packaged JNI differs from sealed build output: " + member)
                found[abi][name] = value.hexdigest()

    return found


def scons_command(scons: Path, engine: Path, config: dict, source_sha256: str,
                  target: str, arch: str, jobs: int) -> list[str]:
    if target not in ("debug", "release") or arch not in ARCHES:
        raise RuntimeError("Unapproved Native target or architecture")
    return [str(scons), "-C", str(engine), "platform=android", f"target=template_{target}",
            f"arch={arch}", f"precision={config['precision']}", "debug_symbols=no", "production=yes",
            native_define(source_sha256), "generate_android_binaries=no", f"-j{jobs}"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--sdk", required=True, type=Path)
    parser.add_argument("--java-home", required=True, type=Path)
    parser.add_argument("--java-socket-tmp-dir", type=Path,
                        help="Existing temporary directory for this build's child processes only; avoids Windows JDK AF_UNIX failures with DOS-short TEMP paths")
    parser.add_argument("--resume-jni-receipt", type=Path,
                        help="Reuse proven unchanged JNI from a terminal prior receipt, then run fresh official template packaging")
    parser.add_argument("--resume-jni-receipt-sha256")
    parser.add_argument("--scons", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=1)
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args()
    for name in ("manifest", "engine", "sdk", "java_home", "scons"):
        setattr(args, name, getattr(args, name).resolve(strict=True))
    if args.java_socket_tmp_dir is not None:
        args.java_socket_tmp_dir = args.java_socket_tmp_dir.resolve(strict=True)
        if not args.java_socket_tmp_dir.is_dir():
            raise RuntimeError("Java socket temporary path must be an existing directory")
    if (args.resume_jni_receipt is None) != (args.resume_jni_receipt_sha256 is None):
        raise RuntimeError("JNI resume requires both exact receipt and SHA256")
    args.output = args.output.resolve()
    if sha(args.manifest) != args.manifest_sha256:
        raise RuntimeError("Native manifest bytes differ")
    manifest = json.loads(args.manifest.read_text(encoding="utf-8-sig"))
    config = manifest["build_config"]
    ndk = args.sdk / "ndk" / config["ndk_version"]
    java = args.java_home / "bin/java.exe"
    gradle_root = args.engine / "platform/android/java"
    jar = gradle_root / "gradle/wrapper/gradle-wrapper.jar"
    for tool in [args.scons, java, jar, ndk / "source.properties"]:
        if not tool.is_file():
            raise RuntimeError("Required existing tool missing: " + str(tool))
    args.output.mkdir(parents=True, exist_ok=False)
    receipt_path = args.output / "ANDROID_TEMPLATE_RECEIPT.json"
    receipt = {"status": "NOT_RUN", "scope": "Sealed Native Android JNI/templates only; no game/signing/install acceptance",
               "manifest": fact(args.manifest), "native_source_sha256": manifest["source_sha256"],
               "game_APK115": "NOT_RUN", "device_test": "NOT_RUN", "commands": [], "jni": {}, "artifacts": {},
               "builder": fact(Path(__file__).resolve()), "runtime_capability": "NOT_RUN",
               "compile_identity_argument": native_define(manifest["source_sha256"])}
    env = dict(os.environ)
    for key in ["PYTHONHOME", "PYTHONPATH"]:
        env.pop(key, None)
    env.update(ANDROID_HOME=str(args.sdk), ANDROID_SDK_ROOT=str(args.sdk), JAVA_HOME=str(args.java_home))
    # Gradle configures its native tasks even when the official template task
    # excludes their execution. Resolve the same already-pinned SCons in PATH.
    env["PATH"] = str(args.scons.parent) + os.pathsep + env.get("PATH", "")
    if args.java_socket_tmp_dir is not None:
        # JDK17 UnixDomainSocketsUtil prefers TEMP even over java.io.tmpdir.
        # Keep the tested canonical socket path for launcher/daemon/workers;
        # never modify the user's process or persistent environment.
        env.update(TEMP=str(args.java_socket_tmp_dir), TMP=str(args.java_socket_tmp_dir))
        receipt["java_socket_temporary_directory"] = {
            "path": str(args.java_socket_tmp_dir), "scope": "build child processes only"}

    def save() -> None:
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")

    receipt["tools"] = [fact(path) for path in [args.scons, java, jar, ndk / "source.properties"]]
    resume = None
    if args.resume_jni_receipt is not None:
        args.resume_jni_receipt = args.resume_jni_receipt.resolve(strict=True)
        if sha(args.resume_jni_receipt) != args.resume_jni_receipt_sha256:
            raise RuntimeError("Prior JNI receipt SHA256 differs")
        resume = json.loads(args.resume_jni_receipt.read_text(encoding="utf-8-sig"))
        if (resume.get("status") not in ("PASS", "FAIL", "BLOCKED")
                or resume.get("native_source_sha256") != manifest["source_sha256"]
                or resume.get("manifest", {}).get("sha256") != args.manifest_sha256
                or resume.get("tools") != receipt["tools"]):
            raise RuntimeError("Prior JNI receipt is active, foreign, or has different pinned tools/source")
        receipt["reused_native_receipt"] = fact(args.resume_jni_receipt)
        receipt["reused_native_builds"] = []

    def frozen() -> dict:
        for tool in receipt["tools"]:
            if sha(Path(tool["path"])) != tool["sha256"]:
                raise RuntimeError("Pinned Android build tool drift: " + tool["path"])
        if sha(args.manifest) != args.manifest_sha256:
            raise RuntimeError("Native manifest bytes changed during build")
        if sha(Path(__file__).resolve()) != receipt["builder"]["sha256"]:
            raise RuntimeError("Native build tool changed during build")
        return verify_inputs(manifest, args.engine)

    def run(command: list[str], label: str, preexisting: dict | None = None) -> dict:
        before = frozen()
        log = args.output / (label + ".log")
        record = {"argv": command, "cwd": str(gradle_root), "log": str(log),
                  "started": time.time(), "started_ns": time.time_ns(), "inputs_before": before, "preexisting_artifacts": preexisting or {}}
        receipt["commands"].append(record)
        save()
        with log.open("wb") as stream:
            result = subprocess.run(command, cwd=gradle_root, env=env, stdout=stream, stderr=subprocess.STDOUT)
        record.update(exit_code=result.returncode, finished=time.time())
        save()
        record["inputs_after"] = frozen()
        save()
        if result.returncode:
            raise RuntimeError(label + " failed; see " + str(log))
        return record

    try:
        receipt["preflight"] = frozen()
        if config.get("android_archs") != list(ARCHES) or config.get("android_abis") != [a[0] for a in ARCHES.values()]:
            raise RuntimeError("BLOCKED: manifest must explicitly seal both phone and emulator architectures")
        receipt["compile_identity_source"] = verify_identity_source(args.engine)
        receipt["status"] = "PASS"
        receipt["build"] = "NOT_RUN"
        save()
        if not args.build:
            print(json.dumps({"status": "PASS", "scope": "Native preflight ONLY", "receipt": str(receipt_path)}))
            return 0
        receipt["status"] = "NOT_RUN"
        receipt["build"] = "NOT_RUN"
        for target in ("debug", "release"):
            receipt["jni"][target] = {}
            for arch, (abi, machine) in ARCHES.items():
                command = scons_command(args.scons, args.engine, config, manifest["source_sha256"], target, arch, args.jobs)
                source = gradle_root / f"lib/libs/{target}/{abi}"
                if resume is not None:
                    records = [record for record in resume.get("commands", []) if record.get("argv") == command]
                    before = frozen()
                    if (len(records) != 1 or records[0].get("exit_code") != 0
                            or records[0].get("inputs_before") != before
                            or records[0].get("inputs_after") != before):
                        raise RuntimeError("Prior JNI needs one exact successful SCons command and unchanged source: " + target + "/" + arch)
                    record = records[0]
                    prior = resume.get("jni", {}).get(target, {}).get(abi, {})
                    files = {}
                    for name in ("libgodot_android.so", "libc++_shared.so"):
                        path = source / name
                        saved = prior.get(name, {})
                        if not saved or Path(saved["path"]).resolve() != path.resolve():
                            raise RuntimeError("Prior JNI path differs: " + str(path))
                        current = verify_elf(path, machine, manifest["source_sha256"] if name == "libgodot_android.so" else None)
                        if current["sha256"] != saved.get("sha256") or current["bytes"] != saved.get("bytes"):
                            raise RuntimeError("Prior JNI bytes changed: " + str(path))
                        if name == "libgodot_android.so":
                            fresh = verify_fresh(path, record["started_ns"])
                            if (fresh["mtime_ns"] != saved.get("mtime_ns")
                                    or saved.get("produced_after_ns") != record["started_ns"]):
                                raise RuntimeError("Prior JNI original build timestamp differs: " + str(path))
                        else:
                            triple = "aarch64-linux-android" if arch == "arm64" else "x86_64-linux-android"
                            runtime = ndk / f"toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/lib/{triple}/libc++_shared.so"
                            if saved.get("ndk_source") != fact(runtime) or sha(runtime) != current["sha256"]:
                                raise RuntimeError("Prior JNI runtime differs from pinned NDK")
                        files[name] = saved
                    receipt["jni"][target][abi] = files
                    receipt["reused_native_builds"].append({"original_command": record, "original_log": fact(Path(record["log"])), "verified_inputs": before})
                    save()
                    continue
                previous = {name: fact(source / name) if (source / name).is_file() else None
                            for name in ("libgodot_android.so", "libc++_shared.so")}
                record = run(command, f"scons_{target}_{arch}", previous)
                fresh = verify_fresh(source / "libgodot_android.so", record["started_ns"])
                files = {"libgodot_android.so": verify_elf(source / "libgodot_android.so", machine, manifest["source_sha256"])}
                files["libgodot_android.so"].update(mtime_ns=fresh["mtime_ns"], produced_after_ns=record["started_ns"])
                files["libc++_shared.so"] = verify_elf(source / "libc++_shared.so", machine, None)
                triple = "aarch64-linux-android" if arch == "arm64" else "x86_64-linux-android"
                runtime = ndk / f"toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/lib/{triple}/libc++_shared.so"
                if not runtime.is_file() or sha(runtime) != files["libc++_shared.so"]["sha256"]:
                    raise RuntimeError("JNI C++ runtime differs from pinned NDK source: " + str(runtime))
                files["libc++_shared.so"]["ndk_source"] = fact(runtime)
                receipt["jni"][target][abi] = files
                save()
        # Filter both AAR and APK to exactly the two verified ABIs; do not delete
        # other pre-existing engine libraries. Keep exact JNI bytes for audit.
        init = args.output / "exact_native_abis.gradle"
        init.write_text("""allprojects { p ->
    ['com.android.library','com.android.application'].each { kind ->
        p.plugins.withId(kind) {
            p.android.defaultConfig.ndk.abiFilters.clear()
            p.android.defaultConfig.ndk.abiFilters.addAll(['arm64-v8a','x86_64'])
        }
    }
}
""", encoding="utf-8")
        receipt["gradle_init"] = fact(init)
        old_packages = {name: fact(args.engine / "bin" / name) if (args.engine / "bin" / name).is_file() else None
                        for name in ("android_debug.apk", "android_release.apk", "android_source.zip")}
        gradle_record = run([str(java), "-Xmx64m", "-Xms64m", "-classpath", str(jar), "org.gradle.wrapper.GradleWrapperMain",
             "--no-daemon", f"--max-workers={args.jobs}", "-Dorg.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m",
             "--init-script", str(init), "-Pexport_enabled_abis=arm64-v8a|x86_64", "-PdoNotStrip=true",
             "generateGodotTemplates"], "gradle_actual_templates", old_packages)
        templates = args.output / "templates"
        templates.mkdir()
        for target in ("debug", "release"):
            source = args.engine / f"bin/android_{target}.apk"
            verify_fresh(source, gradle_record["started_ns"])
            receipt["artifacts"][target] = {"jni": verify_jni_zip(source, receipt["jni"][target], "lib")}
            dest = templates / source.name
            shutil.copyfile(source, dest)
            receipt["artifacts"][target]["file"] = fact(dest)
        source_zip = args.engine / "bin/android_source.zip"
        verify_fresh(source_zip, gradle_record["started_ns"])
        with zipfile.ZipFile(source_zip) as archive:
            for target in ("debug", "release"):
                name = f"libs/{target}/godot-lib.template_{target}.aar"
                aar = args.output / f"source_{target}.aar"
                with archive.open(name) as source, aar.open("wb") as dest:
                    shutil.copyfileobj(source, dest, 1 << 20)
                receipt["artifacts"]["source_" + target] = {"file": fact(aar), "jni": verify_jni_zip(aar, receipt["jni"][target], "jni")}
        dest = templates / source_zip.name
        shutil.copyfile(source_zip, dest)
        receipt["artifacts"]["source_zip"] = fact(dest)
        for targets in receipt["jni"].values():
            for libraries in targets.values():
                for library in libraries.values():
                    if sha(Path(library["path"])) != library["sha256"]:
                        raise RuntimeError("Actual JNI changed during packaging: " + library["path"])
        receipt["postflight"] = frozen()
        receipt["status"] = "PASS"
        receipt["build"] = "PASS"
        save()
        print(json.dumps({"status": "PASS", "scope": receipt["scope"], "receipt": str(receipt_path)}))
        return 0
    except Exception as error:
        receipt["status"] = "BLOCKED" if str(error).startswith("BLOCKED:") else "FAIL"
        receipt["error"] = str(error)
        save()
        raise


if __name__ == "__main__":
    sys.exit(main())
