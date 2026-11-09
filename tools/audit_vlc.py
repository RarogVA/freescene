#!/usr/bin/env python3
"""Record licences in the selected VLC module source headers (not a full binary audit)."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from build_native import MODULES

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source',type=Path,required=True)
p.add_argument('--archive',type=Path,required=True)
p.add_argument('--report',type=Path,required=True)
a=p.parse_args()
source=a.source/'modules'; definitions={}
for makefile in source.rglob('Makefile.am'):
    text=makefile.read_text().replace('\\\n',' ')
    for match in re.finditer(r'^lib(\w+)_plugin_la_SOURCES\s*(?:\+?=)\s*(.+)$',text,re.M):
        definitions.setdefault(match[1],[]).extend(re.findall(r'[\w/.-]+\.(?:c|cpp|m|mm)\b',match[2]))
modules=[]
for name in MODULES:
    entries=[]
    for path in sorted(set(definitions.get(name,[]))):
        file=source/path
        if not file.exists(): continue
        header=file.read_text(errors='replace')[:5000]
        license='LGPL' if 'GNU Lesser General Public' in header or 'GNU Library General Public' in header else 'GPL' if 'GNU General Public' in header else 'manual'
        # The TS demuxer includes Xiph's two-clause BSD Opus header parser,
        # not an additional Opus decoder/library. Pin the reviewed source.
        if path == 'codec/opus_header.c' and hashlib.sha256(file.read_bytes()).hexdigest() == 'f4bfc2284e8753c494fd73cd6fed923ed3a6a38600c4eecdc2ea2c2329c0e2e6':
            license='BSD-2-Clause'
        entries.append({'source':path,'headerLicense':license})
    if not entries or any(e['headerLicense'] not in ('LGPL','BSD-2-Clause') for e in entries): raise RuntimeError(f'Module needs review: {name}')
    modules.append({'module':name,'sources':entries})
report={'vlcVersion':'3.0.21','sourceArchiveSha256':hashlib.sha256(a.archive.read_bytes()).hexdigest(),'scope':'Source headers only; static dependency inventory remains a separate release check','modules':modules}
a.report.write_text(json.dumps(report,indent=2)+'\n')
print(f'Checked source headers for {len(modules)} modules')
