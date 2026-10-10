# Enabling eBPF in WSL2 — Custom Kernel for Tetragon & OTel OBI

Build a reproducible x86-64 WSL2 kernel profile for Docker Engine, Tetragon,
Cilium, OpenTelemetry OBI, and transparent proxy workloads. Microsoft's kernel
already enables much of the required eBPF functionality, including BTF and
kprobes. First inspect your running kernel: a custom build is useful when you
need missing features, such as Tetragon's kprobe return override, BPF LSM
activation, or sockmap support.

The [configuration fragment](ebpf-kernel.config) pins this project's requested
profile. [KERNEL_CONFIG_EXPLAINED.md](KERNEL_CONFIG_EXPLAINED.md) explains the
options. Kernel support alone does not install or configure these applications.

## Scope and verification status

| Component | Baseline / status |
|---|---|
| Architecture | x86-64 only; ARM64 needs its own config, image path, and validation |
| Build environment | Ubuntu 24.04 on x86-64 Linux / WSL2; configuration CI uses Ubuntu 24.04 |
| Kernel source | Git submodule pinned to the release and commit in [kernel-version.env](kernel-version.env) |
| WSL | WSL2 with support for `.wslconfig` `kernel` and `kernelModules`; inspect `wsl --version` |
| Docker example | Docker Engine inside the same WSL distro; Compose v2 |
| OBI example | Versioned image selected in [examples/.env.example](examples/.env.example) |
| Automated checks | Script syntax, validator regressions, local links, Compose parsing, and Linux Kconfig resolution |
| Windows boot and workload tests | Require the runtime and smoke checks below; CI does not boot WSL |

The source pin is a reproducibility baseline, not a claim that this is the newest
or recommended security release. Review Microsoft's supported releases when
maintaining your installation. Update both entries in
[kernel-version.env](kernel-version.env) and the submodule commit together, then
repeat configuration, boot, and workload validation. Do not follow a moving upstream branch: different
kernel series can change configuration symbols and module packaging scripts.

## 1. Check the environment and install prerequisites

In Windows PowerShell:

```powershell
wsl --version
wsl --list --verbose
```

Confirm the build distro uses WSL version 2. Inside that distro:

```bash
uname -m # these instructions require x86_64
sudo apt update
sudo apt install -y git build-essential flex bison dwarves libssl-dev libelf-dev \
  cpio qemu-utils rsync python3 xz-utils bc libncurses-dev
pahole --version
```

`dwarves` supplies `pahole` for BTF generation. The detected version depends on
your installed package; it need not be exactly 1.25. `libncurses-dev` is used by
the optional `menuconfig` interface. Build on the distro's Linux filesystem
(for example, under `$HOME`), rather than a Windows `/mnt/c` directory.

## 2. Fetch the pinned kernel source

```bash
git clone https://github.com/knightfall/WSL2-enable-eBPF.git
cd WSL2-enable-eBPF
REPO_DIR="$PWD"
./scripts/prepare-kernel.sh
KERNEL_DIR="$REPO_DIR/WSL2-Linux-Kernel"
```

The setup script checks that the Git submodule commit and source lock agree,
then initializes the kernel at that exact commit. Local changes in an existing
submodule are rejected and preserved. You can also initialize a fresh clone with
`git submodule update --init --depth 1`; do not use `--remote` for ordinary builds,
because it bypasses the committed source pin.

The remaining Linux commands assume the same shell and the variables above.
After opening a new shell, set `REPO_DIR` to the absolute path of this repository
and `KERNEL_DIR` to its nested kernel checkout.

## 3. Configure and validate the kernel

```bash
"$REPO_DIR/scripts/configure-kernel.sh" "$KERNEL_DIR"
```

This backs up any previous `.config`, starts from `Microsoft/config-wsl`, merges
`ebpf-kernel.config`, preserves Microsoft's LSM list and appends `bpf`, then runs
`olddefconfig`. The validator fails if any requested value is missing, disabled,
or changed by dependency resolution. It also checks that `CONFIG_LSM` contains
`bpf`. The fragment enables `CONFIG_FUNCTION_ERROR_INJECTION` and
`CONFIG_BPF_KPROBE_OVERRIDE` for Tetragon policies using kprobe `Override` actions.

