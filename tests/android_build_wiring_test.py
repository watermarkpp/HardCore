"""Build-wiring regressions; these are NOT native/export/device acceptance."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class AndroidBuildWiring(unittest.TestCase):
    def test_registered_two_pass_hook_exists(self):
        source = (ROOT / 'tools/build_android_isolated.ps1').read_text(encoding='utf-8-sig')
        match = re.search(r"\. \(Join-Path \$ProjectRoot '([^']*android_two_pass_export_hook\.ps1)'\)", source)
        self.assertIsNotNone(match)
        self.assertTrue((ROOT / match[1].replace('\\', '/')).is_file(), 'production build references a missing two-pass hook')

    def test_generated_catalogue_is_installed_before_return(self):
        source = (ROOT / 'tools/build_android_isolated.ps1').read_text(encoding='utf-8-sig')
        begin = source.index('$RegenerateStageCatalogue = {')
        end = source.index('$VerifyProductionBuild = {', begin)
        callback = source[begin:end]
        self.assertIn('Copy-Item -LiteralPath $cataloguePath -Destination $InstalledCatalogue', callback)
        self.assertIn('SourceCatalogue = $InstalledCatalogue', callback)
        self.assertIn('scripts\\features\\generated\\internal_code_preparation_catalog_data.gd', callback)

    def test_owned_source_injection_precedes_export_hash(self):
        source = (ROOT / 'tools/android_seal/bridge/android_two_pass_export_hook.ps1').read_text(encoding='utf-8-sig')
        begin = source.index('function Invoke-CodeOfficialExport(')
        end = source.index('function Invoke-TwoPassAndroidCodeExport', begin)
        export = source[begin:end]
        self.assertIn('inject_sources_resign.ps1', export)
        self.assertLess(export.index('inject_sources_resign.ps1'), export.index('apk_sha256='))


if __name__ == '__main__':
    unittest.main(verbosity=2)
