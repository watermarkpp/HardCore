"""Loopback-only browser workspace for Half Moon Generator V1."""

from __future__ import annotations

import hashlib
import io
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from PIL import Image

from tools.half_moon_generator import exploding_flame_editor, fire_editor, fire_wall_editor, fireball_editor, great_fireball_editor, hell_lightning_editor, hellfire_editor, hmg, holy_word_editor, ice_storm_editor, lightning_editor, magic_shield_editor, power_editor, repulsion_editor, teleport_editor, temptation_editor, thrust_editor


HTML = Path(__file__).with_name("index.html")
POWER_HTML = Path(__file__).with_name("power_editor.html")
FIREBALL_HTML = Path(__file__).with_name("fireball_editor.html")
REPULSION_HTML = Path(__file__).with_name("repulsion_editor.html")
ICE_STORM_BLEND_HTML = Path(__file__).with_name("ice_storm_blend_lab.html")
LIGHTNING_HTML = Path(__file__).with_name("lightning_editor.html")
HELLFIRE_HTML = Path(__file__).with_name("hellfire_editor.html")


class Workspace:
    def __init__(self):
        self.lock = threading.RLock()
        self.project = (hmg.load_project(hmg.PROJECT_PATH) if hmg.PROJECT_PATH.exists()
                        else hmg.new_original_project())
        if hmg.select_original_work(self.project) or not hmg.PROJECT_PATH.exists():
            hmg.save_project(self.project, hmg.PROJECT_PATH)
        self.cache: dict[tuple, bytes] = {}
        self.revision = 0

    def state(self) -> dict:
        with self.lock:
            candidate_id = self.project["selected_id"]
            return {"revision": self.revision, "selected_id": candidate_id,
                    "candidate": json.loads(json.dumps(self.project["candidates"][candidate_id])),
                    "directions": hmg.DIRECTIONS,
                    "formal_sha256": hashlib.sha256(hmg.FORMAL.read_bytes()).hexdigest()}

    def image(self, kind: str, direction: int, equipment: str) -> bytes:
        with self.lock:
            key = (self.revision, kind, direction, equipment)
            if key not in self.cache:
                candidate = self.project["candidates"][self.project["selected_id"]]
                if kind == "preview":
                    image = hmg.composite_strip(candidate, direction, equipment)
                elif kind == "contact":
                    image = hmg.bake(candidate)
                else:
                    raise ValueError("Unknown image")
                buffer = io.BytesIO()
                image.save(buffer, format="PNG", optimize=False)
                self.cache[key] = buffer.getvalue()
            return self.cache[key]

    def action(self, request: dict) -> dict:
        with self.lock:
            name = request["action"]
            candidate_id = self.project["selected_id"]
            if request.get("candidate_id", candidate_id) != candidate_id:
                raise ValueError("Only the working animation can be edited")
            if name == "nudge":
                candidate = self.project["candidates"][candidate_id]
                if int(candidate.get("render_version", 1)) != 4:
                    raise ValueError("Direction nudge requires original material editing")
                direction = int(request["direction"])
                if direction not in range(8):
                    raise ValueError("Unknown direction")
                dx, dy = int(request["dx"]), int(request["dy"])
                if abs(dx) + abs(dy) not in (1, 10):
                    raise ValueError("Nudge must move one axis by 1 or 10 pixels")
                name_of_direction = hmg.DIRECTIONS[direction]
                current = candidate["direction_overrides"].get(name_of_direction, {})
                hmg.edit_candidate(self.project, candidate_id, {
                    "offset_x": int(current.get("offset_x", 0)) + dx,
                    "offset_y": int(current.get("offset_y", 0)) + dy,
                }, name_of_direction)
            elif name == "tune":
                hmg.edit_candidate(self.project, candidate_id, request["changes"])
            elif name == "undo":
                candidate = self.project["candidates"][candidate_id]
                revisions = candidate.get("revisions", [])
                if not revisions:
                    raise ValueError("No previous edit to restore")
                previous = revisions.pop()
                candidate["parameters"] = previous["parameters"]
                candidate["direction_overrides"] = previous["direction_overrides"]
            elif name == "contact_export":
                target = hmg.export_contact_sheet(self.project["candidates"][candidate_id])
                return {"action": name, "path": str(target)}
            elif name == "bake_preview":
                target = hmg.OUTPUT_DIR / f"{candidate_id}.png"
                result = hmg.bake_preview(self.project["candidates"][candidate_id], target)
                result["action"] = name
                return result
            else:
                raise ValueError("Unknown action")
            hmg.save_project(self.project, hmg.PROJECT_PATH)
            self.revision += 1
            self.cache.clear()
            return {"action": name, "revision": self.revision}


