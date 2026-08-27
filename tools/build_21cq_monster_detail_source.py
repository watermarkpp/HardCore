#!/usr/bin/env python3
"""Fetch and validate the user-authoritative 21CQ monster detail source.

The 21CQ detail page contains several unrelated tables after the attribute
header.  This tool deliberately parses only the header before the first
spawn-table navigation element, and never serializes page HTML or drop/spawn
rows into the checked-in source snapshot.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import hashlib
import html
import json
import re
import sys
import urllib.error
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
VANILLA_PATH = ROOT / "assets/data/vanilla_176/monsters.json"
DEFAULT_OUTPUT = ROOT / "assets/data/monster_21cq_detail_source_v1.json"
LIST_URL = "https://www.21cq.com/mir/Monster.Aspx"
DETAIL_URL_TEMPLATE = "https://www.21cq.com/mir/Mob.Aspx?ID={monster_id}"
PARSER_VERSION = "21cq_monster_detail_parser_v1.0.0"
USER_AGENT = "HardCore-monster-source-audit/1.0 (+https://www.21cq.com/mir/)"
EXPECTED_RECORD_COUNT = 217


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def fetch(url: str) -> tuple[bytes, int, str]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read(), int(response.status), response.headers.get_content_charset() or "gb2312"
    except urllib.error.HTTPError as exc:
        body = exc.read()
        return body, int(exc.code), exc.headers.get_content_charset() or "gb2312"


def decode_html(raw: bytes, charset: str) -> str:
    # The site advertises gb2312 and the current pages are gb2312.  Keep a
    # deterministic fallback for a future server correction without silently
    # accepting replacement characters.
    for encoding in (charset, "gb2312", "gb18030", "utf-8"):
        try:
            text = raw.decode(encoding)
        except (LookupError, UnicodeDecodeError):
            continue
        if "\ufffd" not in text:
            return text
    raise ValueError("page could not be decoded without replacement characters")


def normalized_text(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(value)).strip()


class MonsterListParser(HTMLParser):
    """Extract rows from the list table by exact Mob.Aspx ID links."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rows: list[dict[str, Any]] = []
        self._cells: list[str] = []
        self._cell_text: list[str] = []
        self._links: list[str] = []
        self._in_tr = False
        self._in_td = False
        self._in_a = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if tag == "tr":
            self._in_tr = True
            self._cells = []
            self._links = []
        elif self._in_tr and tag == "td":
            self._in_td = True
            self._cell_text = []
        elif self._in_tr and tag == "a":
            self._in_a = True
            attributes = dict(attrs)
            href = str(attributes.get("href") or "")
            if href:
                self._links.append(href)

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag == "a":
            self._in_a = False
        elif tag == "td" and self._in_td:
            self._cells.append(normalized_text("".join(self._cell_text)))
            self._in_td = False
        elif tag == "tr" and self._in_tr:
            self._in_tr = False
            id_match = next(
                (
                    re.search(r"Mob\.Aspx\?ID=(\d+)", link, flags=re.IGNORECASE)
                    for link in self._links
                    if re.search(r"Mob\.Aspx\?ID=(\d+)", link, flags=re.IGNORECASE)
                ),
                None,
            )
            if id_match and len(self._cells) >= 8:
                attack_match = re.fullmatch(r"(\d+)\s*-\s*(\d+)", self._cells[7])
                if not attack_match:
                    raise ValueError(f"list row {id_match.group(1)} has invalid attack range")
                self.rows.append(
                    {
                        "monster_id": int(id_match.group(1)),
                        "name": self._cells[1],
                        "level": int(self._cells[2]),
                        "exp": int(self._cells[3]),
                        "hp": int(self._cells[4]),
                        "defense": int(self._cells[5]),
                        "magic_defense": int(self._cells[6]),
                        "attack_min": int(attack_match.group(1)),
                        "attack_max": int(attack_match.group(2)),
                    }
                )

    def handle_data(self, data: str) -> None:
        if self._in_td:
            self._cell_text.append(data)


