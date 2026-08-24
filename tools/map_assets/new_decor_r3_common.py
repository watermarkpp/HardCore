from __future__ import annotations

import hashlib
import json
import subprocess
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any


REPO_ROOT = Path(
    r"C:\Users\Administrator\Documents\HardCore-worktrees\maps"
)

SOURCE_ROOT = Path(
    r"C:\Users\Administrator\Desktop\sucai\新增"
)

CATALOG_REL = "assets/data/assets/map_asset_catalog.json"
CATALOG_PATH = REPO_ROOT / CATALOG_REL

PRE_IMPORT_BASE = "cf4ceb344d7a612104347917c1e32ef0392eeff6"
IMPORT_COMMIT = "c4d260866935132b95a4a2498fe322acf7050e17"
R2_BASE_SHA = "d55c4294b5830ca70dfb7c1e7cf41bf6e6de1433"

MANUAL_OVERRIDE_PATH = (
    REPO_ROOT
    / "docs"
    / "mafa_scene_editor"
    / "new_decor_manual_geometry_overrides.json"
)

UNRESOLVED_PATH = (
    REPO_ROOT
    / "docs"
    / "mafa_scene_editor"
    / "new_decor_geometry_unresolved.json"
)

GEOMETRY_REPORT_PATH = (
    REPO_ROOT
    / "docs"
    / "mafa_scene_editor"
    / "new_decor_authoritative_geometry_report.md"
)

WHITE_REPORT_PATH = (
    REPO_ROOT
    / "docs"
    / "mafa_scene_editor"
    / "new_decor_white_residue_report.md"
)

WHITE_PREVIEW_DIR = (
    REPO_ROOT
    / "docs"
    / "mafa_scene_editor"
    / "previews"
    / "new_decor_white_cleanup"
)

