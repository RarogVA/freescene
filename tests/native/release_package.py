"""Exercise release-verifier extraction guards without macOS UI or Keychain."""
import sys
from pathlib import Path
import stat
import tempfile
import unittest
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import verify_release_package as verifier
from release_assets import check_images, dmg_names, finalize


class PackageGuardTests(unittest.TestCase):
    def test_transition_and_final_download_sets(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            legacy = directory / 'FreeScene-2.0.4-macos-arm64.dmg'
            legacy.write_bytes(b'arm64')
            self.assertEqual(check_images(directory, '2.0.4', ['arm64']), [legacy])
            stable = directory / 'FreeScene-macos-arm64.dmg'
            stable.write_bytes(b'arm64')
            self.assertEqual(check_images(directory, '2.0.4', ['arm64']), [legacy, stable])
            legacy.unlink()
            for arch in ('arm64', 'x86_64'):
                for name in dmg_names('2.0.5', arch):
                    (directory / name).write_bytes(arch.encode())
            self.assertEqual(len(check_images(directory, '2.0.5', ('arm64', 'x86_64'))), 4)
            (directory / 'FreeScene-2.0.5-macos-arm64.dmg').write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'identical'):
                check_images(directory, '2.0.5', ('arm64', 'x86_64'))
            with self.assertRaisesRegex(ValueError, 'Unexpected'):
                check_images(directory, '2.0.6', ('arm64', 'x86_64'))
            for alias in directory.glob('FreeScene-2.0.5-*.dmg'):
                alias.unlink()
            finalize(directory, '2.0.6')
            self.assertEqual(len((directory / 'SHA256SUMS.txt').read_text().splitlines()), 2)

    def archive(self, entries):
        temporary = tempfile.TemporaryDirectory(prefix='freescene-release-package-test-')
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / 'fixture.zip'
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('FreeScene.app/Contents/Info.plist', b'fixture')
                for name, target in entries:
                    entry = zipfile.ZipInfo(name)
                    entry.create_system = 3
                    entry.external_attr = ((stat.S_IFLNK | 0o777) if target is not None else
                                           (stat.S_IFREG | 0o644)) << 16
                    archive.writestr(entry, target.encode() if target is not None else b'fixture')
        return path

    def test_internal_framework_chain_and_resource_fork_are_allowed(self):
        path = self.archive([
            ('FreeScene.app/Contents/Frameworks/F.framework/Versions/Current', 'A'),
            ('FreeScene.app/Contents/Frameworks/F.framework/F', 'Versions/Current/F'),
            ('FreeScene.app/Contents/Frameworks/F.framework/Versions/A/F', None),
            ('__MACOSX/FreeScene.app/Contents/._Info.plist', None),
        ])
        self.assertTrue(verifier.safe_zip(path)['safePathsBeforeExtraction'])

    def test_unsafe_entry_paths_are_rejected(self):
        for name in ('/tmp/escaped', '../escaped', 'FreeScene.app/../../escaped',
                     'FreeScene.app\\escaped', 'Another.app/Contents/file', '.'):
            with self.subTest(name=name), self.assertRaises(RuntimeError):
                verifier.safe_zip(self.archive([(name, None)]))

    def test_duplicate_paths_are_rejected(self):
        path = self.archive([('FreeScene.app/Contents/Info.plist', None)])
        with self.assertRaisesRegex(RuntimeError, 'duplicate'):
            verifier.safe_zip(path)

    def test_direct_escape_symlink_is_rejected(self):
        for target in ('/Applications', '../../escaped'):
            with self.subTest(target=target), self.assertRaises(RuntimeError):
                verifier.safe_zip(self.archive([('FreeScene.app/link', target)]))

    def test_lexically_internal_chain_cannot_escape_bundle(self):
        path = self.archive([
            ('FreeScene.app/Contents/Deep/a', '../../X'),
            ('FreeScene.app/Contents/Deep/b', 'a/../../escaped'),
        ])
        with self.assertRaisesRegex(RuntimeError, 'chain leaves'):
            verifier.safe_zip(path)

    def test_cyclic_symlink_is_rejected(self):
        path = self.archive([('FreeScene.app/a', 'b'), ('FreeScene.app/b', 'a')])
        with self.assertRaisesRegex(RuntimeError, 'cyclic'):
            verifier.safe_zip(path)

    def test_exact_designated_requirement_is_required(self):
        requirement = 'identifier "local.freescene.freescene" and certificate leaf = H"1234"'
        self.assertEqual(verifier.designated_requirement('Executable=fixture\ndesignated => ' + requirement), requirement)
        with self.assertRaises(RuntimeError):
            verifier.designated_requirement('Executable=fixture')
        with self.assertRaises(RuntimeError):
            verifier.designated_requirement('designated => first\ndesignated => second')


if __name__ == '__main__':
    unittest.main()
