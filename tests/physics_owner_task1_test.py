"""Compile the phase protocol test only. This is not a physics/motion parity test."""
from pathlib import Path
import argparse,subprocess,shutil,json,hashlib,datetime
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',choices=['cl','g++'],default='cl');args=parser.parse_args()
    output=ROOT/'outputs/v115_multicore/physics_exact_rework/protocol';output.mkdir(parents=True,exist_ok=True)
    sources=[ROOT/'native/hardcore_simulation/physics_port.cpp',ROOT/'tests/physics_owner_task1_test.cpp']
    exe=output/'physics_owner_protocol.exe'
    if args.compiler=='cl':cmd=['cl','/nologo','/std:c++17','/EHsc','/W4','/WX',*map(str,sources),'/Fe:'+str(exe)]
    else:cmd=['g++','-std=c++17','-Wall','-Wextra','-Werror',*map(str,sources),'-o',str(exe)]
    built=subprocess.run(cmd,cwd=output,capture_output=True,text=True);(output/'build.log').write_text(built.stdout+built.stderr)
    rc=built.returncode
    if rc==0:
        run=subprocess.run([str(exe)],cwd=output,capture_output=True,text=True);rc=run.returncode;(output/'run.log').write_text(run.stdout+run.stderr)
    receipt={'status':'PASS' if rc==0 else 'FAIL','scope':'Standalone phase protocol only; real engine motion and owner validation NOT_RUN','command':cmd,'native_exit':rc,'inputs':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
    (output/'RECEIPT.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt,indent=2));return rc
if __name__=='__main__':raise SystemExit(main())
