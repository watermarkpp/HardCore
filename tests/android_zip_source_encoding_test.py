"""Actual Windows/.NET ZIP update of Godot UTF-8 names without EFS flags.

Executes the production injector's Open expression; no APK signing/device claim.
"""
import base64
import pathlib
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


class AndroidZipSourceEncoding(unittest.TestCase):
    def test_source_injection_preserves_utf8_asset_names(self):
        powershell = shutil.which('powershell.exe')
        if not powershell:
            self.skipTest('Windows PowerShell is required for the real .NET regression')
        source = (ROOT / 'tools/android_seal/bridge/inject_sources_resign.ps1').read_text(encoding='utf-8-sig')
        expression = re.search(r'^\$zip = \[System\.IO\.Compression\.ZipFile\]::Open\([^\r\n]+\)$', source, re.MULTILINE)
        self.assertIsNotNone(expression)
        name = 'assets/assets/art/maps/新增/树/owned.png.import'
        payload = b'owned import metadata'
        with tempfile.TemporaryDirectory(prefix='hc_zip_encoding_') as directory:
            archive = pathlib.Path(directory) / 'owned.zip'
            with zipfile.ZipFile(archive, 'w', zipfile.ZIP_STORED) as out:
                out.writestr(name, payload)
            # Godot's observed APK has UTF-8 name bytes without the ZIP EFS bit.
            raw = bytearray(archive.read_bytes())
            self.assertEqual(raw[:4], b'PK\x03\x04')
            central = raw.index(b'PK\x01\x02')
            for offset in (6, central + 8):
                flags = struct.unpack_from('<H', raw, offset)[0]
                struct.pack_into('<H', raw, offset, flags & ~0x800)
            archive.write_bytes(raw)
            script = "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.IO.Compression.FileSystem; "
            script += "$ApkPath='" + str(archive).replace("'", "''") + "'; "
            script += expression.group(0) + "; "
            script += "try { $entry=$zip.CreateEntry('added.txt'); $stream=$entry.Open(); $stream.WriteByte(1); $stream.Dispose() } finally { $zip.Dispose() }"
            encoded = base64.b64encode(script.encode('utf-16-le')).decode('ascii')
            completed = subprocess.run([powershell, '-NoProfile', '-EncodedCommand', encoded],
                                       stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
            self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors='replace'))
            with zipfile.ZipFile(archive, metadata_encoding='utf-8') as result:
                self.assertIn(name, result.namelist(), 'source injection renamed an existing sparse-pack asset')
                self.assertEqual(result.read(name), payload)
                self.assertEqual(result.read('added.txt'), b'\x01')
                self.assertIsNone(result.testzip())


if __name__ == '__main__':
    unittest.main(verbosity=2)
