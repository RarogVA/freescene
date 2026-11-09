#!/usr/bin/env python3
"""Serve a private, loopback-only video torrent for manual streaming regression tests."""
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, unquote
import argparse, hashlib, struct, threading, time

def encode(value):
    if isinstance(value, int): return b'i' + str(value).encode() + b'e'
    if isinstance(value, str): value = value.encode()
    if isinstance(value, bytes): return str(len(value)).encode() + b':' + value
    if isinstance(value, list): return b'l' + b''.join(encode(item) for item in value) + b'e'
    return b'd' + b''.join(encode(key) + encode(value[key]) for key in sorted(value)) + b'e'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('video', type=Path)
    parser.add_argument('--torrent', type=Path, required=True)
    parser.add_argument('--port', type=int, default=18765)
    parser.add_argument('--bytes-per-second', type=int, default=524288)
    parser.add_argument('--name', default='FreeScene streaming fixture.mp4')
    args = parser.parse_args()
    if args.bytes_per_second <= 0 or Path(args.name).name != args.name:
        parser.error('Positive speed and a plain filename are required')
    video = args.video.resolve(); piece_length = 262144
    pieces = bytearray()
    with video.open('rb') as source:
        while block := source.read(piece_length): pieces.extend(hashlib.sha1(block).digest())
    info = {'name': args.name, 'length': video.stat().st_size, 'piece length': piece_length, 'pieces': bytes(pieces), 'private': 1}
    torrent = {'announce': f'http://127.0.0.1:{args.port}/announce', 'url-list': [f'http://127.0.0.1:{args.port}/'], 'url-list-params': {'fast_start': 1}, 'info': info}
    args.torrent.write_bytes(encode(torrent))
    print(f'Torrent: {args.torrent}\nBytes: {video.stat().st_size}\nSHA1: {hashlib.sha1(encode(info)).hexdigest()}', flush=True)
    lock = threading.Lock(); next_send = [time.monotonic()]
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def do_GET(self):
            if urlparse(self.path).path == '/announce':
                data = encode({'interval': 20, 'complete': 0, 'incomplete': 1, 'peers': b''})
                self.send_response(200); self.send_header('Content-Length',len(data)); self.end_headers(); self.wfile.write(data); return
            if unquote(urlparse(self.path).path) not in ('/', '/' + args.name):
                self.send_error(404); return
            length = video.stat().st_size; start = 0; end = length - 1
            header = self.headers.get('Range')
            if header:
                first, last = header.removeprefix('bytes=').split('-',1)
                start = int(first or 0); end = min(int(last or end), end)
            self.send_response(206 if header else 200)
            self.send_header('Content-Type','video/mp4'); self.send_header('Content-Length',end-start+1)
            self.send_header('Accept-Ranges','bytes')
            if header: self.send_header('Content-Range',f'bytes {start}-{end}/{length}')
            self.end_headers(); sent = 0
            try:
                with video.open('rb') as source:
                    source.seek(start)
                    while start + sent <= end:
                        data = source.read(min(32768,end-start-sent+1))
                        if not data: break
                        with lock:
                            now = time.monotonic(); delay = max(0, next_send[0]-now)
                            next_send[0] = max(now,next_send[0])+len(data)/args.bytes_per_second
                        if delay: time.sleep(delay)
                        self.wfile.write(data); sent += len(data)
                print(f'Served {start}-{start+sent-1}',flush=True)
            except (BrokenPipeError,ConnectionResetError): pass
    ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()

if __name__ == '__main__': main()
