#!/usr/bin/env python3
"""Build a content-first catalog for every local MIR client/server source.

The scanner never treats a filename or directory category as proof of actual
content.  Every file is inventoried and hashed first.  Format parsers and
semantic indexes are layered on top of that immutable inventory, while all
parse failures remain visible in the database and validation report.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
import os
import re
import shutil
import sqlite3
import struct
import subprocess
import sys
import wave
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "dev_art_sources"
DEFAULT_OUTPUT = ROOT / "outputs/resource_catalog/complete_local_mir_sources"
SEVEN_ZIP = Path(r"C:\Program Files\7-Zip\7z.exe")
TEXT_EXTENSIONS = {
    ".txt", ".ini", ".cfg", ".conf", ".config", ".csv", ".json", ".xml",
    ".html", ".htm", ".md", ".rtf", ".pas", ".dfm", ".dpr", ".dpk",
    ".cs", ".csproj", ".sln", ".resx", ".cpp", ".h", ".inc", ".bat",
    ".cmd", ".ps1", ".py", ".gd", ".tscn", ".tres", ".godot", ".lst",
    ".nfo", ".diz", ".info", ".gitattributes", ".gitignore", ".editorconfig",
}
IMAGE_EXTENSIONS = {".png", ".bmp", ".gif", ".jpg", ".jpeg", ".ico", ".tga"}
ARCHIVE_EXTENSIONS = {".zip", ".rar", ".7z", ".cab", ".tar", ".gz", ".bz2", ".xz"}
SPECIALIZED_EXTENSIONS = IMAGE_EXTENSIONS | {".wav", ".map", ".wil", ".wix", ".wzl", ".wzx"} | ARCHIVE_EXTENSIONS
SEMANTIC_TERMS = {
    "npc": ["npc", "merchant", "market_def", "shop", "vendor", "商店", "商人", "修理", "仓库", "传送员"],
    "item": ["stditems", "iteminfo", "itemdata", "equipment", "装备", "物品", "武器", "衣服", "头盔"],
    "monster": ["monster", "mongen", "monitems", "怪物", "刷新", "掉落"],
    "map": ["mapinfo", "safezone", "startpoint", "地图", "安全区", "传送点"],
    "quest": ["questdiary", "questinfo", "任务", "奖励", "[@main]", "#if", "#act"],
    "magic": ["magic.db", "magicinfo", "技能", "魔法", "技能书"],
}
ASCII_STRINGS = re.compile(rb"[\x20-\x7e]{4,}")
UTF16_STRINGS = re.compile(rb"(?:[\x20-\x7e]\x00){4,}")
SYMBOL_PATTERNS = [
    ("class", re.compile(r"\b(?:class|record|object)\s+([A-Za-z_][\w.]*)", re.I)),
    ("function", re.compile(r"\b(?:function|procedure|func|def)\s+([A-Za-z_][\w.]*)", re.I)),
    ("csharp_method", re.compile(r"\b(?:public|private|protected|internal)\s+(?:static\s+)?[\w<>,?\[\].]+\s+([A-Za-z_]\w*)\s*\(")),
    ("label", re.compile(r"^\s*\[@([^\]]+)\]", re.I | re.M)),
]

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import read_library as read_wil_library  # noqa: E402
from extract_wzl import decode_sprite as decode_wzl_sprite  # noqa: E402
from extract_wzl import read_library as read_wzl_library  # noqa: E402
from extract_wzl import sprite_meta as wzl_sprite_meta  # noqa: E402


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def source_group(relative: Path) -> tuple[str, str]:
    text = relative.as_posix().casefold()
    if "reference/mir2_client_raw/" in text:
        return "classic_client_complete", "A-client-bytes"
    if "external/mir2opensource_full/" in text:
        return "2013_client_complete", "B-versioned-client"
    if "reference/original_gameofmir/" in text:
        return "classic_open_source", "A-rule-source"
    if "reference/mir2_database_candidates/" in text:
        return "private_server_database_candidate", "B/C-candidate"
    if "reference/mir2_sources/" in text:
        return "community_server_client_source", "B/C-source"
    if "extracted_archives/" in text or "external/mirfiles" in text:
        return "supplemental_private_client", "C-unknown-version"
    if "external/" in text:
        return "external_reference", "C-reference"
    if "original_client/" in text:
        return "classic_client_subset", "A-client-bytes"
    return "project_work_source", "C-working-copy"


def distribution_identity(relative: Path) -> tuple[str, str, str, str, str]:
    """Return stable identity for one client/server/source distribution.

    Separate distributions are never merged merely because their filenames or
    payload names happen to match.
    """
    parts = relative.as_posix().split("/")
    folded = [part.casefold() for part in parts]

    def result(key: str, kind: str, depth: int, provenance: str, confidence: str) -> tuple[str, str, str, str, str]:
        return key, kind, "/".join(parts[:depth]), provenance, confidence

    if folded[:3] == ["reference", "mir2_client_raw", "data"] or folded[:2] == ["reference", "mir2_client_raw"]:
        return result("client.classic_raw_complete", "client", 2, "complete classic client migrated into project", "A-client-bytes")
    if folded[:2] == ["external", "mir2opensource_full"]:
        return result("client.mir2opensource_2013_complete", "client", 2, "2013 paired client", "B-versioned-client")
    if folded[:2] == ["original_client", "data"] or folded[:1] == ["original_client"]:
        return result("client.classic_subset", "client-subset", 1, "classic client subset", "A-client-bytes")
    if len(parts) >= 2 and folded[0] == "extracted_archives":
        name = re.sub(r"_[0-9a-f]{12}$", "", parts[1], flags=re.I)
        kind = "server-archive-extract" if name.casefold() in {"mir2server", "gm"} else "client-resource-archive-extract"
        return result(f"archive_extract.{name}.{parts[1][-12:]}", kind, 2, "locally extracted archive; original preserved", "C-unknown-version")
    if folded[:2] == ["reference", "original_gameofmir"]:
        child = folded[2] if len(folded) >= 3 else ""
        if child == "client":
            return result("source.original_gameofmir.client", "client-source", 3, "classic Client source endpoint", "A-rule-source")
        if child == "mirclient":
            return result("source.original_gameofmir.mirclient", "client-source", 3, "classic MirClient source endpoint", "A-rule-source")
        if child in {"dbserver", "gamecenter", "logdataserver", "logingate", "loginsrv", "m2server", "mirserver", "rungate", "selgate"}:
            return result("source.original_gameofmir.server_suite", "server-source", 2, "classic multi-process server suite", "A-rule-source")
        return result("source.original_gameofmir.shared_tools", "shared-source", 2, "classic shared components, SDK and documentation", "A-rule-source")
    if folded[:3] == ["reference", "mir2_sources", "minipizza_mir2"]:
        child = folded[3] if len(folded) >= 4 else ""
        if child == "client":
            return result("source.minipizza_mir2.client", "client-source", 4, "community client source endpoint", "B/C-source")
        if child in {"server", "server.mirforms"}:
            return result("source.minipizza_mir2.server", "server-source", 3, "community server source endpoint", "B/C-source")
        if child in {"autopatcher", "autopatcheradmin"}:
            return result("source.minipizza_mir2.patchers", "client-server-tool-source", 3, "community patcher tools", "B/C-source")
        return result("source.minipizza_mir2.shared_tools", "shared-source", 3, "community shared libraries and tools", "B/C-source")
    if folded[:3] == ["reference", "mir2_sources", "suprcode_crystal"]:
        child = folded[3] if len(folded) >= 4 else ""
        if child == "server":
            return result("source.suprcode_crystal.server", "server-source", 4, "community Crystal server source endpoint", "B/C-source")
        return result("source.suprcode_crystal.shared", "shared-source", 3, "community Crystal shared protocol source", "B/C-source")
    if folded[:3] == ["reference", "mir2_database_candidates", "angelk727_full"]:
        return result("server.angelk727_full", "server-database", 3, "private-server executable export", "B/C-candidate")
    if folded[:3] == ["reference", "mir2_database_candidates", "angelk727"]:
        return result("server.angelk727_exports", "server-export", 3, "private-server CSV export", "B/C-candidate")
    if (len(parts) >= 5 and folded[:3] == ["reference", "mir2_database_candidates", "suprcode_crystal_database"]
            and not folded[3].startswith(".")):
        server_name = re.sub(r"[^0-9A-Za-z_.-]+", "_", parts[3])
        return result(f"server.crystal.{server_name}", "server-database", 4, "private-server Crystal database", "B/C-candidate")
    if folded[:3] == ["reference", "mir2_database_candidates", "suprcode_crystal_database"]:
        return result("source.suprcode_crystal_database.metadata", "source-metadata", 3, "private-server database package metadata", "B/C-candidate")
    if len(parts) >= 3 and folded[:2] == ["reference", "mir2_database"]:
        return result(f"server_reference.{parts[2]}", "server-reference", 3, "server data reference", "B/C-candidate")
    if len(parts) >= 2 and folded[0] == "external" and folded[1].startswith("mirfiles_"):
        return result(f"client_pack.{parts[1]}", "client-resource-pack", 2, "supplemental private client/resource pack", "C-unknown-version")
    if len(parts) >= 2 and folded[0] == "external" and folded[1].startswith("mir2opensource_"):
        return result(f"client_probe.{parts[1]}", "client-probe", 2, "selected client probe", "C-working-copy")
    if folded[:2] == ["reference", "mir2_client"]:
        return result("client.classic_reference_subset", "client-subset", 2, "classic client reference subset", "A-client-bytes")
    depth = min(2, len(parts))
    key = "working." + ".".join(re.sub(r"[^0-9A-Za-z_.-]+", "_", part) for part in parts[:depth])
    return result(key, "working-source", depth, "project working source", "C-working-copy")


def logical_source_path(source: Path, relative: Path) -> Path:
    """Keep distribution identity stable when scanning either all sources or one endpoint."""
    source_parts = list(source.resolve().parts)
    folded = [part.casefold() for part in source_parts]
    if "dev_art_sources" in folded:
        anchor = folded.index("dev_art_sources")
        prefix = source_parts[anchor + 1 :]
        return Path(*prefix, *relative.parts) if prefix else relative
    return relative


def classify_kind(path: Path, header: bytes) -> str:
    ext = path.suffix.casefold()
    if ext in TEXT_EXTENSIONS:
        return "text"
    if ext in IMAGE_EXTENSIONS:
        return "image"
    if ext == ".wav":
        return "audio"
    if ext == ".map":
        return "map"
    if ext in {".wil", ".wix"}:
        return "wil_library" if ext == ".wil" else "wil_index"
    if ext in {".wzl", ".wzx"}:
        return "wzl_library" if ext == ".wzl" else "wzl_index"
    if ext == ".lib" and len(header) >= 12:
        version, count, frame_seek = struct.unpack_from("<iii", header, 0)
        if version in {2, 3} and 0 <= count <= 10_000_000 and (version == 2 or frame_seek >= 0):
            return "mir_lib"
    if ext in ARCHIVE_EXTENSIONS:
        return "archive"
    if header.startswith(b"MZ"):
        return "pe_binary"
    if header.startswith(b"SQLite format 3\x00"):
        return "sqlite"
    if ext in {".db", ".dbf", ".mdb", ".accdb", ".sqlite", ".sqlite3", ".mirdb"}:
        return "database_binary"
    return "binary_or_unknown"


def decode_text(raw: bytes, force: bool = False) -> tuple[str | None, str | None, float]:
    if not raw:
        return "", "empty", 1.0
    if not force and b"\x00" in raw[:4096] and not (raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff")):
        return None, None, 0.0
    candidates: list[tuple[float, str, str]] = []
    for encoding in ("utf-8-sig", "gb18030", "big5", "utf-16", "utf-16-le", "utf-16-be", "latin-1"):
        try:
            text = raw.decode(encoding)
        except (UnicodeDecodeError, UnicodeError):
            continue
        if not text:
            return "", encoding, 1.0
        printable = sum(char.isprintable() or char in "\r\n\t" for char in text)
        controls = sum(ord(char) < 32 and char not in "\r\n\t" for char in text)
        replacement = text.count("\ufffd")
        score = (printable - controls * 4 - replacement * 8) / max(1, len(text))
        if encoding == "latin-1":
            score -= 0.08
        candidates.append((score, encoding, text))
    if not candidates:
        return None, None, 0.0
    score, encoding, text = max(candidates, key=lambda row: row[0])
    if not force and score < 0.78:
        return None, None, score
    return text, encoding, score


def create_database(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    connection = sqlite3.connect(path)
    connection.execute("PRAGMA journal_mode=WAL")
    connection.execute("PRAGMA synchronous=NORMAL")
    connection.execute("PRAGMA temp_store=MEMORY")
    connection.executescript(
        """
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE distributions (
            id INTEGER PRIMARY KEY,
            distribution_key TEXT NOT NULL UNIQUE,
            distribution_kind TEXT NOT NULL,
            root_prefix TEXT NOT NULL,
            provenance TEXT NOT NULL,
            confidence TEXT NOT NULL
        );
        CREATE TABLE files (
            id INTEGER PRIMARY KEY,
            distribution_id INTEGER NOT NULL,
            relative_path TEXT NOT NULL UNIQUE,
            source_group TEXT NOT NULL,
            confidence TEXT NOT NULL,
            extension TEXT NOT NULL,
            kind TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            modified_ns INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            header_hex TEXT NOT NULL,
            text_encoding TEXT,
            text_quality REAL,
            line_count INTEGER,
            decoded_chars INTEGER,
            parse_status TEXT NOT NULL DEFAULT 'inventoried',
            parse_error TEXT
        );
        CREATE INDEX files_distribution ON files(distribution_id);
        CREATE INDEX files_sha256 ON files(sha256);
        CREATE INDEX files_kind ON files(kind);
        CREATE INDEX files_source_group ON files(source_group);
        CREATE TABLE text_content (
            file_id INTEGER PRIMARY KEY,
            content TEXT NOT NULL,
            FOREIGN KEY(file_id) REFERENCES files(id)
        );
        CREATE VIRTUAL TABLE text_fts USING fts5(file_id UNINDEXED, relative_path, content);
        CREATE TABLE semantic_hits (
            file_id INTEGER NOT NULL,
            category TEXT NOT NULL,
            hit_count INTEGER NOT NULL,
            terms_json TEXT NOT NULL,
            PRIMARY KEY(file_id, category)
        );
        CREATE TABLE symbols (
            file_id INTEGER NOT NULL,
            symbol_kind TEXT NOT NULL,
            symbol_name TEXT NOT NULL,
            line_number INTEGER NOT NULL,
            PRIMARY KEY(file_id, symbol_kind, symbol_name, line_number)
        );
        CREATE TABLE binary_strings (
            file_id INTEGER NOT NULL,
            encoding TEXT NOT NULL,
            value TEXT NOT NULL,
            occurrences INTEGER NOT NULL,
            first_offset INTEGER NOT NULL,
            PRIMARY KEY(file_id, encoding, value)
        );
        CREATE TABLE structured_metadata (
            file_id INTEGER NOT NULL,
            format TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            PRIMARY KEY(file_id, format)
        );
        CREATE TABLE archive_members (
            archive_file_id INTEGER NOT NULL,
            member_path TEXT NOT NULL,
            is_directory INTEGER NOT NULL,
            size_bytes INTEGER,
            packed_bytes INTEGER,
            crc TEXT,
            encrypted INTEGER,
            modified TEXT,
            method TEXT,
            PRIMARY KEY(archive_file_id, member_path)
        );
        CREATE TABLE resource_libraries (
            file_id INTEGER PRIMARY KEY,
            format TEXT NOT NULL,
            companion_file_id INTEGER,
            content_sha256 TEXT NOT NULL,
            canonical_file_id INTEGER NOT NULL,
            frame_count INTEGER NOT NULL,
            valid_frames INTEGER NOT NULL,
            invalid_frames INTEGER NOT NULL,
            version TEXT,
            parse_error TEXT
        );
        CREATE TABLE resource_frames (
            canonical_file_id INTEGER NOT NULL,
            frame_index INTEGER NOT NULL,
            byte_offset INTEGER NOT NULL,
            valid INTEGER NOT NULL,
            width INTEGER,
            height INTEGER,
            draw_x INTEGER,
            draw_y INTEGER,
            payload_bytes INTEGER,
            opaque_pixels INTEGER,
            pixel_sha256 TEXT,
            parse_error TEXT,
            PRIMARY KEY(canonical_file_id, frame_index)
        ) WITHOUT ROWID;
        CREATE TABLE map_profiles (
            file_id INTEGER PRIMARY KEY,
            format_variant TEXT NOT NULL,
            width INTEGER,
            height INTEGER,
            cell_count INTEGER,
            blocked_cells INTEGER,
            light_cells INTEGER,
            door_cells INTEGER,
            tile_histogram_json TEXT,
            object_histogram_json TEXT,
            area_histogram_json TEXT,
            parse_error TEXT
        );
        CREATE TABLE archive_checks (
            archive_file_id INTEGER PRIMARY KEY,
            archive_type TEXT,
            physical_size INTEGER,
            member_count INTEGER NOT NULL,
            test_status TEXT NOT NULL,
            test_error TEXT
        );
        """
    )
    return connection


def semantic_index(connection: sqlite3.Connection, file_id: int, text: str) -> None:
    folded = text.casefold()
    for category, terms in SEMANTIC_TERMS.items():
        counts = {term: folded.count(term.casefold()) for term in terms}
        counts = {term: count for term, count in counts.items() if count}
        if counts:
            connection.execute(
                "INSERT INTO semantic_hits VALUES (?,?,?,?)",
                (file_id, category, sum(counts.values()), json.dumps(counts, ensure_ascii=False)),
            )


def symbol_index(connection: sqlite3.Connection, file_id: int, text: str) -> None:
    rows: set[tuple[int, str, str, int]] = set()
    for kind, pattern in SYMBOL_PATTERNS:
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            rows.add((file_id, kind, match.group(1)[:240], line))
    if rows:
        connection.executemany("INSERT OR IGNORE INTO symbols VALUES (?,?,?,?)", sorted(rows))


def image_metadata(path: Path) -> dict:
    with Image.open(path) as image:
        return {
            "width": image.width,
            "height": image.height,
            "mode": image.mode,
            "format": image.format,
            "frames": int(getattr(image, "n_frames", 1)),
            "infoKeys": sorted(str(key) for key in image.info),
        }


def wave_metadata(path: Path) -> dict:
    with wave.open(str(path), "rb") as handle:
        return {
            "channels": handle.getnchannels(),
            "sampleWidth": handle.getsampwidth(),
            "sampleRate": handle.getframerate(),
            "frameCount": handle.getnframes(),
            "compression": handle.getcomptype(),
            "durationSeconds": round(handle.getnframes() / max(1, handle.getframerate()), 6),
        }


def structured_text_metadata(path: Path, text: str) -> tuple[str, dict] | None:
    ext = path.suffix.casefold()
    if ext == ".csv":
        rows = list(csv.reader(text.splitlines()))
        widths = Counter(len(row) for row in rows)
        return "csv", {
            "rowCount": max(0, len(rows) - 1),
            "header": rows[0] if rows else [],
            "rowWidthHistogram": dict(widths),
        }
    if ext == ".json":
        value = json.loads(text)
        return "json", {
            "rootType": type(value).__name__,
            "rootLength": len(value) if isinstance(value, (dict, list)) else None,
            "rootKeys": list(value.keys()) if isinstance(value, dict) else [],
        }
    if ext in {".ini", ".cfg", ".conf"}:
        sections = re.findall(r"^\s*\[([^\]]+)\]", text, re.M)
        assignments = re.findall(r"^\s*([^#;\s][^=\r\n]*?)\s*=", text, re.M)
        return "ini_like", {"sectionCount": len(sections), "sections": sections, "assignmentCount": len(assignments)}
    if ext in {".xml", ".csproj", ".resx", ".config"}:
        tags = Counter(re.findall(r"<\s*([A-Za-z_][\w:.-]*)\b", text))
        return "xml_like", {"tagHistogram": dict(tags), "tagCount": sum(tags.values())}
    return None


def extract_binary_strings(connection: sqlite3.Connection, file_id: int, raw: bytes) -> None:
    values: dict[tuple[str, str], list[int]] = {}
    for encoding, pattern in (("ascii", ASCII_STRINGS), ("utf-16-le", UTF16_STRINGS)):
        for match in pattern.finditer(raw):
            value = match.group().decode(encoding, errors="replace")[:2000]
            key = (encoding, value)
            if key not in values:
                values[key] = [1, match.start()]
            else:
                values[key][0] += 1
    if values:
        connection.executemany(
            "INSERT INTO binary_strings VALUES (?,?,?,?,?)",
            [(file_id, encoding, value, info[0], info[1]) for (encoding, value), info in values.items()],
        )


def extract_dotnet_utf8_strings(connection: sqlite3.Connection, file_id: int, raw: bytes) -> None:
    """Index plausible BinaryReader/BinaryWriter length-prefixed UTF-8 strings.

    Crystal Server.MirDB data uses this representation.  The scan is content
    based and intentionally does not require the database filename to be known.
    """
    found: dict[str, list[int]] = {}
    for offset in range(len(raw)):
        value = 0
        shift = 0
        position = offset
        valid_prefix = False
        for _ in range(5):
            if position >= len(raw):
                break
            byte = raw[position]
            position += 1
            value |= (byte & 0x7F) << shift
            if not byte & 0x80:
                valid_prefix = True
                break
            shift += 7
        if not valid_prefix or value < 2 or value > 4096 or position + value > len(raw):
            continue
        payload = raw[position : position + value]
        try:
            text = payload.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if len(text) < 2 or not all(char.isprintable() or char in "\r\n\t" for char in text):
            continue
        if not any(char.isalpha() or "\u4e00" <= char <= "\u9fff" for char in text):
            continue
        if text not in found:
            found[text] = [1, offset]
        else:
            found[text][0] += 1
    if found:
        connection.executemany(
            "INSERT OR IGNORE INTO binary_strings VALUES (?,?,?,?,?)",
            [(file_id, "dotnet-utf8", value[:2000], info[0], info[1]) for value, info in found.items()],
        )


def inventory(source: Path, connection: sqlite3.Connection, progress_every: int = 250) -> dict:
    files = sorted((path for path in source.rglob("*") if path.is_file()), key=lambda p: p.as_posix().casefold())
    totals = Counter()
    distribution_ids: dict[str, int] = {}
    for index, path in enumerate(files, 1):
        relative = path.relative_to(source)
        logical_relative = logical_source_path(source, relative)
        stat = path.stat()
        with path.open("rb") as header_handle:
            header = header_handle.read(64)
        digest = sha256_file(path)
        group, confidence = source_group(logical_relative)
        distribution_key, distribution_kind, root_prefix, provenance, distribution_confidence = distribution_identity(logical_relative)
        distribution_id = distribution_ids.get(distribution_key)
        if distribution_id is None:
            cursor = connection.execute(
                "INSERT INTO distributions(distribution_key,distribution_kind,root_prefix,provenance,confidence) VALUES (?,?,?,?,?)",
                (distribution_key, distribution_kind, root_prefix, provenance, distribution_confidence),
            )
            distribution_id = int(cursor.lastrowid)
            distribution_ids[distribution_key] = distribution_id
        kind = classify_kind(path, header)
        text = encoding = None
        quality = 0.0
        if kind == "text":
            raw = path.read_bytes()
            text, encoding, quality = decode_text(raw, force=True)
        cursor = connection.execute(
            """INSERT INTO files(distribution_id,relative_path,source_group,confidence,extension,kind,size_bytes,modified_ns,sha256,header_hex,
               text_encoding,text_quality,line_count,decoded_chars,parse_status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                distribution_id, relative.as_posix(), group, confidence, path.suffix.casefold(), kind, stat.st_size,
                stat.st_mtime_ns, digest, header.hex(), encoding, quality if encoding else None,
                (text.count("\n") + 1) if text is not None else None, len(text) if text is not None else None,
                "text-indexed" if text is not None else "inventoried",
            ),
        )
        file_id = int(cursor.lastrowid)
        if text is not None:
            connection.execute("INSERT INTO text_content VALUES (?,?)", (file_id, text))
            connection.execute("INSERT INTO text_fts VALUES (?,?,?)", (file_id, relative.as_posix(), text))
            semantic_index(connection, file_id, text)
            symbol_index(connection, file_id, text)
            try:
                structured = structured_text_metadata(path, text)
                if structured:
                    connection.execute(
                        "INSERT INTO structured_metadata VALUES (?,?,?)",
                        (file_id, structured[0], json.dumps(structured[1], ensure_ascii=False)),
                    )
            except Exception as error:
                connection.execute(
                    "UPDATE files SET parse_error=? WHERE id=?",
                    (f"structured text: {type(error).__name__}: {error}", file_id),
                )
        try:
            metadata = None
            if kind == "image":
                metadata = ("image", image_metadata(path))
            elif kind == "audio":
                metadata = ("wav", wave_metadata(path))
            if metadata:
                connection.execute(
                    "INSERT INTO structured_metadata VALUES (?,?,?)",
                    (file_id, metadata[0], json.dumps(metadata[1], ensure_ascii=False)),
                )
                connection.execute("UPDATE files SET parse_status='structured' WHERE id=?", (file_id,))
        except Exception as error:
            connection.execute(
                "UPDATE files SET parse_status='parse-error', parse_error=? WHERE id=?",
                (f"{kind}: {type(error).__name__}: {error}", file_id),
            )
        if kind in {"pe_binary", "database_binary", "sqlite", "binary_or_unknown"} and stat.st_size <= 256 * 1024 * 1024:
            try:
                binary_raw = path.read_bytes()
                extract_binary_strings(connection, file_id, binary_raw)
                if kind == "database_binary":
                    extract_dotnet_utf8_strings(connection, file_id, binary_raw)
            except Exception as error:
                connection.execute(
                    "UPDATE files SET parse_error=COALESCE(parse_error||'; ','')||? WHERE id=?",
                    (f"binary strings: {type(error).__name__}: {error}", file_id),
                )
        totals["files"] += 1
        totals["bytes"] += stat.st_size
        totals[f"kind:{kind}"] += 1
        if index % progress_every == 0:
            connection.commit()
            print(f"INVENTORY_PROGRESS files={index}/{len(files)} bytes={totals['bytes']}", flush=True)
    connection.commit()
    return dict(totals)


