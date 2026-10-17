from pathlib import Path
import hashlib,json
D=Path(__file__).resolve().parent;R=D.parents[3];E=Path('C:/Users/Administrator/Documents/HardCore-engine-v115/godot')
proof=json.loads((R/'outputs/v115_multicore/invocations/codex_immutable_prefix_RED_20261018_01/PROTECTION.json').read_text(encoding='utf-8-sig'));assert proof['source_unchanged'] and proof['real_index_preserved']
out=D/'immutable_prefix_cache_preimages';out.mkdir(exist_ok=False)
changed=[]
for name in ['simulation_host.h','simulation_host_original_primitives.cpp']:
    rp=R/'native/hardcore_simulation'/name;ep=E/'modules/hardcore_simulation'/name
    before=rp.read_bytes();assert before==ep.read_bytes(),name
    (out/name).write_bytes(before);s=rp.read_text(encoding='utf-8')
    if name.endswith('.h'):
        old='\tstd::unique_ptr<OriginalMailbox> original_primitives;'
        new=old+'''
\t// Main-only cache of the actual accepted immutable Native wire. It is not
\t// a publication, claim, receipt, event cursor or gameplay authority.
\tOriginalMailbox::Prefix main_published_prefix_cache;
\tDictionary main_published_prefix_value;
\tbool cached_original_published_prefix(const Dictionary &p_value, OriginalMailbox::Prefix &r_prefix) const;'''
        assert s.count(old)==1;s=s.replace(old,new)
    else:
        needle='bool integer(const Dictionary&d,const char*k,int64_t&v)'
        pos=s.index(needle)
        s=s[:pos]+'''// Only a freshly decoded, already validated plain Native prefix reaches
// this seal. Delta events sent to the physical dispatcher remain independent
// mutable decodes, exactly as before; only the framing snapshot is shared.
void seal_main_prefix_value(const Variant &value) {
    if(value.get_type()==Variant::ARRAY){
        Array values=value;const Array &read=values;
        for(int i=0;i<read.size();++i)seal_main_prefix_value(read[i]);
        values.make_read_only();
    }else if(value.get_type()==Variant::DICTIONARY){
        Dictionary values=value;const Array keys=values.keys();
        for(int i=0;i<keys.size();++i){seal_main_prefix_value(keys[i]);seal_main_prefix_value(values.get(keys[i],Variant()));}
        values.make_read_only();
    }
}
'''+s[pos:]
        needle='int64_t HardCoreSimulationHost::owner_thread_id()const'
        pos=s.index(needle)
        s=s[:pos]+'''bool HardCoreSimulationHost::cached_original_published_prefix(const Dictionary &value, OriginalMailbox::Prefix &prefix) const {
    if(!Thread::is_main_thread()||main_published_prefix_value.is_empty()||!value.is_read_only()||value.id()!=main_published_prefix_value.id()||!main_published_prefix_cache.bytes||main_published_prefix_cache.generation!=bridge_generation)return false;
    // Exact collection identity is safe only because the entire decoded tree
    // is read-only and this owner retains it. Mutable/foreign/equal copies use
    // the original full validation and encoding path below, without trust.
    prefix=main_published_prefix_cache;
    return true;
}
'''+s[pos:]
        old='Mailbox::Prefix prefix;int64_t generation=0,journal=0,through=0;\n    if(!prefix_wire(p,bridge_generation,prefix)||a.size()!=4'
        new='Mailbox::Prefix prefix;int64_t generation=0,journal=0,through=0;\n    if((!cached_original_published_prefix(p,prefix)&&!prefix_wire(p,bridge_generation,prefix))||a.size()!=4'
        assert s.count(old)==1;s=s.replace(old,new)
        needle='    // A final ordinary ACK may be the only remaining closing progress.'
        assert s.count(needle)==1;s=s.replace(needle,'    main_published_prefix_value=Dictionary();main_published_prefix_cache=Mailbox::Prefix();\n'+needle)
        old='ERR_FAIL_COND_V(!Thread::is_main_thread()||!original_primitives,Dictionary());Mailbox::Prefix prefix;if(!prefix_wire(p,bridge_generation,prefix))return {};\n    auto claim=original_primitives->claim_main_prefix(prefix);'
        new='ERR_FAIL_COND_V(!Thread::is_main_thread()||!original_primitives,Dictionary());Mailbox::Prefix prefix;const bool cached=cached_original_published_prefix(p,prefix);if(!cached&&!prefix_wire(p,bridge_generation,prefix))return {};\n    auto claim=original_primitives->claim_main_prefix(prefix);'
        assert s.count(old)==1;s=s.replace(old,new)
        old='Dictionary d;d["main_prefix"]=p.duplicate(true);d["after_ordinal"]'
        new='Dictionary d;d["main_prefix"]=cached?p:p.duplicate(true);d["after_ordinal"]'
        assert s.count(old)==1;s=s.replace(old,new)
        old='''    if(read.status==State::READY){
        Variant prefix;
        if(!thaw(read.prefix.bytes,prefix)){out["status"]="INVALID";out["error"]="registered_prefix_wire_invalid";return out;}
        out["prefix"]=prefix;
    }'''
        new='''    if(read.status==State::READY){
        if(main_published_prefix_cache.bytes!=read.prefix.bytes){
            Variant prefix;
            if(!thaw(read.prefix.bytes,prefix)||prefix.get_type()!=Variant::DICTIONARY){out["status"]="INVALID";out["error"]="registered_prefix_wire_invalid";return out;}
            seal_main_prefix_value(prefix);
            main_published_prefix_value=prefix;
            main_published_prefix_cache=read.prefix;
        }
        out["prefix"]=main_published_prefix_value;
    }'''
        assert s.count(old)==1;s=s.replace(old,new)
    data=s.encode('utf-8')
    for f in [rp,ep]:f.write_bytes(data)
    changed.append({'name':name,'before':hashlib.sha256(before).hexdigest(),'after':hashlib.sha256(data).hexdigest()})
(D/'IMMUTABLE_PREFIX_CACHE_IMPLEMENTATION.json').write_text(json.dumps({'status':'NOT_RUN','scope':'Main exact deeply immutable prefix snapshot -> reuse same accepted wire for acquire/ACK; same Native claim/physical event delta/ACK/receipt; mutable copies retain original full-validation fallback','RED':'codex_immutable_prefix_RED_20261018_01 actual31/3 native1/errors0/protectiontrue','World39':'FAIL initial_bootstrap_timeout before exit fix exercised; repeated Native acquisition/ACK encoding dominant, raw retained','files':changed,'required':'new Native seal + Windows/Android builds + component GREEN + fixed-source World + six save stages + genuine115 APK'},indent=2)+'\n',encoding='utf-8')
print(json.dumps(changed))
