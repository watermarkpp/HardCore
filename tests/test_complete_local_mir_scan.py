from pathlib import Path


def test_scanner_contract_is_content_first() -> None:
    source = (Path(__file__).resolve().parents[1] / "tools" / "scan_complete_local_mir_sources.py").read_text(encoding="utf-8")
    assert "filename and directory names are search hints only" in source
    assert "sha256_file(path)" in source
    assert "CREATE TABLE archive_members" in source
    assert "CREATE TABLE resource_frames" in source
    assert "CREATE TABLE map_profiles" in source
    assert "CREATE VIRTUAL TABLE text_fts" in source
    assert "CREATE TABLE distributions" in source
    assert "cross_distribution_duplicates.csv" in source


def test_scanner_keeps_private_server_confidence_separate() -> None:
    source = (Path(__file__).resolve().parents[1] / "tools" / "scan_complete_local_mir_sources.py").read_text(encoding="utf-8")
    assert '"private_server_database_candidate", "B/C-candidate"' in source
    assert '"supplemental_private_client", "C-unknown-version"' in source
    assert "private-server data remains B/C candidate until cross-checked" in source
    assert "same names in other distributions never overwrite it" in source


def test_completed_scan_has_a_standalone_acceptance_verifier() -> None:
    source = (Path(__file__).resolve().parents[1] / "tools" / "verify_complete_local_mir_scan.py").read_text(encoding="utf-8")
    assert 'connection.execute("PRAGMA integrity_check")' in source
    assert '"databaseSha256MatchesManifest"' in source
    assert '"distributionFoldersExact"' in source
    assert '"onlyExpectedParseErrors"' in source
    assert "COMPLETE_LOCAL_MIR_SCAN_ACCEPTANCE_PASS" in source
