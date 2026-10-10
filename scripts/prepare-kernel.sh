#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../kernel-version.env
source "$repo_dir/kernel-version.env"
kernel_dir="$repo_dir/WSL2-Linux-Kernel"

if [[ $# != 0 ]]; then
    printf 'Usage: %s (initializes the pinned kernel submodule)\n' "$0" >&2
    exit 1
fi
gitlink=$(git -C "$repo_dir" ls-files --stage -- WSL2-Linux-Kernel | awk '$1 == "160000" { print $2 }')
if [[ "$gitlink" != "$KERNEL_COMMIT" ]]; then
    printf 'Submodule commit and kernel-version.env disagree; update them together.\n' >&2
    exit 1
fi
if [[ "$(git -C "$repo_dir" config -f .gitmodules --get submodule.WSL2-Linux-Kernel.url)" != "$KERNEL_REPOSITORY" ]]; then
    printf 'Submodule URL and kernel-version.env disagree.\n' >&2
    exit 1
fi
if [[ -e "$kernel_dir/.git" ]]; then
    if [[ -n "$(git -C "$kernel_dir" status --porcelain --untracked-files=normal)" ]]; then
        printf 'Kernel checkout contains local changes; preserve them before proceeding.\n' >&2
        exit 1
    fi
fi
git -C "$repo_dir" submodule update --init --depth 1 -- WSL2-Linux-Kernel
if [[ "$(git -C "$kernel_dir" rev-parse HEAD)" != "$KERNEL_COMMIT" ]]; then
    printf 'Initialized submodule does not match the recorded kernel commit.\n' >&2
    exit 1
fi
printf 'Kernel submodule: %s (%s, %s)\n' "$kernel_dir" "$KERNEL_TAG" "$KERNEL_COMMIT"
