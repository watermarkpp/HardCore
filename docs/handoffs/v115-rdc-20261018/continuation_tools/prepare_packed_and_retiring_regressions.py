from pathlib import Path
D=Path(__file__).resolve().parent;R=D.parents[3]
# Existing real service lifecycle component: strengthen its actual transitions.
p=R/'tests/framework/multicore_service_registry_core_20261014.gd';b=p.read_bytes();s=p.read_text(encoding='utf-8');(D/'service_registry_core.before_retiring_checks.gd').write_bytes(b)
n='\tvar scheduler_id: int = scheduler_handle.get_instance_id()'
assert s.count(n)==1;s=s.replace(n,n+'\n\tvar has_retiring_lookup: bool = _registry.has_method("resolve_original_retiring_service")\n\t_check(has_retiring_lookup,"real registry provides original retiring-handle lookup")\n\tif has_retiring_lookup: _check(_registry.resolve_original_retiring_service(driver_id)==null and _registry.resolve_original_retiring_service(0)==null and _registry.resolve_original_retiring_service(-1)==null,"retirement-only lookup rejects active/invalid identities")')
n='\t_check(driver_handle.is_inside_world() and driver_handle.is_queued_for_retirement() and _scheduler.jobs.has(driver_id), "queued and inside remain independent; accepted task retained before exit")'
assert s.count(n)==1;s=s.replace(n,n+'\n\tif has_retiring_lookup: _check(_registry.resolve_original_retiring_service(driver_id)==null,"queued alone is not the original retiring boundary")')
n='\t_check(_registry.resolve_service(driver_id) == null, "retiring service cannot resolve for new jobs")'
assert s.count(n)==1;s=s.replace(n,n+'\n\tif has_retiring_lookup: _check(_registry.resolve_original_retiring_service(driver_id)==driver_handle and _registry.resolve_original_retiring_service(driver_id).model()==_driver and _registry.resolve_original_retiring_service(scheduler_id)==null,"same canonical retiring Object/model remains available only to original final-free")')
n='\t_check(not is_instance_valid(driver_handle), "canonical driver ObjectID is invalid after final-free")'
assert s.count(n)==1;s=s.replace(n,n+'\n\tif has_retiring_lookup: _check(_registry.resolve_original_retiring_service(driver_id)==null,"final-free removes original retiring identity")')
p.write_text(s,encoding='utf-8')
# Same actual Native FIFO, with every Packed leaf type nested below containers.
p=R/'tests/framework/helpers/publication_prefix_packed_source_20261018.gd';assert not p.exists()
s=(R/'tests/framework/helpers/publication_prefix_immutable_source_20261018.gd').read_text(encoding='utf-8')
s=s.replace('"nested":{"array":[{"index":index}]}','"nested":{"array":[{"index":index,"packed_leaves":[PackedByteArray(),PackedByteArray([1,2]),PackedInt32Array(),PackedInt64Array(),PackedFloat32Array(),PackedFloat64Array(),PackedStringArray(),PackedVector2Array(),PackedVector3Array(),PackedColorArray(),PackedVector4Array()]}]}')
p.write_text(s,encoding='utf-8')
p=R/'tests/framework/publication_prefix_packed_20261018.gd';assert not p.exists()
s=(R/'tests/framework/publication_batch_20261018.gd').read_text(encoding='utf-8').replace('publication_batch_source_20261018.gd','publication_prefix_packed_source_20261018.gd')
n='\t\tBudget.configure_for_tests(0,_budget_epoch,Callable())'
extra='''\t\tvar exposed: Dictionary = _host.inspect_next_original_published_prefix().prefix
\t\tvar empty_alias = exposed.events[0].nested.array[0].packed_leaves[0]
\t\tvar filled_alias = exposed.events[0].nested.array[0].packed_leaves[1]
\t\tempty_alias.append(9); filled_alias[0]=9
\t\tcheck(exposed.events[0].nested.array[0].packed_leaves[0].size()==1 and exposed.events[0].nested.array[0].packed_leaves[1][0]==9,"actual Packed aliases mutate nested data while top identity is retained")
\t\tcheck(not exposed.is_read_only(),"Packed-containing prefixes keep original uncached decode semantics")
\t\tvar fresh: Dictionary = _host.inspect_next_original_published_prefix().prefix
\t\tcheck(not is_same(exposed,fresh) and fresh.events[0].nested.array[0].packed_leaves[0].is_empty() and fresh.events[0].nested.array[0].packed_leaves[1][0]==1,"repeat inspect cannot expose an earlier caller's modified Packed alias")
\t\tif exposed.is_read_only():
\t\t\t# The unsafe old candidate would wrongly claim original bytes. Record
\t\t\t# its failure without stealing a live claim from the production pump.
\t\t\tcheck(false,"modified Packed alias must use original wire rejection")
\t\telse: check(_host.acquire_original_main_prefix(exposed).is_empty(),"modified Packed alias must use original wire rejection")
'''
assert s.count(n)==1;s=s.replace(n,extra+n);p.write_text(s,encoding='utf-8')
p=R/'tests/framework/publication_prefix_packed_20261018.tscn';assert not p.exists();p.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/framework/publication_prefix_packed_20261018.gd" id="1"]\n[node name="PublicationPrefixPacked" type="Node"]\nscript = ExtResource("1")\n',encoding='utf-8')
print('Actual Packed alias/fallback and real service retirement transitions prepared for RED')
