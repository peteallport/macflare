#!/usr/bin/env python3
"""Test the tracked signing hook in disposable repos; never install it locally.

Created by Peter C. Allport
"""

import contextlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


REPOSITORY = Path(__file__).resolve().parents[1]
HOOK = REPOSITORY / '.githooks/pre-commit'
PROJECT = 'macflare.xcodeproj/project.pbxproj'
GIT = shutil.which('git')


def object_id(number):
    return f'{number:024X}'


def project_data():
    objects = {object_id(1): {'isa': 'PBXProject'}}
    for number, name in enumerate(('macflare', 'macflareTests', 'macflareUITests'), 2):
        objects[object_id(number)] = {
            'isa': 'PBXNativeTarget', 'name': name,
            'buildConfigurationList': object_id(number + 10),
        }
        objects[object_id(number + 10)] = {
            'isa': 'XCConfigurationList', 'buildConfigurations': [object_id(number + 20)],
        }
        objects[object_id(number + 20)] = {
            'isa': 'XCBuildConfiguration', 'name': 'Debug', 'buildSettings': {
                'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.' + name,
                'DEVELOPMENT_TEAM': '', 'CODE_SIGN_IDENTITY': '',
                'PROVISIONING_PROFILE_SPECIFIER': '',
            },
        }
    return {'objects': objects, 'rootObject': object_id(1)}


def openstep(value):
    if isinstance(value, dict):
        return '{\n' + ''.join(f'{json.dumps(key)} = {openstep(item)};\n'
                              for key, item in value.items()) + '}'
    if isinstance(value, list):
        return '(' + ','.join(openstep(item) for item in value) + ')'
    return json.dumps(value)


VALID_PROJECT = openstep(project_data()) + '\n'


def working_files(root):
    result = {}
    for path in root.rglob('*'):
        if '.git' in path.relative_to(root).parts or path.is_dir():
            continue
        result[str(path.relative_to(root))] = (
            ('symlink', os.readlink(path)) if path.is_symlink() else ('file', path.read_bytes())
        )
    return result