WORKSPACE = None
POWER_WORKSPACE = None
THRUST_WORKSPACE = None
FIRE_WORKSPACE = None
FIREBALL_WORKSPACE = None
GREAT_FIREBALL_WORKSPACE = None
EXPLODING_FLAME_WORKSPACE = None
FIRE_WALL_WORKSPACE = None
HELL_LIGHTNING_WORKSPACE = None
MAGIC_SHIELD_WORKSPACE = None
HOLY_WORD_WORKSPACE = None
ICE_STORM_WORKSPACE = None
REPULSION_WORKSPACE = None
TEMPTATION_WORKSPACE = None
LIGHTNING_WORKSPACE = None
HELLFIRE_WORKSPACE = None
TELEPORT_WORKSPACE = None


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, payload: bytes, mime: str):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)

    def _json(self, status: int, data: dict):
        self._send(status, json.dumps(data, ensure_ascii=False).encode("utf-8"),
                   "application/json; charset=utf-8")

    def do_GET(self):
        url = urlsplit(self.path)
        try:
            if url.path == "/":
                self._send(200, HTML.read_bytes(), "text/html; charset=utf-8")
            elif url.path in ("/power", "/thrust", "/fire"):
                self._send(200, POWER_HTML.read_bytes(), "text/html; charset=utf-8")
            elif url.path in ("/fireball", "/great-fireball"):
                self._send(200, FIREBALL_HTML.read_bytes(), "text/html; charset=utf-8")
            elif url.path in ("/repulsion", "/temptation", "/teleport", "/exploding-flame", "/fire-wall", "/hell-lightning", "/magic-shield", "/holy-word", "/ice-storm"):
                self._send(200, REPULSION_HTML.read_bytes(), "text/html; charset=utf-8")
            elif url.path == "/ice-storm-blend":
                self._send(200, ICE_STORM_BLEND_HTML.read_bytes(), "text/html; charset=utf-8")
            elif url.path == "/lightning":
                self._send(200, LIGHTNING_HTML.read_bytes(), "text/html; charset=utf-8")
            elif url.path == "/hellfire":
                self._send(200, HELLFIRE_HTML.read_bytes(), "text/html; charset=utf-8")
            elif url.path == "/api/state":
                self._json(200, WORKSPACE.state())
            elif url.path == "/api/power/state":
                self._json(200, POWER_WORKSPACE.state())
            elif url.path == "/api/thrust/state":
                self._json(200, THRUST_WORKSPACE.state())
            elif url.path == "/api/fire/state":
                self._json(200, FIRE_WORKSPACE.state())
            elif url.path == "/api/fireball/state":
                self._json(200, FIREBALL_WORKSPACE.state())
            elif url.path == "/api/great-fireball/state":
                self._json(200, GREAT_FIREBALL_WORKSPACE.state())
            elif url.path == "/api/exploding-flame/state":
                self._json(200, EXPLODING_FLAME_WORKSPACE.state())
            elif url.path == "/api/fire-wall/state":
                self._json(200, FIRE_WALL_WORKSPACE.state())
            elif url.path == "/api/hell-lightning/state":
                self._json(200, HELL_LIGHTNING_WORKSPACE.state())
            elif url.path == "/api/magic-shield/state":
                self._json(200, MAGIC_SHIELD_WORKSPACE.state())
            elif url.path == "/api/holy-word/state":
                self._json(200, HOLY_WORD_WORKSPACE.state())
            elif url.path == "/api/ice-storm/state":
                self._json(200, ICE_STORM_WORKSPACE.state())
            elif url.path == "/api/repulsion/state":
                self._json(200, REPULSION_WORKSPACE.state())
            elif url.path == "/api/temptation/state":
                self._json(200, TEMPTATION_WORKSPACE.state())
            elif url.path == "/api/lightning/state":
                self._json(200, LIGHTNING_WORKSPACE.state())
            elif url.path == "/api/hellfire/state":
                self._json(200, HELLFIRE_WORKSPACE.state())
            elif url.path == "/api/teleport/state":
                self._json(200, TELEPORT_WORKSPACE.state())
            elif url.path == "/api/fireball/frame.png":
                query = parse_qs(url.query)
                direction = int(query.get("direction", ["0"])[0])
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, FIREBALL_WORKSPACE.image(direction, frame), "image/png")
            elif url.path == "/api/great-fireball/frame.png":
                query = parse_qs(url.query)
                direction = int(query.get("direction", ["0"])[0])
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, GREAT_FIREBALL_WORKSPACE.image(direction, frame), "image/png")
            elif url.path == "/api/exploding-flame/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, EXPLODING_FLAME_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/fire-wall/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, FIRE_WALL_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/hell-lightning/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, HELL_LIGHTNING_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/magic-shield/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, MAGIC_SHIELD_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/magic-shield/actor.png":
                self._send(200, magic_shield_editor.actor_idle_frame()[0], "image/png")
            elif url.path == "/api/holy-word/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, HOLY_WORD_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/ice-storm/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, ICE_STORM_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/ice-storm/original-frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, ice_storm_editor.original_frame_png(frame), "image/png")
            elif url.path == "/api/ice-storm/approved-frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, ice_storm_editor.approved_frame_png(frame), "image/png")
            elif url.path == "/api/repulsion/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, REPULSION_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/temptation/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, TEMPTATION_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/lightning/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, LIGHTNING_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/hellfire/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, HELLFIRE_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/teleport/frame.png":
                query = parse_qs(url.query)
                frame = int(query.get("frame", ["0"])[0])
                self._send(200, TELEPORT_WORKSPACE.image(frame), "image/png")
            elif url.path == "/api/power/preview.png":
                query = parse_qs(url.query)
                direction = int(query.get("direction", ["0"])[0])
                equipment = query.get("equipment", ["base"])[0]
                self._send(200, POWER_WORKSPACE.image(direction, equipment), "image/png")
            elif url.path == "/api/thrust/preview.png":
                query = parse_qs(url.query)
                direction = int(query.get("direction", ["0"])[0])
                equipment = query.get("equipment", ["base"])[0]
                self._send(200, THRUST_WORKSPACE.image(direction, equipment), "image/png")
            elif url.path == "/api/fire/preview.png":
                query = parse_qs(url.query)
                direction = int(query.get("direction", ["0"])[0])
                equipment = query.get("equipment", ["heavy"])[0]
                self._send(200, FIRE_WORKSPACE.image(direction, equipment), "image/png")
            elif url.path in ("/api/preview.png", "/api/contact.png"):
                query = parse_qs(url.query)
                direction = int(query.get("direction", ["0"])[0])
                equipment = query.get("equipment", ["base"])[0]
                kind = "preview" if url.path == "/api/preview.png" else "contact"
                self._send(200, WORKSPACE.image(kind, direction, equipment), "image/png")
            elif url.path == "/api/ground.png":
                ground = hmg.ROOT / "assets/art/maps/bich/editor_runtime_chunks/c_2_1.png"
                with Image.open(ground) as source:
                    crop = source.convert("RGBA").crop((392, 400, 632, 624))
                buffer = io.BytesIO()
                crop.save(buffer, format="PNG")
                self._send(200, buffer.getvalue(), "image/png")
            elif url.path == "/api/ground_wide.png":
                ground = hmg.ROOT / "assets/art/maps/bich/editor_runtime_chunks/c_2_1.png"
                with Image.open(ground) as source:
                    crop = source.convert("RGBA").crop((332, 362, 692, 662))
                buffer = io.BytesIO()
                crop.save(buffer, format="PNG")
                self._send(200, buffer.getvalue(), "image/png")
            else:
                self._json(404, {"error": "Not found"})
        except (KeyError, ValueError, IndexError) as error:
            self._json(400, {"error": str(error)})

    def do_POST(self):
        if self.path not in ("/api/action", "/api/power/action", "/api/thrust/action", "/api/fire/action", "/api/fireball/action", "/api/great-fireball/action", "/api/exploding-flame/action", "/api/fire-wall/action", "/api/hell-lightning/action", "/api/magic-shield/action", "/api/holy-word/action", "/api/ice-storm/action", "/api/repulsion/action", "/api/temptation/action", "/api/lightning/action", "/api/hellfire/action", "/api/teleport/action"):
            self._json(404, {"error": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 65536:
                raise ValueError("Invalid request size")
            request = json.loads(self.rfile.read(length))
            if not isinstance(request, dict):
                raise ValueError("Expected object")
            workspace = ({"/api/power/action": POWER_WORKSPACE,
                          "/api/thrust/action": THRUST_WORKSPACE,
                          "/api/fire/action": FIRE_WORKSPACE,
                          "/api/fireball/action": FIREBALL_WORKSPACE,
                          "/api/great-fireball/action": GREAT_FIREBALL_WORKSPACE,
                          "/api/exploding-flame/action": EXPLODING_FLAME_WORKSPACE,
                          "/api/fire-wall/action": FIRE_WALL_WORKSPACE,
                          "/api/hell-lightning/action": HELL_LIGHTNING_WORKSPACE,
                          "/api/magic-shield/action": MAGIC_SHIELD_WORKSPACE,
                          "/api/holy-word/action": HOLY_WORD_WORKSPACE,
                          "/api/ice-storm/action": ICE_STORM_WORKSPACE,
                          "/api/repulsion/action": REPULSION_WORKSPACE,
                          "/api/temptation/action": TEMPTATION_WORKSPACE,
                          "/api/lightning/action": LIGHTNING_WORKSPACE,
                          "/api/hellfire/action": HELLFIRE_WORKSPACE,
                          "/api/teleport/action": TELEPORT_WORKSPACE}.get(self.path, WORKSPACE))
            self._json(200, workspace.action(request))
        except (KeyError, ValueError, TypeError) as error:
            self._json(400, {"error": str(error)})

    def log_message(self, format_string, *args):
        # Keep the console usable; development diagnostics go to explicit logs.
        return


def serve(port: int = 8765):
    global WORKSPACE, POWER_WORKSPACE, THRUST_WORKSPACE, FIRE_WORKSPACE, GREAT_FIREBALL_WORKSPACE, EXPLODING_FLAME_WORKSPACE, FIRE_WALL_WORKSPACE, HELL_LIGHTNING_WORKSPACE, MAGIC_SHIELD_WORKSPACE, HOLY_WORD_WORKSPACE, ICE_STORM_WORKSPACE, FIREBALL_WORKSPACE, REPULSION_WORKSPACE, TEMPTATION_WORKSPACE, LIGHTNING_WORKSPACE, HELLFIRE_WORKSPACE, TELEPORT_WORKSPACE
    WORKSPACE = Workspace()
    POWER_WORKSPACE = power_editor.Workspace()
    THRUST_WORKSPACE = thrust_editor.Workspace()
    FIRE_WORKSPACE = fire_editor.Workspace()
    FIREBALL_WORKSPACE = fireball_editor.Workspace()
    GREAT_FIREBALL_WORKSPACE = great_fireball_editor.Workspace()
    EXPLODING_FLAME_WORKSPACE = exploding_flame_editor.Workspace()
    FIRE_WALL_WORKSPACE = fire_wall_editor.Workspace()
    HELL_LIGHTNING_WORKSPACE = hell_lightning_editor.Workspace()
    MAGIC_SHIELD_WORKSPACE = magic_shield_editor.Workspace()
    HOLY_WORD_WORKSPACE = holy_word_editor.Workspace()
    ICE_STORM_WORKSPACE = ice_storm_editor.Workspace()
    REPULSION_WORKSPACE = repulsion_editor.Workspace()
    TEMPTATION_WORKSPACE = temptation_editor.Workspace()
    LIGHTNING_WORKSPACE = lightning_editor.Workspace()
    HELLFIRE_WORKSPACE = hellfire_editor.Workspace()
    TELEPORT_WORKSPACE = teleport_editor.Workspace()
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"HMG_V1_READY http://127.0.0.1:{port}/", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    serve(parser.parse_args().port)
