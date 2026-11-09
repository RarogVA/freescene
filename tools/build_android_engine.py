#!/usr/bin/env python3
"""Cross-build the shared FreeScene/libtorrent engine with pinned dependencies."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/android-native'
VENDOR = BUILD / 'vendor'
NDK_VERSION = '28.2.13676358'
LIBTORRENT = '6da363d2994f17c0b3c0450d124cf73a31a73847'


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def fetch(url, filename, digest, reuse=None):
    path = VENDOR / filename
    if not path.exists():
        if reuse and reuse.is_file():
            shutil.copy2(reuse, path)
        else:
            run('curl', '--fail', '--location', '--silent', '--show-error',
                '--connect-timeout', '20', '--max-time', '300', url, '-o', path)
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise RuntimeError('Dependency checksum mismatch: ' + filename)
    return path


def extract(archive, directory):
    if not directory.exists():
        with tarfile.open(archive) as source:
            if hasattr(tarfile, 'data_filter'):
                source.extractall(VENDOR, filter='data')
            else:
                source.extractall(VENDOR)
    if not directory.is_dir():
        raise RuntimeError('Unexpected dependency archive layout')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--abi', action='append', choices=['armeabi-v7a', 'arm64-v8a'])
    parser.add_argument('--sdk', type=Path)
    args = parser.parse_args()
    sdk = args.sdk or Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
                          or str(Path.home() / 'Library/Android/sdk'))
    ndk = sdk / 'ndk' / NDK_VERSION
    host = 'darwin-x86_64' if sys.platform == 'darwin' else 'linux-x86_64'
    toolchain = ndk / 'toolchains/llvm/prebuilt' / host
    if not toolchain.is_dir():
        raise RuntimeError(f'Install Android NDK {NDK_VERSION} in {sdk}')
    VENDOR.mkdir(parents=True, exist_ok=True)
    boost = VENDOR / 'boost-1.92.0'
    extract(fetch('https://github.com/boostorg/boost/releases/download/boost-1.92.0/boost-1.92.0-b2-nodocs.tar.gz',
                  'boost-1.92.0-b2-nodocs.tar.gz', 'e2a814b3a158ab482c7a3d330f8bf5a7a8423d258a4e2fb396996e00fcee2111'), boost)
    json_header = fetch('https://github.com/nlohmann/json/releases/download/v3.12.0/json.hpp', 'json.hpp',
                        'aaf127c04cb31c406e5b04a63f1ae89369fccde6d8fa7cdda1ed4f32dfc5de63')
    json_include = VENDOR / 'json-include'
    (json_include / 'nlohmann').mkdir(parents=True, exist_ok=True)
    shutil.copy2(json_header, json_include / 'nlohmann/json.hpp')
    ssl = VENDOR / 'openssl-3.5.9'
    extract(fetch('https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz',
                  'openssl-3.5.9.tar.gz', '603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a',
                  ROOT / 'build/vendor/openssl-3.5.9.tar.gz'), ssl)
    torrent = ROOT / 'build/dependencies/libtorrent'
    if not (torrent / '.git').exists():
        torrent.mkdir(parents=True, exist_ok=True)
        run('git', 'init', torrent)
        run('git', '-C', torrent, 'remote', 'add', 'origin', 'https://github.com/arvidn/libtorrent.git')
        run('git', '-C', torrent, 'fetch', '--depth=1', 'origin', LIBTORRENT)
        run('git', '-C', torrent, 'checkout', '--detach', 'FETCH_HEAD')
        run('git', '-C', torrent, 'submodule', 'update', '--init', '--depth=1', 'deps/try_signal')
    if subprocess.check_output(['git', '-C', str(torrent), 'rev-parse', 'HEAD'], text=True).strip() != LIBTORRENT:
        raise RuntimeError('Unexpected cached libtorrent revision')
    env = dict(os.environ, ANDROID_NDK_ROOT=str(ndk), PATH=str(toolchain / 'bin') + os.pathsep + os.environ['PATH'])
    for abi in args.abi or ['armeabi-v7a', 'arm64-v8a']:
        target = 'android-arm' if abi == 'armeabi-v7a' else 'android-arm64'
        triple = 'arm-linux-androideabi' if abi == 'armeabi-v7a' else 'aarch64-linux-android'
        prefix = BUILD / abi / 'openssl'
        obj = BUILD / abi / 'ssl-obj'
        if not (prefix / 'complete').exists():
            obj.mkdir(parents=True, exist_ok=True)
            run('perl', ssl / 'Configure', target, 'no-shared', 'no-tests', 'no-module',
                '-D__ANDROID_API__=24', '-fPIC', f'--prefix={prefix}', '--libdir=lib', cwd=obj, env=env)
            run('make', '-j6', 'build_libs', cwd=obj, env=env)
            run('make', 'install_sw', cwd=obj, env=env)
            (prefix / 'complete').write_text('OpenSSL 3.5.9 NDK ' + NDK_VERSION + '\n')
        native = BUILD / abi / 'engine'
        # Host pkg-config must not inject Linux/macOS OpenSSL dependencies into Android.
        target_env = dict(env, PKG_CONFIG_LIBDIR=str(prefix / 'lib/pkgconfig'),
                          PKG_CONFIG_PATH='', PKG_CONFIG_SYSROOT_DIR='')
        run('cmake', '-S', ROOT / 'native', '-B', native, '-U', '*OPENSSL*', '-DCMAKE_BUILD_TYPE=Release',
            f'-DCMAKE_TOOLCHAIN_FILE={ndk}/build/cmake/android.toolchain.cmake',
            f'-DANDROID_ABI={abi}', '-DANDROID_PLATFORM=android-24', '-DANDROID_STL=c++_shared',
            f'-DFETCHCONTENT_SOURCE_DIR_LIBTORRENT={torrent}', f'-DFREESCENE_BOOST_ROOT={boost}',
            f'-DFREESCENE_JSON_INCLUDE={json_include}', f'-DOPENSSL_ROOT_DIR={prefix}',
            f'-DOPENSSL_INCLUDE_DIR={prefix}/include', f'-DOPENSSL_SSL_LIBRARY={prefix}/lib/libssl.a',
            f'-DOPENSSL_CRYPTO_LIBRARY={prefix}/lib/libcrypto.a', '-Di2p=OFF', '-Dlogging=OFF', env=target_env)
        run('cmake', '--build', native, '--target', 'FreeSceneEngine', '-j6', env=target_env)
        destination = ROOT / 'build/android-engine/jniLibs' / abi
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(native / 'libFreeSceneEngine.so', destination / 'libFreeSceneEngine.so')
        shutil.copy2(toolchain / 'sysroot/usr/lib' / triple / 'libc++_shared.so', destination / 'libc++_shared.so')
        run(toolchain / 'bin/llvm-strip', '--strip-unneeded', destination / 'libFreeSceneEngine.so', destination / 'libc++_shared.so')
        print(f'Built shared torrent engine for {abi}', flush=True)


if __name__ == '__main__':
    main()
