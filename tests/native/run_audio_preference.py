"""Verify automatic and manual selection against actual multitrack libVLC media."""
from pathlib import Path
import subprocess
import tempfile

from run_player_lifecycle import build_player_test, root

binary = build_player_test('tests/native/audio_preference.mm', 'audio-preference')
with tempfile.TemporaryDirectory(prefix='freescene-audio-') as directory:
    files = []
    for name, languages, labels in [('english', ['rus','jpn','eng','eng'], ['Russian','Original','Commentary','English']),
                                     ('original',['rus','jpn'],['Russian','Original'])]:
        path=Path(directory)/(name+'.mkv');files.append(str(path))
        command=['ffmpeg','-v','error','-f','lavfi','-i','color=c=black:s=64x64:r=1','-f','lavfi','-i','anullsrc=r=48000:cl=stereo','-map','0:v']
        for _ in languages:command+=['-map','1:a']
        command+=['-c:v','libx264','-c:a','aac','-t','10']
        for i,(language,label) in enumerate(zip(languages,labels)):
            command += [f'-metadata:s:a:{i}','language='+language,f'-metadata:s:a:{i}','title='+label,f'-disposition:a:{i}','default' if i==0 else '0']
        subprocess.run(command+[str(path)],check=True)
    subprocess.run([str(binary),*files],cwd=root,check=True,timeout=30)