def companion_id(connection: sqlite3.Connection, relative_path: str, suffixes: Iterable[str]) -> int | None:
    base = str(Path(relative_path).with_suffix(""))
    for suffix in suffixes:
        row = connection.execute(
            "SELECT id FROM files WHERE lower(relative_path)=lower(?)", (base + suffix,)
        ).fetchone()
        if row:
            return int(row[0])
    return None


def scan_wil(path: Path, file_id: int, connection: sqlite3.Connection, canonical_by_sha: dict[str, int]) -> None:
    row = connection.execute("SELECT relative_path,sha256 FROM files WHERE id=?", (file_id,)).fetchone()
    relative, digest = str(row[0]), str(row[1])
    companion = companion_id(connection, relative, (".wix", ".WIX"))
    canonical = canonical_by_sha.get(digest)
    if canonical is not None:
        profile = connection.execute(
            "SELECT frame_count,valid_frames,invalid_frames,version,parse_error FROM resource_libraries WHERE file_id=?",
            (canonical,),
        ).fetchone()
        connection.execute(
            "INSERT INTO resource_libraries VALUES (?,?,?,?,?,?,?,?,?,?)",
            (file_id, "WIL/WIX", companion, digest, canonical, *profile),
        )
        connection.execute("UPDATE files SET parse_status='structured-duplicate' WHERE id=?", (file_id,))
        return
    canonical_by_sha[digest] = file_id
    valid = invalid = 0
    version = None
    error_text = None
    try:
        data, _palette, offsets, info = read_wil_library(path)
        version = str(info.get("version", ""))
        rows = []
        for index, offset in enumerate(offsets):
            frame = [file_id, index, int(offset), 0, None, None, None, None, None, None, None, None]
            try:
                if offset <= 0 or offset + 8 > len(data):
                    raise ValueError("empty-or-out-of-range")
                width, height, x, y = struct.unpack_from("<hhhh", data, offset)
                end = offset + 8 + width * height
                if width <= 0 or height <= 0 or width > 4096 or height > 4096 or end > len(data):
                    raise ValueError("invalid-dimensions-or-payload")
                pixels = data[offset + 8:end]
                frame[3:11] = [1, width, height, x, y, len(pixels), len(pixels) - pixels.count(0), hashlib.sha256(pixels).hexdigest()]
                valid += 1
            except Exception as error:
                frame[11] = str(error)
                invalid += 1
            rows.append(tuple(frame))
            if len(rows) >= 5000:
                connection.executemany("INSERT INTO resource_frames VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", rows)
                rows.clear()
        if rows:
            connection.executemany("INSERT INTO resource_frames VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", rows)
        frame_count = len(offsets)
        connection.execute("UPDATE files SET parse_status='structured' WHERE id=?", (file_id,))
    except Exception as error:
        frame_count = 0
        error_text = f"{type(error).__name__}: {error}"
        connection.execute("UPDATE files SET parse_status='parse-error',parse_error=? WHERE id=?", (error_text, file_id))
    connection.execute(
        "INSERT INTO resource_libraries VALUES (?,?,?,?,?,?,?,?,?,?)",
        (file_id, "WIL/WIX", companion, digest, file_id, frame_count, valid, invalid, version, error_text),
    )


