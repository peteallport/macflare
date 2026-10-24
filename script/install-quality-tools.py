#!/usr/bin/env python3
"""Install checksum-pinned tools into an explicit disposable directory.

Created by Peter C. Allport
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

def install_executable(source, target):
    # Replace the entry itself, never follow a package manager's existing symlink.
    with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.macflare-tool-', delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(source.read_bytes())
            stream.flush()
            os.fchmod(stream.fileno(), 0o755)
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)


def main():
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
            for name in asset.get('companions', []):
                source = candidates[0].parent / name
                if not source.is_file() or source.is_symlink():
                    raise SystemExit(f'{tool}: missing regular companion {name}')
                install_executable(source, args.destination / name)
            target = args.destination / tool
            install_executable(candidates[0], target)
            version_flag = 'version' if tool == 'periphery' else '--version'
            subprocess.run([str(target.resolve()), version_flag], check=True)
            print(f'Installed {tool}')


if __name__ == "__main__":
    main()
