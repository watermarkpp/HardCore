"""Materialize one tracked, hash-bound source according to its exact checkout EOL."""
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path(sys.argv[1]).resolve()
rel='tools/loot_sheet_compiler/evidence/armor_single_slot_directive_v92.json'
attribute=subprocess.check_output(['git','-C',str(root),'check-attr','eol','--',rel],text=True).strip()
if not attribute.endswith(': eol: crlf'):
    raise SystemExit('Exact CRLF checkout contract missing')
blob=subprocess.check_output(['git','-C',str(root),'show',f'HEAD:{rel}'])
canonical=blob.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
authority=json.loads((root/'assets/data/drop/dpv2_user_loot_sheet_authority_v1.json').read_text(encoding='utf-8-sig'))
expected=authority['source']['armor_single_slot_directive_sha256']
if hashlib.sha256(canonical).hexdigest()!=expected:
    raise SystemExit('Git-source materialization does not match published binding; no write')
path=root/rel
before=hashlib.sha256(path.read_bytes()).hexdigest()
if before!=expected:
    path.write_bytes(canonical)
print(json.dumps({'status':'PASS','path':rel,'attribute':attribute,'before':before,'expected':expected,'final':hashlib.sha256(path.read_bytes()).hexdigest(),'source':'independent Git HEAD blob + exact checkout attribute; no Main-file/cache copy'},ensure_ascii=False))