def scan_wzl(path: Path, file_id: int, connection: sqlite3.Connection, canonical_by_sha: dict[str, int]) -> None:
    row = connection.execute("SELECT relative_path,sha256 FROM files WHERE id=?", (file_id,)).fetchone()
    relative, digest = str(row[0]), str(row[1])
    companion = companion_id(connection, relative, (".wzx", ".WZX"))
    canonical = canonical_by_sha.get(digest)
    if canonical is not None:
        profile = connection.execute(
            "SELECT frame_count,valid_frames,invalid_frames,version,parse_error FROM resource_libraries WHERE file_id=?",
            (canonical,),
        ).fetchone()
        connection.execute("INSERT INTO resource_libraries VALUES (?,?,?,?,?,?,?,?,?,?)", (file_id, "WZL/WZX", companion, digest, canonical, *profile))
        connection.execute("UPDATE files SET parse_status='structured-duplicate' WHERE id=?", (file_id,))
        return
    canonical_by_sha[digest] = file_id
    valid = invalid = 0
    error_text = None
    try:
        data, offsets, palette, info = read_wzl_library(path)
        rows = []
        for index, offset in enumerate(offsets):
            frame = [file_id, index, int(offset), 0, None, None, None, None, None, None, None, None]
            try:
                meta = wzl_sprite_meta(data, offset)
                image, _ = decode_wzl_sprite(data, offset, palette)
                rgba = image.tobytes()
                alpha = rgba[3::4]
                frame[3:11] = [
                    1, meta["width"], meta["height"], meta["x"], meta["y"], meta["compressed_size"],
                    sum(value > 0 for value in alpha), hashlib.sha256(rgba).hexdigest(),
                ]
                valid += 1
            except Exception as error:
                frame[11] = str(error)
                invalid += 1
            rows.append(tuple(frame))
            if len(rows) >= 2000:
                connection.executemany("INSERT INTO resource_frames VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", rows)
                rows.clear()
        if rows:
            connection.executemany("INSERT INTO resource_frames VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", rows)
        frame_count = len(offsets)
        version = f"wzx_header={info.get('wzx_header_size', '')}"
        connection.execute("UPDATE files SET parse_status='structured' WHERE id=?", (file_id,))
    except Exception as error:
        frame_count = 0
        version = None
        error_text = f"{type(error).__name__}: {error}"
        connection.execute("UPDATE files SET parse_status='parse-error',parse_error=? WHERE id=?", (error_text, file_id))
    connection.execute(
        "INSERT INTO resource_libraries VALUES (?,?,?,?,?,?,?,?,?,?)",
        (file_id, "WZL/WZX", companion, digest, file_id, frame_count, valid, invalid, version, error_text),
    )


