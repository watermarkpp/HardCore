import importlib.util
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path, PureWindowsPath

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SOURCE = "outputs/wooma_temple_regenerated"
OLD_CHINESE_ROOT = "我的刷子游戏"


def load_module(name: str, relative_path: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


STANDARD = load_module(
    "wooma_wall_builder_under_test",
    "tools/map_assets/build_wooma_temple_wall_pack.py",
)
WARM = load_module(
    "wooma_warm_wall_builder_under_test",
    "tools/map_assets/build_wooma_temple_warm_wall_variant.py",
)


class WoomaTempleWallCatalogSourcePathTest(unittest.TestCase):
    def test_real_builds_keep_both_catalogs_project_relative(self):
        with tempfile.TemporaryDirectory(prefix="wooma_wall_catalog_") as folder:
            isolated_root = Path(folder)
            data = isolated_root / "assets/data/assets"
            source_dir = isolated_root / EXPECTED_SOURCE
            source_dir.mkdir(parents=True)
            data.mkdir(parents=True)

            front_source = source_dir / "wooma_wall_front_bay_alpha.png"
            cap_source = source_dir / "wooma_wall_capstone_alpha.png"
            Image.new("RGBA", (32, 160), (120, 130, 110, 255)).save(front_source)
            Image.new("RGBA", (64, 64), (150, 155, 135, 255)).save(cap_source)

            modules = []
            for index in range(16):
                axis = "iso_x" if index < 8 else "iso_y"
                modules.append(
                    {
                        "asset_id": f"orc_tomb_wall_{axis}_{index:02d}",
                        "display_name": f"fixture {index}",
                        "asset_type": "wall_module",
                        "topology": "straight",
                        "axis": axis,
                        "length_tiles": 1,
                        "variant": 1,
                        "footprint_tiles": [1, 1],
                        "wall_family_id": STANDARD.SOURCE_FAMILY_ID,
                        "connectors": [],
                        "repeat_group": f"orc_tomb_fixture_{index:02d}",
                    }
                )
            (data / "wall_module_catalog.json").write_text(
                json.dumps({"modules": modules}),
                encoding="utf-8",
            )
            (data / "wall_family_catalog.json").write_text(
                json.dumps({"wall_families": []}),
                encoding="utf-8",
            )

            standard_catalog = data / "map_wooma_temple_wall_asset_catalog.json"
            warm_catalog = data / "map_wooma_temple_warm_wall_asset_catalog.json"
            self._configure_standard(
                isolated_root,
                data,
                source_dir,
                front_source,
                cap_source,
                standard_catalog,
            )
            STANDARD.main()
            self._configure_warm(isolated_root, data, standard_catalog, warm_catalog)
            WARM.main()

            self.assertTrue(source_dir.is_dir())
            self._assert_portable_sources(standard_catalog)
            self._assert_portable_sources(warm_catalog)

    def _configure_standard(
        self,
        isolated_root: Path,
        data: Path,
        source_dir: Path,
        front_source: Path,
        cap_source: Path,
        standard_catalog: Path,
    ) -> None:
        STANDARD.ROOT = isolated_root
        STANDARD.SOURCE_DIR = source_dir
        STANDARD.FRONT_SOURCE = front_source
        STANDARD.CAP_SOURCE = cap_source
        STANDARD.ART_ROOT = isolated_root / STANDARD.ART_ROOT.relative_to(ROOT)
        STANDARD.MODULE_CATALOG = data / "wall_module_catalog.json"
        STANDARD.FAMILY_CATALOG = data / "wall_family_catalog.json"
        STANDARD.ASSET_CATALOG = standard_catalog

    def _configure_warm(
        self,
        isolated_root: Path,
        data: Path,
        standard_catalog: Path,
        warm_catalog: Path,
    ) -> None:
        WARM.ROOT = isolated_root
        WARM.DATA = data
        WARM.STANDARD_CATALOG = standard_catalog
        WARM.WARM_CATALOG = warm_catalog
        WARM.MODULE_CATALOG = data / "wall_module_catalog.json"
        WARM.FAMILY_CATALOG = data / "wall_family_catalog.json"
        WARM.WARM_ART_ROOT = isolated_root / WARM.WARM_ART_SEGMENT

    def _assert_portable_sources(self, catalog_path: Path) -> None:
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        assets = catalog["assets"]
        self.assertEqual(len(assets), 16)
        for asset in assets:
            source = asset["source_external_path"]
            self.assertEqual(source, EXPECTED_SOURCE)
            self.assertFalse(Path(source).is_absolute())
            self.assertEqual(PureWindowsPath(source).drive, "")
            self.assertIsNone(re.match(r"^[A-Za-z]:", source))
            self.assertNotIn(OLD_CHINESE_ROOT, source)


if __name__ == "__main__":
    unittest.main()