Optional interactive changes must be followed by validation:

```bash
cd "$KERNEL_DIR"
make menuconfig KCONFIG_CONFIG=.config
make olddefconfig KCONFIG_CONFIG=.config
python3 "$REPO_DIR/scripts/check-config.py" .config
grep '^CONFIG_PAHOLE_VERSION=' .config
```

If BTF configuration fails, check `pahole --version` and the Kconfig dependency
messages, then rerun configuration. Setting `CONFIG_DEBUG_INFO=y` alone cannot
select a debug-information format; Microsoft's base config supplies that choice.
Keep module BTF mismatch disabled so incompatible module BTF does not get
silently accepted.

## 4. Build and package modules

```bash
cd "$KERNEL_DIR"
# JOBS can be reduced when the WSL VM has limited memory.
make -j"${JOBS:-$(nproc)}" KCONFIG_CONFIG=.config
make KCONFIG_CONFIG=.config INSTALL_MOD_PATH="$KERNEL_DIR/modules" modules_install
make -s KCONFIG_CONFIG=.config kernelrelease > "$REPO_DIR/kernel-release.txt"

sudo ./Microsoft/scripts/gen_modules_vhdx.sh \
  "$KERNEL_DIR/modules" \
  "$(cat "$REPO_DIR/kernel-release.txt")" \
  "$KERNEL_DIR/modules.vhdx"
```

`make clean` preserves `.config`; `make mrproper` removes it. If you change the
source pin, use a fresh source checkout and module staging directory so stale
artifacts cannot be included. The packaging command above belongs to the pinned
6.6 source series; check upstream instructions when changing kernel series.

## 5. Copy artifacts and preserve a rollback path

In PowerShell, back up your existing global WSL settings before editing:

```powershell
$configPath = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $configPath) {
    Copy-Item $configPath "$configPath.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
```

Inside the WSL build shell, obtain the actual Windows profile path. A profile
directory is not necessarily `C:\Users\<USERNAME>`:

```bash
WIN_PROFILE=$(powershell.exe -NoProfile -Command '[Console]::Write($env:USERPROFILE)' | tr -d '\r\n')
test -n "$WIN_PROFILE"
WIN_KERNEL_DIR="$(wslpath -u "$WIN_PROFILE")/wsl-kernel/$(cat "$REPO_DIR/kernel-release.txt")-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$WIN_KERNEL_DIR"
cp "$KERNEL_DIR/arch/x86/boot/bzImage" "$WIN_KERNEL_DIR/bzImage"
cp "$KERNEL_DIR/modules.vhdx" "$WIN_KERNEL_DIR/modules.vhdx"
wslpath -w "$WIN_KERNEL_DIR/bzImage"
wslpath -w "$WIN_KERNEL_DIR/modules.vhdx"
```

Use a new release directory for each installation and retain the previous
artifacts until the new kernel passes runtime checks.

## 6. Configure Windows WSL

In PowerShell:

```powershell
notepad "$env:USERPROFILE\.wslconfig"
```

Add or update these keys in the existing `[wsl2]` section. Substitute the paths
printed above, doubling each backslash as shown. Use literal paths:

```ini
[wsl2]
kernel=C:\\Users\\YOUR-PROFILE\\wsl-kernel\\YOUR-INSTALL-DIRECTORY\\bzImage
kernelModules=C:\\Users\\YOUR-PROFILE\\wsl-kernel\\YOUR-INSTALL-DIRECTORY\\modules.vhdx
```

Preserve other settings and avoid duplicate `[wsl2]` sections. These settings
apply globally to WSL2 distributions. If an existing `kernelCommandLine` includes
an `lsm=` argument, it overrides `CONFIG_LSM`; preserve that argument's existing
LSMs and append `bpf`, or remove the override if it is no longer needed.

If Windows reports access denied for either artifact, grant read access to the
virtual-machine group from an Administrator PowerShell session. SID syntax also
works on non-English Windows installations:

