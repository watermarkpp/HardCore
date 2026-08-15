"""Lock the canonical generator's checkout-independent text hash contract."""

from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR_PATH = ROOT / "tools" / "build_canonical_monster_catalog.py"
SPEC = importlib.util.spec_from_file_location("canonical_monster_catalog_generator", GENERATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


def main() -> None:
    source = ROOT / "assets" / "data" / "canonical_monster_catalog_policy_v1.json"
    source_bytes = source.read_bytes()
    source_text = source_bytes.decode("utf-8")
    lf_bytes = source_text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    crlf_bytes = lf_bytes.replace(b"\n", b"\r\n")

    with tempfile.TemporaryDirectory(dir=ROOT, prefix="canonical_hash_") as temp:
        temp_root = Path(temp)
        lf_copy = temp_root / "policy_lf.json"
        crlf_copy = temp_root / "policy_crlf.json"
        lf_copy.write_bytes(lf_bytes)
        crlf_copy.write_bytes(crlf_bytes)

        assert GENERATOR.sha256_file(lf_copy) == GENERATOR.sha256_file(crlf_copy)
        assert GENERATOR.hash_normalization_for(lf_copy) == "lf_text"
        assert GENERATOR.hash_normalization_for(crlf_copy) == "lf_text"
        assert json.loads(lf_copy.read_text(encoding="utf-8")) == json.loads(
            crlf_copy.read_text(encoding="utf-8")
        )
        evidence = GENERATOR.source_ref(
            crlf_copy,
            role="hash_contract_test",
            distribution="test",
            tier="test",
        )
        assert evidence["hash_normalization"] == "lf_text"

        binary_lf = temp_root / "atlas.png"
        binary_crlf = temp_root / "atlas_crlf.png"
        binary_lf.write_bytes(b"PNG\nfixture")
        binary_crlf.write_bytes(b"PNG\r\nfixture")
        assert GENERATOR.hash_normalization_for(binary_lf) == "raw_bytes"
        assert GENERATOR.sha256_file(binary_lf) != GENERATOR.sha256_file(binary_crlf)

    catalog = json.loads(
        (ROOT / "assets" / "data" / "runtime" / "canonical_monster_catalog.json").read_text(
            encoding="utf-8"
        )
    )
    for path, evidence in catalog.get("sources", {}).items():
        expected = "lf_text" if path.lower().endswith(".json") else "raw_bytes"
        assert evidence.get("hash_normalization") == expected, (path, evidence)

    print("CANONICAL_MONSTER_CATALOG_HASH_PASS: lf_crlf_equivalent=1 binary_raw=1 source_metadata=1")


if __name__ == "__main__":
    main()
