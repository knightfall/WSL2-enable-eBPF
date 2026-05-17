# Enabling eBPF in WSL2 — Custom Kernel for Tetragon & OTel OBI

## Overview

This guide covers building and installing a custom WSL2 kernel to enable eBPF features required for **Tetragon** and **OpenTelemetry OBI** (eBPF-based instrumentation). It also covers fixing the `bpffs` mount issue when running OBI via Docker Compose.

---

## Prerequisites

```bash
sudo apt update && sudo apt install build-essential flex bison dwarves libssl-dev libelf-dev cpio qemu-utils
```

> `dwarves` provides `pahole`, which is required for BTF generation. Verify it's present and working:
> ```bash
> pahole --version
> scripts/pahole-version.sh pahole  # should return 125 for v1.25
> ```

---

## 1. Clone or update the WSL2 Kernel Source

This repository includes `WSL2-Linux-Kernel` as a git submodule, it may be out of date. Make sure the submodule is updated to its primary upstream branch before building.

```bash
git submodule update --init --remote --checkout --recursive
cd ~/WSL2-Linux-Kernel
```

---

## 2. Configure the Kernel

Start from Microsoft's WSL2 config:

```bash
cp Microsoft/config-wsl .config
```

Optionally customise interactively:

```bash
make menuconfig KCONFIG_CONFIG=.config
```

### Fix `CONFIG_PAHOLE_VERSION=0`

Check if `pahole` is detected properly:

```bash
grep CONFIG_PAHOLE_VERSION .config
```

If `pahole` is installed but `CONFIG_PAHOLE_VERSION` is still `0`, regenerate the config so detection runs properly:

```bash
make oldconfig KCONFIG_CONFIG=.config
grep CONFIG_PAHOLE_VERSION .config
# Expected: CONFIG_PAHOLE_VERSION=125
```

### Key config decisions for Tetragon / OBI

| Prompt | Answer | Reason |
|---|---|---|
| `MODULE_ALLOW_BTF_MISMATCH` | `N` (default) | BTF mismatch would silently break BPF CO-RE |
| `NET_SCH_BPF` | `N` (default) | BPF qdisc — not needed for observability |

---

## 2.5 Apply the eBPF Stack Config Addendum

Microsoft's `config-wsl` is intentionally minimal. To run **Docker + Tetragon + Cilium + OBI + Envoy** on this kernel, you need a sizeable set of additional options (BTF, tc-BPF, LWT-BPF, sockmap, conntrack, virtual netdevs, WireGuard, etc.). The repo ships these as a single fragment at [ebpf-stack.config](ebpf-stack.config).

Merge it on top of the base config and let kconfig resolve dependencies:

```bash
cd ~/WSL2-Linux-Kernel

# Merge the addendum into .config (preserves existing values, adds new ones)
./scripts/kconfig/merge_config.sh -m .config ../ebpf-stack.config

# Let kconfig pick defaults for any newly-exposed sub-options
make olddefconfig KCONFIG_CONFIG=.config
```

> Adjust the path to `ebpf-stack.config` for wherever you cloned this repo. Inside WSL2, Windows paths are accessible under `/mnt/<drive>/...`.

### Verify the critical options stuck

```bash
grep -E '^CONFIG_(DEBUG_INFO_BTF|FTRACE|KPROBE_EVENTS|UPROBES|UPROBE_EVENTS|BPF_LSM|CGROUP_BPF|NET_CLS_BPF|NET_ACT_BPF|LWTUNNEL_BPF|BPF_STREAM_PARSER|NF_CONNTRACK|NF_TABLES|VETH|VXLAN|WIREGUARD|OVERLAY_FS|XDP_SOCKETS|INET|IPV6|NETDEVICES|CRYPTO|XFRM_USER)=' .config
```

Every line should report `=y`. If something is missing it means a parent option (typically `NETDEVICES`, `INET`, `CRYPTO`, or `NET_SCHED`) was disabled — fix the parent and re-run `olddefconfig`.

> **Why a fragment instead of editing `.config` directly?** `make olddefconfig` (and any future config refresh) will silently drop options whose parent dependencies are off. Keeping the desired options in a separate file lets you re-apply them cleanly after every kernel-tag rebase.

---

## 3. Build the Kernel

