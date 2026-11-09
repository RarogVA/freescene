"""Real signing/Keychain regression using only disposable private fixtures."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import sign_freescene as signing

OUTPUT = ROOT / 'build/signing-regression'
OUTPUT.mkdir(parents=True, exist_ok=True)
checks = []


def run(*command, input_text=None):
    return signing._run(list(command), input_text=input_text)


def expect_rejected(name, action):
    try:
        action()
    except signing.SigningError:
        checks.append(name)
    else:
        raise AssertionError(name)


def fixture_bundle(folder: Path, version: int) -> Path:
    bundle = folder / f'Version-{version}.app'
    (bundle / 'Contents/MacOS').mkdir(parents=True)
    (bundle / 'Contents/Helpers').mkdir()
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': signing.APP_IDENTIFIER, 'CFBundleName': 'FreeScene Signing Fixture',
        'CFBundleExecutable': 'FreeScene', 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': str(version), 'CFBundleShortVersionString': f'1.0.{version}',
        'LSMinimumSystemVersion': '13.0',
    }))
    for relative in ('Contents/MacOS/FreeScene', 'Contents/Helpers/FreeSceneUpdateHelper'):
        run('xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-arch', 'arm64',
            '-mmacosx-version-min=13.0', f'-DPROBE_VERSION={version}',
            '-framework', 'Foundation', '-framework', 'Security',
            ROOT / 'tests/native/signing_probe.m', '-o', bundle / relative)
        run('/usr/bin/codesign', '--force', '--sign', '-', '--options', 'kill',
            '--entitlements', folder / 'entitlements.plist', bundle / relative)
    run('/usr/bin/codesign', '--force', '--sign', '-', '--options', 'kill',
        '--entitlements', folder / 'entitlements.plist', bundle)
    return bundle


def metadata(target):
    flags = subprocess.run(['/usr/bin/codesign', '-dvvv', str(target)], capture_output=True, text=True, check=True).stderr
    entitlements = subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(target)], capture_output=True, check=True).stdout
    # Signature kind changes from ad hoc to a certificate; retain all policy flags.
    return int(re.search(r'flags=(0x[0-9a-f]+)', flags).group(1), 16) & ~0x2, plistlib.loads(entitlements)


def main():
    before = signing._keychain({'operation': 'state'})
    public = None
    with tempfile.TemporaryDirectory(prefix='freescene-signing-regression-', dir=OUTPUT) as temporary:
        folder = Path(temporary)
        os.chmod(folder, 0o700)
        (folder / 'entitlements.plist').write_bytes(plistlib.dumps({'com.apple.security.cs.allow-jit': True}))
        first = signing.prepare_identity(folder / 'identity-a')
        second = signing.prepare_identity(folder / 'identity-b')
        signing.validate_identity(first)
        expect_rejected('prepare_never_rotates_existing_identity', lambda: signing.prepare_identity(folder / 'identity-a'))
        expect_rejected('missing_identity_fails_closed', lambda: signing.load_identity(folder / 'missing'))
        public = signing.public_metadata(first)
        assert first['certificateSHA256'] != second['certificateSHA256']
        a1, a2, b = [fixture_bundle(folder, version) for version in (1, 2, 3)]
        prior_metadata = metadata(a1)
        signing.sign_bundle(a1, folder / 'identity-a')
        signing.sign_bundle(a2, folder / 'identity-a')
        signing.sign_bundle(b, folder / 'identity-b')
        assert metadata(a1) == prior_metadata
        checks.append('entitlements_and_code_flags_preserved')
        one, two = a1 / 'Contents/MacOS/FreeScene', a2 / 'Contents/MacOS/FreeScene'
        assert hashlib.sha256(one.read_bytes()).digest() != hashlib.sha256(two.read_bytes()).digest()
        for app in (a1, a2):
            run('/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', '=' + signing.requirement(first, signing.APP_IDENTIFIER), app)
        checks.append('different_versions_satisfy_same_certificate_and_identifier_requirement')
        read_request = {'operation': 'read', 'keychain': str(first['_keychain']), 'password': first['_password']}
        write = dict(read_request, operation='write')
        assert json.loads(run(one, input_text=json.dumps(write)))['status'] == 0
        assert json.loads(run(two, input_text=json.dumps(read_request)))['matched']
        checks.append('default_keychain_acl_persists_across_version_update')
        assert not json.loads(run(b / 'Contents/MacOS/FreeScene', input_text=json.dumps(read_request)))['matched']
        assert not json.loads(run(a2 / 'Contents/Helpers/FreeSceneUpdateHelper', input_text=json.dumps(read_request)))['matched']
        assert json.loads(run(two, input_text=json.dumps(read_request)))['matched']
        checks.extend(['other_certificate_cannot_read_item', 'same_certificate_helper_identifier_cannot_read_item', 'rejected_access_preserves_item'])

        validator = OUTPUT / 'signer-validation'
        run('xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-Wno-unused-function',
            '-framework', 'Cocoa', '-framework', 'Security',
            ROOT / 'tests/native/signing_update_validation.m', '-o', validator)
        def accepted(candidate, reference):
            return json.loads(run(validator, candidate, reference))['valid']
        assert accepted(a2, a1)
        assert not accepted(b, a1)
        adhoc = folder / 'Adhoc.app'
        shutil.copytree(a2, adhoc, symlinks=True)
        run('/usr/bin/codesign', '--force', '--sign', '-', '--identifier', signing.APP_IDENTIFIER, adhoc)
        assert not accepted(adhoc, a1)
        assert accepted(a2, adhoc)
        invalid = folder / 'Unsatisfiable.app'
        shutil.copytree(a2, invalid, symlinks=True)
        run('/usr/bin/codesign', '--force', '--sign', first['certificateSHA1'], '--keychain', first['_keychain'],
            '--timestamp=none', '--identifier', signing.APP_IDENTIFIER,
            '--requirements', '=designated => identifier "wrong.identifier" and certificate leaf = H"' + first['certificateSHA1'] + '"', invalid)
        assert not accepted(invalid, adhoc)
        checks.extend(['updater_accepts_same_signer', 'updater_rejects_other_certificate',
                       'updater_rejects_adhoc_downgrade', 'updater_allows_adhoc_to_signed_migration',
                       'updater_rejects_unsatisfiable_own_requirement'])
        # A symlinked helper directory must not authorize signing external code.
        escaped = folder / 'Escaped.app'
        shutil.copytree(a2, escaped)
        external = folder / 'external-helpers'
        (escaped / 'Contents/Helpers').rename(external)
        (escaped / 'Contents/Helpers').symlink_to(external, target_is_directory=True)
        unchanged = hashlib.sha256((external / 'FreeSceneUpdateHelper').read_bytes()).hexdigest()
        expect_rejected('symlinked_helper_ancestor_rejected', lambda: signing.sign_bundle(escaped, folder / 'identity-a'))
        assert hashlib.sha256((external / 'FreeSceneUpdateHelper').read_bytes()).hexdigest() == unchanged
        metadata_path = folder / 'identity-a/identity.json'
        original_metadata = metadata_path.read_bytes()
        metadata_path.write_text('[]')
        expect_rejected('invalid_metadata_type_rejected', lambda: signing.load_identity(folder / 'identity-a'))
        metadata_path.write_bytes(original_metadata)
        password_file = folder / 'identity-a/keychain-password'
        os.chmod(password_file, 0o644)
        expect_rejected('unsafe_password_permissions_rejected', lambda: signing.load_identity(folder / 'identity-a'))
        os.chmod(password_file, 0o600)
        try:
            signing._run(['/usr/bin/false', 'unrelated-sanitization-sentinel'], input_text=first['_password'])
        except signing.SigningError as error:
            assert first['_password'] not in str(error)
        else:
            raise AssertionError('Expected a sanitized subprocess failure')
        checks.append('subprocess_failure_does_not_expose_password')
        for identity_dir in (folder / 'identity-a', folder / 'identity-b'):
            assert identity_dir.stat().st_mode & 0o777 == 0o700
            identity = signing.load_identity(identity_dir)
            data_files = {signing.PASSWORD_FILE, signing.METADATA_FILE, signing.CERTIFICATE_FILE, identity['_keychain'].name}
            for path in identity_dir.iterdir():
                mode = path.lstat()
                assert stat.S_ISREG(mode.st_mode) and mode.st_uid == os.getuid()
                if path.name in data_files:
                    assert stat.S_IMODE(mode.st_mode) == 0o600
                else:
                    # Security.framework owns a read-only .fl* lock marker.
                    # It contains no signing material and lives inside 0700.
                    assert path.name.startswith('.fl') and not mode.st_mode & 0o222
        checks.append('persistent_identity_files_are_private')
    after = signing._keychain({'operation': 'state'})
    assert before['searchList'] == after['searchList'] and before['default'] == after['default']
    checks.append('global_keychain_search_list_and_default_unchanged')
    report = {'passed': True, 'checks': checks, 'count': len(checks), 'signing': public,
              'privateKeychainsOnly': True, 'userKeychainItemsAccessed': False,
              'systemTrustChanged': False, 'installedApplicationModified': False}
    (OUTPUT / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
