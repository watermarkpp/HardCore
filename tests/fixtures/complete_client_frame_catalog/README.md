# Frozen complete-client regression metadata

This fixture is an exact export of the existing formal scanner's manifest,
verified against its read-only SQLite database by
`tools/export_complete_client_catalog_test_fixture.py`.

The exporter checks all 122 library rows and their provenance, 962251 indexed
frame rows, 962250 valid frames and 332460 decoded head candidates. It preserves
the original manifest bytes and records the scanner and database identities in
`provenance.json`. It refuses to replace a differing existing fixture.

The original scanner remains `tools/scan_complete_client_headwear.py`. This
portable test input removes the regression's dependency on an ignored local
`outputs/` directory. It neither regenerates images nor supplies runtime art.
No approved helmet, skill, character, map or monster pixels are changed.