```powershell
$kernelDir = Read-Host 'Full Windows path to the release directory created above'
icacls "$kernelDir\bzImage" /grant '*S-1-5-83-0:(R)'
icacls "$kernelDir\modules.vhdx" /grant '*S-1-5-83-0:(R)'
```

Restart WSL from PowerShell:

```powershell
wsl --shutdown
wsl
```

### Roll back if WSL fails to boot

Windows can edit `.wslconfig` even when the Linux distro cannot start. Restore
your saved configuration, or remove only `kernel` and `kernelModules` from
`[wsl2]` to return to Microsoft's managed kernel. If you added an `lsm=` override
for this setup, restore its previous value too. Then run `wsl --shutdown` and
start the distro again. Keep other WSL settings intact.

## 7. Mount filesystems and verify the running kernel

Inside the WSL distro using the custom kernel:

```bash
mountpoint -q /sys/fs/bpf || sudo mount -t bpf bpffs /sys/fs/bpf
mountpoint -q /sys/kernel/tracing || sudo mount -t tracefs tracefs /sys/kernel/tracing
mountpoint -q /sys/kernel/security || sudo mount -t securityfs securityfs /sys/kernel/security
findmnt -T /sys/fs/cgroup # expected: cgroup2
```

To persist mounts, add the following entries to `/etc/fstab` once, preserving
existing entries:

```fstab
bpffs /sys/fs/bpf bpf defaults 0 0
tracefs /sys/kernel/tracing tracefs defaults 0 0
securityfs /sys/kernel/security securityfs defaults 0 0
```

WSL processes `/etc/fstab` when `[automount] mountFsTab=true` in `/etc/wsl.conf`
(the default); systemd is not required for that mechanism. If you use systemd to
run Docker Engine, enable it separately:

```ini
# /etc/wsl.conf — merge into any existing [boot] section
[boot]
systemd=true
```

After changing `wsl.conf`, restart with `wsl --shutdown` from Windows. Install
`bpftool` using a distro package or build it from the pinned kernel's
`tools/bpf/bpftool` source. Some `linux-tools` wrappers require a binary matching
the running kernel, so verify that `bpftool version` actually works.

```bash
sudo "$REPO_DIR/scripts/verify-runtime.sh" "$(cat "$REPO_DIR/kernel-release.txt")"
```

This checks the expected kernel release, embedded configuration, readable kernel
BTF, filesystem types, active BPF LSM, and available BPF program/map types.
It runs Tetragon's probes when `tetra` is installed. Before using enforcement,
install the CLI matching your Tetragon deployment and run:

```bash
tetra probe config
sudo tetra probe
```

Check `override_return` and `lsm` in the probe output, then exercise your actual
policy against a disposable target. A successful kernel probe does not prove a
specific policy, application runtime, or Cilium networking mode works.

## 8. Run OBI with Docker Engine inside WSL

Use Docker Engine running in this distro and mount the host filesystems **before**
starting the agent. Check `docker context show` and `docker info` to confirm which
daemon the CLI uses. The agent needs the daemon host's PID namespace and
filesystems, which may differ from those of the shell running Compose.

The [Compose example](examples/compose.yaml) supplies `pid: host`, the capabilities
used by application instrumentation and context propagation, and host mounts for
bpffs, tracefs, and cgroup v2. It relaxes the agent's AppArmor and seccomp profiles
and grants broad `SYS_ADMIN` access; review and narrow permissions for your
selected OBI features using the official capability guide. It fails early when
required capabilities are absent. Mounting existing bpffs before startup makes
pinned maps visible through a normal bind; shared propagation is unnecessary for
this example.

```bash
cd "$REPO_DIR"
cp examples/.env.example examples/.env
docker compose --env-file examples/.env -f examples/compose.yaml config --quiet
docker compose --env-file examples/.env -f examples/compose.yaml --profile demo up -d
curl http://localhost:18080/
docker compose --env-file examples/.env -f examples/compose.yaml logs obi
```

Repeat the request after the agent finishes attaching. Confirm the logs contain
an HTTP trace for the demo server. The example prints traces locally; configure
an OTLP exporter separately when you want to send telemetry to a Collector.
Clean up the smoke workload with:

```bash
docker compose --env-file examples/.env -f examples/compose.yaml --profile demo down
```

To observe your own application, omit `--profile demo` and set `SERVICE_PORT` to
the target process's listening port inside its container. Select the appropriate
versioned OBI image in `examples/.env`. The base example leaves context
propagation at OBI's default; enable it deliberately and test requests between
your services. The tracefs and cgroup mounts are already supplied for modes that
need them. Log enrichment and profile correlation have their own application
and OBI configuration requirements; mounting bpffs alone does not enable them.

### Docker Desktop

Docker Desktop runs its daemon in a separate environment. Do not assume that
mounting bpffs in a user distro mounts it on Desktop's daemon host, or that
`pid: host` refers to that user distro's processes. Docker explicitly documents
that mount propagation does not work with Desktop. The example above targets
Docker Engine inside WSL; Desktop needs separate validation for the precise
version, daemon mounts, and target-process visibility. `privileged: true` does
not correct a namespace or filesystem mismatch.

## Maintenance and local checks

A custom `kernel=` setting bypasses Microsoft's managed kernel selection.
Rebuild and repeat runtime and workload checks when updating the source pin.
Cilium feature requirements vary by routing, encryption, and device mode; for
example, the 6.6 baseline cannot supply features requiring kernel 6.8 or newer.

```bash
python3 -m unittest discover -s tests -v
python3 scripts/check-links.py
for script in scripts/*.sh; do bash -n "$script"; done
```

[Configuration CI](.github/workflows/validate.yml) also runs ShellCheck, parses
Compose, fetches the pinned source, merges the fragment, resolves Kconfig on
Linux, and uploads the resulting `.config`. CI success establishes configuration
resolution, not a complete kernel build or WSL boot.

### Scheduled upstream updates

[The upstream update workflow](.github/workflows/update-kernel.yml) runs weekly
on Monday at 03:17 UTC and can be started manually from GitHub Actions. It checks
Microsoft's stable release tags in the currently pinned kernel series (initially
6.6), selects the newest version numerically, and updates both the submodule
gitlink and `kernel-version.env`. New kernel series and prerelease tags are
excluded; changing kernel series requires a separate compatibility review.

When an update exists, the workflow validates the repository and resolves Kconfig
on Linux before pushing the managed `automation/update-wsl-kernel` branch and
opening or refreshing its pull request. It never merges automatically. Unchanged
upstream state avoids downloading the kernel and creates no commit or pull
request. An identical pending update preserves its existing commit and review
state. A moved or missing pinned tag fails the run for manual investigation.

The workflow uses the repository's `GITHUB_TOKEN` with write permissions limited
to its update job. Under **Settings → Actions → General → Workflow permissions**,
allow GitHub Actions to create pull requests; the default token permission can
remain read-only. Pull-request checks created by `GITHUB_TOKEN` may need a
maintainer to approve them. The update run itself validates configuration before
publishing; build, WSL boot, and workload smoke checks remain required before
merging the update. The schedule becomes active only after this workflow is on
the repository's default branch.

For a read-only local update check:

```bash
python3 scripts/update-kernel.py --check
```

## Upstream references

- [Microsoft's 6.6 kernel build instructions](https://github.com/microsoft/WSL2-Linux-Kernel/blob/linux-msft-wsl-6.6.y/README.md)
- [WSL configuration, custom kernels, and fstab processing](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
- [Tetragon runtime probes](https://tetragon.io/docs/installation/faq/)
- [Tetragon BPF LSM activation](https://tetragon.io/docs/concepts/tracing-policy/hooks/)
- [Tetragon Override action](https://tetragon.io/docs/concepts/tracing-policy/selectors/)
- [OBI Docker setup](https://opentelemetry.io/docs/zero-code/obi/setup/docker/)
- [OBI capabilities](https://opentelemetry.io/docs/zero-code/obi/security/)
- [Docker bind mounts and propagation](https://docs.docker.com/engine/storage/bind-mounts/)
- [Cilium kernel and feature requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)