WHITE_CATEGORIES = {
    "雕塑",
    "烛台",
    "旗帜",
    "囚笼",
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.write("\n")
    temporary.replace(path)


def git_json(commit: str, path: str) -> Any:
    payload = subprocess.check_output(
        ["git", "show", f"{commit}:{path}"],
        cwd=str(REPO_ROOT),
    )
    return json.loads(payload.decode("utf-8"))


def asset_map(catalog: dict) -> dict[str, dict]:
    return {
        str(asset.get("asset_id", "")): asset
        for asset in catalog.get("assets", [])
        if str(asset.get("asset_id", ""))
    }


def original_new_batch_ids() -> set[str]:
    before = asset_map(git_json(PRE_IMPORT_BASE, CATALOG_REL))
    imported = asset_map(git_json(IMPORT_COMMIT, CATALOG_REL))
    return set(imported) - set(before)


def category_cn(asset: dict) -> str:
    path = str(asset.get("palette_path", "")).replace("\\", "/")
    parts = [part for part in path.split("/") if part]
    if len(parts) >= 2 and parts[0] == "装饰物1":
        return parts[1]
    return ""


def is_split_cage(asset: dict) -> bool:
    asset_id = str(asset.get("asset_id", ""))
    image = str(asset.get("image", "")).lower()
    display_name = str(asset.get("display_name", "")).lower()

    return (
        asset_id.startswith("user.cage.")
        or "cage_split_" in image
        or "cage_split_" in display_name
    )


def is_target_asset(asset: dict, batch_ids: set[str]) -> bool:
    asset_id = str(asset.get("asset_id", ""))
    return asset_id in batch_ids or is_split_cage(asset)


def valid_pair(value: Any) -> bool:
    return (
        isinstance(value, (list, tuple))
        and len(value) == 2
    )


def positive_int_pair(value: Any) -> list[int] | None:
    if not valid_pair(value):
        return None
    try:
        result = [int(value[0]), int(value[1])]
    except Exception:
        return None
    if result[0] <= 0 or result[1] <= 0:
        return None
    return result


def numeric_pair(value: Any) -> list[float] | None:
    if not valid_pair(value):
        return None
    try:
        return [float(value[0]), float(value[1])]
    except Exception:
        return None


def iter_dicts(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from iter_dicts(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_dicts(child)


def png_refs(value: Any) -> list[str]:
    result: list[str] = []

    if isinstance(value, str):
        if value.lower().endswith(".png"):
            result.append(value)

    elif isinstance(value, dict):
        for child in value.values():
            result.extend(png_refs(child))

    elif isinstance(value, list):
        for child in value:
            result.extend(png_refs(child))

    return result


def extract_geometry(value: Any) -> dict | None:
    for node in iter_dicts(value):
        footprint = positive_int_pair(
            node.get("footprint_tiles")
        )

        if footprint is None:
            continue

        anchor = None
        for key in (
            "anchor",
            "anchor_px",
            "placement_anchor_px",
        ):
            anchor = numeric_pair(node.get(key))
            if anchor is not None:
                break

        geometry = {
            "footprint_tiles": footprint,
        }

        if anchor is not None:
            geometry["anchor_px"] = anchor

        visible = node.get("visible_bounds_px")
        if (
            isinstance(visible, (list, tuple))
            and len(visible) == 4
        ):
            try:
                geometry["visible_bounds_px"] = [
                    int(v) for v in visible
                ]
            except Exception:
                pass

        if isinstance(node.get("occlusion"), bool):
            geometry["occlusion"] = bool(
                node["occlusion"]
            )

        for key in (
            "sort_baseline_tile_offset",
            "sort_baseline_offset_px",
        ):
            pair = numeric_pair(node.get(key))
            if pair is not None:
                geometry[key] = pair

        if "approved_scale" in node:
            try:
                scale = float(node["approved_scale"])
                if scale > 0:
                    geometry["approved_scale"] = scale
            except Exception:
                pass

        return geometry

    return None


def normalized_stem(value: str) -> str:
    value = str(value).replace("\\", "/").strip()
    if "::" in value:
        value = value.split("::")[-1]

    name = PurePosixPath(value).name
    return Path(name).stem.strip().lower()


class SourceMetadataIndex:
    def __init__(self):
        self.by_sha: dict[str, list[dict]] = {}
        self.by_stem: dict[str, list[dict]] = {}
        self.all_candidates: list[dict] = []
        self._seen: set[tuple] = set()

    def add(
        self,
        geometry: dict,
        source: str,
        image_name: str = "",
        image_payload: bytes | None = None,
    ) -> None:
        if not geometry:
            return

        footprint = positive_int_pair(
            geometry.get("footprint_tiles")
        )
        if footprint is None:
            return

        anchor = numeric_pair(
            geometry.get("anchor_px")
        )

        signature = (
            source,
            image_name,
            tuple(footprint),
            tuple(anchor) if anchor else (),
        )

        if signature in self._seen:
            return

        self._seen.add(signature)

        candidate = {
            "source": source,
            "image_name": image_name,
            "geometry": geometry,
            "image_sha256": (
                sha256_bytes(image_payload)
                if image_payload is not None
                else ""
            ),
        }

        self.all_candidates.append(candidate)

        digest = candidate["image_sha256"]
        if digest:
            self.by_sha.setdefault(
                digest, []
            ).append(candidate)

        stem = normalized_stem(image_name)
        if stem:
            self.by_stem.setdefault(
                stem, []
            ).append(candidate)


def _normalize_zip_name(value: str) -> str:
    return value.replace("\\", "/").lstrip("./")


def _find_zip_name(
    names: list[str],
    reference: str,
) -> str | None:
    ref = _normalize_zip_name(reference)

    exact = [
        name for name in names
        if _normalize_zip_name(name) == ref
    ]

    if len(exact) == 1:
        return exact[0]

    suffix = [
        name for name in names
        if _normalize_zip_name(name).endswith("/" + ref)
        or _normalize_zip_name(name) == ref
    ]

    if len(suffix) == 1:
        return suffix[0]

    return None


def _scan_zip(
    archive_path: Path,
    index: SourceMetadataIndex,
) -> None:
    try:
        archive = zipfile.ZipFile(archive_path, "r")
    except Exception:
        return

    with archive:
        names = [
            name
            for name in archive.namelist()
            if not name.endswith("/")
        ]

        parsed_json: dict[str, Any] = {}

        for name in names:
            if not name.lower().endswith(".json"):
                continue
            try:
                parsed_json[name] = json.loads(
                    archive.read(name).decode("utf-8")
                )
            except Exception:
                continue

        # 第一优先：
        # manifest 中明确 path + meta 的记录。
        for json_name, parsed in parsed_json.items():
            for node in iter_dicts(parsed):
                image_ref = node.get("path")
                meta_ref = node.get("meta")

                if (
                    not isinstance(image_ref, str)
                    or not image_ref.lower().endswith(".png")
                    or not isinstance(meta_ref, str)
                    or not meta_ref.lower().endswith(".json")
                ):
                    continue

                image_name = _find_zip_name(
                    names, image_ref
                )
                meta_name = _find_zip_name(
                    names, meta_ref
                )

                if image_name is None or meta_name is None:
                    continue

                meta_value = parsed_json.get(meta_name)

                if meta_value is None:
                    try:
                        meta_value = json.loads(
                            archive.read(meta_name).decode(
                                "utf-8"
                            )
                        )
                    except Exception:
                        continue

                geometry = extract_geometry(meta_value)

                if geometry is None:
                    continue

                try:
                    payload = archive.read(image_name)
                except Exception:
                    payload = None

                index.add(
                    geometry,
                    f"{archive_path}::{meta_name}",
                    image_name,
                    payload,
                )

        # 第二优先：
        # 任意包含 footprint_tiles 的 meta JSON。
        for json_name, parsed in parsed_json.items():
            geometry = extract_geometry(parsed)

            if geometry is None:
                continue

            refs = png_refs(parsed)

            if refs:
                for ref in refs:
                    image_name = _find_zip_name(
                        names, ref
                    )

                    payload = None

                    if image_name is not None:
                        try:
                            payload = archive.read(
                                image_name
                            )
                        except Exception:
                            payload = None

                    index.add(
                        geometry,
                        f"{archive_path}::{json_name}",
                        image_name or ref,
                        payload,
                    )

            else:
                # 没有明确 PNG 路径时，
                # 只用 meta 文件名 stem 建立弱匹配。
                index.add(
                    geometry,
                    f"{archive_path}::{json_name}",
                    Path(json_name).stem + ".png",
                    None,
                )


def _scan_direct_json(
    json_path: Path,
    index: SourceMetadataIndex,
) -> None:
    try:
        parsed = load_json(json_path)
    except Exception:
        return

    geometry = extract_geometry(parsed)

    if geometry is None:
        return

    refs = png_refs(parsed)

    if refs:
        for ref in refs:
            candidate_paths = [
                json_path.parent / ref,
                SOURCE_ROOT / ref,
            ]

            image_path = next(
                (
                    p for p in candidate_paths
                    if p.is_file()
                ),
                None,
            )

            payload = (
                image_path.read_bytes()
                if image_path is not None
                else None
            )

            index.add(
                geometry,
                str(json_path),
                (
                    str(image_path)
                    if image_path is not None
                    else ref
                ),
                payload,
            )

    else:
        sibling = json_path.with_suffix(".png")

        index.add(
            geometry,
            str(json_path),
            str(sibling),
            (
                sibling.read_bytes()
                if sibling.is_file()
                else None
            ),
        )


def build_source_metadata_index() -> SourceMetadataIndex:
    index = SourceMetadataIndex()

    if not SOURCE_ROOT.exists():
        raise SystemExit(
            f"SOURCE_ROOT_NOT_FOUND={SOURCE_ROOT}"
        )

    for archive in sorted(
        SOURCE_ROOT.rglob("*.zip")
    ):
        _scan_zip(archive, index)

    for json_path in sorted(
        SOURCE_ROOT.rglob("*.json")
    ):
        _scan_direct_json(
            json_path,
            index,
        )

    return index


def candidate_geometry_signature(candidate: dict) -> tuple:
    geometry = candidate["geometry"]

    footprint = positive_int_pair(
        geometry.get("footprint_tiles")
    ) or [0, 0]

    anchor = numeric_pair(
        geometry.get("anchor_px")
    ) or []

    return (
        tuple(footprint),
        tuple(anchor),
    )


def dedupe_candidates(
    candidates: list[dict],
) -> list[dict]:
    result = []
    seen = set()

    for candidate in candidates:
        signature = (
            candidate.get("source", ""),
            candidate_geometry_signature(candidate),
        )

        if signature in seen:
            continue

        seen.add(signature)
        result.append(candidate)

    return result


def match_asset_to_source_meta(
    asset: dict,
    index: SourceMetadataIndex,
) -> tuple[dict | None, str]:
    exact_candidates: list[dict] = []

    for key in (
        "source_sha256",
        "output_sha256",
        "thumbnail_source_sha256",
    ):
        digest = str(asset.get(key, ""))

        if digest:
            exact_candidates.extend(
                index.by_sha.get(digest, [])
            )

    exact_candidates = dedupe_candidates(
        exact_candidates
    )

    if exact_candidates:
        signatures = {
            candidate_geometry_signature(candidate)
            for candidate in exact_candidates
        }

        if len(signatures) == 1:
            return (
                exact_candidates[0],
                "sha256",
            )

        return (
            None,
            "ambiguous_sha256_metadata",
        )

    stems = set()

    for value in (
        asset.get("image", ""),
        asset.get("source_external_path", ""),
        asset.get("display_name", ""),
    ):
        stem = normalized_stem(str(value))
        if stem:
            stems.add(stem)

    stem_candidates: list[dict] = []

    for stem in stems:
        stem_candidates.extend(
            index.by_stem.get(stem, [])
        )

    stem_candidates = dedupe_candidates(
        stem_candidates
    )

    if not stem_candidates:
        return (
            None,
            "no_source_metadata_match",
        )

    signatures = {
        candidate_geometry_signature(candidate)
        for candidate in stem_candidates
    }

    if len(signatures) == 1:
        return (
            stem_candidates[0],
            "filename",
        )

    return (
        None,
        "ambiguous_filename_metadata",
    )


def collision_snapshot(asset: dict) -> dict:
    keys = (
        "collision_policy",
        "collision_profile_id",
        "collision_footprint_tiles",
        "collision_cells",
        "navigation_policy",
        "manual_collision_expected",
        "map_collision_override",
        "collision_authority",
        "collision_policy_id",
    )

    return {
        key: json.loads(
            json.dumps(
                asset.get(key, None),
                ensure_ascii=False,
            )
        )
        for key in keys
    }
