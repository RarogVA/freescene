"""Exercise the real macOS WebKit/native panel with isolated, local media."""
import functools
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading

root=Path(__file__).resolve().parents[2]
flutter=Path(shutil.which('flutter')).resolve().parents[1]
framework=flutter/'bin/cache/artifacts/engine/darwin-x64-release/FlutterMacOS.xcframework/macos-arm64_x86_64'
vlc=root/'build/native/vlc'
build=root/'build/web-controls-test'
build.mkdir(parents=True,exist_ok=True)
app=build/'FreeSceneWebTest.app'
executable=app/'Contents/MacOS/FreeSceneWebTest'
executable.parent.mkdir(parents=True,exist_ok=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'FreeSceneWebTest','CFBundleIdentifier':'local.freescene.web-test','NSAppTransportSecurity':{'NSAllowsArbitraryLoads':True}}))
assets=app/'Contents/Frameworks/App.framework/Resources/flutter_assets/assets/player'
assets.mkdir(parents=True,exist_ok=True)
for file in (root/'assets/player').glob('*.js'):shutil.copy2(file,assets/file.name)
command=['xcrun','clang++','-std=c++17','-fobjc-arc','-F'+str(framework),'-framework','FlutterMacOS','-I'+str(root/'build/native/include'),'-L'+str(vlc/'lib'),'-lvlc','-L'+str(root/'build/native'),'-lFreeSceneEngine']
host=root/'packages/freescene_provider_host/macos/freescene_provider_host/Sources/freescene_provider_host'
command+=['-I'+str(host/'include'),'-x','objective-c++',str(host/'FreesceneProviderHostPlugin.m')]
for name in ['Cocoa','QuartzCore','WebKit','CoreText','Security','UserNotifications','UniformTypeIdentifiers']:command+=['-framework',name]
for path in [framework,vlc/'lib',root/'build/native']:command+=['-Wl,-rpath,'+str(path)]
command+=[str(root/'tests/native/web_controls.mm'),'-o',str(executable)]
environment=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
with (build/'compile.log').open('w') as log:subprocess.run(command,env=environment,stdout=log,stderr=log,check=True)
with tempfile.TemporaryDirectory(prefix='freescene-web-media-') as directory:
    path=Path(directory)
    subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=c=0x202329:s=640x360:r=1','-t','180','-c:v','libx264','-pix_fmt','yuv420p','-g','1','-movflags','+faststart',str(path/'video.mp4')],check=True)
    (path/'frame.html').write_text('<style>html,body{margin:0;background:#17181b}video{width:100vw;height:100vh;object-fit:contain}</style><video muted controls src="/video.mp4"></video><button>Provider controls</button>')
    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self,*args):pass
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=directory))
    port=server.server_port
    (path/'index.html').write_text(f'<style>html,body{{margin:0;background:#17181b}}iframe{{width:100vw;height:100vh;border:0}}</style><iframe src="http://localhost:{port}/frame.html"></iframe>')
    # A document.write player receives no fresh WebKit document-start script.
    (path/'dynamic.html').write_text('''<style>html,body{margin:0}iframe{width:100vw;height:100vh;border:0}</style><section id="selected"></section><script>setTimeout(()=>{const f=document.createElement('iframe');document.querySelector('#selected').append(f);f.contentDocument.open();f.contentDocument.write('<style>body{margin:0}video{width:100vw;height:100vh}</style><video muted controls src="/video.mp4"></video><button>Provider controls</button>');f.contentDocument.close();},300)</script>''')
    threading.Thread(target=server.serve_forever,daemon=True).start()
    try:
        for route in ['frame','index','dynamic']:
            subprocess.run([str(executable),f'http://127.0.0.1:{port}/{route}.html',str(build/f'{route}.png')],env=dict(environment,FREESCENE_DATA=str(path/'profile')),check=True,timeout=45)
    finally:server.shutdown();server.server_close()
print(build)
