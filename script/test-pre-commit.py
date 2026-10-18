#!/usr/bin/env python3
"""Test the tracked staged-validation hook in disposable repos; never install it locally.

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
FORMAT_CONFIG = '--swift-version 6.0\n--language-mode 6\n--rules spaceAroundOperators\n'
LINT_CONFIG = 'only_rules:\n  - trailing_whitespace\ntrailing_whitespace: warning\n'


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
        self.write('Example.swift', 'let value = 0\n')
        self.write('.swiftformat', FORMAT_CONFIG)
        self.write('.swiftlint.yml', LINT_CONFIG)
        self.write('script/check-public-content.py', (REPOSITORY / 'script/check-public-content.py').read_text())
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
            for required in ('bash', 'git', 'mktemp', 'rm', 'plutil', 'python3', 'gitleaks'):
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


def swift_cases():
    for valid in (True, False):
        with fixture() as test:
            test.stage('Example.swift', 'let value = 1\n' if valid else 'let value=1\n')
            test.write('Example.swift', 'let value=2\n' if valid else 'let value = 2\n')
            test.write('Untracked.swift', 'let unfinished=3\n')
            test.check_hook('Staged checks passed' if valid else 'SwiftFormat failed', failure=not valid)
        print('PASS partial Swift staging uses staged content: ' + ('valid' if valid else 'invalid'))
    for staged_rules, working_rules, failure in (
        ('trailingSpace', 'spaceAroundOperators', False),
        ('spaceAroundOperators', 'trailingSpace', True),
    ):
        with fixture() as test:
            test.stage('.swiftformat', FORMAT_CONFIG.replace('spaceAroundOperators', staged_rules))
            test.write('.swiftformat', FORMAT_CONFIG.replace('spaceAroundOperators', working_rules))
            test.stage('Example.swift', 'let value=1\n')
            test.check_hook('SwiftFormat failed' if failure else 'Staged checks passed', failure=failure)
        print('PASS staged formatter config wins over working config: ' + staged_rules)
    for severity in ('warning', 'error'):
        with fixture() as test:
            test.stage('.swiftlint.yml', LINT_CONFIG.replace('warning', severity))
            test.write('.swiftlint.yml', LINT_CONFIG.replace('warning', 'error' if severity == 'warning' else 'warning'))
            test.stage('Example.swift', 'let value = 1 \n')
            test.check_hook('SwiftLint failed' if severity == 'error' else 'warning: Trailing Whitespace',
                            failure=severity == 'error')
        print('PASS staged linter config: ' + severity + (' blocks' if severity == 'error' else ' is advisory'))
    with fixture() as test:
        test.stage('Nested/.swiftformat', FORMAT_CONFIG.replace('spaceAroundOperators', 'trailingSpace'))
        test.write('Nested/.swiftformat', FORMAT_CONFIG)
        test.stage('Nested/Example.swift', 'let value=1\n')
        test.check_hook('Staged checks passed')
    print('PASS staged nested formatter config and directory layout are preserved')
    with fixture() as test:
        test.stage('Nested/.swiftlint.yml', LINT_CONFIG.replace('warning', 'error'))
        test.write('Nested/.swiftlint.yml', LINT_CONFIG)
        test.stage('Nested/Example.swift', 'let value = 1 \n')
        test.check_hook('SwiftLint failed', failure=True)
    print('PASS staged nested linter config is respected')
    with fixture() as test:
        alternate = test.root.parent / 'alternate-index'
        shutil.copyfile(test.root / '.git/index', alternate)
        primary_index = (test.root / '.git/index').read_bytes()
        test.env['GIT_INDEX_FILE'] = str(alternate)
        test.stage('Example.swift', 'let value=1\n')
        test.write('Example.swift', 'let value = 1\n')
        test.check_hook('SwiftFormat failed', failure=True)
        assert (test.root / '.git/index').read_bytes() == primary_index
    print('PASS staged Swift uses alternate index and preserves primary index')
    for tool in ('swiftformat', 'swiftlint'):
        with fixture() as test:
            test.stage('Example.swift', 'let value = 1\n')
            for required in ('bash', 'git', 'mktemp', 'mkdir', 'rm', 'swiftformat', 'swiftlint', 'python3', 'gitleaks'):
                if required != tool:
                    (test.tools / required).symlink_to(shutil.which(required))
            test.env['PATH'] = str(test.tools)
            test.check_hook(f'required tool {tool} is unavailable', failure=True)
        print('PASS missing ' + tool + ' blocks without mutation')
    for config in ('.swiftformat', '.swiftlint.yml'):
        for kind in ('deleted', 'symlink'):
            with fixture() as test:
                test.stage('Example.swift', 'let value = 1\n')
                test.git('rm', '--', config)
                if kind == 'symlink':
                    (test.root / config).symlink_to('README.md')
                    test.git('add', '--', config)
                test.check_hook(f'staged {config} is missing or not a regular file', failure=True)
            print('PASS ' + kind + ' ' + config + ' blocks staged Swift checks')
    with fixture() as test:
        test.git('rm', '--', 'Example.swift')
        test.check_hook('No staged project changes or Swift files')
    print('PASS deleted Swift file is skipped')
    with fixture() as test:
        test.git('rm', '--', 'Example.swift')
        (test.root / 'Example.swift').symlink_to('README.md')
        test.git('add', '--', 'Example.swift')
        test.check_hook('staged Swift path is not a regular file', failure=True)
    print('PASS staged Swift symlink is rejected')
    with fixture() as test:
        test.git('mv', '--', 'Example.swift', '-New name\n.swift')
        test.check_hook('Staged checks passed')
    print('PASS renamed Swift path with spaces, newline and leading dash')
    with fixture() as test:
        test.stage('Example.swift', 'let value = 1\n')
        test.fake_tool('git', 'if [ "$1" = checkout-index ]; then echo "simulated snapshot failure" >&2; exit 73; fi\n'
                       + 'exec ' + json.dumps(GIT) + ' "$@"\n')
        test.check_hook('simulated snapshot failure', failure=True)
    print('PASS snapshot failure blocks and cleans temporary files')


def config_only_cases():
    for staged_rule, failure in (('trailingSpace', False), ('spaceAroundOperators', True)):
        with fixture() as test:
            # Commit a source/config baseline, then stage only the configuration.
            test.stage('.swiftformat', FORMAT_CONFIG.replace('spaceAroundOperators', 'trailingSpace'))
            test.stage('Example.swift', 'let value=1\n')
            test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture formatter baseline')
            test.stage('.swiftformat', FORMAT_CONFIG.replace('spaceAroundOperators', staged_rule) + '# staged\n')
            test.write('.swiftformat', FORMAT_CONFIG.replace('spaceAroundOperators',
                       'trailingSpace' if failure else 'spaceAroundOperators'))
            test.write('Example.swift', 'let value = 1\n' if failure else 'unfinished working source')
            test.check_hook('SwiftFormat failed' if failure else 'Staged checks passed', failure=failure)
        print('PASS config-only formatter change checks unchanged staged Swift: ' + staged_rule)
    for severity in ('warning', 'error'):
        with fixture() as test:
            test.stage('Example.swift', 'let value = 1 \n')
            test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture linter baseline')
            test.stage('.swiftlint.yml', LINT_CONFIG.replace('warning', severity) + '# staged\n')
            test.write('.swiftlint.yml', LINT_CONFIG.replace('warning', 'warning' if severity == 'error' else 'error'))
            test.write('Example.swift', 'let value = 1\n')
            test.check_hook('SwiftLint failed' if severity == 'error' else 'warning: Trailing Whitespace',
                            failure=severity == 'error')
        print('PASS config-only linter change checks unchanged staged Swift: ' + severity)
    for config, valid, malformed, message in (
        ('.swiftformat', FORMAT_CONFIG, '--rules noSuchFormattingRule\n', 'SwiftFormat failed'),
        ('.swiftlint.yml', LINT_CONFIG, 'only_rules: [\n', 'SwiftLint failed'),
    ):
        with fixture() as test:
            test.stage(config, malformed)
            test.write(config, valid)
            test.check_hook(message, failure=True)
        print('PASS malformed staged root config is rejected despite valid working config: ' + config)
        with fixture() as test:
            test.git('rm', '--', config)
            test.write(config, valid)
            test.check_hook(f'staged {config} is missing or not a regular file', failure=True)
        print('PASS config-only root deletion is rejected despite existing working config: ' + config)
    for config, parent, nested, source, message in (
        ('.swiftformat', FORMAT_CONFIG.replace('spaceAroundOperators', 'trailingSpace'),
         FORMAT_CONFIG, 'let value=1\n', 'SwiftFormat failed'),
        ('.swiftlint.yml', LINT_CONFIG, LINT_CONFIG.replace('warning', 'error'),
         'let value = 1 \n', 'SwiftLint failed'),
    ):
        with fixture() as test:
            test.stage(config, parent)
            test.stage('Nested/Unchanged.swift', source)
            test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture nested configuration baseline')
            test.stage('Nested/' + config, nested)
            test.write('Nested/' + config, parent)
            test.check_hook(message, failure=True)
        print('PASS nested config-only addition checks unchanged staged Swift: ' + config)
        with fixture() as test:
            test.stage(config, nested)
            test.stage('Nested/' + config, parent)
            test.stage('Nested/Unchanged.swift', source)
            test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture nested deletion baseline')
            test.git('rm', '--', 'Nested/' + config)
            test.write('Nested/' + config, parent)
            test.check_hook(message, failure=True)
        print('PASS nested config-only deletion applies staged parent config: ' + config)


    with fixture() as test:
        test.stage('Nested/Unchanged.swift', 'let value = 1\n')
        test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture nested YAML baseline')
        test.stage('Nested/.swiftlint.yml', 'only_rules: [\n')
        test.write('Nested/.swiftlint.yml', LINT_CONFIG)
        test.check_hook('SwiftLint failed to validate staged configuration: Nested/.swiftlint.yml', failure=True)
    print('PASS malformed nested-only linter configuration is rejected without falling back')
    with fixture() as test:
        test.stage('Nested/Unchanged.swift', 'let value = 1\n')
        test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture nested symlink baseline')
        (test.root / 'Nested/.swiftlint.yml').symlink_to('../.swiftlint.yml')
        test.git('add', '--', 'Nested/.swiftlint.yml')
        test.check_hook('staged Nested/.swiftlint.yml is missing or not a regular file', failure=True)
    print('PASS nested-only linter configuration symlink is rejected')


def nested_formatter_symlink_cases():
    config = 'Nested/.swiftformat'
    blocked = f'staged {config} is missing or not a regular file'
    permissive = FORMAT_CONFIG.replace('spaceAroundOperators', 'trailingSpace')

    for kind in ('external', 'broken'):
        with fixture() as test:
            test.stage('Nested/Unchanged.swift', 'let value=1\n')
            test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture formatter baseline')
            external = test.root.parent / 'external.swiftformat'
            if kind == 'external':
                external.write_text(permissive)
            before_external = external.read_bytes() if external.exists() else None
            (test.root / config).symlink_to(external)
            test.git('add', '--', config)
            test.check_hook(blocked, failure=True)
            assert (external.read_bytes() if external.exists() else None) == before_external
        print('PASS config-only nested formatter ' + kind + ' symlink rejected; external target preserved')

    with fixture() as test:
        test.stage('Nested/Unchanged.swift', 'let value=1\n')
        test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture partial formatter baseline')
        external = test.root.parent / 'external.swiftformat'
        external.write_text(permissive)
        before_external = external.read_bytes()
        (test.root / config).symlink_to(external)
        test.git('add', '--', config)
        (test.root / config).unlink()
        test.write(config, FORMAT_CONFIG)
        test.check_hook(blocked, failure=True)
        assert external.read_bytes() == before_external
    print('PASS staged nested formatter symlink rejected despite regular working config')

    with fixture() as test:
        test.stage('Nested/Unchanged.swift', 'let value=1\n')
        test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture regular formatter baseline')
        test.stage(config, permissive)
        external = test.root.parent / 'external.swiftformat'
        external.write_text(FORMAT_CONFIG)
        before_external = external.read_bytes()
        (test.root / config).unlink()
        (test.root / config).symlink_to(external)
        test.check_hook('Staged checks passed')
        assert external.read_bytes() == before_external
    print('PASS staged regular nested formatter config wins over unstaged working symlink')

    with fixture() as test:
        test.stage('Nested/Changed.swift', 'let value=1\n')
        external = test.root.parent / 'external.swiftformat'
        external.write_text(permissive)
        before_external = external.read_bytes()
        (test.root / config).symlink_to(external)
        test.git('add', '--', config)
        test.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Fixture existing formatter symlink')
        test.stage('Nested/Changed.swift', 'let value=2\n')
        test.check_hook(blocked, failure=True)
        assert external.read_bytes() == before_external
    print('PASS existing nested formatter symlink rejected during Swift-only staging')


def formatter_config_validation_cases():
    config = 'Nested/.swiftformat'
    blocked = f'Commit blocked: SwiftFormat failed to validate staged configuration: {config}'
    for name, invalid in (
        ('unknown rule', '--rules noSuchFormattingRule\n'),
        ('unknown option', '--no-such-format-option true\n'),
        ('malformed option value', '--indent banana\n'),
    ):
        with fixture() as test:
            # No indexed Swift file is beneath this config, so source discovery
            # alone would never parse it. The staged version must still win.
            test.stage(config, invalid)
            test.write(config, FORMAT_CONFIG)
            test.check_hook(blocked, failure=True)
        print('PASS nested formatter ' + name + ' rejected without nested Swift; valid working config preserved')

    with fixture() as test:
        # Applying this config to the unrelated root source would demand a header.
        test.stage(config, '--rules fileHeader\n--header Nested files only\n')
        test.write(config, '--rules noSuchFormattingRule\n')
        test.check_hook('Staged checks passed')
    print('PASS valid staged nested formatter config ignores invalid working config and preserves source scope')

    with fixture() as test:
        test.git('rm', '--', 'Example.swift')
        test.stage(config, '--rules noSuchFormattingRule\n')
        test.check_hook(blocked, failure=True)
    print('PASS invalid nested formatter config rejected with no Swift files in the index')


def actual_commits(linked=False):
    with fixture() as test:
        if linked:
            linked_root = test.root.parent / 'linked'
            test.git('worktree', 'add', '--detach', str(linked_root), 'HEAD')
            test.root = linked_root
        test.stage('Example.swift', 'let value = 1\n')
        test.write('Example.swift', 'let value=2\n')
        test.write('Untracked.swift', 'let unfinished=3\n')
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
        assert test.git('show', 'HEAD:Example.swift').stdout == b'let value = 1\n'
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
    for required in ('git', 'plutil', 'python3', 'swiftformat', 'swiftlint'):
        if shutil.which(required) is None:
            raise SystemExit('Required test tool unavailable: ' + required)
    project_cases()
    artifact_cases()
    index_cases()
    swift_cases()
    config_only_cases()
    nested_formatter_symlink_cases()
    formatter_config_validation_cases()
    actual_commits()
    actual_commits(linked=True)
    print('All staged-validation fixtures passed; disposable repositories removed.')
