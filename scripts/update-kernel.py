#!/usr/bin/env python3
"""Select the newest stable WSL kernel tag in the currently pinned series."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TAG = re.compile(r'linux-msft-wsl-(\d+)\.(\d+)\.(\d+)\.(\d+)')
SHA = re.compile(r'[0-9a-f]{40}')


def run(*command, cwd=ROOT):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def read_lock(path):
    values = {}
    for line in Path(path).read_text().splitlines():
        if line and not line.startswith('#'):
            key, value = line.split('=', 1)
            values[key] = value
    if not TAG.fullmatch(values['KERNEL_TAG']) or not SHA.fullmatch(values['KERNEL_COMMIT']):
        raise ValueError('Invalid pinned kernel tag or commit')
    return values


def select_release(advertisement, current_tag, current_commit):
    """Use peeled commit IDs for annotated tags; exclude prereleases and new series."""
    current = TAG.fullmatch(current_tag)
    if current is None:
        raise ValueError('Invalid current release tag')
    version = tuple(map(int, current.groups()))
    tags = {}
    peeled = {}
    for line in advertisement.splitlines():
        commit, ref = line.split()
        if not SHA.fullmatch(commit) or not ref.startswith('refs/tags/'):
            raise ValueError('Invalid upstream tag advertisement')
        name = ref.removeprefix('refs/tags/')
        if name.endswith('^{}'):
            peeled[name[:-3]] = commit
        else:
            tags[name] = commit
    tags.update(peeled)
    if current_tag not in tags:
        raise ValueError('Pinned release tag disappeared from upstream')
    if tags[current_tag] != current_commit:
        raise ValueError('Pinned upstream release tag moved; manual investigation required')
    releases = []
    for name, commit in tags.items():
        match = TAG.fullmatch(name)
        if match:
            candidate = tuple(map(int, match.groups()))
            if candidate[:2] == version[:2] and candidate > version:
                releases.append((candidate, name, commit))
    if not releases:
        return None
    _, name, commit = max(releases)
    return name, commit


def set_output(**values):
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        with open(output, 'a') as stream:
            for key, value in values.items():
                stream.write(f'{key}={value}\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='report updates without changing files')
    args = parser.parse_args()
    lock_path = ROOT / 'kernel-version.env'
    lock = read_lock(lock_path)
    kernel = ROOT / 'WSL2-Linux-Kernel'
    gitlink = run('git', 'ls-files', '--stage', '--', 'WSL2-Linux-Kernel').split()
    if len(gitlink) < 3 or gitlink[:3] != ['160000', lock['KERNEL_COMMIT'], '0']:
        raise ValueError('Submodule gitlink and source lock disagree')
    repository = run('git', 'config', '-f', '.gitmodules', '--get', 'submodule.WSL2-Linux-Kernel.url')
    if repository != lock['KERNEL_REPOSITORY']:
        raise ValueError('Submodule URL and source lock disagree')
    current = TAG.fullmatch(lock['KERNEL_TAG'])
    series = '.'.join(current.groups()[:2])
    branch = run('git', 'config', '-f', '.gitmodules', '--get', 'submodule.WSL2-Linux-Kernel.branch')
    if branch != f'linux-msft-wsl-{series}.y':
        raise ValueError('Submodule tracking branch does not match the pinned kernel series')
    advertisement = run('git', 'ls-remote', '--tags', lock['KERNEL_REPOSITORY'],
                        f'refs/tags/linux-msft-wsl-{series}.*')
    release = select_release(advertisement, lock['KERNEL_TAG'], lock['KERNEL_COMMIT'])
    if release is None:
        set_output(changed='false')
        print(f'Already at the newest stable {series} release: {lock["KERNEL_TAG"]}')
        return 0
    tag, commit = release
    if args.check:
        set_output(changed='true', tag=tag, commit=commit)
        print(f'Available: {tag} ({commit})')
        return 0
    if run('git', 'status', '--porcelain', cwd=kernel):
        raise ValueError('Kernel submodule contains local changes; refusing update')
    if run('git', 'rev-parse', 'HEAD', cwd=kernel) != lock['KERNEL_COMMIT']:
        raise ValueError('Kernel checkout does not match the recorded source pin')
    # Fetch and verify the tag again before changing the checkout.
    subprocess.run(['git', 'fetch', '--depth=1', lock['KERNEL_REPOSITORY'], f'refs/tags/{tag}'],
                   cwd=kernel, check=True)
    if run('git', 'rev-parse', 'FETCH_HEAD^{commit}', cwd=kernel) != commit:
        raise ValueError('Release tag changed during fetch; refusing update')
    subprocess.run(['git', 'checkout', '--detach', commit], cwd=kernel, check=True)
    contents = lock_path.read_text()
    contents = re.sub(r'^KERNEL_TAG=.*$', f'KERNEL_TAG={tag}', contents, flags=re.MULTILINE)
    contents = re.sub(r'^KERNEL_COMMIT=.*$', f'KERNEL_COMMIT={commit}', contents, flags=re.MULTILINE)
    lock_path.write_text(contents)
    subprocess.run(['git', 'add', '--', 'WSL2-Linux-Kernel', 'kernel-version.env'], cwd=ROOT, check=True)
    set_output(changed='true', tag=tag, commit=commit)
    print(f'Updated source pin and submodule to {tag} ({commit}); validate before committing.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