def scan_mir_lib(path: Path, file_id: int, connection: sqlite3.Connection, canonical_by_sha: dict[str, int]) -> None:
    row = connection.execute("SELECT sha256 FROM files WHERE id=?", (file_id,)).fetchone()
    digest = str(row[0])
    canonical = canonical_by_sha.get(digest)
    if canonical is not None:
        profile = connection.execute(
            "SELECT frame_count,valid_frames,invalid_frames,version,parse_error FROM resource_libraries WHERE file_id=?",
            (canonical,),
        ).fetchone()
        connection.execute("INSERT INTO resource_libraries VALUES (?,?,?,?,?,?,?,?,?,?)", (file_id, "MIR-LIB", None, digest, canonical, *profile))
        connection.execute("UPDATE files SET parse_status='structured-duplicate' WHERE id=?", (file_id,))
        return
    canonical_by_sha[digest] = file_id
    valid = invalid = 0
    error_text = None
    frame_count = 0
    version_text = None
    try:
        data = path.read_bytes()
        if len(data) < 8:
            raise ValueError("library header is too short")
        version, frame_count = struct.unpack_from("<ii", data, 0)
        if version not in {2, 3} or frame_count < 0 or frame_count > 10_000_000:
            raise ValueError(f"unsupported MLibrary header version={version} count={frame_count}")
        index_start = 12 if version >= 3 else 8
        frame_seek = struct.unpack_from("<i", data, 8)[0] if version >= 3 else 0
        index_end = index_start + frame_count * 4
        if index_end > len(data):
            raise ValueError("index table exceeds library bytes")
        offsets = struct.unpack_from(f"<{frame_count}i", data, index_start) if frame_count else ()
        rows = []
        for index, offset in enumerate(offsets):
            frame = [file_id, index, int(offset), 0, None, None, None, None, None, None, None, None]
            try:
                if offset <= 0 or offset + 17 > len(data):
                    raise ValueError("empty-or-out-of-range")
                width, height, x, y, _shadow_x, _shadow_y = struct.unpack_from("<hhhhhh", data, offset)
                shadow = data[offset + 12]
                packed_length = struct.unpack_from("<i", data, offset + 13)[0]
                payload_start = offset + 17
                payload_end = payload_start + packed_length
                if width <= 0 or height <= 0 or width > 8192 or height > 8192 or packed_length <= 0 or payload_end > len(data):
                    raise ValueError("invalid-dimensions-or-gzip-payload")
                pixels = gzip.decompress(data[payload_start:payload_end])
                expected = width * height * 4
                if len(pixels) < expected:
                    raise ValueError(f"short-rgba-payload {len(pixels)}<{expected}")
                pixels = pixels[:expected]
                opaque = sum(value > 0 for value in pixels[3::4])
                if shadow >> 7:
                    mask_offset = payload_end
                    if mask_offset + 12 > len(data):
                        raise ValueError("mask-header-out-of-range")
                    mask_width, mask_height, _mask_x, _mask_y, mask_length = struct.unpack_from("<hhhhi", data, mask_offset)
                    mask_end = mask_offset + 12 + mask_length
                    if mask_width < 0 or mask_height < 0 or mask_length < 0 or mask_end > len(data):
                        raise ValueError("mask-payload-out-of-range")
                frame[3:11] = [1, width, height, x, y, packed_length, opaque, hashlib.sha256(pixels).hexdigest()]
                valid += 1
            except Exception as error:
                frame[11] = str(error)
                invalid += 1
            rows.append(tuple(frame))
            if len(rows) >= 2000:
                connection.executemany("INSERT INTO resource_frames VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", rows)
                rows.clear()
        if rows:
            connection.executemany("INSERT INTO resource_frames VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", rows)
        version_text = f"MLibrary-v{version};frameSeek={frame_seek}"
        connection.execute(
            "INSERT INTO structured_metadata VALUES (?,?,?)",
            (file_id, "mir_lib_header", json.dumps({"version": version, "count": frame_count, "frameSeek": frame_seek}, ensure_ascii=False)),
        )
        connection.execute("UPDATE files SET parse_status='structured' WHERE id=?", (file_id,))
    except Exception as error:
        error_text = f"{type(error).__name__}: {error}"
        connection.execute("UPDATE files SET parse_status='parse-error',parse_error=? WHERE id=?", (error_text, file_id))
    connection.execute(
        "INSERT INTO resource_libraries VALUES (?,?,?,?,?,?,?,?,?,?)",
        (file_id, "MIR-LIB", None, digest, file_id, frame_count, valid, invalid, version_text, error_text),
    )


