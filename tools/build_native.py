#!/usr/bin/env python3
"""Build the pinned torrent engine and bundle an explicit VLC 3.0.21 module set."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build/native'
# Decoder, demux, audio/video output and converters only. No interfaces,
# encoders, network discovery, Lua, access-output or stream-output modules.
MODULES = '''filesystem http https securetransport mp4 mkv avi ts avcodec videotoolbox
vout_macosx caopengllayer auhal audio_format float_mixer integer_mixer
trivial_channel_mixer simple_channel_mixer ugly_resampler speex_resampler glconv_cvpx
swscale i420_rgb i420_yuy2 i422_i420 yuy2_i420 i420_nv12 i420_10_p010
packetizer_h264 packetizer_hevc packetizer_mpeg4audio packetizer_mpeg4video
packetizer_mpegvideo packetizer_mpegaudio packetizer_a52 packetizer_dts
packetizer_flac packetizer_copy subsdec subtitle substx3g freetype
cache_read cache_block vdummy adummy'''.split()

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)

def main():
    global BUILD
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--arch', choices=['arm64','x86_64'], default=os.environ.get('FREESCENE_ARCH','arm64'))
    p.add_argument('--bundle', type=Path)
    p.add_argument('--vlc', type=Path, default=Path(os.environ.get('FREESCENE_VLC_PATH','/Applications/VLC.app')))
    p.add_argument('--allow-modified-vlc', action='store_true',
                   help='Use a locally modified VLC; do not claim the upstream distribution audit')
    args = p.parse_args()
    BUILD=ROOT/('build/native' if args.arch=='arm64' else 'build/native-x86_64')
    openssl=ROOT/('build/openssl' if args.arch=='arm64' else 'build/openssl-x86_64')
    env = dict(os.environ)
    env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    run(sys.executable, ROOT/'tools/build_openssl.py', '--arch', args.arch)
    cached_torrent=ROOT/'build/dependencies/libtorrent'
    source_args=[]
    if (cached_torrent/'.git').exists():
        revision=run('git','-C',cached_torrent,'rev-parse','HEAD',capture_output=True,text=True).stdout.strip()
        if revision!='6da363d2994f17c0b3c0450d124cf73a31a73847':
            raise RuntimeError('Unexpected cached libtorrent revision')
        source_args=[f'-DFETCHCONTENT_SOURCE_DIR_LIBTORRENT={cached_torrent}']
    run('/opt/homebrew/bin/cmake', '-S', ROOT/'native', '-B', BUILD, *source_args,
        '-DCMAKE_BUILD_TYPE=Release', f'-DCMAKE_OSX_ARCHITECTURES={args.arch}',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0', '-DCMAKE_PREFIX_PATH=/opt/homebrew',
        f'-DOPENSSL_ROOT_DIR={openssl}',
        f'-DOPENSSL_INCLUDE_DIR={openssl}/include',
        f'-DOPENSSL_CRYPTO_LIBRARY={openssl}/lib/libcrypto.a',
        f'-DOPENSSL_SSL_LIBRARY={openssl}/lib/libssl.a', env=env)
    run('/opt/homebrew/bin/cmake', '--build', BUILD, '-j', '6', env=env)
    update_helper = BUILD/'FreeSceneUpdateHelper'
    run('xcrun', 'clang', '-fobjc-arc', '-mmacosx-version-min=13.0',
        '-arch', args.arch, '-framework', 'Cocoa', '-framework', 'Security',
        ROOT/'macos/Native/FSUpdateHelper.m', '-o', update_helper, env=env)
    run('codesign', '--force', '--sign', '-', update_helper,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    original = args.vlc / 'Contents/MacOS'
    version = plistlib.loads((args.vlc/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    if version != '3.0.21':
        raise RuntimeError(f'Expected audited VLC 3.0.21, found {version}')
    destination = BUILD/'vlc'
    if (destination/'plugins').exists(): shutil.rmtree(destination/'plugins')
    (destination/'lib').mkdir(parents=True, exist_ok=True)
    (destination/'plugins').mkdir(parents=True, exist_ok=True)
    shutil.copytree(original/'include', BUILD/'include', dirs_exist_ok=True)
    manifest = {'version': version, 'auditStatus': 'module source headers reviewed; complete static contribution source packaging pending before public distribution', 'source': 'https://download.videolan.org/pub/videolan/vlc/3.0.21/vlc-3.0.21.tar.xz', 'modules': []}
    (destination/'audit.json').unlink(missing_ok=True)
    audit_file = ROOT/('validation/freescene/vlc-distribution-arm64.json' if args.arch=='arm64' else 'validation/freescene/vlc-distribution-x86_64.json')
    if not audit_file.exists() and not args.allow_modified_vlc:
        raise RuntimeError('Missing VLC distribution audit for the selected module set')
    if audit_file.exists() and not args.allow_modified_vlc:
        audit = json.loads(audit_file.read_text())
        expected_paths = {'lib/libvlc.dylib', 'lib/libvlccore.dylib'} | {
            f'plugins/lib{name}_plugin.dylib' for name in MODULES}
        if not audit.get('passed') or {entry['path'] for entry in audit['binaries']} != expected_paths:
            raise RuntimeError('VLC distribution audit does not match the module set')
        for entry in audit['binaries']:
            if hashlib.sha256((original/entry['path']).read_bytes()).hexdigest() != entry['sourceSHA256']:
                raise RuntimeError('VLC binary differs from audited upstream: '+entry['path'])
        manifest.update(auditStatus='passed: official upstream bytes, static contrib closure and source/notice package',
                        staticDependencies=audit['staticDependencies'], sourceCompanion=audit['sourceCompanion'])
        shutil.copy2(audit_file, destination/'audit.json')
    for name in ['libvlc.dylib', 'libvlccore.dylib']:
        target=destination/'lib'/name
        shutil.copy2(original/'lib'/name,target)
        if run('lipo','-archs',target,capture_output=True,text=True).stdout.strip()!=args.arch:
            raise RuntimeError(f'Unexpected VLC architecture: {target.name}')
        rpaths=run('otool','-l',target,capture_output=True,text=True).stdout
        if 'path @loader_path ' not in rpaths:
            run('install_name_tool','-add_rpath','@loader_path',target)
    for module in MODULES:
        name=f'lib{module}_plugin.dylib'
        source=original/'plugins'/name
        target=destination/'plugins'/name
        shutil.copy2(source,target)
        if run('lipo','-archs',target,capture_output=True,text=True).stdout.strip()!=args.arch:
            raise RuntimeError(f'Unexpected VLC architecture: {name}')
        binary=source.read_bytes()
        if b'--enable-gpl' in binary or b'--enable-nonfree' in binary:
            raise RuntimeError(f'GPL/nonfree configuration detected in {name}')
        run('install_name_tool','-add_rpath','@loader_path/../lib',target)
        manifest['modules'].append({'name':name,'sourceSha256':hashlib.sha256(binary).hexdigest()})
    (destination/'modules.json').write_text(json.dumps(manifest,indent=2)+'\n')
    shutil.copytree(ROOT/'licenses',destination/'licenses',dirs_exist_ok=True)
    for binary in destination.rglob('*.dylib'):
        run('codesign','--force','--sign','-',binary,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    run('codesign','--force','--sign','-',BUILD/'libFreeSceneEngine.dylib',stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if args.bundle:
        helpers=args.bundle/'Contents/Helpers'
        helpers.mkdir(parents=True,exist_ok=True)
        shutil.copy2(update_helper,helpers/'FreeSceneUpdateHelper')
        frameworks=args.bundle/'Contents/Frameworks'
        frameworks.mkdir(parents=True,exist_ok=True)
        shutil.copy2(BUILD/'libFreeSceneEngine.dylib',frameworks/'libFreeSceneEngine.dylib')
        target=args.bundle/'Contents/Resources/VLC'
        if target.exists(): shutil.rmtree(target)
        shutil.copytree(destination,target)

if __name__ == '__main__':
    main()
