#!/usr/bin/env python3
"""Persistent, certificate-pinned signing without changing macOS trust settings."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_IDENTITY_DIR = Path.home() / 'Library/Application Support/FreeScene Signing'
APP_IDENTIFIER = 'local.freescene.freescene'
HELPER_IDENTIFIER = APP_IDENTIFIER + '.update-helper'
CERTIFICATE_FILE = 'certificate.der'
PASSWORD_FILE = 'keychain-password'
METADATA_FILE = 'identity.json'
KEYCHAIN_NAME = 'signing.keychain'


class SigningError(RuntimeError):
    """A sanitized signing failure that never contains command passwords."""


def _run(command: list, *, input_text: str | None = None, environment: dict | None = None) -> str:
    try:
        process = subprocess.run(
            list(map(str, command)), input=input_text, text=True,
            capture_output=True, timeout=90, env=environment, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SigningError(f'{Path(str(command[0])).name} could not complete') from None
    if process.returncode:
        # Do not interpolate argv, stdin, environment or subprocess diagnostics:
        # they may include signing credentials from future tool versions.
        raise SigningError(f'{Path(str(command[0])).name} failed (exit {process.returncode})')
    return process.stdout.strip()


def _private_directory(path: Path, *, create: bool = False) -> Path:
    path = path.expanduser().absolute()
    if create:
        try:
            path.mkdir(mode=0o700, parents=False)
        except FileExistsError:
            pass
        except OSError:
            raise SigningError('Signing identity directory could not be created') from None
    try:
        value = path.lstat()
    except FileNotFoundError:
        raise SigningError('Signing identity is missing; run the explicit prepare command first') from None
    if not stat.S_ISDIR(value.st_mode) or value.st_uid != os.getuid() or stat.S_IMODE(value.st_mode) != 0o700:
        raise SigningError('Signing directory must be an owned real directory with mode 0700')
    return path


def _private_file(path: Path) -> None:
    try:
        value = path.lstat()
    except FileNotFoundError:
        raise SigningError('Signing identity is incomplete; existing identities are never regenerated automatically') from None
    if not stat.S_ISREG(value.st_mode) or value.st_uid != os.getuid() or stat.S_IMODE(value.st_mode) != 0o600:
        raise SigningError('Signing files must be owned regular files with mode 0600, without symlinks')


def _write_private(path: Path, data: bytes) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(data)


@contextmanager
def _keychain_helper():
    source = ROOT / 'tools/signing_keychain.m'
    parent = ROOT / 'build'
    parent.mkdir(exist_ok=True)
    # Never execute a reusable ignored-build artifact with a password on stdin:
    # compile each invocation into a fresh private directory instead.
    with tempfile.TemporaryDirectory(prefix='signing-tool-', dir=parent) as temporary:
        temporary = Path(temporary)
        os.chmod(temporary, 0o700)
        binary = temporary / 'keychain-admin'
        _run(['xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations',
              '-framework', 'Foundation', '-framework', 'Security', source, '-o', binary])
        os.chmod(binary, 0o700)
        yield binary


def _keychain(request: dict) -> dict:
    with _keychain_helper() as helper:
        raw = _run([helper], input_text=json.dumps(request))
    try:
        result = json.loads(raw)
    except (TypeError, ValueError):
        raise SigningError('Signing Keychain returned an invalid result') from None
    if (not isinstance(result, dict) or result.get('status') != 0
            or not result.get('searchListUnchanged') or not result.get('defaultUnchanged')):
        raise SigningError('Signing Keychain operation did not preserve its isolation')
    return result


def prepare_identity(directory: Path = DEFAULT_IDENTITY_DIR) -> dict:
    """Create one explicit identity; never overwrite or rotate an existing one."""
    directory = _private_directory(directory, create=True)
    if any(directory.iterdir()):
        raise SigningError('Signing directory already contains an identity or partial state; it was left unchanged')
    password = secrets.token_urlsafe(48)
    _write_private(directory / PASSWORD_FILE, (password + '\n').encode())
    try:
        # The temporary PEM/P12 never leave this private directory, and are
        # removed on success or failure. The imported Keychain is the only
        # lasting private-key container.
        with tempfile.TemporaryDirectory(prefix='preparing-', dir=directory) as temporary:
            temporary = Path(temporary)
            os.chmod(temporary, 0o700)
            pem, key, archive, certificate = (temporary / name for name in ('certificate.pem', 'private.key', 'identity.p12', CERTIFICATE_FILE))
            environment = dict(os.environ)
            environment['FREESCENE_SIGNING_ARCHIVE_PASSWORD'] = password
            previous_mask = os.umask(0o077)
            try:
                _run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-sha256',
                      '-keyout', key, '-out', pem, '-days', '3650', '-nodes',
                      '-subj', '/CN=FreeScene Local Code Signing',
                      '-addext', 'extendedKeyUsage=codeSigning', '-addext', 'keyUsage=digitalSignature'])
                _run(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', key, '-in', pem,
                      '-out', archive, '-passout', 'env:FREESCENE_SIGNING_ARCHIVE_PASSWORD'], environment=environment)
                _run(['/usr/bin/openssl', 'x509', '-in', pem, '-outform', 'der', '-out', certificate])
            finally:
                os.umask(previous_mask)
            public_certificate = certificate.read_bytes()
            created = _keychain({'operation': 'create', 'keychain': str(directory / KEYCHAIN_NAME),
                                 'password': password, 'pkcs12': str(archive), 'archivePassword': password})
            keychain = Path(created['keychain'])
            if keychain.parent != directory or keychain.name not in (KEYCHAIN_NAME, KEYCHAIN_NAME + '-db'):
                raise SigningError('Unexpected private signing Keychain location')
            os.chmod(keychain, 0o600)
            _write_private(directory / CERTIFICATE_FILE, public_certificate)
            metadata = {'format': 1, 'kind': 'persistent-self-signed',
                        'keychainFile': keychain.name, 'certificateFile': CERTIFICATE_FILE,
                        'certificateSHA1': hashlib.sha1(public_certificate).hexdigest(),
                        'certificateSHA256': hashlib.sha256(public_certificate).hexdigest(),
                        'applicationIdentifier': APP_IDENTIFIER, 'helperIdentifier': HELPER_IDENTIFIER}
            _write_private(directory / METADATA_FILE, (json.dumps(metadata, indent=2) + '\n').encode())
    except SigningError:
        raise
    except (OSError, ValueError, KeyError):
        raise SigningError('Signing identity preparation failed; partial state was preserved for explicit recovery') from None
    return load_identity(directory)


def load_identity(directory: Path = DEFAULT_IDENTITY_DIR) -> dict:
    directory = _private_directory(directory)
    for name in (PASSWORD_FILE, METADATA_FILE, CERTIFICATE_FILE):
        _private_file(directory / name)
    try:
        metadata = json.loads((directory / METADATA_FILE).read_text())
    except (OSError, ValueError):
        raise SigningError('Signing identity metadata is invalid') from None
    if (not isinstance(metadata, dict) or metadata.get('format') != 1 or metadata.get('kind') != 'persistent-self-signed'
            or metadata.get('keychainFile') not in (KEYCHAIN_NAME, KEYCHAIN_NAME + '-db')
            or metadata.get('certificateFile') != CERTIFICATE_FILE
            or metadata.get('applicationIdentifier') != APP_IDENTIFIER
            or metadata.get('helperIdentifier') != HELPER_IDENTIFIER):
        raise SigningError('Signing identity metadata is not supported')
    keychain = directory / metadata['keychainFile']
    _private_file(keychain)
    certificate = (directory / CERTIFICATE_FILE).read_bytes()
    if (hashlib.sha1(certificate).hexdigest() != metadata.get('certificateSHA1')
            or hashlib.sha256(certificate).hexdigest() != metadata.get('certificateSHA256')):
        raise SigningError('Signing certificate fingerprint does not match its metadata')
    if not re.fullmatch(r'[0-9a-f]{40}', metadata['certificateSHA1']):
        raise SigningError('Signing certificate fingerprint is invalid')
    password = (directory / PASSWORD_FILE).read_text().strip()
    if not 32 <= len(password) <= 256:
        raise SigningError('Signing Keychain password file is invalid')
    # These private values stay in memory and never enter build-result.json.
    return {**metadata, '_directory': directory, '_keychain': keychain, '_password': password}


def validate_identity(identity: dict) -> None:
    _keychain({'operation': 'check', 'keychain': str(identity['_keychain']),
               'password': identity['_password'], 'certificateSHA256': identity['certificateSHA256']})
    _run(['/usr/bin/openssl', 'x509', '-inform', 'der', '-in',
          identity['_directory'] / CERTIFICATE_FILE, '-noout', '-checkend', '0'])


def requirement(identity: dict, identifier: str) -> str:
    if identifier not in (APP_IDENTIFIER, HELPER_IDENTIFIER):
        raise SigningError('Unexpected FreeScene code identifier')
    return f'identifier "{identifier}" and certificate leaf = H"{identity["certificateSHA1"]}"'


def public_metadata(identity: dict) -> dict:
    return {'kind': 'persistent-self-signed', 'certificateSHA256': identity['certificateSHA256'],
            'applicationRequirement': requirement(identity, APP_IDENTIFIER),
            'helperRequirement': requirement(identity, HELPER_IDENTIFIER),
            'developerID': False, 'notarized': False}


def sign_bundle(bundle: Path, directory: Path = DEFAULT_IDENTITY_DIR) -> dict:
    identity = load_identity(directory)
    bundle = bundle.absolute()
    if bundle.is_symlink() or not bundle.is_dir() or bundle.suffix != '.app':
        raise SigningError('Signing target must be a real .app bundle')
    try:
        import plistlib
        info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    except (OSError, ValueError):
        raise SigningError('Signing target Info.plist is invalid') from None
    if info.get('CFBundleIdentifier') != APP_IDENTIFIER:
        raise SigningError('Signing target is not the FreeScene application')
    for relative in ('Contents', 'Contents/Helpers', 'Contents/MacOS', 'Contents/Info.plist'):
        if (bundle / relative).is_symlink():
            raise SigningError('Signing target contains a symlinked code ancestor')
    executable_name = info.get('CFBundleExecutable')
    if (not isinstance(executable_name, str) or not executable_name
            or Path(executable_name).name != executable_name
            or (bundle / 'Contents/MacOS' / executable_name).is_symlink()
            or not (bundle / 'Contents/MacOS' / executable_name).is_file()):
        raise SigningError('Signing target main executable is invalid')
    helper = bundle / 'Contents/Helpers/FreeSceneUpdateHelper'
    if helper.is_symlink() or not helper.is_file():
        raise SigningError('The update helper is missing or is a symlink')
    validate_identity(identity)
    for target, identifier in ((helper, HELPER_IDENTIFIER), (bundle, APP_IDENTIFIER)):
        code_requirement = requirement(identity, identifier)
        _run(['/usr/bin/codesign', '--force', '--sign', identity['certificateSHA1'],
              '--keychain', identity['_keychain'], '--timestamp=none', '--identifier', identifier,
              '--requirements', '=designated => ' + code_requirement,
              '--preserve-metadata=entitlements,flags,runtime', target])
        _run(['/usr/bin/codesign', '--verify', '--strict', target])
        # --verify alone can succeed even for an unsatisfied explicit DR.
        _run(['/usr/bin/codesign', '--verify', '--strict', '-R', '=' + code_requirement, target])
    _run(['/usr/bin/codesign', '--verify', '--deep', '--strict', bundle])
    return public_metadata(identity)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['prepare', 'describe', 'sign'])
    parser.add_argument('--identity-dir', type=Path, default=DEFAULT_IDENTITY_DIR)
    parser.add_argument('--bundle', type=Path)
    args = parser.parse_args()
    try:
        if args.operation == 'prepare':
            result = {'prepared': True, **public_metadata(prepare_identity(args.identity_dir))}
        elif args.operation == 'describe':
            result = public_metadata(load_identity(args.identity_dir))
        else:
            if not args.bundle:
                parser.error('sign requires --bundle')
            result = sign_bundle(args.bundle, args.identity_dir)
    except SigningError as error:
        parser.exit(1, f'{error}\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