def parse_list_page(text: str) -> list[dict[str, Any]]:
    parser = MonsterListParser()
    parser.feed(text)
    parser.close()
    rows = sorted(parser.rows, key=lambda row: int(row["monster_id"]))
    ids = [int(row["monster_id"]) for row in rows]
    if len(rows) != EXPECTED_RECORD_COUNT or len(set(ids)) != EXPECTED_RECORD_COUNT:
        raise ValueError(f"expected {EXPECTED_RECORD_COUNT} unique list rows, got {len(rows)}")
    return rows


def detail_header(text: str) -> str:
    # This marker is the first navigation element for the spawn/respawn table.
    # Fail closed if the page layout changes: parsing the complete page could
    # accidentally ingest drop or refresh data.
    marker = re.search(r"<ul\b[^>]*class=[\"'][^\"']*nav-tabs[^\"']*[\"'][^>]*>", text, re.IGNORECASE)
    if not marker:
        raise ValueError("detail page has no spawn-table boundary")
    return text[: marker.start()]


def plain_header(text: str) -> str:
    header = detail_header(text)
    header = re.sub(r"<br\s*/?>", "\n", header, flags=re.IGNORECASE)
    header = re.sub(r"<[^>]+>", " ", header)
    return normalized_text(header)


def first_int(pattern: str, text: str, field: str) -> int:
    match = re.search(pattern, text, flags=re.IGNORECASE)
    if not match:
        raise ValueError(f"detail page missing {field}")
    return int(match.group(1))


def parse_detail(text: str, monster_id: int) -> dict[str, Any]:
    header = detail_header(text)
    plain = plain_header(text)
    name_match = re.search(r'class=["\'][^"\']*selectable[^"\']*["\'][^>]*>\s*([^<]+?)\s*</span>', header, re.IGNORECASE)
    if not name_match:
        raise ValueError(f"monster_id={monster_id} detail page missing name")
    life_match = re.search(r"属性\s*[：:]\s*(生物系|不死系)", plain)
    if not life_match:
        raise ValueError(f"monster_id={monster_id} detail page missing life_type")
    attack_match = re.search(r"攻击\s*[：:]\s*(\d+)\s*-\s*(\d+)", plain)
    if not attack_match:
        raise ValueError(f"monster_id={monster_id} detail page missing attack range")
    hp_match = re.search(r'class=["\'][^"\']*progress[^"\']*["\'][^>]*>\s*(\d+)\s*/\s*(\d+)', header, re.IGNORECASE)
    if not hp_match:
        raise ValueError(f"monster_id={monster_id} detail page missing hp")
    return {
        "monster_id": monster_id,
        "name": normalized_text(name_match.group(1)),
        "level": first_int(r"等级\s*[：:]\s*(\d+)", plain, "level"),
        "exp": first_int(r"经验\s*[：:]\s*(\d+)", plain, "exp"),
        "hp": int(hp_match.group(1)),
        "defense": first_int(r"防御\s*[：:]\s*(\d+)", plain, "defense"),
        "agility": first_int(r"敏捷\s*[：:]\s*(\d+)", plain, "agility"),
        "attack_min": int(attack_match.group(1)),
        "attack_max": int(attack_match.group(2)),
        "magic_defense": first_int(r"魔御\s*[：:]\s*(\d+)", plain, "magic_defense"),
        "accuracy": first_int(r"准确\s*[：:]\s*(\d+)", plain, "accuracy"),
        "attack_interval_ms": first_int(r"攻击间隔\s*[:：]\s*(\d+)\s*ms", plain, "attack_interval_ms"),
        "move_interval_ms": first_int(r"移动间隔\s*[:：]\s*(\d+)\s*ms", plain, "move_interval_ms"),
        "life_type": life_match.group(1),
        "undead": life_match.group(1) == "不死系",
        "anti_stealth": "反隐身" in plain,
    }


