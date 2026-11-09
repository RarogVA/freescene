#!/usr/bin/env python3
"""Pinned static OpenSSL LTS, built for FreeScene's macOS 13 minimum."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parent.parent
VERSION='3.5.9'
SHA256='603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a'
PREFIX=ROOT/'build/openssl'

def main():
    global PREFIX
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['arm64','x86_64'], default=os.environ.get('FREESCENE_ARCH','arm64'))
    args=parser.parse_args()
    arch=args.arch
    PREFIX=ROOT/('build/openssl' if arch=='arm64' else 'build/openssl-x86_64')
    if (PREFIX/'build-version.txt').exists() and (PREFIX/'build-version.txt').read_text()==VERSION+' macOS13 '+arch+'\n': return
    vendor=ROOT/'build/vendor'; vendor.mkdir(parents=True,exist_ok=True)
    archive=vendor/f'openssl-{VERSION}.tar.gz'
    if not archive.exists():
        subprocess.run(['curl','-L','--fail','--silent','--show-error',f'https://github.com/openssl/openssl/releases/download/openssl-{VERSION}/openssl-{VERSION}.tar.gz','-o',str(archive)],check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA256: raise RuntimeError('OpenSSL source checksum mismatch')
    source_parent=vendor if arch=='arm64' else vendor/'x86_64'
    source_parent.mkdir(exist_ok=True)
    source=source_parent/f'openssl-{VERSION}'
    if not source.exists(): subprocess.run(['tar','-xzf',str(archive),'-C',str(source_parent)],check=True)
    env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer',MACOSX_DEPLOYMENT_TARGET='13.0')
    for command in [
        ['perl','Configure','darwin64-arm64-cc' if arch=='arm64' else 'darwin64-x86_64-cc','no-shared','no-tests','no-module',f'--prefix={PREFIX}','--libdir=lib','-mmacosx-version-min=13.0'],
        ['make','-j6','build_libs'],['make','install_sw'],
    ]: subprocess.run(command,cwd=source,env=env,check=True)
    for library in ('libcrypto.a','libssl.a'):
        actual=subprocess.check_output(['lipo','-archs',str(PREFIX/'lib'/library)],text=True).strip()
        if actual!=arch: raise RuntimeError(f'Unexpected OpenSSL architecture: {actual}')
    (PREFIX/'build-version.txt').write_text(VERSION+' macOS13 '+arch+'\n')

if __name__=='__main__': main()
