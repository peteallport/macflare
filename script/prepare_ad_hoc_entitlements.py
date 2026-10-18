#!/usr/bin/env python3
"""Derive an entitlement copy for credential-free local or CI validation.

Created by Peter C. Allport
"""

import argparse
import os
from pathlib import Path
import plistlib
import tempfile


REPOSITORY = Path(__file__).resolve().parents[1]
SOURCES = {
    'Debug': REPOSITORY / 'macflare/macflare-Debug.entitlements',
    'Release': REPOSITORY / 'macflare/macflare.entitlements',
}
RESTRICTED_KEYS = {
    'aps-environment',
    'com.apple.developer.aps-environment',
    'com.apple.developer.icloud-container-identifiers',
    'com.apple.developer.icloud-services',
}


def prepare(configuration, destination):
    output = Path(destination).resolve()
    for source in SOURCES.values():
        if output == source.resolve() or (output.exists() and output.samefile(source)):
            raise ValueError('output must not overwrite either canonical entitlement file')

    with SOURCES[configuration].open('rb') as source:
        entitlements = plistlib.load(source)
    if not isinstance(entitlements, dict):
        raise ValueError('the canonical entitlement file must contain a dictionary')
    generated = {key: value for key, value in entitlements.items() if key not in RESTRICTED_KEYS}

    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix='.ad-hoc-entitlements-', dir=output.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, 'wb') as target:
            plistlib.dump(generated, target, sort_keys=False)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('configuration', choices=SOURCES)
    parser.add_argument('output_file', metavar='OUTPUT_FILE')
    arguments = parser.parse_args()
    try:
        output = prepare(arguments.configuration, arguments.output_file)
    except (OSError, ValueError, RuntimeError, plistlib.InvalidFileException) as error:
        parser.exit(1, f'Cannot prepare ad-hoc entitlements: {error}\n')
    print(f'Generated {arguments.configuration} ad-hoc entitlements: {output}')
    print('This build omits push and iCloud entitlements; it does not verify those provisioned services.')


if __name__ == '__main__':
    main()