def local_ids() -> list[int]:
    payload = json.loads(VANILLA_PATH.read_text(encoding="utf-8"))
    ids = sorted(
        int(row["monsterId"])
        for row in payload.get("records", [])
        if isinstance(row, dict) and int(row.get("monsterId", -1)) > 0
    )
    if len(ids) != EXPECTED_RECORD_COUNT or len(set(ids)) != EXPECTED_RECORD_COUNT:
        raise ValueError(f"expected {EXPECTED_RECORD_COUNT} local monster IDs, got {len(ids)}")
    return ids


def make_record(monster_id: int, list_row: dict[str, Any], result: tuple[bytes, int, str, str]) -> dict[str, Any]:
    raw, status, charset, fetched_at = result
    if status != 200:
        raise ValueError(f"monster_id={monster_id} detail HTTP status={status}")
    parsed = parse_detail(decode_html(raw, charset), monster_id)
    expected_keys = ("name", "level", "exp", "hp", "defense", "magic_defense", "attack_min", "attack_max")
    for key in expected_keys:
        if parsed[key] != list_row[key]:
            raise ValueError(
                f"monster_id={monster_id} list/detail mismatch {key}: {list_row[key]!r} != {parsed[key]!r}"
            )
    return {
        **parsed,
        "source_url": DETAIL_URL_TEMPLATE.format(monster_id=monster_id),
        "list_source_url": LIST_URL,
        "fetched_at_utc": fetched_at,
        "http_status": status,
        "raw_html_sha256": sha256(raw),
        "raw_html_encoding": charset,
        "parser_version": PARSER_VERSION,
    }


