"""Export verified existing catalog metadata; never regenerate client/helmet art."""
import hashlib
import json
import sqlite3
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "outputs/resource_catalog/complete_client_frame_catalog"
TARGET = ROOT / "tests/fixtures/complete_client_frame_catalog"
GENERATOR = "tools/scan_complete_client_headwear.py"


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    manifest = SOURCE / "manifest.json"
    database = SOURCE / "frame_catalog.sqlite"
    raw = manifest.read_bytes()
    data = json.loads(raw)
    database_hash = sha(database)
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as connection:
        aggregate = connection.execute("SELECT COUNT(*),SUM(indexed_frames_scanned),SUM(valid_frames),SUM(decoded_head_candidates) FROM libraries").fetchone()
        frame_aggregate = connection.execute("SELECT COUNT(*),SUM(valid) FROM frames").fetchone()
        head_count = connection.execute("SELECT COUNT(*) FROM head_candidates").fetchone()[0]
        fields = ("id", "name", "sourcePath", "wilBytes", "wixBytes", "wilSha256", "wixSha256",
                  "imageCount", "indexedFramesScanned", "validFrames", "headGeometryCandidates", "decodedHeadCandidates")
        rows = connection.execute("SELECT id,name,source_path,wil_bytes,wix_bytes,wil_sha256,wix_sha256,image_count,indexed_frames_scanned,valid_frames,head_geometry_candidates,decoded_head_candidates FROM libraries ORDER BY id").fetchall()
    declared = (data["libraryCount"], data["indexedFramesScanned"], data["validFrames"], data["decodedHeadCandidates"])
    assert aggregate == declared == (122, 962251, 962250, 332460), "catalog/database aggregate mismatch"
    assert frame_aggregate == (962251, 962250) and head_count == 332460, "catalog database rows incomplete"
    assert len(data["libraries"]) == 122 and len({row["id"] for row in data["libraries"]}) == 122
    declared_rows = {row["id"]: tuple(row[field] for field in fields) for row in data["libraries"]}
    assert all(declared_rows[row[0]] == row for row in rows), "library provenance mismatch"
    assert sha(database) == database_hash and manifest.read_bytes() == raw, "source changed during export"
    generator_blob = subprocess.check_output(["git", "-C", str(ROOT), "hash-object", "--", GENERATOR], text=True).strip()
    receipt = {
        "contract_id": "hardcore.complete_client_catalog.test_fixture.v1",
        "purpose": "Frozen historical resource scan metadata for a portable regression; not a runtime art authority.",
        "source_manifest": SOURCE.relative_to(ROOT).as_posix() + "/manifest.json",
        "manifest_sha256": hashlib.sha256(raw).hexdigest(),
        "source_database_sha256": database_hash,
        "source_database_bytes": database.stat().st_size,
        "generator": GENERATOR,
        "generator_git_blob": generator_blob,
        "generator_sha256": sha(ROOT / GENERATOR),
        "library_rows_verified": len(rows),
        "library_aggregate": list(aggregate),
        "frame_aggregate": list(frame_aggregate),
        "head_candidate_rows": head_count,
    }
    receipt_bytes = (json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    outputs = {TARGET / "manifest.json": raw, TARGET / "provenance.json": receipt_bytes}
    # Check every target before writing either. Existing different fixtures
    # require an explicit review; this exporter does not silently replace them.
    for path, content in outputs.items():
        if path.exists() and path.read_bytes() != content:
            raise RuntimeError("refuse different existing fixture: " + str(path))
    TARGET.mkdir(parents=True, exist_ok=True)
    for path, content in outputs.items():
        if not path.exists():
            with path.open("xb") as handle:
                handle.write(content)
        assert path.read_bytes() == content
    print(json.dumps({"status": "PASS", **receipt}, ensure_ascii=False))


if __name__ == "__main__":
    main()
