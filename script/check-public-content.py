#!/usr/bin/env python3
"""Validate indexed content without printing private matches or editing the index.

Created by Peter C. Allport
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def git(*args):
    return subprocess.check_output(['git', *args])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--history', action='store_true')
    args = parser.parse_args()
    if not shutil.which('gitleaks'):
        sys.exit('Commit blocked: required tool gitleaks is unavailable.')
    findings = []
    # Deliberately no general email/name detector: public attribution is intended.
    rules = {
        'local-home-path': re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/'),
        'private-account-id': re.compile(rb'(?i)(?:account[_-]?id|zone[_-]?id)[\s"\x27:=]+[a-f0-9]{32}\b'),
        'private-key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----'),
    }
    for entry in git('ls-files', '--stage', '-z').split(b'\0'):
        if not entry:
            continue
        meta, raw_path = entry.split(b'\t', 1)
        mode, oid, stage = meta.split()
        name = os.fsdecode(raw_path)
        path = Path(name)
        lower = name.lower()
        if stage != b'0':
            findings.append((name, 'unresolved-index'))
            continue
        if (path.suffix.lower() in {'.p12', '.pfx', '.mobileprovision', '.provisionprofile', '.key'}
                or path.name.lower() in {'.env', 'development.xcconfig', 'buildserver.json', 'id_rsa', 'id_ed25519'}
                or (path.name.startswith('.env.') and path.name not in {'.env.example', '.env.template'})
                or re.search(r'(^|/)(?:private|captures|account-exports)/', lower)):
            findings.append((name, 'private-file'))
        data = git('cat-file', 'blob', oid.decode()) if mode != b'160000' else b''
        for rule, pattern in rules.items():
            if pattern.search(data):
                findings.append((name, rule))
    # Ignore project/env allowlists: secrets may not exempt themselves with comments.
    with tempfile.TemporaryDirectory(prefix='macflare-public-') as directory:
        config = Path(directory) / 'rules.toml'
        config.write_text('[extend]\nuseDefault = true\n')
        report = Path(directory) / 'report.json'
        command = ['gitleaks', 'git', '--no-banner', '--redact=100',
                   '--ignore-gitleaks-allow', '--gitleaks-ignore-path', os.devnull,
                   '--config', str(config), '--report-format=json', '--report-path', str(report)]
        scans = [['--staged']]
        if args.history:
            scans.append(['--log-opts=--all'])
        for scope in scans:
            report.unlink(missing_ok=True)
            result = subprocess.run(command + scope, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode not in (0, 1) or not report.exists():
                sys.exit('Public-content check failed: Gitleaks could not complete; no scanner output published.')
            detected = json.loads(report.read_text())
            for finding in detected:
                findings.append((finding['File'], finding['RuleID']))
            if result.returncode and not detected:
                sys.exit('Public-content check failed: Gitleaks did not complete successfully.')
    for name, rule in sorted(set(findings)):
        # JSON escapes newlines/control characters in filenames. Never print matches.
        print(f'Public-content check blocked: {json.dumps(name)} ({rule})')
    if findings:
        return 1
    print('Public-content checks passed (credentials and private operational patterns).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