def build_snapshot() -> dict[str, Any]:
    list_raw, list_status, list_charset = fetch(LIST_URL)
    list_fetched_at = utc_now()
    if list_status != 200:
        raise ValueError(f"monster list HTTP status={list_status}")
    list_text = decode_html(list_raw, list_charset)
    list_rows = parse_list_page(list_text)
    expected_ids = local_ids()
    list_ids = [int(row["monster_id"]) for row in list_rows]
    if list_ids != expected_ids:
        raise ValueError("21CQ list IDs differ from local vanilla monster IDs")
    by_id = {int(row["monster_id"]): row for row in list_rows}

    def get_one(monster_id: int) -> tuple[int, dict[str, Any]]:
        url = DETAIL_URL_TEMPLATE.format(monster_id=monster_id)
        raw, status, charset = fetch(url)
        return monster_id, make_record(monster_id, by_id[monster_id], (raw, status, charset, utc_now()))

    records: dict[int, dict[str, Any]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as executor:
        futures = [executor.submit(get_one, monster_id) for monster_id in expected_ids]
        for future in concurrent.futures.as_completed(futures):
            monster_id, record = future.result()
            records[monster_id] = record
    if sorted(records) != expected_ids:
        raise ValueError("detail records do not cover all expected IDs")
    return {
        "schema_version": 1,
        "source_id": "monster_21cq_detail_source_v1",
        "authority": "user_authoritative_override",
        "authority_scope": ["monster_attributes", "monster_timing", "monster_life_flags"],
        "distribution": "user.21cq.com.mir.monster_detail",
        "tier": "user_authoritative",
        "source_list_url": LIST_URL,
        "fetched_at_utc": list_fetched_at,
        "http_status": list_status,
        "raw_list_html_sha256": sha256(list_raw),
        "raw_list_html_encoding": list_charset,
        "parser": {
            "name": PARSER_VERSION,
            "version": PARSER_VERSION,
            "detail_boundary": "first ul.nav-tabs before spawn/respawn tables",
        },
        "excluded_content": [
            "spawn_table",
            "drop_tables",
            "map",
            "spawn_quantity",
            "respawn_time",
            "drop_probability",
        ],
        "list_row_count": len(list_rows),
        "records": [records[monster_id] for monster_id in expected_ids],
    }


def validate_snapshot(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if payload.get("authority") != "user_authoritative_override":
        errors.append("authority must be user_authoritative_override")
    if payload.get("authority_scope") != ["monster_attributes", "monster_timing", "monster_life_flags"]:
        errors.append("authority_scope mismatch")
    if payload.get("list_row_count") != EXPECTED_RECORD_COUNT:
        errors.append("list_row_count mismatch")
    if payload.get("excluded_content") != [
        "spawn_table", "drop_tables", "map", "spawn_quantity", "respawn_time", "drop_probability"
    ]:
        errors.append("excluded_content mismatch")
    records = payload.get("records")
    if not isinstance(records, list) or len(records) != EXPECTED_RECORD_COUNT:
        errors.append("records must contain exactly 217 rows")
        return errors
    required = {
        "monster_id", "name", "level", "exp", "hp", "defense", "agility", "attack_min", "attack_max",
        "magic_defense", "accuracy", "attack_interval_ms", "move_interval_ms", "life_type", "undead",
        "anti_stealth", "source_url", "list_source_url", "fetched_at_utc", "http_status", "raw_html_sha256",
        "raw_html_encoding", "parser_version",
    }
    ids: list[int] = []
    for index, row in enumerate(records):
        if not isinstance(row, dict):
            errors.append(f"record[{index}] must be an object")
            continue
        missing = sorted(required - set(row))
        if missing:
            errors.append(f"record[{index}] missing {missing}")
            continue
        monster_id = row.get("monster_id")
        if isinstance(monster_id, bool) or not isinstance(monster_id, int) or monster_id <= 0:
            errors.append(f"record[{index}] invalid monster_id")
        else:
            ids.append(monster_id)
            if row.get("source_url") != DETAIL_URL_TEMPLATE.format(monster_id=monster_id):
                errors.append(f"record[{index}] source_url is not exact ID URL")
        for field in ("level", "exp", "hp", "defense", "agility", "attack_min", "attack_max", "magic_defense", "accuracy", "attack_interval_ms", "move_interval_ms"):
            value = row.get(field)
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                errors.append(f"record[{index}] invalid {field}")
        if row.get("life_type") not in ("生物系", "不死系"):
            errors.append(f"record[{index}] invalid life_type")
        if row.get("undead") != (row.get("life_type") == "不死系"):
            errors.append(f"record[{index}] undead/life_type mismatch")
        if row.get("http_status") != 200 or not re.fullmatch(r"[0-9A-F]{64}", str(row.get("raw_html_sha256", ""))):
            errors.append(f"record[{index}] HTTP/hash evidence invalid")
        if "drop" in json.dumps(row, ensure_ascii=False).lower() or "spawn" in json.dumps(row, ensure_ascii=False).lower():
            # Source URLs and parser evidence are allowed; page-derived rows
            # must not grow forbidden content fields.
            forbidden = {"drop", "spawn", "respawn", "map", "quantity", "probability"}
            if any(key.lower() in forbidden for key in row):
                errors.append(f"record[{index}] contains excluded field")
    if ids != sorted(ids) or len(set(ids)) != len(ids):
        errors.append("record IDs must be unique and sorted")
    if ids != local_ids():
        errors.append("snapshot IDs differ from local vanilla monster IDs")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="fetch and write a new source snapshot")
    parser.add_argument("--check", action="store_true", help="validate an existing source snapshot offline")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    try:
        if args.write:
            payload = build_snapshot()
            errors = validate_snapshot(payload)
            if errors:
                for error in errors:
                    print(f"ERROR: {error}", file=sys.stderr)
                return 1
            rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8", newline="\n")
            print(f"21CQ_MONSTER_DETAIL_SOURCE_BUILD_PASS: records={len(payload['records'])} output={args.output}")
            return 0
        if not args.check:
            parser.error("one of --write or --check is required")
        if not args.output.is_file():
            print(f"ERROR: missing {args.output}", file=sys.stderr)
            return 1
        payload = json.loads(args.output.read_text(encoding="utf-8"))
        errors = validate_snapshot(payload)
        if errors:
            for error in errors:
                print(f"ERROR: {error}", file=sys.stderr)
            return 1
        print(f"21CQ_MONSTER_DETAIL_SOURCE_CHECK_PASS: records={len(payload['records'])}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