def scan_map(path: Path, file_id: int, connection: sqlite3.Connection) -> None:
    raw = path.read_bytes()
    width = height = cells = blocked = lights = doors = None
    tile_histogram: dict = {}
    object_histogram: dict = {}
    area_histogram: dict = {}
    variant = "unknown"
    error_text = None
    try:
        if len(raw) < 8:
            raise ValueError("file-shorter-than-minimum-map-header")
        map_type = 0
        if len(raw) > 25 and raw[0] == 0:
            map_type = 5
        elif len(raw) > 19 and raw[0] == 0x0F and raw[5] == 0x53 and raw[14] == 0x33:
            map_type = 6
        elif len(raw) > 19 and raw[0] == 0x15 and raw[4] == 0x32 and raw[6] == 0x41 and raw[19] == 0x31:
            map_type = 4
        elif len(raw) > 25 and raw[0] == 0x10 and raw[2] == 0x61 and raw[7] == 0x31 and raw[14] == 0x31:
            map_type = 1
        elif len(raw) > 19 and raw[4] == 0x0F and raw[18] == 0x0D and raw[19] == 0x0A:
            test_width, test_height = struct.unpack_from("<HH", raw, 0)
            map_type = 3 if len(raw) > 52 + test_width * test_height * 14 else 2
        elif len(raw) > 27 and raw[0] == 0x0D and raw[1] == 0x4C and raw[7] == 0x20 and raw[11] == 0x6D:
            map_type = 7
        elif len(raw) > 7 and raw[0] == 0xC8 and raw[2] == 0xC8 and raw[4] == 0x0D:
            map_type = 8
        elif len(raw) > 7 and raw[2] == 0x43 and raw[3] == 0x23:
            map_type = 100

        xor_key = 0
        if map_type in {0, 2, 3, 8}:
            width, height = struct.unpack_from("<HH", raw, 0)
            header_size = 52
            stride = {0: 12, 2: 14, 3: 36, 8: 12}[map_type]
        elif map_type == 1:
            width_raw, xor_key, height_raw = struct.unpack_from("<hhh", raw, 21)
            width, height = width_raw ^ xor_key, height_raw ^ xor_key
            header_size, stride = 54, 15
        elif map_type == 4:
            width_raw, xor_key, height_raw = struct.unpack_from("<hhh", raw, 31)
            width, height = width_raw ^ xor_key, height_raw ^ xor_key
            header_size, stride = 64, 12
        elif map_type == 5:
            width, height = struct.unpack_from("<HH", raw, 22)
            header_size = 28 + 3 * ((width // 2) + (width % 2)) * (height // 2)
            stride = 14
        elif map_type == 6:
            width, height = struct.unpack_from("<HH", raw, 16)
            header_size, stride = 40, 20
        elif map_type == 7:
            width = struct.unpack_from("<H", raw, 21)[0]
            height = struct.unpack_from("<H", raw, 25)[0]
            header_size, stride = 54, 15
        elif map_type == 100:
            if raw[0] != 1 or raw[1] != 0:
                raise ValueError("unsupported-csharp-map-version")
            width, height = struct.unpack_from("<HH", raw, 4)
            header_size, stride = 8, 26
        else:
            raise ValueError(f"unsupported-map-type {map_type}")
        expected = header_size + width * height * stride
        if width <= 0 or height <= 0 or width > 32767 or height > 32767 or expected > len(raw):
            raise ValueError(
                f"map-size-mismatch type={map_type} width={width} height={height} "
                f"header={header_size} stride={stride} expected={expected} actual={len(raw)}"
            )
        variant_names = {
            0: "classic-wemade-12", 1: "wemade-2010-15", 2: "old-shanda-14", 3: "shanda-2012-36",
            4: "wemade-antihack-12", 5: "wemade-mir3-14", 6: "shanda-mir3-20", 7: "heroes-15",
            8: "shortys-12", 100: "csharp-26",
        }
        variant = variant_names[map_type]
        cells = width * height
        blocked = lights = doors = 0
        tiles: Counter[int] = Counter()
        objects: Counter[str] = Counter()
        areas: Counter[int] = Counter()
        for offset in range(header_size, expected, stride):
            if map_type in {5, 6}:
                flag = raw[offset]
                blocked += int((flag & 0x01) != 1 or (flag & 0x02) != 2)
            elif map_type == 1:
                back = struct.unpack_from("<I", raw, offset)[0] ^ 0xAA38AA38
                front = struct.unpack_from("<H", raw, offset + 6)[0] ^ (xor_key & 0xFFFF)
                blocked += int(bool((back & 0x20000000) or (front & 0x8000)))
            elif map_type == 100:
                back = struct.unpack_from("<I", raw, offset + 2)[0]
                front = struct.unpack_from("<H", raw, offset + 12)[0]
                blocked += int(bool((back & 0x20000000) or (front & 0x8000)))
                doors += int((raw[offset + 14] & 0x7F) > 0)
                lights += int(raw[offset + 25] > 0)
            else:
                back = struct.unpack_from("<H", raw, offset)[0]
                second = struct.unpack_from("<H", raw, offset + 2)[0]
                blocked += int(bool((back | second) & 0x8000))
                if map_type in {0, 8}:
                    _bk, _mid, front, door_index, _door_offset, _ani_frame, _ani_tick, area, light = struct.unpack_from("<HHHBBBBBB", raw, offset)
                    lights += int(light > 0)
                    doors += int((door_index & 0x7F) > 0)
                    if _bk & 0x7FFF:
                        tiles[_bk & 0x7FFF] += 1
                    if front & 0x7FFF:
                        objects[f"Objects{area + 1}:{front & 0x7FFF}"] += 1
                    areas[area] += 1
        tile_histogram = dict(tiles)
        object_histogram = dict(objects)
        area_histogram = dict(areas)
        connection.execute("UPDATE files SET parse_status='structured' WHERE id=?", (file_id,))
    except Exception as error:
        error_text = f"{type(error).__name__}: {error}"
        connection.execute("UPDATE files SET parse_status='parse-error',parse_error=? WHERE id=?", (error_text, file_id))
    connection.execute(
        "INSERT INTO map_profiles VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        (
            file_id, variant, width, height, cells, blocked, lights, doors,
            json.dumps(tile_histogram, ensure_ascii=False), json.dumps(object_histogram, ensure_ascii=False),
            json.dumps(area_histogram, ensure_ascii=False), error_text,
        ),
    )


def parse_7z_slt(output: str) -> tuple[dict, list[dict]]:
    blocks: list[dict[str, str]] = []
    current: dict[str, str] = {}
    for line in output.splitlines():
        if not line.strip():
            if current:
                blocks.append(current)
                current = {}
            continue
        if " = " in line:
            key, value = line.split(" = ", 1)
            current[key.strip()] = value.strip()
    if current:
        blocks.append(current)
    archive = next((block for block in blocks if "Type" in block and "Physical Size" in block), {})
    members = [block for block in blocks if "Path" in block and "Size" in block and block is not archive]
    return archive, members


def scan_archive(path: Path, file_id: int, connection: sqlite3.Connection) -> None:
    if not SEVEN_ZIP.exists():
        connection.execute("INSERT INTO archive_checks VALUES (?,?,?,?,?,?)", (file_id, None, None, 0, "tool-missing", str(SEVEN_ZIP)))
        return
    try:
        listed = subprocess.run(
            [str(SEVEN_ZIP), "l", "-slt", str(path)], capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=180, check=False, stdin=subprocess.DEVNULL,
        )
        archive, members = parse_7z_slt(listed.stdout)
        rows = []
        for member in members:
            member_path = member.get("Path", "")
            if not member_path:
                continue
            rows.append((
                file_id, member_path.replace("\\", "/"), 1 if member.get("Folder") == "+" else 0,
                int(member["Size"]) if member.get("Size", "").isdigit() else None,
                int(member["Packed Size"]) if member.get("Packed Size", "").isdigit() else None,
                member.get("CRC"), 1 if member.get("Encrypted") == "+" else 0,
                member.get("Modified"), member.get("Method"),
            ))
        connection.executemany("INSERT OR REPLACE INTO archive_members VALUES (?,?,?,?,?,?,?,?,?)", rows)
        encrypted_members = sum(1 for member in members if member.get("Encrypted") == "+")
        if encrypted_members:
            status = "password-locked"
            error = f"{encrypted_members} encrypted members; no password stored in project"
        else:
            tested = subprocess.run(
                [str(SEVEN_ZIP), "t", "-p__NO_PASSWORD__", str(path)], capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=1800, check=False, stdin=subprocess.DEVNULL,
            )
            status = "ok" if tested.returncode == 0 and "Everything is Ok" in tested.stdout else "failed"
            error = None if status == "ok" else (tested.stdout + "\n" + tested.stderr)[-4000:]
        connection.execute(
            "INSERT INTO archive_checks VALUES (?,?,?,?,?,?)",
            (
                file_id, archive.get("Type"), int(archive.get("Physical Size", 0) or 0), len(rows), status, error,
            ),
        )
        connection.execute(
            "UPDATE files SET parse_status=?,parse_error=COALESCE(parse_error,?) WHERE id=?",
            ("structured" if status == "ok" else "parse-error", error, file_id),
        )
    except Exception as error:
        message = f"{type(error).__name__}: {error}"
        connection.execute("INSERT INTO archive_checks VALUES (?,?,?,?,?,?)", (file_id, None, None, 0, "failed", message))
        connection.execute("UPDATE files SET parse_status='parse-error',parse_error=? WHERE id=?", (message, file_id))


def structured_scan(source: Path, connection: sqlite3.Connection) -> None:
    canonical_wil: dict[str, int] = {}
    canonical_wzl: dict[str, int] = {}
    canonical_mir_lib: dict[str, int] = {}
    rows = connection.execute("SELECT id,relative_path,kind FROM files ORDER BY id").fetchall()
    targeted = [(int(file_id), source / relative, kind) for file_id, relative, kind in rows if kind in {"wil_library", "wzl_library", "mir_lib", "map", "archive"}]
    for index, (file_id, path, kind) in enumerate(targeted, 1):
        if kind == "wil_library":
            scan_wil(path, file_id, connection, canonical_wil)
        elif kind == "wzl_library":
            scan_wzl(path, file_id, connection, canonical_wzl)
        elif kind == "mir_lib":
            scan_mir_lib(path, file_id, connection, canonical_mir_lib)
        elif kind == "map":
            scan_map(path, file_id, connection)
        elif kind == "archive":
            scan_archive(path, file_id, connection)
        if index % 20 == 0:
            connection.commit()
            print(f"STRUCTURED_PROGRESS files={index}/{len(targeted)} kind={kind} path={path.name}", flush=True)
    connection.commit()


def export_csv(connection: sqlite3.Connection, output: Path, query: str, name: str) -> None:
    cursor = connection.execute(query)
    fields = [column[0] for column in cursor.description]
    with (output / name).open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(fields)
        writer.writerows(cursor)


def safe_distribution_folder(key: str) -> str:
    return re.sub(r"[^0-9A-Za-z_.-]+", "_", key).strip("._") or "distribution"


def export_distribution_archives(connection: sqlite3.Connection, output: Path) -> list[dict]:
    root = output / "distributions"
    root.mkdir(parents=True, exist_ok=True)
    summaries: list[dict] = []
    distributions = connection.execute(
        "SELECT id,distribution_key,distribution_kind,root_prefix,provenance,confidence FROM distributions ORDER BY distribution_key"
    ).fetchall()
    for distribution_id, key, kind, root_prefix, provenance, confidence in distributions:
        folder = root / safe_distribution_folder(str(key))
        folder.mkdir(parents=True, exist_ok=True)
        file_count, byte_count, parse_errors = connection.execute(
            "SELECT COUNT(*),COALESCE(SUM(size_bytes),0),SUM(CASE WHEN parse_status='parse-error' THEN 1 ELSE 0 END) FROM files WHERE distribution_id=?",
            (distribution_id,),
        ).fetchone()
        extensions = dict(connection.execute(
            "SELECT CASE WHEN extension='' THEN '<none>' ELSE extension END,COUNT(*) FROM files WHERE distribution_id=? GROUP BY extension ORDER BY COUNT(*) DESC",
            (distribution_id,),
        ))
        kinds = dict(connection.execute(
            "SELECT kind,COUNT(*) FROM files WHERE distribution_id=? GROUP BY kind ORDER BY kind", (distribution_id,),
        ))
        resource_libraries, logical_frames = connection.execute(
            "SELECT COUNT(*),COALESCE(SUM(r.frame_count),0) FROM resource_libraries r JOIN files f ON f.id=r.file_id WHERE f.distribution_id=?",
            (distribution_id,),
        ).fetchone()
        maps = connection.execute(
            "SELECT COUNT(*) FROM map_profiles m JOIN files f ON f.id=m.file_id WHERE f.distribution_id=?", (distribution_id,),
        ).fetchone()[0]
        archives = connection.execute(
            "SELECT COUNT(*) FROM archive_checks a JOIN files f ON f.id=a.archive_file_id WHERE f.distribution_id=?", (distribution_id,),
        ).fetchone()[0]
        summary = {
            "schemaVersion": 1,
            "distributionKey": key,
            "distributionKind": kind,
            "rootPrefix": root_prefix,
            "provenance": provenance,
            "confidence": confidence,
            "fileCount": file_count,
            "byteCount": byte_count,
            "parseErrorFiles": int(parse_errors or 0),
            "resourceLibraries": resource_libraries,
            "logicalFrames": logical_frames,
            "mapProfiles": maps,
            "archives": archives,
            "extensions": extensions,
            "kinds": kinds,
            "separationPolicy": "This distribution is independently archived; same names in other distributions never overwrite it.",
        }
        (folder / "manifest.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        export_csv(
            connection, folder,
            f"SELECT relative_path,size_bytes,sha256,kind,confidence,parse_status,COALESCE(parse_error,'') parse_error FROM files WHERE distribution_id={int(distribution_id)} ORDER BY relative_path",
            "files.csv",
        )
        export_csv(
            connection, folder,
            f"SELECT f.relative_path,s.category,s.hit_count,s.terms_json FROM semantic_hits s JOIN files f ON f.id=s.file_id WHERE f.distribution_id={int(distribution_id)} ORDER BY f.relative_path,s.category",
            "semantic_hits.csv",
        )
        export_csv(
            connection, folder,
            f"SELECT f.relative_path,r.format,r.frame_count,r.valid_frames,r.invalid_frames,COALESCE(r.parse_error,'') parse_error FROM resource_libraries r JOIN files f ON f.id=r.file_id WHERE f.distribution_id={int(distribution_id)} ORDER BY f.relative_path",
            "resource_libraries.csv",
        )
        export_csv(
            connection, folder,
            f"SELECT f.relative_path,m.format_variant,m.width,m.height,m.cell_count,COALESCE(m.parse_error,'') parse_error FROM map_profiles m JOIN files f ON f.id=m.file_id WHERE f.distribution_id={int(distribution_id)} ORDER BY f.relative_path",
            "maps.csv",
        )
        summaries.append(summary)
    (root / "index.json").write_text(json.dumps(summaries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    export_csv(
        connection, output,
        """SELECT f.sha256,COUNT(DISTINCT f.distribution_id) distribution_count,GROUP_CONCAT(DISTINCT d.distribution_key) distributions,
                  COUNT(*) file_count,GROUP_CONCAT(f.relative_path,' | ') paths
           FROM files f JOIN distributions d ON d.id=f.distribution_id
           GROUP BY f.sha256 HAVING COUNT(DISTINCT f.distribution_id)>1 ORDER BY distribution_count DESC,file_count DESC""",
        "cross_distribution_duplicates.csv",
    )
    return summaries


def validate(source: Path, connection: sqlite3.Connection, output: Path, inventory_totals: dict) -> dict:
    disk_files = [path for path in source.rglob("*") if path.is_file()]
    disk_count = len(disk_files)
    disk_bytes = sum(path.stat().st_size for path in disk_files)
    db_count, db_bytes, unhashed = connection.execute(
        "SELECT COUNT(*),COALESCE(SUM(size_bytes),0),SUM(CASE WHEN length(sha256)=64 THEN 0 ELSE 1 END) FROM files"
    ).fetchone()
    text_count = connection.execute("SELECT COUNT(*) FROM text_content").fetchone()[0]
    semantic_count = connection.execute("SELECT COUNT(*) FROM semantic_hits").fetchone()[0]
    archive_count = connection.execute("SELECT COUNT(*) FROM archive_checks").fetchone()[0]
    archive_failures = connection.execute("SELECT COUNT(*) FROM archive_checks WHERE test_status!='ok'").fetchone()[0]
    library_count, frame_count, valid_frames = connection.execute(
        "SELECT COUNT(*),COALESCE(SUM(frame_count),0),COALESCE(SUM(valid_frames),0) FROM resource_libraries"
    ).fetchone()
    canonical_frames = connection.execute("SELECT COUNT(*) FROM resource_frames").fetchone()[0]
    map_count = connection.execute("SELECT COUNT(*) FROM map_profiles").fetchone()[0]
    parse_errors = connection.execute("SELECT COUNT(*) FROM files WHERE parse_status='parse-error'").fetchone()[0]
    duplicate_files = connection.execute("SELECT COALESCE(SUM(c-1),0) FROM (SELECT COUNT(*) c FROM files GROUP BY sha256 HAVING c>1)").fetchone()[0]
    source_groups = dict(connection.execute("SELECT source_group,COUNT(*) FROM files GROUP BY source_group ORDER BY source_group"))
    distribution_summaries = export_distribution_archives(connection, output)
    kinds = dict(connection.execute("SELECT kind,COUNT(*) FROM files GROUP BY kind ORDER BY kind"))
    extensions = dict(connection.execute("SELECT CASE WHEN extension='' THEN '<none>' ELSE extension END,COUNT(*) FROM files GROUP BY extension ORDER BY COUNT(*) DESC"))
    report = {
        "schemaVersion": 1,
        "generatedAt": utc_now(),
        "sourceRoot": str(source),
        "coverage": {
            "diskFiles": disk_count,
            "catalogFiles": db_count,
            "diskBytes": disk_bytes,
            "catalogBytes": db_bytes,
            "unhashedFiles": int(unhashed or 0),
            "fileCountExact": disk_count == db_count,
            "byteCountExact": disk_bytes == db_bytes,
        },
        "contentIndexes": {
            "textFiles": text_count,
            "semanticCategoryRows": semantic_count,
            "resourceLibraries": library_count,
            "logicalFramesAcrossAllPaths": frame_count,
            "validFramesAcrossAllPaths": valid_frames,
            "canonicalFrameRows": canonical_frames,
            "mapProfiles": map_count,
            "archives": archive_count,
            "archiveFailures": archive_failures,
            "duplicateFilesBySha256": duplicate_files,
            "parseErrorFiles": parse_errors,
        },
        "sourceGroups": source_groups,
        "distributionCount": len(distribution_summaries),
        "distributions": distribution_summaries,
        "kinds": kinds,
        "extensions": extensions,
        "inventoryTotals": inventory_totals,
        "policy": {
            "identity": "filename and directory names are search hints only",
            "privateServer": "private-server data remains B/C candidate until cross-checked",
            "parseFailures": "failures remain indexed and are never silently dropped",
        },
    }
    (output / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    export_csv(connection, output, "SELECT d.distribution_key,f.relative_path,f.size_bytes,f.sha256,f.kind,f.source_group,f.confidence,f.parse_status,COALESCE(f.parse_error,'') parse_error FROM files f JOIN distributions d ON d.id=f.distribution_id ORDER BY d.distribution_key,f.relative_path", "files.csv")
    export_csv(connection, output, "SELECT extension,COUNT(*) file_count,SUM(size_bytes) bytes FROM files GROUP BY extension ORDER BY file_count DESC", "extensions.csv")
    export_csv(connection, output, "SELECT source_group,confidence,COUNT(*) file_count,SUM(size_bytes) bytes FROM files GROUP BY source_group,confidence ORDER BY source_group", "source_groups.csv")
    export_csv(connection, output, "SELECT distribution_key,distribution_kind,root_prefix,provenance,confidence FROM distributions ORDER BY distribution_key", "distributions.csv")
    export_csv(connection, output, "SELECT f.relative_path,a.member_path,a.size_bytes,a.packed_bytes,a.crc,a.encrypted FROM archive_members a JOIN files f ON f.id=a.archive_file_id ORDER BY f.relative_path,a.member_path", "archive_members.csv")
    export_csv(connection, output, "SELECT f.relative_path,r.format,r.frame_count,r.valid_frames,r.invalid_frames,r.canonical_file_id,COALESCE(r.parse_error,'') parse_error FROM resource_libraries r JOIN files f ON f.id=r.file_id ORDER BY f.relative_path", "resource_libraries.csv")
    export_csv(connection, output, "SELECT f.relative_path,m.format_variant,m.width,m.height,m.cell_count,COALESCE(m.parse_error,'') parse_error FROM map_profiles m JOIN files f ON f.id=m.file_id ORDER BY f.relative_path", "maps.csv")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Full local MIR client/server byte and content catalog")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--inventory-only", action="store_true")
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    distribution_output = output / "distributions"
    if distribution_output.exists():
        shutil.rmtree(distribution_output)
    database = output / "catalog.sqlite"
    connection = create_database(database)
    connection.executemany("INSERT INTO meta VALUES (?,?)", [
        ("schemaVersion", "1"), ("startedAt", utc_now()), ("sourceRoot", str(source)),
    ])
    print(f"FULL_MIR_SCAN_START source={source} output={output}", flush=True)
    totals = inventory(source, connection)
    print(f"INVENTORY_COMPLETE files={totals.get('files', 0)} bytes={totals.get('bytes', 0)}", flush=True)
    if not args.inventory_only:
        structured_scan(source, connection)
    connection.execute("INSERT OR REPLACE INTO meta VALUES (?,?)", ("finishedAt", utc_now()))
    connection.commit()
    report = validate(source, connection, output, totals)
    integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    connection.close()
    database_sha = sha256_file(database)
    manifest = {
        "schemaVersion": 1,
        "generatedAt": utc_now(),
        "database": database.name,
        "databaseSha256": database_sha,
        "sqliteIntegrity": integrity,
        **report,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "FULL_MIR_SCAN_COMPLETE "
        f"files={report['coverage']['catalogFiles']} bytes={report['coverage']['catalogBytes']} "
        f"libraries={report['contentIndexes']['resourceLibraries']} "
        f"frames={report['contentIndexes']['logicalFramesAcrossAllPaths']} "
        f"maps={report['contentIndexes']['mapProfiles']} archives={report['contentIndexes']['archives']} "
        f"parseErrors={report['contentIndexes']['parseErrorFiles']} integrity={integrity}",
        flush=True,
    )


if __name__ == "__main__":
    main()
