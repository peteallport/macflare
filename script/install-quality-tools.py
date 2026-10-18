#!/usr/bin/env python3
"""Install checksum-pinned tools into an explicit disposable directory.

Created by Peter C. Allport
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination', type=Path)
parser.add_argument('tools', nargs='+')
args = parser.parse_args()
platform_key = platform.system().lower() + '-' + platform.machine()
manifest = json.loads(Path(__file__).with_name('quality-tools.json').read_text())
args.destination.mkdir(parents=True, exist_ok=True)
for tool in args.tools:
    asset = manifest[tool][platform_key]
    with tempfile.TemporaryDirectory(prefix='macflare-tool-') as temporary:
        archive = Path(temporary) / 'download'
        subprocess.run(['curl', '-fsSL', '--retry', '3', asset['url'], '-o', str(archive)], check=True)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != asset['sha256']:
            raise SystemExit(f'{tool}: archive checksum mismatch')
        if asset['url'].endswith('.zip'):
            subprocess.run(['unzip', '-q', str(archive), '-d', temporary], check=True)
        else:
            subprocess.run(['tar', '-xzf', str(archive), '-C', temporary], check=True)
        candidates = [p for p in Path(temporary).rglob(tool) if p.is_file() and not p.is_symlink()]
        if len(candidates) != 1:
            raise SystemExit(f'{tool}: expected one executable')
        target = args.destination / tool
        target.write_bytes(candidates[0].read_bytes())
        target.chmod(0o755)
        print(f'Installed {tool}')
