from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import messagebox

from PIL import Image, ImageDraw, ImageTk

from new_decor_r3_common import (
    CATALOG_PATH,
    MANUAL_OVERRIDE_PATH,
    REPO_ROOT,
    UNRESOLVED_PATH,
    asset_map,
    category_cn,
    load_json,
    numeric_pair,
    positive_int_pair,
    save_json,
)


HALF_TILE_W = 32.0
HALF_TILE_H = 16.0

CANVAS_W = 1180
CANVAS_H = 780

MAX_FP = 16


def checkerboard(
    width: int,
    height: int,
    cell: int = 16,
) -> Image.Image:
    image = Image.new(
        "RGB",
        (width, height),
        (72, 72, 72),
    )

    draw = ImageDraw.Draw(image)

    for y in range(0, height, cell):
        for x in range(0, width, cell):
            if (
                (x // cell + y // cell)
                % 2
            ):
                fill = (96, 96, 96)
            else:
                fill = (72, 72, 72)

            draw.rectangle(
                (
                    x,
                    y,
                    min(width, x + cell),
                    min(height, y + cell),
                ),
                fill=fill,
            )

    return image


class GeometryCalibrator:
    def __init__(self) -> None:
        if not UNRESOLVED_PATH.exists():
            raise SystemExit(
                f"missing unresolved file: "
                f"{UNRESOLVED_PATH}"
            )

        self.catalog = load_json(
            CATALOG_PATH
        )

        self.assets = asset_map(
            self.catalog
        )

        unresolved = load_json(
            UNRESOLVED_PATH
        )

        if not isinstance(unresolved, list):
            raise SystemExit(
                "unresolved JSON must be an array"
            )

        self.entries = [
            entry
            for entry in unresolved
            if str(
                entry.get(
                    "asset_id",
                    "",
                )
            )
            in self.assets
        ]

        if MANUAL_OVERRIDE_PATH.exists():
            value = load_json(
                MANUAL_OVERRIDE_PATH
            )

            self.overrides = (
                value
                if isinstance(value, dict)
                else {}
            )
        else:
            self.overrides = {}

        self.index = 0

        self.width_tiles = 1
        self.depth_tiles = 1

        self.anchor_x = 0.0
        self.anchor_y = 0.0

        self.root = tk.Tk()

        self.root.title(
            "MSE New Decor Geometry Calibrator R3"
        )

        self.root.geometry(
            "1240x900"
        )

        self.info = tk.Label(
            self.root,
            text="",
            anchor="w",
            justify="left",
            font=(
                "Consolas",
                12,
            ),
        )

        self.info.pack(
            fill="x",
            padx=12,
            pady=8,
        )

        self.canvas = tk.Canvas(
            self.root,
            width=CANVAS_W,
            height=CANVAS_H,
            bg="#303030",
            highlightthickness=0,
        )

        self.canvas.pack(
            padx=12,
            pady=4,
        )

        self.help_label = tk.Label(
            self.root,
            text=(
                "A/D = footprint宽度 -/+    "
                "S/W = footprint深度 -/+    "
                "J/L = anchor X -/+1px    "
                "I/K = anchor Y -/+1px    "
                "Enter = 保存并下一个    "
                "Backspace = 上一个    "
                "Q = 退出"
            ),
            anchor="w",
            justify="left",
            font=(
                "Microsoft YaHei",
                11,
            ),
        )

        self.help_label.pack(
            fill="x",
            padx=12,
            pady=8,
        )

        self.root.bind(
            "<Key>",
            self.on_key,
        )

        self.photo = None

        if not self.entries:
            messagebox.showinfo(
                "完成",
                "没有 unresolved geometry。",
            )
            self.root.destroy()
            return

        self.load_current()

    def current_asset_id(self) -> str:
        return str(
            self.entries[
                self.index
            ].get(
                "asset_id",
                "",
            )
        )

    def current_asset(self) -> dict:
        return self.assets[
            self.current_asset_id()
        ]

    def load_current(self) -> None:
        asset_id = (
            self.current_asset_id()
        )

        asset = self.current_asset()

        override = self.overrides.get(
            asset_id,
            {},
        )

        fp = positive_int_pair(
            override.get(
                "footprint_tiles"
            )
        )

        if fp is None:
            fp = positive_int_pair(
                asset.get(
                    "footprint_tiles"
                )
            )

        if fp is None:
            fp = [1, 1]

        self.width_tiles = int(
            fp[0]
        )

        self.depth_tiles = int(
            fp[1]
        )

        anchor = numeric_pair(
            override.get(
                "anchor_px"
            )
        )

        if anchor is None:
            anchor = numeric_pair(
                asset.get(
                    "anchor_px"
                )
            )

        if anchor is None:
            canvas_size = asset.get(
                "canvas_size",
                [64, 64],
            )

            anchor = [
                float(canvas_size[0])
                * 0.5,
                float(canvas_size[1])
                - 1.0,
            ]

        self.anchor_x = float(
            anchor[0]
        )

        self.anchor_y = float(
            anchor[1]
        )

        self.redraw()

    def image_path(self) -> Path:
        return (
            REPO_ROOT
            / str(
                self.current_asset().get(
                    "image",
                    "",
                )
            )
        )

    def iso_source_point(
        self,
        tile_x: float,
        tile_y: float,
        approved_scale: float,
    ) -> tuple[float, float]:
        # 当前 anchor 对应 footprint 最前方/最下方顶点：
        # tile=(width, depth)
        dx = (
            tile_x
            - self.width_tiles
        )

        dy = (
            tile_y
            - self.depth_tiles
        )

        px = (
            self.anchor_x
            + (
                (dx - dy)
                * HALF_TILE_W
            )
            / approved_scale
        )

        py = (
            self.anchor_y
            + (
                (dx + dy)
                * HALF_TILE_H
            )
            / approved_scale
        )

        return px, py

    def redraw(self) -> None:
        asset = self.current_asset()

        path = self.image_path()

        if not path.is_file():
            self.info.config(
                text=(
                    f"ERROR: missing image\n"
                    f"{path}"
                )
            )
            return

        original = Image.open(
            path
        ).convert("RGBA")

        margin = 40

        fit = min(
            (
                CANVAS_W
                - margin * 2
            )
            / max(
                1,
                original.width,
            ),
            (
                CANVAS_H
                - margin * 2
            )
            / max(
                1,
                original.height,
            ),
            1.5,
        )

        display_w = max(
            1,
            int(
                round(
                    original.width
                    * fit
                )
            ),
        )

        display_h = max(
            1,
            int(
                round(
                    original.height
                    * fit
                )
            ),
        )

        resized = original.resize(
            (
                display_w,
                display_h,
            ),
            Image.Resampling.LANCZOS,
        )

        panel = checkerboard(
            CANVAS_W,
            CANVAS_H,
        )

        offset_x = (
            CANVAS_W
            - display_w
        ) // 2

        offset_y = (
            CANVAS_H
            - display_h
        ) // 2

        panel.paste(
            resized,
            (
                offset_x,
                offset_y,
            ),
            resized,
        )

        draw = ImageDraw.Draw(
            panel
        )

        approved_scale = float(
            asset.get(
                "approved_scale",
                1.0,
            )
        )

        if approved_scale <= 0:
            approved_scale = 1.0

        def screen_point(
            tile_x: float,
            tile_y: float,
        ) -> tuple[float, float]:
            sx, sy = (
                self.iso_source_point(
                    tile_x,
                    tile_y,
                    approved_scale,
                )
            )

            return (
                offset_x
                + sx * fit,
                offset_y
                + sy * fit,
            )

        # footprint 内所有 X 方向网格线
        for x in range(
            self.width_tiles + 1
        ):
            p1 = screen_point(
                x,
                0,
            )

            p2 = screen_point(
                x,
                self.depth_tiles,
            )

            draw.line(
                (
                    p1,
                    p2,
                ),
                fill=(60, 255, 150),
                width=2,
            )

        # footprint 内所有 Y 方向网格线
        for y in range(
            self.depth_tiles + 1
        ):
            p1 = screen_point(
                0,
                y,
            )

            p2 = screen_point(
                self.width_tiles,
                y,
            )

            draw.line(
                (
                    p1,
                    p2,
                ),
                fill=(60, 255, 150),
                width=2,
            )

        # anchor 点
        anchor_screen_x = (
            offset_x
            + self.anchor_x
            * fit
        )

        anchor_screen_y = (
            offset_y
            + self.anchor_y
            * fit
        )

        r = 7

        draw.ellipse(
            (
                anchor_screen_x - r,
                anchor_screen_y - r,
                anchor_screen_x + r,
                anchor_screen_y + r,
            ),
            outline=(255, 80, 80),
            width=3,
        )

        draw.line(
            (
                anchor_screen_x - 12,
                anchor_screen_y,
                anchor_screen_x + 12,
                anchor_screen_y,
            ),
            fill=(255, 80, 80),
            width=2,
        )

        draw.line(
            (
                anchor_screen_x,
                anchor_screen_y - 12,
                anchor_screen_x,
                anchor_screen_y + 12,
            ),
            fill=(255, 80, 80),
            width=2,
        )

        self.photo = ImageTk.PhotoImage(
            panel
        )

        self.canvas.delete(
            "all"
        )

        self.canvas.create_image(
            0,
            0,
            anchor="nw",
            image=self.photo,
        )

        saved = (
            asset.get(
                "asset_id",
                "",
            )
            in self.overrides
        )

        self.info.config(
            text=(
                f"[{self.index + 1}/"
                f"{len(self.entries)}]    "
                f"{'SAVED' if saved else 'UNSAVED'}\n"
                f"asset_id = "
                f"{asset.get('asset_id', '')}\n"
                f"category = "
                f"{category_cn(asset)}\n"
                f"display_name = "
                f"{asset.get('display_name', '')}\n"
                f"footprint = "
                f"[{self.width_tiles}, "
                f"{self.depth_tiles}]\n"
                f"anchor_px = "
                f"[{self.anchor_x:.1f}, "
                f"{self.anchor_y:.1f}]\n"
                f"approved_scale = "
                f"{approved_scale:.4f}\n"
                f"image = "
                f"{asset.get('image', '')}"
            )
        )

    def save_current(self) -> None:
        asset_id = (
            self.current_asset_id()
        )

        previous = self.overrides.get(
            asset_id,
            {},
        )

        value = (
            previous.copy()
            if isinstance(
                previous,
                dict,
            )
            else {}
        )

        value[
            "footprint_tiles"
        ] = [
            int(
                self.width_tiles
            ),
            int(
                self.depth_tiles
            ),
        ]

        value[
            "anchor_px"
        ] = [
            round(
                self.anchor_x,
                3,
            ),
            round(
                self.anchor_y,
                3,
            ),
        ]

        value[
            "manual_reviewed"
        ] = True

        self.overrides[
            asset_id
        ] = value

        save_json(
            MANUAL_OVERRIDE_PATH,
            self.overrides,
        )

    def next_asset(self) -> None:
        self.save_current()

        if (
            self.index
            >= len(self.entries) - 1
        ):
            messagebox.showinfo(
                "全部完成",
                (
                    "全部 unresolved 素材"
                    "已经保存到：\n"
                    f"{MANUAL_OVERRIDE_PATH}"
                ),
            )

            self.redraw()
            return

        self.index += 1

        self.load_current()

    def previous_asset(self) -> None:
        if self.index <= 0:
            return

        self.index -= 1

        self.load_current()

    def on_key(
        self,
        event,
    ) -> None:
        key = (
            event.keysym.lower()
        )

        changed = False

        if key == "a":
            self.width_tiles = max(
                1,
                self.width_tiles - 1,
            )
            changed = True

        elif key == "d":
            self.width_tiles = min(
                MAX_FP,
                self.width_tiles + 1,
            )
            changed = True

        elif key == "s":
            self.depth_tiles = max(
                1,
                self.depth_tiles - 1,
            )
            changed = True

        elif key == "w":
            self.depth_tiles = min(
                MAX_FP,
                self.depth_tiles + 1,
            )
            changed = True

        elif key == "j":
            self.anchor_x -= 1.0
            changed = True

        elif key == "l":
            self.anchor_x += 1.0
            changed = True

        elif key == "i":
            self.anchor_y -= 1.0
            changed = True

        elif key == "k":
            self.anchor_y += 1.0
            changed = True

        elif key == "return":
            self.next_asset()
            return

        elif key == "backspace":
            self.previous_asset()
            return

        elif key == "q":
            self.root.destroy()
            return

        if changed:
            self.redraw()

    def run(self) -> None:
        self.root.mainloop()


if __name__ == "__main__":
    GeometryCalibrator().run()
