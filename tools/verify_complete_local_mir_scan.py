#!/usr/bin/env python3
"""Verify the completed multi-distribution MIR source catalog without rescanning it."""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "outputs/resource_catalog/complete_local_mir_sources"
SOURCE = ROOT / "dev_art_sources"
REPORT = ROOT / "outputs/validation/complete_local_mir_scan_acceptance.json"
REQUIRED_DISTRIBUTION_FILES = {
    "manifest.json",
    "files.csv",
    "semantic_hits.csv",
    "resource_libraries.csv",
    "maps.csv",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_distribution_folder(key: str) -> str:
    return re.sub(r"[^0-9A-Za-z_.-]+", "_", key).strip("._") or "distribution"


def main() -> None:
    manifest = json.loads((CATALOG / "manifest.json").read_text(encoding="utf-8"))
    validation = json.loads((CATALOG / "validation.json").read_text(encoding="utf-8"))
    database = CATALOG / manifest["database"]
    connection = sqlite3.connect(database)

    integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    catalog_files, catalog_bytes, unhashed = connection.execute(
        "SELECT COUNT(*),COALESCE(SUM(size_bytes),0),SUM(CASE WHEN length(sha256)=64 THEN 0 ELSE 1 END) FROM files"
    ).fetchone()
    distributions = list(
        connection.execute(
            "SELECT id,distribution_key FROM distributions ORDER BY distribution_key"
        )
    )
    distribution_root = CATALOG / "distributions"
    actual_distribution_folders = {path.name for path in distribution_root.iterdir() if path.is_dir()}
    expected_distribution_folders = {safe_distribution_folder(key) for _, key in distributions}

    missing_distribution_files: dict[str, list[str]] = {}
    distribution_file_sum = 0
    distribution_byte_sum = 0
    separation_policy_failures: list[str] = []
    for _, key in distributions:
        folder = distribution_root / safe_distribution_folder(key)
        present = {path.name for path in folder.iterdir() if path.is_file()} if folder.exists() else set()
        missing = sorted(REQUIRED_DISTRIBUTION_FILES - present)
        if missing:
            missing_distribution_files[key] = missing
            continue
        endpoint_manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
        distribution_file_sum += int(endpoint_manifest["fileCount"])
        distribution_byte_sum += int(endpoint_manifest["byteCount"])
        if "independently archived" not in endpoint_manifest.get("separationPolicy", ""):
            separation_policy_failures.append(key)

    parse_errors = list(
        connection.execute(
            """SELECT d.distribution_key,f.relative_path,f.kind,f.size_bytes,COALESCE(f.parse_error,'')
               FROM files f JOIN distributions d ON d.id=f.distribution_id
               WHERE f.parse_status='parse-error' ORDER BY f.kind,d.distribution_key,f.relative_path"""
        )
    )
    password_locked = list(
        connection.execute(
            """SELECT d.distribution_key,f.relative_path,a.member_count,a.test_error
               FROM archive_checks a
               JOIN files f ON f.id=a.archive_file_id
               JOIN distributions d ON d.id=f.distribution_id
               WHERE a.test_status='password-locked' ORDER BY f.relative_path"""
        )
    )
    unexpected_archive_states = list(
        connection.execute(
            """SELECT f.relative_path,a.test_status,COALESCE(a.test_error,'')
               FROM archive_checks a JOIN files f ON f.id=a.archive_file_id
               WHERE a.test_status NOT IN ('ok','password-locked') ORDER BY f.relative_path"""
        )
    )

    zero_byte_placeholders = [row for row in parse_errors if row[2] != "archive" and row[3] == 0]
    extension_collisions = [
        row for row in parse_errors
        if row[2] == "map" and row[3] > 0 and "DelphiX" in row[0] and row[1].endswith("Level1.map")
    ]
    expected_error_keys = {
        (row[0], row[1]) for row in password_locked
    } | {
        (row[0], row[1]) for row in zero_byte_placeholders
    } | {
        (row[0], row[1]) for row in extension_collisions
    }
    unexpected_parse_errors = [
        {
            "distribution": row[0],
            "path": row[1],
            "kind": row[2],
            "bytes": row[3],
            "error": row[4],
        }
        for row in parse_errors
        if (row[0], row[1]) not in expected_error_keys
    ]

    disk_files = [path for path in SOURCE.rglob("*") if path.is_file()]
    disk_count = len(disk_files)
    disk_bytes = sum(path.stat().st_size for path in disk_files)
    database_sha256 = sha256_file(database)
    checks = {
        "sqliteIntegrity": integrity == "ok",
        "databaseSha256MatchesManifest": database_sha256 == manifest["databaseSha256"],
        "sourceFileCountMatches": disk_count == catalog_files == validation["coverage"]["diskFiles"],
        "sourceByteCountMatches": disk_bytes == catalog_bytes == validation["coverage"]["diskBytes"],
        "allFilesHashed": int(unhashed or 0) == 0,
        "distributionCountMatches": len(distributions) == validation["distributionCount"] == 58,
        "distributionFoldersExact": actual_distribution_folders == expected_distribution_folders,
        "distributionFilesComplete": not missing_distribution_files,
        "distributionTotalsMatch": distribution_file_sum == catalog_files and distribution_byte_sum == catalog_bytes,
        "separationPolicyPresent": not separation_policy_failures,
        "crossDistributionIndexPresent": (CATALOG / "cross_distribution_duplicates.csv").is_file(),
        "onlyExpectedArchiveBlocks": len(password_locked) == 3 and not unexpected_archive_states,
        "onlyExpectedParseErrors": len(parse_errors) == 22 and not unexpected_parse_errors,
    }
    passed = all(checks.values())
    report = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "passed": passed,
        "checks": checks,
        "totals": {
            "files": catalog_files,
            "bytes": catalog_bytes,
            "distributions": len(distributions),
            "resourceLibraries": validation["contentIndexes"]["resourceLibraries"],
            "logicalFrames": validation["contentIndexes"]["logicalFramesAcrossAllPaths"],
            "maps": validation["contentIndexes"]["mapProfiles"],
            "archives": validation["contentIndexes"]["archives"],
            "parseErrors": len(parse_errors),
        },
        "knownBlocks": {
            "passwordLockedArchives": [
                {"distribution": row[0], "path": row[1], "members": row[2], "reason": row[3]}
                for row in password_locked
            ],
            "zeroByteEncryptedExtractionPlaceholders": len(zero_byte_placeholders),
            "nonMirMapExtensionCollisions": [
                {"distribution": row[0], "path": row[1], "bytes": row[3]} for row in extension_collisions
            ],
        },
        "unexpected": {
            "parseErrors": unexpected_parse_errors,
            "archiveStates": unexpected_archive_states,
            "missingDistributionFiles": missing_distribution_files,
            "separationPolicyFailures": separation_policy_failures,
        },
        "databaseSha256": database_sha256,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    connection.close()
    if not passed:
        raise SystemExit(f"COMPLETE_LOCAL_MIR_SCAN_ACCEPTANCE_FAIL report={REPORT.relative_to(ROOT)}")
    print(
        "COMPLETE_LOCAL_MIR_SCAN_ACCEPTANCE_PASS "
        f"files={catalog_files} bytes={catalog_bytes} distributions={len(distributions)} "
        f"parseErrors={len(parse_errors)} report={REPORT.relative_to(ROOT).as_posix()}"
    )


if __name__ == "__main__":
    main()
