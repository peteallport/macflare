#!/usr/bin/env python3
"""Public-content regressions using synthetic data in disposable local repos.

Created by Peter C. Allport
"""
import importlib.util
from pathlib import Path
import shutil
import subprocess

spec = importlib.util.spec_from_file_location('hook_tests', Path(__file__).with_name('test-pre-commit.py'))
hooks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hooks)

secret = 'gh' + 'p_' + 'AbC123dEf456GhI789jKl012MnO345pQr678sT'
cases = [
    ('notes.txt', 'token=' + secret, 'github-pat'),
    ('notes.txt', 'token=' + secret + ' # gitleaks:allow', 'github-pat'),
    ('notes.txt', '/' + 'Users/private-person/project', 'local-home-path'),
    ('notes.txt', 'account_id=' + 'a1' * 16, 'private-account-id'),
    ('.env.production', 'NOT_A_SECRET=example', 'private-file'),
    ('captures/account.json', '{}', 'private-file'),
]
for name, content, rule in cases:
    with hooks.fixture() as test:
        test.stage(name, content)
        test.write(name, 'safe unstaged replacement')
        test.check_hook(rule, failure=True)
        result = test.git('diff', '--cached')
        assert content.encode() in result.stdout
        print('PASS private content blocked: ' + rule)
with hooks.fixture() as test:
    test.stage('README.md', 'Created by Peter C. Allport. client_id=public-client-id\n')
    test.write('README.md', secret)
    test.check_hook('Public-content checks passed')
    print('PASS only index content scanned; public attribution and client IDs allowed')
with hooks.fixture() as test:
    alternate = test.root / '.git/alternate-index'
    shutil.copyfile(test.root / '.git/index', alternate)
    primary = (test.root / '.git/index').read_bytes()
    test.env['GIT_INDEX_FILE'] = str(alternate)
    test.stage('notes.txt', secret)
    test.check_hook('github-pat', failure=True)
    assert (test.root / '.git/index').read_bytes() == primary
    print('PASS alternate index scanned without modifying primary index')
with hooks.fixture() as test:
    test.fake_tool('gitleaks', 'exit 2\n')
    test.stage('README.md', 'safe\n')
    test.check_hook('could not complete', failure=True)
    print('PASS scanner failure blocks commit')
with hooks.fixture() as test:
    test.stage('notes.txt', secret)
    test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Synthetic historical fixture')
    test.git('rm', 'notes.txt')
    test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Remove synthetic fixture')
    result = subprocess.run(['bash', str(hooks.REPOSITORY / '.githooks/pre-push')],
                            cwd=test.root, env=test.env, capture_output=True)
    assert result.returncode != 0 and b'github-pat' in result.stdout
    assert secret.encode() not in result.stdout + result.stderr
    print('PASS pre-push blocks removed historical credentials without printing them')
with hooks.fixture() as test:
    test.stage(hooks.PROJECT, hooks.VALID_PROJECT.replace('"DEVELOPMENT_TEAM" = ""',
                                                       '"DEVELOPMENT_TEAM" = "PRIVATE"'))
    test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Synthetic signing fixture')
    test.check_hook('nonempty DEVELOPMENT_TEAM', failure=True, arguments=('--all',))
    print('PASS full-snapshot CI rejects already-committed private signing settings')
with hooks.fixture() as test:
    test.check_hook('Staged checks passed', arguments=('--all',))
    print('PASS full-snapshot CI validates a clean index without staged changes')
for name, content, rule in [
        ('captures/account.json', '{}', 'private-file'),
        ('notes.txt', '/' + 'Users/private-person/project', 'local-home-path'),
        ('notes.txt', 'account_id=' + 'a1' * 16, 'private-account-id')]:
    with hooks.fixture() as test:
        test.stage(name, content)
        test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Synthetic privacy fixture')
        test.git('rm', name)
        test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Remove synthetic fixture')
        result = subprocess.run(['bash', str(hooks.REPOSITORY / '.githooks/pre-push')],
                                cwd=test.root, env=test.env, capture_output=True)
        assert result.returncode != 0 and rule.encode() in result.stdout
        assert content.encode() not in result.stdout + result.stderr
        print('PASS historical private content remains blocked: ' + rule)
with hooks.fixture() as test:
    safe = test.git('rev-parse', 'HEAD').stdout.decode().strip()
    test.git('switch', '-c', 'unsafe-fixture')
    test.stage('notes.txt', secret)
    test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Synthetic other-branch fixture')
    unsafe = test.git('rev-parse', 'HEAD').stdout.decode().strip()
    test.git('switch', '--detach', safe)
    hook = ['bash', str(hooks.REPOSITORY / '.githooks/pre-push')]
    clean = subprocess.run(hook, cwd=test.root, env=test.env, input=b'', capture_output=True)
    assert clean.returncode == 0, clean.stdout
    push = f'refs/heads/unsafe-fixture {unsafe} refs/heads/unsafe-fixture {"0" * 40}\n'.encode()
    blocked = subprocess.run(hook, cwd=test.root, env=test.env, input=push, capture_output=True)
    assert blocked.returncode != 0 and b'github-pat' in blocked.stdout
    assert secret.encode() not in blocked.stdout + blocked.stderr
    deletion = f'(delete) {"0" * 40} refs/heads/unsafe-fixture {unsafe}\n'.encode()
    deleted = subprocess.run(hook, cwd=test.root, env=test.env, input=deletion, capture_output=True)
    assert deleted.returncode == 0
    print('PASS every uploaded ref checked independently of HEAD; deletion and unrelated local history handled')
print('Public-content regression checks passed.')
