#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]; DATA=ROOT/"assets/data/map_design"
ALLOWED={"remake_compact","shrink_and_recompose","preserve_function","preserve_route","reduce_duplicates","preserve_arena","exact_clone_of_orc_tomb_1","exact_clone_of_wooma_temple_1","exact_clone_of_stone_tomb_1","exact_clone_of_zuma_temple_1"}
def main():
    catalog=json.loads((DATA/"map_design_catalog.json").read_text(encoding="utf-8")); errors=[]; warnings=[]
    blank=json.loads((DATA/"map_blank_templates.json").read_text(encoding="utf-8"))
    registry=json.loads((DATA/"map_identity_registry.json").read_text(encoding="utf-8"))
    overrides=json.loads((DATA/"map_scale_overrides.json").read_text(encoding="utf-8"))
    maps=catalog.get("maps",[]); blank_templates=blank.get("templates",[]); seen=set()
    canonical={str(row.get("map_id")):row for row in registry.get("maps",[])}
    authoring={str(row.get("map_id")):row for row in overrides.get("overrides",[])}
    # The override file is the authoring authority for decisions that the
    # catalogue must preserve.  Keep this list data-driven: new fields can be
    # added to the authoring contract without reintroducing an old hard-coded
    # map inventory.
    authoring_contract_fields=(
        "runtime_map_id", "name", "map_type", "design_size",
        "pre_scale_design_size", "size_status", "size_decision_source",
        "source_map_path", "source_usage", "strategy",
        "clone_source_map_id", "source_distribution",
    )
    legal_legacy={str(row.get("legacy_map_id")) for row in registry.get("maps",[])}
    legal_template_map_ids=set(canonical) | legal_legacy
    allowed_strategies={str(row.get("strategy")) for row in overrides.get("overrides",[])}
    factor=Decimal(str(catalog.get("scale_policy",{}).get("factor",0)))
    for m in maps:
        mid=m.get("map_id"); size=m.get("design_size",[]); maxs=m.get("template_max_size",[])
        if not mid or mid in seen: errors.append(f"duplicate/missing map_id: {mid}")
        if mid not in canonical and mid not in authoring:
            errors.append(f"{mid}: unknown canonical/authoring map_id")
        elif mid in canonical:
            accepted_runtime_ids = {
                canonical[mid].get("runtime_map_id"),
                canonical[mid].get("legacy_runtime_map_id"),
            }
            if m.get("runtime_map_id") not in accepted_runtime_ids:
                errors.append(f"{mid}: runtime_map_id differs from canonical registry")
        seen.add(mid)
        for key in ("runtime_map_id","name","map_type","source_map_path","strategy","coordinate_systems"):
            if key not in m: errors.append(f"{mid}: missing {key}")
        if len(size)!=2 or min(size)<=0: errors.append(f"{mid}: invalid design_size")
        elif len(maxs)==2 and (size[0]>maxs[0] or size[1]>maxs[1]): errors.append(f"{mid}: exceeds template max")
        if m.get("strategy") not in allowed_strategies: errors.append(f"{mid}: invalid strategy")
        if m.get("map_type")=="boss_room" and min(size)<18: errors.append(f"{mid}: scaled boss room below 18")
        if m.get("map_type")=="shop_interior" and max(size)>40: warnings.append(f"{mid}: shop above 40")
        if m.get("map_type")=="outdoor_province" and max(size)>320: errors.append(f"{mid}: province above 320")
        if m.get("map_type")=="maze_room" and max(size)>80: warnings.append(f"{mid}: maze above 80")
        if m.get("source_size_is_design_size") is not False: errors.append(f"{mid}: source/design separation missing")
        if m.get("source_audit_status") in ("unresolved","missing"): warnings.append(f"{mid}: source {m['source_audit_status']}")
        if not isinstance(m.get("source_audit_status"), str) or not m.get("source_audit_status"):
            errors.append(f"{mid}: missing source_audit_status")
        if mid in authoring:
            source=authoring[mid]
            for field in authoring_contract_fields:
                if field in source and m.get(field) != source[field]:
                    errors.append(f"{mid}: {field} differs from authoring override")
        original=m.get("pre_scale_design_size",[])
        if len(original)!=2: errors.append(f"{mid}: missing pre-scale size")
        else:
            scaled=[int((Decimal(int(value))*factor).quantize(Decimal("1"),rounding=ROUND_HALF_UP)) for value in original]
            size_is_user_confirmed = str(m.get("size_status", "")).startswith("user_confirmed_")
            if not str(m.get("strategy", "")).startswith("exact_clone_of_") and not size_is_user_confirmed and size!=scaled: errors.append(f"{mid}: scale mismatch {size} != {scaled}")
    lookup={m["map_id"]:m for m in maps}
    missing_authoring=sorted(set(authoring) - set(lookup))
    for missing in missing_authoring:
        errors.append(f"{missing}: missing catalog map for authoring override")
    template_ids=set()
    template_map_ids=set()
    canonical_by_legacy={str(row.get("legacy_map_id")):str(row.get("map_id")) for row in registry.get("maps",[])}
    for template in blank_templates:
        template_id=str(template.get("template_id", ""))
        template_map_id=str(template.get("map_id", ""))
        if not template_id or template_id in template_ids:
            errors.append(f"duplicate/missing template_id: {template_id}")
        template_ids.add(template_id)
        if template_map_id not in legal_template_map_ids:
            errors.append(f"{template_id}: unknown legacy/canonical map_id")
        if template_map_id in template_map_ids:
            errors.append(f"duplicate template map_id: {template_map_id}")
        template_map_ids.add(template_map_id)
        if template.get("template_kind") not in ("existing_map_or_empty_template", "empty_map"):
            errors.append(f"{template_id}: invalid template_kind")
        expected_policy={
            "existing_map_or_empty_template": "open_existing_workspace_first",
            "empty_map": "empty_layers",
        }.get(template.get("template_kind"))
        if expected_policy and template.get("content_policy") != expected_policy:
            errors.append(f"{template_id}: content_policy disagrees with template_kind")
        for field in ("design_size", "pre_scale_design_size"):
            value=template.get(field)
            if not isinstance(value, list) or len(value)!=2 or any(float(v)<=0 for v in value):
                errors.append(f"{template_id}: invalid {field}")
        canonical_id=template_map_id if template_map_id in lookup else canonical_by_legacy.get(template_map_id)
        target=lookup.get(canonical_id) if canonical_id else None
        if target:
            # Blank templates may intentionally use an empty-layer strategy
            # even when the runtime catalog uses an exact clone strategy; the
            # identity and physical size must still agree.
            for field in ("runtime_map_id", "design_size", "pre_scale_design_size"):
                if field in template and field in target and template.get(field) != target.get(field):
                    errors.append(f"{template_id}: {field} differs from catalogue")
            if not isinstance(template.get("content_policy"), str) or not template.get("content_policy"):
                errors.append(f"{template_id}: missing content_policy")
            if canonical_id == "world_bich_province":
                if template.get("template_kind") != "existing_map_or_empty_template" or template.get("content_policy") != "open_existing_workspace_first":
                    errors.append(f"{template_id}: structure_reference_only requires existing workspace policy")
        elif not isinstance(template.get("content_policy"), str) or not template.get("content_policy"):
            errors.append(f"{template_id}: missing content_policy")
    canonical_template_ids={canonical_by_legacy.get(mid, mid) for mid in template_map_ids}
    for mid in lookup:
        if mid not in canonical_template_ids:
            errors.append(f"{mid}: missing legal blank template coverage")
    if factor != Decimal(str(overrides.get("scale_policy", {}).get("factor", ""))):
        errors.append("acceptance: global scale factor differs from authoring policy")
    print(f"maps={len(maps)} blank_templates={len(blank_templates)} errors={len(errors)} warnings={len(warnings)}")
    for x in errors: print("ERROR",x)
    for x in warnings: print("WARN",x)
    return 1 if errors else 0
if __name__=="__main__": raise SystemExit(main())