```bash
cd ~/WSL2-Linux-Kernel

# Optional clean if previous build exists
make clean KCONFIG_CONFIG=.config
# Note: make mrproper would wipe .config — don't use it

make -j$(nproc) KCONFIG_CONFIG=.config && \
  make INSTALL_MOD_PATH="$HOME/WSL2-Linux-Kernel/modules" modules_install
```

---

## 4. Package Modules into a VHDX

```bash
sudo ./Microsoft/scripts/gen_modules_vhdx.sh \
  "$HOME/WSL2-Linux-Kernel/modules" \
  $(make -s kernelrelease) \
  "$HOME/WSL2-Linux-Kernel/modules.vhdx"
```

---

## 5. Copy Artifacts to Windows

```bash
WIN_USER=$(powershell.exe -NoProfile -Command '[Console]::Write($env:USERNAME)' 2>/dev/null | tr -d '\r\n')
WIN_KERNEL_DIR="/mnt/c/Users/$WIN_USER/wsl-kernel"
mkdir -p "$WIN_KERNEL_DIR"

cp ~/WSL2-Linux-Kernel/arch/x86/boot/bzImage "$WIN_KERNEL_DIR/bzImage"
cp ~/WSL2-Linux-Kernel/modules.vhdx       "$WIN_KERNEL_DIR/modules.vhdx"
```

---

## 6. Configure `.wslconfig`

Open `%USERPROFILE%\.wslconfig` in PowerShell (creates it if missing):

```powershell
notepad "$env:USERPROFILE\.wslconfig"
```

Under a `[wsl2]` section, add (or update) these lines — substitute your own username for `sazid`. `.wslconfig` does not expand environment variables, so the paths must be literal:

```ini
[wsl2]
kernel=C:\\Users\\sazid\\wsl-kernel\\bzImage
kernelModules=C:\\Users\\sazid\\wsl-kernel\\modules.vhdx
```

If the file already exists with other settings, leave them and just add/update `kernel` and `kernelModules` inside the `[wsl2]` section.

---

## 7. Fix ACL — Access Denied on WSL Start

HCS (Host Compute Service) runs as `NT VIRTUAL MACHINE\Virtual Machines` and needs explicit read access. Run in **PowerShell as Administrator**:

```powershell
icacls "$env:USERPROFILE\wsl-kernel\bzImage"      /grant "NT VIRTUAL MACHINE\Virtual Machines:(R)"
icacls "$env:USERPROFILE\wsl-kernel\modules.vhdx" /grant "NT VIRTUAL MACHINE\Virtual Machines:(R)"
```

---

## 8. Restart WSL

```powershell
wsl --shutdown
wsl
```

Verify:

```bash
uname -r
```

---

## 9. Fix bpffs for OBI in Docker Compose

OBI uses pinned BPF maps at `/sys/fs/bpf/otel` for the log enricher and profile correlation features. When running OBI in a Docker container, the bpffs must be mounted on the host and propagated into the container.

### Mount bpffs on the host

```bash
sudo mount -t bpf bpffs /sys/fs/bpf
mount | grep bpf  # verify
```

To persist across WSL restarts (requires `systemd=true` in `/etc/wsl.conf`):

```
# /etc/fstab
bpffs /sys/fs/bpf bpf defaults 0 0
```

### Docker Compose configuration

Add to your OBI service in `docker-compose.yml`:

```yaml
services:
  obi:
    # ...
    volumes:
      - type: bind
        source: /sys/fs/bpf
        target: /sys/fs/bpf
        bind:
          propagation: shared
    cap_add:
      - SYS_ADMIN
      - NET_ADMIN
    security_opt:
      - apparmor:unconfined
```

> Or use `privileged: true` as a shortcut, accepting the broader security tradeoff.

Without this, OBI will still instrument processes (node, dotnet, envoy, etc.) but the following features will be disabled:
- **Log enricher** (`logenricher=false`)
- **Profile correlation**

---

## Notes

- Microsoft's latest kernel release as of May 2026 is `linux-msft-wsl-6.6.123.2` — newer than `6.6.114.1`. Auto-updates from Microsoft stop once you pin a custom kernel via `.wslconfig`. Factor in the maintenance burden of rebasing onto new tags for security patches.
- Docker Desktop does **not** officially support custom WSL2 kernels. It may still work, but breakage is unsupported.
- `make clean` removes compiled objects but preserves `.config`. Never use `make mrproper` unless you intend to wipe the config.