#!/usr/bin/env python3
"""Verify safe executable replacement without downloading anything.

Created by Peter C. Allport
"""
import importlib.util
from pathlib import Path
import tempfile

spec = importlib.util.spec_from_file_location('installer', Path(__file__).with_name('install-quality-tools.py'))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
with tempfile.TemporaryDirectory(prefix='macflare-installer-test-') as directory:
    root = Path(directory)
    source = root / 'source'
    source.write_bytes(b'new executable')
    external = root / 'external'
    external.write_bytes(b'package-managed executable')
    external.chmod(0o600)
    target = root / 'bin' / 'tool'
    target.parent.mkdir()
    target.symlink_to(external)
    installer.install_executable(source, target)
    assert not target.is_symlink()
    assert target.read_bytes() == source.read_bytes()
    assert target.stat().st_mode & 0o777 == 0o755
    assert external.read_bytes() == b'package-managed executable'
    assert external.stat().st_mode & 0o777 == 0o600
    print('PASS executable symlink replaced; external contents and permissions preserved')
    target.unlink()
    target.mkdir()
    try:
        installer.install_executable(source, target)
        raise AssertionError('directory replaced')
    except IsADirectoryError:
        pass
    assert target.is_dir()
    assert not list(target.parent.glob('.macflare-tool-*'))
    print('PASS directory destination rejected and temporary file cleaned')
