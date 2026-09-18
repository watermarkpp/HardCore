"""BUG-08 source guard: the dormant AI state must never regain a generic
ground marker.

The dormant gray disc (Color(0.52, 0.50, 0.46, 0.72)) drawn under every
sleeping monster duplicated the normal dark contact shadow and read as a
white circle in game. Dormancy stays a pure AI state: this guard forbids the
former marker color and any ``if dormant:`` ground ``draw_circle`` marker in
the production enemy actor, while explicitly keeping every other legitimate
``dormant`` AI decision alive.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENEMY_SOURCE = ROOT / "scripts" / "enemy.gd"
BEHAVIOR_PROFILES = ROOT / "assets" / "data" / "monster_behavior_profiles.json"

# The exact former dormant ground-marker color (gray translucent disc).
FORBIDDEN_DORMANT_MARKER_COLOR = "Color(0.52, 0.50, 0.46, 0.72)"

enemy_text = ENEMY_SOURCE.read_text(encoding="utf-8")
enemy_lines = enemy_text.splitlines()


def _normalized(line: str) -> str:
    return line.strip().replace(" ", "").replace("\t", "")


def _next_nonempty_line(index: int) -> str:
    for later in range(index + 1, len(enemy_lines)):
        stripped = enemy_lines[later].strip()
        if stripped:
            return stripped
    return ""


def test_former_dormant_marker_color_is_gone() -> None:
    assert FORBIDDEN_DORMANT_MARKER_COLOR not in enemy_text, (
        "the former dormant ground-marker color must never return to enemy.gd"
    )


def test_no_dormant_ground_draw_circle_marker() -> None:
    """No ``if dormant:`` body may draw a circle ground marker.

    Other ``dormant`` AI decisions (movement gates, proximity wake, damage
    wake, burrow ambush) must stay untouched - only draw calls are guarded.
    """
    for index, line in enumerate(enemy_lines):
        normalized = _normalized(line)
        if not normalized.startswith("ifdormant") or not normalized.endswith(":"):
            continue
        body = _normalized(_next_nonempty_line(index))
        assert "draw_circle" not in body, (
            f"enemy.gd:{index + 1}: dormant ground marker drawing must stay removed"
        )


def test_dormant_ai_state_contract_still_exists() -> None:
    """The guard forbids drawing only; the dormant AI system itself must stay."""
    assert 'behavior_profile.get("dormant"' in enemy_text, (
        "enemy.gd must keep reading the authored dormant birth state"
    )
    assert "func _wake_dormant_from_received_damage(" in enemy_text, (
        "enemy.gd must keep the shared damage wake contract"
    )
    assert "if dormant:" in enemy_text, (
        "enemy.gd must keep the dormant AI decision points"
    )
    assert "_burrowed" in enemy_text, (
        "enemy.gd must keep the separate burrow ambush mechanic"
    )


def test_dormant_profile_data_still_exists() -> None:
    profiles_text = BEHAVIOR_PROFILES.read_text(encoding="utf-8")
    assert '"zuma_dormant": {"dormant": true}' in profiles_text, (
        "zuma dormant behavior profile must stay authored"
    )