class Fixture:
    def __init__(self, directory):
        self.root = directory / 'repository'
        self.root.mkdir()
        self.temp = directory / 'snapshots'
        self.temp.mkdir()
        self.tools = directory / 'tools'
        self.tools.mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        self.env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                        GIT_OPTIONAL_LOCKS='0', TMPDIR=str(self.temp))
        self.git('init', '-q')
        self.git('config', 'user.name', 'Hook Fixture')
        self.git('config', 'user.email', 'fixture@example.test')
        self.git('config', 'commit.gpgsign', 'false')
        self.hooks = self.root / '.git/hooks'
        self.git('config', 'core.hooksPath', str(self.hooks))
        self.write(PROJECT, VALID_PROJECT)
        self.write('README.md', 'Baseline\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Fixture baseline')
        shutil.copyfile(HOOK, self.hooks / 'pre-commit')
        (self.hooks / 'pre-commit').chmod(0o755)

    def git(self, *arguments, check=True):
        result = subprocess.run([GIT, *arguments], cwd=self.root, env=self.env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if check:
            assert result.returncode == 0, result.stdout.decode()
        return result

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def stage(self, name, content):
        self.write(name, content)
        self.git('add', '--', name)

    def check_hook(self, message, failure=False):
        index = self.root / self.git('rev-parse', '--git-path', 'index').stdout.decode().strip()
        before_index = index.read_bytes()
        before_work = working_files(self.root)
        before_head = self.git('rev-parse', 'HEAD').stdout
        result = subprocess.run([str(HOOK)], cwd=self.root, env=self.env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert (result.returncode != 0) == failure, result.stdout.decode()
        assert message.encode() in result.stdout, result.stdout.decode()
        assert index.read_bytes() == before_index, 'Hook changed index bytes'
        assert working_files(self.root) == before_work, 'Hook changed working files'
        assert self.git('rev-parse', 'HEAD').stdout == before_head, 'Hook moved HEAD'
        assert not list(self.temp.iterdir()), 'Hook left a temporary snapshot behind'

    def fake_tool(self, name, body):
        tool = self.tools / name
        tool.write_text('#!/bin/bash\n' + body)
        tool.chmod(0o755)
        self.env['PATH'] = str(self.tools) + os.pathsep + self.env['PATH']


@contextlib.contextmanager
def fixture():
    with tempfile.TemporaryDirectory(prefix='macflare-hook-test-') as directory:
        yield Fixture(Path(directory))


def project_cases():
    cases = [('valid distinct app and test bundle IDs', VALID_PROJECT, None)]
    for key in ('DEVELOPMENT_TEAM', 'PROVISIONING_PROFILE',
                'PROVISIONING_PROFILE_SPECIFIER', 'CODE_SIGN_IDENTITY'):
        for suffix in ('', '[sdk=macosx*]', '[sdk=macosx*][arch=arm64]'):
            data = project_data()
            data['objects'][object_id(22)]['buildSettings'][key + suffix] = 'LOCAL_VALUE'
            cases.append((key + suffix, openstep(data), 'nonempty ' + key + suffix))
    data = project_data()
    for key in ('DEVELOPMENT_TEAM', 'PROVISIONING_PROFILE',
                'PROVISIONING_PROFILE_SPECIFIER', 'CODE_SIGN_IDENTITY'):
        data['objects'][object_id(22)]['buildSettings'][key + '[sdk=macosx*]'] = ''
    cases.append(('empty conditional settings', openstep(data), None))
    data = project_data()
    data['objects'][object_id(22)]['buildSettings']['OTHER_DEVELOPMENT_TEAM'] = 'not a signing key'
    data['objects'][object_id(1)]['shellScript'] = 'DEVELOPMENT_TEAM = PRIVATE;'
    cases.append(('unrelated keys and quoted script text', openstep(data), None))
    cases.append(('signing text in comments', VALID_PROJECT +
                  '\n/* DEVELOPMENT_TEAM = PRIVATE; */\n// CODE_SIGN_IDENTITY = PRIVATE;\n', None))
    data = project_data()
    data['objects'][object_id(23)]['buildSettings']['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.example.macflare'
    cases.append(('colliding app and test IDs', openstep(data), 'shares a bundle identifier'))
    data = project_data()
    data['objects'][object_id(24)]['buildSettings']['PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*]'] = 'com.example.macflare'
    cases.append(('conditional ID collision', openstep(data), 'shares a bundle identifier'))
    data = project_data()
    data.pop('rootObject')
    cases.append(('missing root object', openstep(data), 'missing a valid rootObject'))
    cases.append(('invalid plist', '{ broken =', 'plist syntax validation'))
    cases.append(('real MacFlare project', (REPOSITORY / PROJECT).read_text(), None))
    for name, content, error in cases:
        with fixture() as test:
            test.stage(PROJECT, content + '\n')
            # Valid staged content wins over unfinished local signing edits; bad
            # staged content fails even if the working file was already repaired.
            test.write(PROJECT, VALID_PROJECT if error else 'personal unfinished signing edits')
            test.check_hook(error or 'Staged project checks passed', failure=bool(error))
        print('PASS ' + name + ': index and personal working edits preserved')


def artifact_cases():
    for name in ('key.p12', 'key.pfx', 'profile.mobileprovision', 'profile.provisionprofile',
                 'Nested Folder/secret.P12', 'profile\nwith newline.MOBILEPROVISION'):
        with fixture() as test:
            test.stage(name, 'fixture signing material')
            test.check_hook('staged signing artifact', failure=True)
        print('PASS signing artifact rejected: ' + repr(name))
    for name in ('profile.mobileprovision.txt', 'keyxp12', 'p12', 'README.md'):
        with fixture() as test:
            test.stage(name, 'not a signing artifact')
            test.write('unstaged.p12', 'local only')
            test.check_hook('signing artifact checks passed')
        print('PASS allowed filename: ' + repr(name))
    with fixture() as test:
        test.stage('legacy.p12', 'existing signing material')
        test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture legacy artifact')
        test.git('rm', '--', 'legacy.p12')
        test.check_hook('signing artifact checks passed')
    print('PASS deleting signing material is allowed')
    with fixture() as test:
        test.git('mv', 'README.md', 'renamed.p12')
        test.check_hook('staged signing artifact', failure=True)
    print('PASS renaming into signing artifact is rejected')


def index_cases():
    for kind in ('deleted', 'symlink'):
        with fixture() as test:
            test.git('rm', '--', PROJECT)
            if kind == 'symlink':
                (test.root / PROJECT).parent.mkdir(parents=True, exist_ok=True)
                (test.root / PROJECT).symlink_to('../README.md')
                test.git('add', '--', PROJECT)
            test.check_hook('missing or not a regular file', failure=True)
        print('PASS ' + kind + ' project rejected')
    with fixture() as test:
        alternate = test.root.parent / 'alternate-index'
        shutil.copyfile(test.root / '.git/index', alternate)
        primary_index = (test.root / '.git/index').read_bytes()
        test.env['GIT_INDEX_FILE'] = str(alternate)
        test.stage(PROJECT, VALID_PROJECT.replace('"DEVELOPMENT_TEAM" = ""',
                                                '"DEVELOPMENT_TEAM" = "PRIVATE"'))
        test.write(PROJECT, VALID_PROJECT)
        test.check_hook('nonempty DEVELOPMENT_TEAM', failure=True)
        assert (test.root / '.git/index').read_bytes() == primary_index
    print('PASS alternate index checked; primary index preserved')
    with fixture() as test:
        test.write(PROJECT, 'unfinished local signing edits')
        test.stage('README.md', 'documentation only')
        test.check_hook('No staged project changes')
    print('PASS unstaged project changes ignored')
    for tool in ('plutil', 'python3'):
        with fixture() as test:
            test.stage(PROJECT, VALID_PROJECT + '\n')
            for required in ('bash', 'git', 'mktemp', 'rm', 'plutil', 'python3'):
                if required != tool:
                    (test.tools / required).symlink_to(shutil.which(required))
            test.env['PATH'] = str(test.tools)
            test.check_hook(f'required tool {tool} is unavailable', failure=True)
        print('PASS missing ' + tool + ' blocks commit without mutation')
    with fixture() as test:
        test.stage(PROJECT, VALID_PROJECT + '\n')
        test.fake_tool('plutil', 'echo "simulated parser failure" >&2\nexit 71\n')
        test.check_hook('plist syntax validation', failure=True)
    print('PASS parser failure blocks commit and cleans snapshot')
    with fixture() as test:
        test.stage(PROJECT, VALID_PROJECT + '\n')
        test.fake_tool('git', 'if [ "$1" = show ]; then echo "simulated index read failure" >&2; exit 72; fi\n'
                       + 'exec ' + json.dumps(GIT) + ' "$@"\n')
        test.check_hook('simulated index read failure', failure=True)
    print('PASS index read failure blocks commit and cleans snapshot')


def actual_commits(linked=False):
    with fixture() as test:
        if linked:
            linked_root = test.root.parent / 'linked'
            test.git('worktree', 'add', '--detach', str(linked_root), 'HEAD')
            test.root = linked_root
        staged = VALID_PROJECT + '// staged project edit\n'
        test.stage(PROJECT, staged)
        test.write(PROJECT, staged.replace('"DEVELOPMENT_TEAM" = ""',
                                          '"DEVELOPMENT_TEAM" = "PERSONAL"'))
        test.write('README.md', 'unstaged unrelated changes')
        test.write('untracked.p12', 'local only')
        before = working_files(test.root)
        result = test.git('commit', '-qm', 'Only intended project changes')
        assert b'Staged project checks passed' in result.stdout
        assert test.git('show', 'HEAD:' + PROJECT).stdout == staged.encode()
        assert test.git('show', 'HEAD:README.md').stdout == b'Baseline\n'
        assert working_files(test.root) == before
        test.stage(PROJECT, staged.replace('"DEVELOPMENT_TEAM" = ""',
                                          '"DEVELOPMENT_TEAM" = "PERSONAL"'))
        test.write(PROJECT, VALID_PROJECT)
        before = working_files(test.root)
        head = test.git('rev-parse', 'HEAD').stdout
        index = test.git('show', ':' + PROJECT).stdout
        result = test.git('commit', '-qm', 'Must reject personal signing', check=False)
        assert result.returncode != 0 and b'nonempty DEVELOPMENT_TEAM' in result.stdout
        assert test.git('rev-parse', 'HEAD').stdout == head
        assert test.git('show', ':' + PROJECT).stdout == index
        assert working_files(test.root) == before
    print(f'PASS actual {"linked-worktree " if linked else ""}commits preserve partial staging and reject personal signing')


if __name__ == '__main__':
    for required in ('git', 'plutil', 'python3'):
        if shutil.which(required) is None:
            raise SystemExit('Required test tool unavailable: ' + required)
    project_cases()
    artifact_cases()
    index_cases()
    actual_commits()
    actual_commits(linked=True)
    print('All signing-hook fixtures passed; disposable repositories removed.')
