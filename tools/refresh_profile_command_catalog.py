"""Regenerate original Profile method seals with an exact reviewed arity delta.

Does not discover extra commands or loosen the existing read/command surface.
The review binds both the old catalogue and actual new Model bytes.
"""
import argparse,hashlib,json,re,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'outputs/v115_multicore/actor_runtime_ports_20261014/parser_runtime'))
from gdtoolkit.parser import parser
sha=lambda b:hashlib.sha256(b).hexdigest()
p=argparse.ArgumentParser();p.add_argument('--review',type=Path,required=True);p.add_argument('--receipt',type=Path,required=True);a=p.parse_args()
review=json.loads(a.review.read_text(encoding='utf-8-sig'))
path=root/'scripts/gameplay/source/profile_original_command_catalog.gd';before=path.read_bytes();text=before.decode('utf-8-sig')
model_path=root/'scripts/gameplay/profile/profile_model.gd';model_bytes=model_path.read_bytes();model=model_bytes.decode('utf-8-sig').replace('\r\n','\n')
assert review['catalog_before_sha256']==sha(before)
assert review['model_after_sha256']==sha(model_bytes)
assert isinstance(review['reason'],str) and review['reason'].strip()
arities=json.loads(text.split('const ARITIES: Dictionary = ',1)[1].split('\nconst READ_FIELDS:',1)[0])
fields=json.loads(text.split('const READ_FIELDS: Array[String] = ',1)[1].split('\nconst SOURCE_METHOD_SHA256:',1)[0])
for name,change in review['arity_changes'].items():
 assert arities[name]==change['before'],name
 assert change['after']==[len(change['parameters'])],name
 arities[name]=change['after']
tree=parser.parse(model,gather_metadata=True);funcs={str(n.children[0].children[0]):n for n in tree.iter_subtrees_topdown() if n.data=='func_def'}
assert set(arities).issubset(funcs)
hashes={name:sha(model[n.meta.start_pos:n.meta.end_pos].encode()) for name,n in funcs.items() if name in arities}
body='extends RefCounted\n## Generated exact original UI->Profile call and read contract.\nconst ARITIES: Dictionary = '+json.dumps(arities,indent=2)+'\nconst READ_FIELDS: Array[String] = '+json.dumps(fields,indent=2)+'\nconst SOURCE_METHOD_SHA256: Dictionary = '+json.dumps(hashes,indent=2,sort_keys=True)+'\nstatic func accepts(method: String,size: int)->bool:\n\treturn ARITIES.has(method) and size in ARITIES[method]\n'
path.write_text(body,encoding='utf-8',newline='\n')
a.receipt.write_text(json.dumps({'status':'PASS','scope':'Formal catalogue generation only; runtime NOT_RUN','catalog_before':sha(before),'catalog_after':sha(path.read_bytes()),'model_after':sha(model_bytes),'review_sha256':sha(a.review.read_bytes()),'command_set_preserved':True,'read_fields_preserved':True,'changed_arities':review['arity_changes']},indent=2),encoding='utf-8')
print('PROFILE_COMMAND_CATALOG_GENERATED',sha(path.read_bytes()))
