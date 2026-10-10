#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
if [[ $# != 1 || -z "$1" ]]; then
    printf 'Usage: sudo %s <expected-kernel-release>\n' "$0" >&2
    exit 1
fi
if [[ "$(uname -s)" != Linux || "$EUID" != 0 ]]; then
    printf 'Run this check as root inside the WSL2 distro using the custom kernel.\n' >&2
    exit 1
fi
if [[ "$(uname -r)" != "$1" ]]; then
    printf 'Running kernel is %s; expected %s.\n' "$(uname -r)" "$1" >&2
    exit 1
fi
for tool in python3 findmnt bpftool gzip; do
    if ! command -v "$tool" >/dev/null; then
        printf 'Missing validation tool: %s\n' "$tool" >&2
        exit 1
    fi
done
if [[ ! -s /sys/kernel/btf/vmlinux ]]; then
    printf 'Kernel BTF is missing at /sys/kernel/btf/vmlinux.\n' >&2
    exit 1
fi
for spec in /sys/fs/bpf:bpf /sys/kernel/tracing:tracefs /sys/fs/cgroup:cgroup2 /sys/kernel/security:securityfs; do
    path=${spec%:*}
    expected_type=${spec##*:}
    if [[ "$(findmnt --noheadings --output FSTYPE --target "$path")" != "$expected_type" ]]; then
        printf 'Expected %s mounted at %s; see the README mount instructions.\n' "$expected_type" "$path" >&2
        exit 1
    fi
done
if ! grep -Eq '(^|,)bpf(,|$)' /sys/kernel/security/lsm; then
    printf 'BPF LSM is not active; inspect CONFIG_LSM and any lsm= boot override.\n' >&2
    exit 1
fi

scratch_dir=$(mktemp -d)
trap 'rm -rf -- "$scratch_dir"' EXIT
gzip -dc /proc/config.gz > "$scratch_dir/config"
python3 "$repo_dir/scripts/check-config.py" "$scratch_dir/config"
bpftool -j feature probe kernel > "$scratch_dir/features.json"
python3 - "$scratch_dir/features.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as stream:
    features = json.load(stream)
required = {
    'program_types': ['have_kprobe_prog_type', 'have_tracepoint_prog_type',
                      'have_sched_cls_prog_type', 'have_lsm_prog_type', 'have_sk_msg_prog_type'],
    'map_types': ['have_hash_map_type', 'have_ringbuf_map_type'],
}
missing = [name for group, names in required.items() for name in names
           if features.get(group, {}).get(name) is not True]
if missing:
    sys.exit('Missing runtime BPF features: ' + ', '.join(missing))
print('Kernel BTF, mounts, active BPF LSM, and BPF program/map probes passed.')
PY

if command -v tetra >/dev/null; then
    tetra probe config
    tetra probe
else
    printf 'Tetragon probe skipped: install tetra and run sudo tetra probe before using enforcement.\n'
fi
