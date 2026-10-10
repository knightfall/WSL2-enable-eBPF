#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../kernel-version.env
source "$repo_dir/kernel-version.env"
kernel_dir=${1:-"$repo_dir/WSL2-Linux-Kernel"}

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    printf 'Configuration requires an x86-64 Linux build host (WSL2 or Linux CI).\n' >&2
    exit 1
fi
if [[ ! -d "$kernel_dir/.git" && ! -f "$kernel_dir/.git" ]]; then
    printf 'Run scripts/prepare-kernel.sh first.\n' >&2
    exit 1
fi
if [[ "$(git -C "$kernel_dir" rev-parse HEAD)" != "$KERNEL_COMMIT" ]]; then
    printf 'Kernel source does not match kernel-version.env.\n' >&2
    exit 1
fi
if ! git -C "$kernel_dir" diff --quiet || ! git -C "$kernel_dir" diff --cached --quiet; then
    printf 'Kernel source has tracked changes; preserve them and use a clean checkout.\n' >&2
    exit 1
fi
for tool in make gcc flex bison pahole python3; do
    if ! command -v "$tool" >/dev/null; then
        printf 'Missing build dependency: %s\n' "$tool" >&2
        exit 1
    fi
done

cd -- "$kernel_dir"
if [[ -f .config ]]; then
    # mktemp avoids overwriting an earlier backup on repeated configuration runs.
    backup=$(mktemp .config.backup.XXXXXX)
    cp .config "$backup"
    printf 'Previous configuration saved as %s/%s\n' "$kernel_dir" "$backup"
fi
cp Microsoft/config-wsl .config
bash scripts/kconfig/merge_config.sh -m .config "$repo_dir/ebpf-kernel.config"

# Compilation and activation are separate. Preserve Microsoft's LSM order and
# append bpf instead of replacing the existing list with a hand-written one.
lsm_list=$(scripts/config --file .config --state LSM)
lsm_list=${lsm_list#\"}
lsm_list=${lsm_list%\"}
if [[ -z "$lsm_list" || "$lsm_list" == undef ]]; then
    printf 'Base CONFIG_LSM is missing; refusing to replace the LSM list.\n' >&2
    exit 1
fi
case ",$lsm_list," in
    *,bpf,*) ;;
    *) scripts/config --file .config --set-str LSM "$lsm_list,bpf" ;;
esac

make ARCH=x86 olddefconfig KCONFIG_CONFIG=.config
python3 "$repo_dir/scripts/check-config.py" .config
