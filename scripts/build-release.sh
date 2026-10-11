#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_dir"
# shellcheck source=../kernel-version.env
source "$repo_dir/kernel-version.env"
kernel_dir="$repo_dir/WSL2-Linux-Kernel"
out="$repo_dir/dist"
# Require fresh staging so previous modules cannot leak into a release.
if [[ -e "$kernel_dir/modules" || -e "$kernel_dir/headers" || -e "$kernel_dir/perf" || -e "$out" ]]; then
    printf 'Use a fresh checkout without dist/, modules/, headers/, or perf/ for release builds.\n' >&2
    exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
    printf 'Commit tracked build inputs before packaging release source.\n' >&2
    exit 1
fi
scripts/prepare-kernel.sh
scripts/configure-kernel.sh
mkdir "$out"
make -C "$kernel_dir" -j"${JOBS:-$(nproc)}" KCONFIG_CONFIG=.config
make -C "$kernel_dir" KCONFIG_CONFIG=.config INSTALL_MOD_PATH="$kernel_dir/modules" modules_install
release=$(make -s -C "$kernel_dir" KCONFIG_CONFIG=.config kernelrelease)
make -C "$kernel_dir" KCONFIG_CONFIG=.config headers_install INSTALL_HDR_PATH="$kernel_dir/headers"
make -C "$kernel_dir/tools/perf" -j"${JOBS:-$(nproc)}" NO_JEVENTS=1 NO_JVMTI=1 NO_LIBTRACEEVENT=1 install DESTDIR="$kernel_dir/perf" prefix=/
sudo "$kernel_dir/Microsoft/scripts/gen_artifacts_vhdx.sh" "$kernel_dir/modules" "$kernel_dir/headers" "$kernel_dir/perf" "$release" "$out/modules.vhdx"
sudo chown "$(id -u):$(id -g)" "$out/modules.vhdx"
cp "$kernel_dir/arch/x86/boot/bzImage" "$out/bzImage"
cp "$kernel_dir/.config" "$out/kernel.config"
cp ebpf-kernel.config kernel-version.env scripts/verify-runtime.sh scripts/check-config.py "$out/"
printf '%s\n' "$release" > "$out/kernel-release.txt"
printf 'repository_commit=%s\narchitecture=x86_64\n' "$(git rev-parse HEAD)" > "$out/build-info.txt"
# Include the exact upstream source, licenses, and first-party build inputs.
git -C "$kernel_dir" archive --format=tar --prefix=WSL2-Linux-Kernel/ "$KERNEL_COMMIT" | xz -T2 > "$out/kernel-source.tar.xz"
git archive --format=tar --prefix=WSL2-enable-eBPF/ HEAD | xz -T2 > "$out/build-source.tar.xz"
cp "$kernel_dir/COPYING" "$out/KERNEL-COPYING"
cp scripts/Install-WslEbpfKernel.ps1 "$out/"
(cd "$out" && sha256sum bzImage modules.vhdx kernel.config ebpf-kernel.config kernel-version.env verify-runtime.sh check-config.py kernel-release.txt build-info.txt kernel-source.tar.xz build-source.tar.xz KERNEL-COPYING Install-WslEbpfKernel.ps1 > SHA256SUMS)
