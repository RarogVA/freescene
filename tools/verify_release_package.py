#!/usr/bin/env python3
"""Verify a signed APP and read-only DMG before publication.

Reads embedded signatures and certificates without opening any Keychain or
launching/modifying the installed application. Writes an ignored JSON report
and SHA256SUMS.txt in the supplied release directory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import posixpath
import re
import stat
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
APP_ID = 'local.freescene.freescene'
HELPER_ID = APP_ID + '.update-helper'
SOURCES_NAME = 'FreeScene-VLC-sources.tar.gz'
SOURCES_SHA256 = '9caa887178b0563aaddfe9d98c243beefe0ff1a829aafc3408f662c0acaff282'
VLC_BINARY_COUNT = 48
VLC_PLUGIN_COUNT = 46
VLC_AUDIT_PATH = ROOT / 'validation/freescene/vlc-distribution-arm64.json'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(*command):
    result = subprocess.run(list(map(str, command)), capture_output=True, check=True)
    return result.stdout, result.stderr


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def designated_requirement(output):
    lines = [line.removeprefix('designated => ').strip()
             for line in output.splitlines() if line.startswith('designated => ')]
    require(len(lines) == 1, 'Missing or ambiguous designated code requirement')
    return lines[0]


def verify_signature(target, requirement, identifier, fingerprint, temporary, name, deep=False):
    command = ['/usr/bin/codesign', '--verify', '--strict']
    if deep:
        command.append('--deep')
    run(*command, target)
    run('/usr/bin/codesign', '--verify', '--strict', '-R', '=' + requirement, target)
    stdout, stderr = run('/usr/bin/codesign', '--display', '-r-', target)
    own_requirement = designated_requirement((stdout + b'\n' + stderr).decode())
    require(own_requirement == requirement, f'{name}: own designated requirement differs from build-result')
    require(f'identifier "{identifier}"' in own_requirement, f'{name}: unexpected code identifier')
    certificate_prefix = temporary / f'{name}-certificate-'
    run('/usr/bin/codesign', '--display', '--extract-certificates=' + str(certificate_prefix), target)
    certificate = Path(str(certificate_prefix) + '0')
    require(certificate.is_file(), f'{name}: embedded signing certificate is missing')
    actual = sha256(certificate)
    require(actual == fingerprint, f'{name}: embedded signing certificate differs from build-result')
    return {'strictIntegrity': True, 'explicitRequirementSatisfied': True,
            'ownDesignatedRequirementPinned': True, 'certificateSHA256': actual}


def safe_zip(path):
    """Check extraction paths before invoking ditto; framework symlinks stay internal."""
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        require(0 < len(entries) < 100000, 'ZIP entry count is invalid')
        require(sum(entry.file_size for entry in entries) < 2 * 1024 ** 3, 'ZIP expands beyond the release limit')
        names, links = set(), {}
        for entry in entries:
            name = entry.filename
            parts = PurePosixPath(name).parts
            require(name and parts and '\\' not in name and '\0' not in name and
                    not name.startswith('/') and '..' not in parts and
                    parts[0] in ('FreeScene.app', '__MACOSX'), 'ZIP contains an unsafe entry path')
            require(name not in names, 'ZIP contains duplicate entry paths')
            names.add(name)
            require(not entry.flag_bits & 1, 'ZIP contains an encrypted entry')
            if stat.S_ISLNK(entry.external_attr >> 16):
                require(parts[0] == 'FreeScene.app' and entry.file_size < 4096,
                        'ZIP contains an unexpected symlink')
                link = archive.read(entry).decode('utf-8')
                require(link and '\\' not in link and '\0' not in link and
                        not link.startswith('/'), 'ZIP symlink target is unsafe')
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), link))
                require(resolved == 'FreeScene.app' or resolved.startswith('FreeScene.app/'),
                        'ZIP symlink leaves the application bundle')
                links[name] = link
        require('FreeScene.app/Contents/Info.plist' in names, 'ZIP lacks the application Info.plist')
        # Validate chains too: lexical checks alone miss a ../ reached through
        # another symlink. Resolve archive names without following host paths.
        for name in names:
            if PurePosixPath(name).parts[0] != 'FreeScene.app':
                continue
            pending, resolved, expansions = name.split('/'), [], 0
            while pending:
                component = pending.pop(0)
                if component in ('', '.'):
                    continue
                if component == '..':
                    require(len(resolved) > 1, 'ZIP symlink chain leaves the application bundle')
                    resolved.pop()
                    continue
                resolved.append(component)
                target = links.get('/'.join(resolved))
                if target is not None:
                    expansions += 1
                    require(expansions <= 64, 'ZIP contains a cyclic symlink chain')
                    resolved.pop()
                    pending = target.split('/') + pending
    return {'safePathsBeforeExtraction': True, 'entries': len(entries)}


def vlc_provenance(bundle):
    directory = bundle / 'Contents/Resources/VLC'
    audit = load_json(directory / 'audit.json')
    architecture = run('/usr/bin/lipo','-archs',bundle/'Contents/MacOS/FreeScene')[0].decode().strip()
    tracked = load_json(VLC_AUDIT_PATH if architecture=='arm64' else ROOT/'validation/freescene/vlc-distribution-x86_64.json')
    modules = load_json(directory / 'modules.json')
    require(audit == tracked and audit.get('passed'), 'Bundled VLC audit differs from the tracked passed audit')
    binaries = audit['binaries']
    paths = {entry['path'] for entry in binaries}
    require(len(binaries) == len(paths) == VLC_BINARY_COUNT,
            f'Expected {VLC_BINARY_COUNT} audited VLC binaries')
    require({str(path.relative_to(directory)) for path in directory.rglob('*.dylib')} == paths,
            'Bundled VLC binary set differs from the audited set')
    require(modules.get('version') == '3.0.21' and modules.get('auditStatus', '').startswith('passed:'),
            'Bundled VLC module provenance is invalid')
    entries = modules.get('modules', [])
    expected = {entry['path']: entry['sourceSHA256'] for entry in binaries
                if entry['path'].startswith('plugins/')}
    actual = {'plugins/' + entry['name']: entry['sourceSha256'] for entry in entries}
    require(len(entries) == len(actual) == VLC_PLUGIN_COUNT and actual == expected,
            f'VLC plugin source provenance differs from the {VLC_PLUGIN_COUNT} audited plugins')
    return {'passed': True, 'auditedUpstreamBinaries': len(paths), 'moduleProvenanceEntries': len(entries),
            'provenanceOnly': True, 'postPackagingBytesComparedToUpstreamHashes': False}, paths


def code_hashes(bundle, vlc_paths):
    relative = ['Contents/MacOS/FreeScene', 'Contents/Helpers/FreeSceneUpdateHelper',
                'Contents/Frameworks/libFreeSceneEngine.dylib',
                'Contents/Frameworks/App.framework/App',
                'Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS']
    relative += ['Contents/Resources/VLC/' + path for path in sorted(vlc_paths)]
    return {name: sha256(bundle / name) for name in relative}


def verify_bundle(bundle, version, build_number, signing, baseline, label, temporary, architecture='arm64'):
    require(bundle.is_dir() and not bundle.is_symlink(), f'{label}: missing real APP bundle')
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == APP_ID, f'{label}: unexpected application identifier')
    require(info.get('CFBundleExecutable') == 'FreeScene', f'{label}: unexpected main executable')
    require(info.get('CFBundleShortVersionString') == version, f'{label}: version mismatch')
    require(str(info.get('CFBundleVersion')) == str(build_number), f'{label}: build number mismatch')
    require(info.get('LSMinimumSystemVersion') == '13.0', f'{label}: minimum macOS must be 13.0')
    executable = bundle / 'Contents/MacOS/FreeScene'
    helper = bundle / 'Contents/Helpers/FreeSceneUpdateHelper'
    for target in (executable, helper):
        require(target.is_file() and not target.is_symlink(), f'{label}: missing real executable')
        actual_architecture = run('/usr/bin/lipo', '-archs', target)[0].decode().strip()
        require(actual_architecture == architecture, f'{label}: executable must be {architecture}')
        metadata = run('/usr/bin/xcrun', 'vtool', '-show-build', target)[0].decode()
        require(re.search(r'^\s*minos\s+13\.0\s*$', metadata, re.MULTILINE),
                f'{label}: executable minimum macOS must be 13.0')
    signatures = {
        'application': verify_signature(bundle, signing['applicationRequirement'], APP_ID,
                                        signing['certificateSHA256'], temporary, label + '-app', deep=True),
        'helper': verify_signature(helper, signing['helperRequirement'], HELPER_ID,
                                   signing['certificateSHA256'], temporary, label + '-helper'),
    }
    provenance, vlc_paths = vlc_provenance(bundle)
    hashes = code_hashes(bundle, vlc_paths)
    require(hashes == baseline, f'{label}: main, helper or native libraries differ from the signed build')
    for target in (bundle/'Contents/Frameworks/App.framework/App', bundle/'Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS'):
        require(architecture in run('/usr/bin/lipo','-archs',target)[0].decode().split(), f'{label}: Flutter framework lacks {architecture}')
    return {'passed': True, 'version': version, 'build': str(build_number), 'architecture': architecture,
            'minimumMacOS': info['LSMinimumSystemVersion'], 'signatures': signatures,
            'helperMinimumMacOS': '13.0', 'mainHelperAndNativeLibrariesMatchSource': True,
            'nativeLibrariesCompared': len(vlc_paths) + 1,
            'flutterFrameworksAlsoMatchSource': True, 'vlc': provenance}


def verify_release(release, version, build_number):
    release = release.resolve()
    require(release.is_dir(), 'Release directory is missing')
    report = load_json(release / 'build-result.json')
    architecture=report.get('architecture')
    require(architecture in ('arm64','x86_64'), 'Unsupported release architecture')
    native_root=ROOT/('build/native' if architecture=='arm64' else 'build/native-x86_64')
    require(report.get('passed') and report.get('channel') == 'stable' and report.get('version') == version,
            'build-result.json does not describe the requested stable version')
    signing = report.get('signing', {})
    require(signing.get('kind') == 'persistent-self-signed' and
            re.fullmatch(r'[0-9a-f]{64}', signing.get('certificateSHA256', '')),
            'build-result.json lacks persistent signing provenance')
    source = ROOT / 'build/macos/Build/Products/Release/FreeScene.app'
    bundle = release / 'FreeScene.app'
    require(not list(release.glob('FreeScene-*-macos-*.zip')),
            'macOS releases must contain DMG packages only; remove legacy application ZIPs')
    image = release / f'FreeScene-{version}-macos-{architecture}.dmg'
    companion = release / SOURCES_NAME
    require(companion.is_file() and sha256(companion) == SOURCES_SHA256,
            'Release directory needs the verified VLC source companion')
    _, vlc_paths = vlc_provenance(source)
    baseline = code_hashes(source, vlc_paths)
    # Compare relocated/ad-hoc-signed native build artifacts, not upstream bytes:
    # install_name_tool and codesign intentionally change those upstream bytes.
    native_libraries = {
        'Contents/Frameworks/libFreeSceneEngine.dylib': native_root/'libFreeSceneEngine.dylib',
        **{'Contents/Resources/VLC/' + path: native_root/'vlc'/path for path in vlc_paths},
    }
    for relative, native in native_libraries.items():
        require(sha256(native) == baseline[relative], 'Signed build differs from native build artifact: ' + relative)
        require(run('/usr/bin/lipo', '-archs', native)[0].decode().strip() == architecture,
                f'Native library must be {architecture}: ' + relative)
    verification = {'passed': True, 'version': version, 'buildNumber': str(build_number),
                    'build': report, 'nativeLibrariesCompared': len(native_libraries),
                    'nativeBuildArtifactsMatchSignedBuild': True,
                    'signedBuildCodeSHA256': baseline}
    with tempfile.TemporaryDirectory(prefix='release-verification-', dir=release) as directory:
        temporary = Path(directory)
        verification['sourceBundleCheck'] = verify_bundle(source, version, build_number, signing, baseline, 'source', temporary, architecture)
        verification['releaseBundleCheck'] = verify_bundle(bundle, version, build_number, signing, baseline, 'release', temporary, architecture)
        run('/usr/bin/hdiutil', 'verify', image)
        mount = temporary / 'mount'
        mount.mkdir()
        attached = False
        try:
            output, _ = run('/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
                            '-plist', '-mountpoint', mount, image)
            attached = True
            mounted = plistlib.loads(output)
            require(any(entity.get('mount-point') == str(mount) for entity in mounted['system-entities']),
                    'DMG did not mount at the isolated verification directory')
            require(os.statvfs(mount).f_flag & os.ST_RDONLY, 'DMG volume is not read-only')
            link = mount / 'Applications'
            require(link.is_symlink() and os.readlink(link) == '/Applications', 'DMG Applications link is invalid')
            repair = mount / 'Исправить запуск.command'
            require(repair.is_file() and not repair.is_symlink() and
                    repair.read_bytes() == (ROOT/'tools/fix_macos_launch.command').read_bytes(),
                    'DMG launch-repair script is missing or differs from the source')
            require(repair.stat().st_mode & 0o111, 'DMG launch-repair script must be executable')
            installation = (mount / 'Установка.txt').read_text(encoding='utf-8')
            platform='Apple Silicon' if architecture=='arm64' else 'Intel x86_64'
            require(f'FreeScene {version} — macOS 13+, {platform}' in installation and 'Preview' not in installation,
                    'DMG installation text does not describe the requested stable version')
            verification['dmgCheck'] = {
                **verify_bundle(mount / 'FreeScene.app', version, build_number, signing, baseline, 'dmg', temporary, architecture),
                'readOnlyMount': True, 'applicationsLink': True, 'stableInstallationText': True,
                'launchRepairScriptVerified': True,
                'diskImageVerification': 'hdiutil verify passed',
            }
        finally:
            if attached or os.path.ismount(mount):
                run('/usr/bin/hdiutil', 'detach', mount)
    assets = [image, companion]
    hashes = {path.name: sha256(path) for path in assets}
    checksums = release / 'SHA256SUMS.txt'
    checksums.write_text(''.join(f'{digest}  {name}\n' for name, digest in hashes.items()), encoding='utf-8')
    hashes[checksums.name] = sha256(checksums)
    verification.update(assets=hashes, assetSizes={path.name: path.stat().st_size for path in [*assets, checksums]},
                        signature='Persistent self-signed certificate; no Developer ID or Apple notarization.',
                        installedApplicationModified=False,
                        keychainAccessed=False,
                        provenanceLimitation='Bundled passed audit/provenance checked; the upstream VLC audit was not rerun.')
    return verification


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-dir', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build-number', required=True)
    args = parser.parse_args()
    require(re.fullmatch(r'\d+\.\d+\.\d+', args.version), 'Version must be a three-part stable version')
    require(re.fullmatch(r'\d+', args.build_number), 'Build number must be numeric')
    result = verify_release(args.release_dir, args.version, args.build_number)
    output = args.release_dir / 'package-verification.json'
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'passed': True, 'report': str(output.resolve()),
                      'assets': result['assets'], 'nativeLibrariesCompared': result['nativeLibrariesCompared']}))


if __name__ == '__main__':
    main()
