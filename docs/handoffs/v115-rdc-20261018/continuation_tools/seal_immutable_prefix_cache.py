from pathlib import Path
import json,hashlib,importlib.util
D=Path(__file__).resolve().parent;R=D.parents[3];O=D.parent;E=Path('C:/Users/Administrator/Documents/HardCore-engine-v115/godot')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
old=O/'SOURCE_MANIFEST.caster_close_cleanup_20261018.json';m=json.loads(old.read_text(encoding='utf-8-sig'))
for group in ['changed_files','module_inputs']:
    for x in m[group]:x['sha256']=sha((E if x['root']=='engine' else R)/x['relative_path'])
assert len(m['changed_files'])+len(m['module_inputs'])==171
for n in ['simulation_host.h','simulation_host_original_primitives.cpp']:
    assert (R/'native/hardcore_simulation'/n).read_bytes()==(E/'modules/hardcore_simulation'/n).read_bytes()
for row in m['reviewed_gd_seals']:assert sha(R/row['path'])==row['after']
pairs=sorted(f"{x['root']}/{x['relative_path']}:{x['sha256']}" for x in m['changed_files']+m['module_inputs'])
m['source_sha256']=hashlib.sha256(('\n'.join(pairs)+'\n').encode()).hexdigest()
m['source_scope']='Preserved fc43 real cleanup fixes; Main deeply immutable accepted-prefix exact-wire reuse, full foreign/mutable fallback. Game/warehouse/APK NOT_RUN.'
new=O/'SOURCE_MANIFEST.immutable_prefix_cache_20261018.json';assert not new.exists();new.write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8')
s=(O/'build_windows_caster_close_cleanup_20261018.py').read_text(encoding='utf-8').replace('windows_caster_close_cleanup_20261018_build','windows_immutable_prefix_cache_20261018_build').replace(old.name,new.name).replace(sha(old),sha(new)).replace('fc43ab30cb3ebddb089278d67bafbbe18cedd878ed849b589e8761ad4750c9de',m['source_sha256'])
s=s.replace('Original LIVE code-result cleanup and retained ACK wake;','Deeply immutable Main accepted-prefix reuse; retained original LIVE cleanup and ACK wake;')
p=O/'build_windows_immutable_prefix_cache_20261018.py';assert not p.exists();p.write_text(s,encoding='utf-8')
spec=importlib.util.spec_from_file_location('validator',R/'tools/build_hardcore_android_templates.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
receipt={'status':'PASS','scope':'171 input/five seals/mirrors only; no engine or game acceptance','validation':v.verify_inputs(m,E),'manifest':str(new),'manifest_sha256':sha(new),'source_sha256':m['source_sha256'],'windows_builder':str(p),'Windows':'NOT_RUN','Android':'NOT_RUN','component_GREEN':'NOT_RUN','World':'NOT_RUN','SourceSave':'NOT_RUN','APK':'NOT_RUN'}
(D/'IMMUTABLE_PREFIX_NATIVE_SEAL.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8');print(json.dumps(receipt))
