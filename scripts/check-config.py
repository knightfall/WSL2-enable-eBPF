#!/usr/bin/env python3
"""Fail when Kconfig drops a requested option or leaves BPF LSM inactive."""

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ASSIGNMENT = re.compile(
    r'(CONFIG_\w+)=(y|m|n|"(?:[^"\\]|\\.)*"|0x[0-9a-fA-F]+|-?[0-9]+)'
    r'\s*(?:#.*)?'
)
UNSET = re.compile(r'# (CONFIG_\w+) is not set')


def read_config(path):
    values = {}
    for number, raw in enumerate(Path(path).read_text().splitlines(), start=1):
        line = raw.strip()
        match = ASSIGNMENT.fullmatch(line)
        if match:
            key, value = match.groups()
        else:
            match = UNSET.fullmatch(line)
            if match:
                key, value = match[1], 'n'
            elif line.startswith('CONFIG_'):
                raise ValueError(f'{path}:{number}: invalid configuration assignment')
            else:
                continue
        if key in values:
            raise ValueError(f'{path}:{number}: duplicate option {key}')
        values[key] = value
    return values


def check_config(config, fragment):
    actual = read_config(config)
    expected = read_config(fragment)
    if not expected:
        raise ValueError(f'{fragment}: no configuration options found')
    errors = []
    for key, value in expected.items():
        if actual.get(key) != value:
            errors.append(f'{key}: expected {value}, got {actual.get(key, "missing")}')
    lsm = actual.get('CONFIG_LSM', '').strip('"').split(',')
    if 'bpf' not in lsm:
        errors.append('CONFIG_LSM must include bpf while preserving the other LSMs')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path, help='resolved .config or decompressed /proc/config.gz')
    parser.add_argument('--fragment', type=Path, default=ROOT / 'ebpf-kernel.config')
    args = parser.parse_args()
    try:
        errors = check_config(args.config, args.fragment)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('All requested options and BPF LSM activation are configured.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
