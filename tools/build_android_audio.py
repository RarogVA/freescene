#!/usr/bin/env python3
"""Build the official Media3 audio-only FFmpeg fallback from checksum-pinned sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/android-audio'
VENDOR = BUILD / 'vendor'
MANIFEST = ROOT / 'tools/android-audio-dependencies.json'
NDK_VERSION = '28.2.13676358'
API = 24
ABIS = {'armeabi-v7a': ('arm', 'armv7a-linux-androideabi'),
        'arm64-v8a': ('aarch64', 'aarch64-linux-android')}


def run(*args, **kwargs):
    subprocess.run(list(map(str, args)), check=True, **kwargs)


def fetch(item):
    path = VENDOR / item['file']
    if not path.is_file():
        temporary = path.with_suffix(path.suffix + '.part')
        run('curl', '--fail', '--location', '--silent', '--show-error',
            '--connect-timeout', '20', '--max-time', '300', item['url'], '-o', temporary)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != item['sha256']:
            raise RuntimeError('Audio source checksum mismatch: ' + item['file'])
        temporary.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
        raise RuntimeError('Audio source checksum mismatch: ' + item['file'])
    return path


def package_sources(archive, sources):
    """Ship the source inputs and a recipe that works from the extracted tree."""
    bundle = BUILD / 'FreeScene-android-audio-sources.tar.gz'
    with tarfile.open(bundle, 'w:gz') as target:
        for path in [archive, *sources, MANIFEST, Path(__file__).resolve(),
                     ROOT / 'android/app/build.gradle.kts',
                     ROOT / 'docs/android-audio.md', ROOT / 'licenses/AndroidX-Media3-LICENSE.txt',
                     ROOT / 'licenses/ANDROID-AUDIO-NOTICES.txt']:
            target.add(path, arcname='FreeScene-android-audio-sources/' + path.relative_to(ROOT).as_posix())
    return bundle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--abi', action='append', choices=list(ABIS))
    parser.add_argument('--sdk', type=Path)
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    version = manifest['media3']['version']
    if f'media3-exoplayer:{version}' not in (ROOT / 'android/app/build.gradle.kts').read_text():
        raise RuntimeError('Update audio sources together with the Media3 dependency')
    sdk = args.sdk or Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
                          or str(Path.home() / 'Library/Android/sdk'))
    host = 'darwin-x86_64' if sys.platform == 'darwin' else 'linux-x86_64'
    cc = sdk / 'ndk' / NDK_VERSION / 'toolchains/llvm/prebuilt' / host / 'bin'
    if not cc.is_dir():
        raise RuntimeError(f'Install Android NDK {NDK_VERSION} in {sdk}')
    VENDOR.mkdir(parents=True, exist_ok=True)
    archive = fetch(manifest['ffmpeg'])
    sources = [fetch(item) for item in manifest['media3']['files']]
    source = VENDOR / ('ffmpeg-' + manifest['ffmpeg']['version'])
    if not source.is_dir():
        with tarfile.open(archive) as bundle:
            # Checksums pin the upstream archive; reject paths escaping our build cache, too.
            for member in bundle.getmembers():
                target = (VENDOR / member.name).resolve()
                if VENDOR.resolve() not in target.parents:
                    raise RuntimeError('Invalid audio source archive path')
            if hasattr(tarfile, 'data_filter'):
                bundle.extractall(VENDOR, filter='data')
            else:
                bundle.extractall(VENDOR)
    java = BUILD / 'java/androidx/media3/decoder/ffmpeg'
    java.mkdir(parents=True, exist_ok=True)
    for path in sources:
        if path.suffix == '.java':
            shutil.copy2(path, java / path.name)
    for abi in args.abi or list(ABIS):
        arch, triple = ABIS[abi]
        obj = BUILD / abi
        obj.mkdir(parents=True, exist_ok=True)
        prefix = obj / 'install'
        output = BUILD / 'jniLibs' / abi / 'libffmpegJNI.so'
        flags = ['--target-os=android', f'--arch={arch}', '--enable-cross-compile', f'--prefix={prefix}',
                 f'--cc={cc}/{triple}{API}-clang', f'--cxx={cc}/{triple}{API}-clang++',
                 f'--nm={cc}/llvm-nm', f'--ar={cc}/llvm-ar',
                 f'--ranlib={cc}/llvm-ranlib', f'--strip={cc}/llvm-strip',
                 '--enable-static', '--disable-shared', '--enable-pic',
                 '--disable-gpl', '--disable-version3', '--disable-nonfree',
                 '--disable-doc', '--disable-programs', '--disable-everything',
                 '--disable-autodetect', '--disable-avdevice', '--disable-avformat',
                 '--disable-swscale', '--disable-postproc', '--disable-avfilter',
                 '--disable-network', '--disable-symver', '--disable-v4l2-m2m',
                 '--disable-vulkan', '--enable-swresample',
                 '--enable-decoder=ac3', '--enable-decoder=eac3', '--enable-decoder=dca']
        if abi == 'armeabi-v7a':
            flags += ['--cpu=armv7-a', '--extra-cflags=-march=armv7-a -mfloat-abi=softfp']
        signature = hashlib.sha256(json.dumps([manifest, NDK_VERSION, flags,
                                              (Path(__file__).read_text())]).encode()).hexdigest()
        stamp = obj / 'complete'
        if output.is_file() and stamp.is_file() and stamp.read_text() == signature:
            print('Cached audio fallback for ' + abi, flush=True)
            continue
        run(source / 'configure', *flags, cwd=obj)
        run('make', '-j' + os.environ.get('AUDIO_BUILD_JOBS', '4'), cwd=obj)
        run('make', 'install-libs', 'install-headers', cwd=obj)
        output.parent.mkdir(parents=True, exist_ok=True)
        run(cc / (triple + str(API) + '-clang++'), '-shared', '-std=c++11',
            '-fno-exceptions', '-fno-rtti', '-nostdlib++', '-fvisibility=hidden',
            '-fvisibility-inlines-hidden', '-I' + str(prefix / 'include'),
            VENDOR / 'ffmpeg_jni.cc', '-Wl,--no-undefined', '-Wl,--exclude-libs,ALL',
            '-Wl,-soname,libffmpegJNI.so',
            '-Wl,-z,max-page-size=16384', '-Wl,--start-group', prefix / 'lib/libavcodec.a',
            prefix / 'lib/libswresample.a', prefix / 'lib/libavutil.a',
            '-Wl,--end-group', '-landroid', '-llog', '-lm', '-latomic', '-o', output)
        run(cc / 'llvm-strip', '--strip-unneeded', output)
        stamp.write_text(signature)
        print('Built audio fallback for ' + abi, flush=True)
    # Ship complete source and rebuild instructions alongside the APKs, without binaries in Git.
    bundle = package_sources(archive, sources)
    print('Source bundle: ' + str(bundle), flush=True)


if __name__ == '__main__':
    main()
