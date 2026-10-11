# WSL2 eBPF Kernel Configuration — Explained

This document explains the options in `ebpf-kernel.config` and their deployment
conditions. Mechanism descriptions follow the pinned 6.18.54.1 kernel source;
application use must be checked against the selected application version.
Each entry covers **what it is**, **which workloads use it**, and links to upstream documentation.

This is a requested kernel profile, not a list of features missing from stock
WSL2 or mandatory for every workload. Most options are inherited from Microsoft's
base config. Use `scripts/configure-kernel.sh` to apply the fragment and preserve
the upstream LSM list; use `scripts/check-config.py` to validate the resolved
configuration. The source baseline is recorded in `kernel-version.env`.

---

The [assurance case](docs/ASSURANCE_CASE.md) and its preserved claim ledger
record the factual review and corrected historical findings. The ledger is audit
history, not a replacement for the current option descriptions. Configuration
comparison and build evidence do not certify application behavior.

## OBI-only use and the upstream baseline

For OBI alone, begin with the managed Microsoft kernel and the
[OBI-only setup path](README.md). Comparing Microsoft's 6.6.123.2 and 6.18.54.1
base configs shows that BPF, kernel BTF, kprobe/uprobe events, perf events, and
cgroup-BPF are already enabled. Both versions provide tc-BPF and ingress as
modules. Modes using tc need those matching modules available; making them
built-in is a packaging choice, not an OBI requirement.

OBI requires exposed BTF and feature-specific privileges, as described in its
[official support matrix](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/blob/main/SUPPORT_MATRIX.md)
and [capability guide](https://opentelemetry.io/docs/zero-code/obi/security/).
The source comparison does not establish live OBI compatibility on a particular
WSL installation. BPF LSM activation, kprobe return override, receive-side stream parsing/LWT support,
legacy iptables, TPROXY, and encryption support serve other workloads in this
combined profile. OBI network propagation does use SK_MSG/sockhash; both compared
configs already enable `NET_SOCK_MSG`. Do not confuse that with the optional
`BPF_STREAM_PARSER` receive-side attachment. See the README for pinned source evidence. The validator intentionally requires the whole profile and
must not be used as an OBI-only compatibility check.

## Exact source comparison for this upgrade

Reviewed on 2026-10-11 against Microsoft tags **6.6.123.2** and **6.18.54.1**
and OBI **v0.14.0**. The source pin is immutable; the installed managed WSL
kernel must be inspected separately.

| Setting | 6.6.123.2 base | 6.18.54.1 base | Custom profile |
|---|---|---|---|
| Core BPF/BTF, kprobe/uprobe events, perf, cgroup-BPF | `y` | `y` | Retained |
| `BPF_LSM` | `y` | `y` | Retained |
| `bpf` in `CONFIG_LSM` | Absent | Present | Ensure present without replacing other LSMs |
| `NET_SOCK_MSG` / `STREAM_PARSER` | `y` / `y` | `y` / `y` | Inherited; socket-message support already exists |
| `BPF_STREAM_PARSER` | Disabled | Disabled | `y`; optional receive-side parser |
| `FUNCTION_ERROR_INJECTION` / `BPF_KPROBE_OVERRIDE` | Disabled | Disabled | `y`; kprobe enforcement |
| `LWTUNNEL` / `LWTUNNEL_BPF` | Disabled | Disabled | `y`; optional per-route processing |
| `NETFILTER_XTABLES_LEGACY` | Symbol absent | `y` | `y`; new parent asserted |
| `IP_NF_IPTABLES_LEGACY` / `IP6_NF_IPTABLES_LEGACY` | Symbols absent | `m` | `y`; permit built-in legacy tables |
| tc, selected legacy netfilter/devices/encryption, `IKHEADERS` | Mostly `m` | Mostly `m` | Selected options promoted to `y` |
| `LOCALVERSION` | `-microsoft-standard-WSL2` | Same | Add `-ebpf` suffix |

Against the 6.18 base, the fragment changes 39 requested assignments: five
from disabled to built-in, 33 from modules to built-in, and the version suffix.
The remaining requested assignments already match upstream. This comparison
covers the fragment's explicit assignments, not every difference between the
upstream kernel configurations or additional values selected by Kconfig.
Linux CI resolves the full fragment; configuration success is separate from
compilation, WSL boot, module loading, and workload acceptance.

Evidence: [6.6 base](https://github.com/microsoft/WSL2-Linux-Kernel/blob/a07f9ea8a99139913acbcc1c160b132cb2a49c81/Microsoft/config-wsl),
[6.18 x86 base](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/arch/x86/configs/config-wsl),
[pinned socket attachment guards](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/core/sock_map.c),
and [OBI context injector](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/blob/v0.14.0/bpf/tpinjector/tpinjector.c).

## Target workloads

| Tool | Purpose |
|---|---|
| **Docker** | Container runtime using an installation-dependent storage backend and network mode |
| **Tetragon** | Cilium's runtime security agent — uses kprobes, tracepoints, and BPF-LSM for enforcement |
| **Cilium** | eBPF-native CNI — tc-BPF datapath, conntrack, overlay encapsulation, WireGuard/IPsec; requirements vary by mode |
| **OpenTelemetry OBI** | eBPF-based auto-instrumentation — uprobes, CO-RE, process discovery, and optional context propagation |
| **Envoy** | L7 proxy — optional TPROXY interception; kernel support does not enable application kTLS or sockmap integration |

---

## 1 · Networking baseline

> These are already present in the pinned Microsoft base configuration. The fragment asserts them as part of this profile, and the validator checks that dependency resolution preserves the requested values.

### `CONFIG_INET`
Enables the IPv4 protocol suite, including TCP, UDP, ICMP, and IPv4 raw
sockets. IPv4 workloads require it; local Unix sockets and individual BPF
program types have different dependencies.
- [Pinned IPv4 Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/ipv4/Kconfig)

### `CONFIG_IPV6`
Enables the **IPv6 protocol stack**. Used by dual-stack networking workloads. Requirements depend on the address families and OBI features in use; this profile preserves IPv6 support.
- [Kconfig: CONFIG_IPV6](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/ipv6/Kconfig)

### `CONFIG_NETDEVICES`
Gates the network-device driver menu, including veth and TUN/TAP. Normal
container networking requires suitable drivers. Loopback is built under
`CONFIG_NET`, and bridge support has separate Kconfig/build rules.
- [Pinned driver Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/drivers/net/Kconfig)
- [Pinned driver Makefile](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/drivers/net/Makefile)
- [Pinned bridge Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/bridge/Kconfig)

### `CONFIG_CRYPTO`
Enables the kernel Crypto API used by consumers such as kernel TLS and IPsec.
Algorithm implementations have their own configuration options. WireGuard's
pinned Kconfig selects `CRYPTO_LIB_CURVE25519` and
`CRYPTO_LIB_CHACHA20POLY1305` library primitives; those should not be conflated
with a requirement to use the general Crypto API framework.
- [Pinned Crypto API Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/crypto/Kconfig)
- [Pinned WireGuard dependencies](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/drivers/net/Kconfig)

### `CONFIG_KEYS`
Provides kernel key retention and keyrings used by facilities such as
network-filesystem authentication, encrypted keys, and trusted public-key
verification. It is not a general TLS session-key or XFRM security-association
store: kTLS receives symmetric keys through socket options, while XFRM receives
SA/key configuration through its own interfaces.
- [Kernel key service](https://docs.kernel.org/security/keys/core.html)
- [Kernel TLS API](https://docs.kernel.org/networking/tls.html)
- [Module signatures](https://docs.kernel.org/admin-guide/module-signing.html)

---

## 2 · BTF / CO-RE — kernel BTF for observability, optional module coverage

> **CO-RE** (Compile Once – Run Everywhere) relocates supported type and field accesses using target-kernel BTF at load
time. It improves portability without compiling on the target, but cannot supply
missing helpers, hooks, or kernel features; it does not guarantee compatibility
with every kernel version.

### `CONFIG_DEBUG_INFO`
Instructs the compiler to embed **DWARF debug information** in kernel objects.
`CONFIG_DEBUG_INFO_BTF` depends on this to generate BTF from the DWARF data via `pahole` (v1.16+, v1.21+ for DWARF 5).
In this kernel series, `DEBUG_INFO` is selected by the debug-information format
choice. Microsoft's base config selects `DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT`;
writing `CONFIG_DEBUG_INFO=y` alone cannot override a `DEBUG_INFO_NONE` choice.
- [Kernel docs: BTF](https://www.kernel.org/doc/html/latest/bpf/btf.html)

### `CONFIG_DEBUG_INFO_BTF`
Generates BTF type metadata for `vmlinux`, normally exposed at
`/sys/kernel/btf/vmlinux`. CO-RE loaders use relevant target types and fields for
relocation; BTF is not a complete description of all kernel implementation
information. Tools read it when the selected operation needs it, rather than
necessarily on every startup. Kernel headers are normally unnecessary for
loading a precompiled CO-RE object, but other workflows can still need headers.
- [Kernel BTF documentation](https://docs.kernel.org/bpf/btf.html)
- [libbpf CO-RE](https://docs.kernel.org/bpf/libbpf/libbpf_overview.html)

### `CONFIG_DEBUG_INFO_BTF_MODULES`
Extends BTF coverage to **loadable kernel modules**. Useful for BPF programs that depend on types or attachment targets in modules. This is not a blanket OBI prerequisite: its documented baseline requires exposed kernel BTF. Microsoft already enables module BTF in the compared configurations.
- [Kernel docs: BTF](https://www.kernel.org/doc/html/latest/bpf/btf.html)
- [BCC to libbpf conversion guide — Nakryiko](https://nakryiko.com/posts/bcc-to-libbpf-howto-guide/)

---

## 3 · BPF core

> Most of these are already set by `Microsoft/config-wsl`; they are pinned here to prevent accidental regression when rebasing on a new WSL2 kernel tag. The pinned BPF Kconfig and build rules below define the mechanisms described here.

### `CONFIG_BPF`
Enables BPF core support, including interpreter infrastructure when the
interpreter is configured. The pinned base also enables `BPF_JIT_ALWAYS_ON`,
which removes the interpreter and permanently enables the JIT. The kernel
eBPF verifier is built with the `BPF_SYSCALL` subsystem, not by this option alone.
- [Pinned BPF Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/kernel/bpf/Kconfig)
- [Pinned BPF build rules](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/kernel/bpf/Makefile)

### `CONFIG_BPF_SYSCALL`
Exposes `bpf(2)` for userspace loading and management of Linux-kernel BPF
programs, maps, and related objects through file descriptors. It also builds
kernel facilities such as the eBPF verifier. Userspace disassemblers or other
non-kernel BPF runtimes do not require this syscall merely to operate.
- [Pinned BPF Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/kernel/bpf/Kconfig)
- [Pinned verifier build rule](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/kernel/bpf/Makefile)

### `CONFIG_BPF_JIT`
Enables a supported architecture's BPF JIT compiler, which can translate
programs to native instructions. Runtime enablement and other configuration
options govern its use. Cilium lists JIT support as a kernel requirement;
throughput still depends on the program, devices, and workload.
- [Pinned BPF Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/kernel/bpf/Kconfig)
- [Cilium system requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)

### `CONFIG_BPF_JIT_DEFAULT_ON`
Selects default JIT enablement where supported. This is distinct from
`BPF_JIT_ALWAYS_ON`: the pinned Microsoft base enables both, so its eBPF JIT is
permanently enabled and the interpreter is removed. The pinned Kconfig says
attempts to set `net.core.bpf_jit_enable` to another value then fail.
- [Pinned BPF JIT configuration](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/kernel/bpf/Kconfig)

### `CONFIG_BPF_LSM`
Enables **BPF Linux Security Module** hooks (since Linux 5.7). Tetragon uses BPF-LSM to enforce policy decisions (e.g., deny `execve`, restrict file access) directly in the kernel, without a traditional LSM module like SELinux or AppArmor. BPF LSM programs are **privileged, validated at load time, and executed at LSM hook points** to perform runtime checks and access control.
Compilation is only one requirement: `CONFIG_LSM` must include `bpf`, and any
`lsm=` kernel command-line override must also include it. The configuration
script appends `bpf` only if absent. Microsoft 6.18.54.1 already includes it;
6.6.123.2 does not. Runtime activation still requires verification. Verify activation with
`cat /sys/kernel/security/lsm` after boot; the list must contain a `bpf` entry.
- [Kernel docs: BPF LSM](https://docs.kernel.org/bpf/prog_lsm.html)
- [Tetragon docs](https://tetragon.io/docs/)

### `CONFIG_CGROUP_BPF`
Allows **BPF programs to be attached to cgroup hooks** (socket, connect, sendmsg, etc.). Cilium uses these for socket-level load balancing; OBI context-propagation modes can use cgroup socket hooks. This does not by itself enable kernel TLS.
- [Kernel docs: cgroup BPF](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

### `CONFIG_XDP_SOCKETS`
Enables AF_XDP sockets for packet exchange with userspace. AF_XDP supports
copy and zero-copy modes; zero-copy requires support from the selected network
driver and binding mode. Enabling this option does not establish zero-copy
support for a WSL device. XDP programs and Cilium XDP acceleration do not
necessarily require AF_XDP sockets.
- [Kernel AF_XDP modes](https://docs.kernel.org/networking/af_xdp.html#xdp-copy-and-xdp-zerocopy-bind-flags)

### `CONFIG_BPF_STREAM_PARSER`
Enables the receive-side `BPF_SK_SKB_STREAM_PARSER` attachment for TCP socket
maps. Both compared Microsoft configs disable this option but already enable
`NET_SOCK_MSG`, so SK_MSG/sockhash support
must not be inferred solely from this setting. OBI's network propagation uses
SK_MSG; it does not establish a need for this separate parser attachment.
This profile includes the parser for applications that explicitly use it.
- [Pinned attachment guard](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/core/sock_map.c)
- [Kernel docs: sockmap](https://www.kernel.org/doc/html/latest/bpf/map_sockmap.html)

### `CONFIG_BPF_EVENTS`
Enables BPF integration with tracing/perf events, including perf-event programs
and perf-buffer output through `bpf_perf_event_output()`. BPF ring-buffer maps
are a separate transport: OBI v0.14.0 uses `BPF_MAP_TYPE_RINGBUF` for its common
application events. Do not infer an agent's transport from this option alone.
- [Kernel BPF documentation](https://docs.kernel.org/bpf/index.html)
- [OBI v0.14.0 application event map](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/blob/v0.14.0/bpf/common/ringbuf.h)

---

## 4 · Tracing — Tetragon (kprobes/tracepoints) + OBI (uprobes)

> These options enable tracing infrastructure and attachment points. Runtime
> probes can be installed without rebuilding application source. Their overhead
> depends on the probes, event rate, and workload; configuration alone supplies
> no performance measurement.

### `CONFIG_FTRACE`
Enables the kernel tracing framework. Individual tracers have their own Kconfig
dependencies; this is not a universal prerequisite for every BPF attachment.
- [Kernel docs: ftrace](https://www.kernel.org/doc/html/latest/trace/ftrace.html)
- [Brendan Gregg: Kernel analysis with bpftrace (LWN)](https://lwn.net/Articles/794135/)

### `CONFIG_FUNCTION_TRACER`
Enables function-entry instrumentation for eligible compiled kernel functions.
The exact instruction and patching mechanism depend on the architecture and
toolchain. Used by function tracing; ordinary breakpoint-based kprobes do not require
function-entry instrumentation.
- [Kernel docs: ftrace](https://www.kernel.org/doc/html/latest/trace/ftrace.html)

### `CONFIG_DYNAMIC_FTRACE`
Enables **runtime patching of ftrace NOP stubs** so only actively traced functions carry overhead. This reduces overhead when function tracing is inactive; it is not a blanket
OBI instrumentation requirement.
- [Kernel docs: ftrace](https://www.kernel.org/doc/html/latest/trace/ftrace.html)

### `CONFIG_FTRACE_SYSCALLS`
Enables named syscall entry/exit events such as `sys_enter_<name>` and
`sys_exit_<name>` for supported syscalls. A tracing policy can select these
explicitly. Generic `raw_syscalls` events and other probe mechanisms are
separate; the option does not establish which events an agent uses.
- [Pinned syscall tracing Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/kernel/trace/Kconfig)

### `CONFIG_KPROBES`
Enables dynamic probes at eligible kernel instruction addresses without a
kernel source rebuild or reboot. Classic probes patch live instructions with
breakpoints; optimized paths can use jumps or ftrace-backed mechanisms. Some
locations are prohibited, and overhead depends on the selected probe path.
Observation does not imply arbitrary blocking: kprobe return override requires
the separate configuration and eligible functions described below.
- [Kernel kprobe mechanisms](https://docs.kernel.org/trace/kprobes.html)
- [Tetragon hook points](https://tetragon.io/docs/concepts/tracing-policy/hooks/)

### `CONFIG_KPROBE_EVENTS`
Enables dynamic kprobe/kretprobe events exposed through tracefs and usable
with tracing/perf. BPF attachment paths can use the perf kprobe PMU or dynamic
trace events; this is not an alternative to all ftrace text interfaces.
- [Pinned tracing Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/kernel/trace/Kconfig)
- [Kernel kprobe events](https://docs.kernel.org/trace/kprobetrace.html)

### `CONFIG_UPROBES`
Enables **user-space probes** — breakpoints inserted into ELF binaries at specific offsets, mapped into process memory. OBI uses uprobes for supported user-space libraries and Go instrumentation.
Language-agnostic network instrumentation and language-specific context tracking
are different mechanisms; consult the pinned OBI support matrix for each runtime. Unlike kprobes (which hook the kernel), uprobes hook into userspace processes.
- [Kernel docs: uprobes](https://www.kernel.org/doc/html/latest/trace/uprobetracer.html)
- [OpenTelemetry eBPF Instrumentation (OBI)](https://opentelemetry.io/docs/zero-code/obi/)

### `CONFIG_UPROBE_EVENTS`
The perf-event interface layer for uprobes; analogous to `CONFIG_KPROBE_EVENTS` but for userspace targets. Required for `BPF_PROG_TYPE_KPROBE` programs attached to uprobes. It enables the uprobe event interface; helper availability is governed separately
by the BPF program type and kernel implementation.
- [Kernel docs: uprobe-event](https://www.kernel.org/doc/html/latest/trace/uprobetracer.html)

### `CONFIG_TRACEPOINTS`
Defines the **static tracepoint instrumentation framework** — pre-placed hooks in the kernel (scheduler, memory, networking subsystems) whose names and fields may change between kernel versions. Used by Tetragon (`sched_process_exec`, etc.) and OBI.
- [Kernel docs: tracepoints](https://www.kernel.org/doc/html/latest/trace/tracepoints.html)

### `CONFIG_PERF_EVENTS`
The **perf subsystem** — hardware performance counters, software events, and the ring-buffer transport used by BPF programs to send data to userspace. All `perf_event_open`-based BPF attachment (kprobes, uprobes, tracepoints) depends on this.
- [Kernel docs: perf events](https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html)

---

## 5 · tc-BPF — Cilium datapath

> tc provides packet-processing attachment points used by Cilium and optional
> OBI networking modes. The exact hooks depend on application version and mode.
> See [Cilium datapath architecture](https://docs.cilium.io/en/stable/network/ebpf/index.html).

### `CONFIG_NET_SCHED`
The **Queueing Discipline (qdisc) framework** — the scheduling and classification layer that sits between the network stack and device drivers. tc-BPF programs execute here at ingress and egress, providing attachment points for network policy and load balancing.
- [Kernel docs: tc](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/sched/Kconfig)

### `CONFIG_NET_SCH_INGRESS`
Enables the classic ingress/clsact qdisc used for ingress and egress tc
classifier attachment. This requirement is specific to that attachment path:
TCX provides a different BPF-link attachment mechanism and does not need a
clsact qdisc. Cilium can use TCX on supported kernels; consult its selected
version and attachment mode instead of assuming every deployment uses clsact.
- [Pinned qdisc Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/sched/Kconfig)
- [Pinned TCX integration](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/core/dev.c)
- [Cilium TCX configuration](https://docs.cilium.io/en/stable/helm-reference/)

### `CONFIG_NET_CLS_ACT`
Enables tc classifier/action support and supplies a parent dependency for the
legacy ingress/clsact qdisc. Cilium documents this setting for tc-based
operation. Its direct-action BPF classifiers return action verdicts without
requiring separate `act_bpf` or `act_mirred` modules for those verdicts.
- [Pinned scheduler Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/sched/Kconfig)
- [Cilium BPF program types](https://docs.cilium.io/en/stable/reference-guides/bpf/progtypes/)

### `CONFIG_NET_CLS_BPF`
Enables the `cls_bpf` classifier for classic tc BPF attachment. TCX and netkit
are different attachment/device paths; `cls_bpf` should not be described as the
universal mechanism for current Cilium versions. The pinned base disables
`CONFIG_NETKIT`, and this fragment does not enable it. A netkit deployment would
require a separate config change and validation.
- [Pinned classifier Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/sched/Kconfig)
- [Pinned base config](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/arch/x86/configs/config-wsl)
- [Cilium datapath and TCX settings](https://docs.cilium.io/en/stable/helm-reference/)

### `CONFIG_NET_ACT_BPF`
The **`act_bpf` action** — allows a BPF program to be invoked as a tc action (distinct from a classifier). It is distinct from tc classifiers using direct-action mode; its inclusion is
not evidence that an ordinary Cilium or Tetragon deployment needs it.
- [Kernel docs: tc BPF](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/sched/Kconfig)

### `CONFIG_NET_ACT_MIRRED`
The **`act_mirred` action** — redirects or mirrors packets between interfaces at the tc layer. Useful for tc mirroring and traffic shaping. BPF redirect helpers are a separate
mechanism and do not establish an `act_mirred` requirement.
- [man8: tc-mirred](https://man7.org/linux/man-pages/man8/tc-mirred.8.html)

---

## 6 · LWT-BPF — optional per-route BPF processing

> **Lightweight Tunnels (LWT)** allow custom packet transformations to be associated with routing table entries. This profile retains optional per-route BPF support; ordinary Cilium host routing
is not proof of an LWT-BPF requirement.

### `CONFIG_LWTUNNEL`
The **LWT framework** core. Provides the hooks (input, output, xmit) that BPF and other encapsulation modules register handlers for within the routing layer.
- [Kernel docs: LWT](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/Kconfig)

### `CONFIG_LWTUNNEL_BPF`
Enables **BPF programs as LWT hooks**. Applications can attach `lwt_in`, `lwt_out`, or `lwt_xmit` programs to routes.
Validate the application integration separately from kernel compilation.
- [Cilium routing](https://docs.cilium.io/en/stable/network/concepts/routing/)

---

## 7 · Cgroup controllers — Docker, Tetragon process correlation

> The examples target cgroup v2. Container runtimes can use different hierarchy
> and driver configurations; a systemd driver alone does not prove that v2 is
> active. Agents can use cgroup identity for container correlation, which is
> distinct from attaching cgroup-BPF programs.

### `CONFIG_CGROUPS`
The cgroup subsystem core. Container runtimes use it for resource and process
grouping; agent correlation and individual controllers have separate requirements.
- [Kernel docs: cgroup v2](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

### `CONFIG_MEMCG`
**Memory cgroup controller** — enforces per-container memory limits and provides OOM tracking. Docker's `--memory` flag and Kubernetes resource limits both depend on this.
- [Kernel docs: memory cgroup](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#memory)

### `CONFIG_BLK_CGROUP`
Provides block-I/O cgroup infrastructure; it does not supply every I/O policy
by itself. Throttling uses `CONFIG_BLK_DEV_THROTTLING`, which the pinned base
already enables. Available controls also depend on hierarchy, delegation,
backing device, and the selected I/O policy.
- [Pinned controller Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/init/Kconfig)
- [Kernel I/O controller](https://docs.kernel.org/admin-guide/cgroup-v2.html#io)

### `CONFIG_CGROUP_PIDS`
**PID cgroup controller** — limits the number of processes a container can create, preventing fork bombs. Required by Docker's `--pids-limit`.
- [Kernel docs: pids cgroup](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#pid)

### `CONFIG_CGROUP_FREEZER`
Enables the legacy cgroup v1 freezer controller for freezing and thawing
process groups. Freezing completes as tasks reach suitable freeze points; it
is not an instantaneous atomic pause of every task. Cgroup v2's
`cgroup.freeze` interface does not require this legacy option.
- [Kernel cgroup v1 freezer](https://docs.kernel.org/admin-guide/cgroup-v1/freezer-subsystem.html)
- [Kernel cgroup v2](https://docs.kernel.org/admin-guide/cgroup-v2.html)

### `CONFIG_CGROUP_DEVICE`
**Device cgroup controller** — allows/denies access to specific device nodes within a container (used to implement Docker's device whitelist and runtime device-access policies).
This option supplies the legacy cgroup v1 device controller. On cgroup v2,
device access is controlled through cgroup BPF programs (`CONFIG_CGROUP_BPF`).
- [Kernel docs: device cgroup](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#device-controller)

### `CONFIG_CGROUP_SCHED`
Provides CPU group-scheduling infrastructure. Fair-scheduling weights use
`CONFIG_FAIR_GROUP_SCHED`, while bandwidth quotas use `CONFIG_CFS_BANDWIDTH`;
the pinned base enables both. Real-time group scheduling is separately
configured through `CONFIG_RT_GROUP_SCHED`, which this base disables. Cgroup v2
does not support bandwidth control for real-time processes. CPU-controller
availability and delegation must also be checked at runtime.
- [Pinned scheduler Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/init/Kconfig)
- [Cgroup v2 CPU controller](https://docs.kernel.org/admin-guide/cgroup-v2.html#cpu)

### `CONFIG_SOCK_CGROUP_DATA`
Embeds **cgroup identity into socket structures** for socket cgroup association and related BPF helpers. This supplies kernel
infrastructure; each agent chooses its own process/container correlation mechanism.
- [Kernel docs: cgroup BPF](https://www.kernel.org/doc/html/latest/bpf/index.html)

---

## 8 · Netfilter / iptables / conntrack

> Netfilter and BPF datapaths provide different mechanisms. Docker bridge
> firewall rules and Cilium Netfilter use depend on the configured backend and
> features. BPF masquerading/connection tracking does not imply every Netfilter
> dependency can be removed. Host and macvlan modes have different requirements.

### `CONFIG_NETFILTER`
The **Netfilter framework** — the hook-based packet filtering layer that iptables, nftables, and conntrack all live on.
- [Netfilter project](https://www.netfilter.org/)

### `CONFIG_NETFILTER_ADVANCED`
Exposes advanced Netfilter selection and gates particular optional
matches/targets, including this profile's BPF/socket/CT choices. Basic modules
can remain available without this setting; it is not a dependency of every
`NETFILTER_XT_*` symbol.
- [Pinned Netfilter Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/netfilter/Kconfig)

### `CONFIG_NF_CONNTRACK`
The **connection tracking subsystem** — maintains state tables for TCP/UDP/ICMP sessions. Netfilter NAT depends on this subsystem. Cilium also has BPF connection-tracking
maps, which are separate from Linux Netfilter conntrack.
- [Kernel docs: conntrack](https://www.kernel.org/doc/html/latest/networking/nf_conntrack-sysctl.html)

### `CONFIG_NF_NAT`
Enables Netfilter NAT, built on Netfilter conntrack. Docker bridge egress can
use masquerading when enabled; Cilium can use Netfilter masquerading in selected
configurations. BPF masquerading is a separate implementation.
- [Pinned NAT Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/netfilter/Kconfig)
- [Docker firewall backends](https://docs.docker.com/engine/network/packet-filtering-firewalls/)

### `CONFIG_NF_TABLES`
The **nftables framework** — the modern, set-based replacement for iptables. Used by nftables rules, iptables-nft compatibility, and workloads explicitly
configured for an nftables backend. Do not assume every Docker release defaults to it.
- [nftables wiki](https://wiki.nftables.org/)

### `CONFIG_NF_TABLES_INET`
The **inet (dual IPv4/IPv6) nftables family** — allows writing a single nftables ruleset that applies to both IP versions. Applications may instead use separate IPv4 and IPv6 tables.
- [nftables wiki](https://wiki.nftables.org/)

### `CONFIG_NETFILTER_XTABLES_LEGACY`, `CONFIG_IP_NF_IPTABLES_LEGACY`, `CONFIG_IP6_NF_IPTABLES_LEGACY`
Linux 6.18 separates legacy table evaluation from the xtables framework. This
profile enables these parent dependencies so the requested filter, NAT, mangle,
raw, CT, and TPROXY options can remain built-in. They support legacy networking
modes and are not required by OBI instrumentation.
- [Pinned IPv4 netfilter Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/ipv4/netfilter/Kconfig)
- [Pinned IPv6 netfilter Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/ipv6/netfilter/Kconfig)

### `CONFIG_IP_NF_IPTABLES`
The **iptables framework for IPv4** — the classic packet filter table architecture.
- [iptables man page](https://man7.org/linux/man-pages/man8/iptables.8.html)

### `CONFIG_IP_NF_FILTER`
Enables the legacy IPv4 filter table with INPUT, OUTPUT, and FORWARD chains.
Docker and kube-proxy deployments using a compatible iptables backend can
create filtering rules; native nftables backends do not require this legacy
table merely to filter traffic.
- [Pinned IPv4 Netfilter Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/ipv4/netfilter/Kconfig)

### `CONFIG_IP_NF_NAT`
Enables the legacy IPv4 NAT table, including PREROUTING, INPUT, OUTPUT, and
POSTROUTING hooks. Container masquerading and port-publishing rules use the
appropriate configured firewall backend; native nftables NAT is separate from
this legacy table.
- [Pinned IPv4 Netfilter Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/ipv4/netfilter/Kconfig)

### `CONFIG_IP_NF_MANGLE`
Enables the legacy IPv4 mangle table for operations such as packet marking.
The rules installed by an application depend on its backend, features, and
version; this option does not itself install Cilium rules.
- [Pinned IPv4 Netfilter Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/ipv4/netfilter/Kconfig)

### `CONFIG_IP6_NF_IPTABLES`
The **ip6tables framework** — IPv6 equivalent of `CONFIG_IP_NF_IPTABLES`.
- [ip6tables man page](https://man7.org/linux/man-pages/man8/ip6tables.8.html)

### `CONFIG_IP6_NF_FILTER`
The IPv6 **`filter` table** for ip6tables.
- [ip6tables man page](https://man7.org/linux/man-pages/man8/ip6tables.8.html)

### `CONFIG_IP6_NF_NAT`
The IPv6 **`nat` table** for ip6tables — used for stateful IPv6 NAT and masquerading. NPTv6 uses separate targets.
- [ip6tables man page](https://man7.org/linux/man-pages/man8/ip6tables.8.html)

### `CONFIG_NETFILTER_XT_MARK`
Enables xtables mark matching/target support for inspecting or changing
`skb->mark`. Application use depends on the installed rules; enabling the
option does not establish a specific Cilium packet-processing path.
- [Pinned mark Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/netfilter/Kconfig)

### `CONFIG_NETFILTER_XT_MATCH_BPF`
The **`bpf` xtables match** — runs a classic BPF filter or a pinned eBPF program on a packet as an iptables match condition. Allows existing iptables rules to delegate classification to a BPF program.
- [iptables-extensions: bpf](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)

### `CONFIG_NETFILTER_XT_MATCH_SOCKET`
The **`socket` xtables match** — looks up the socket that would receive the packet. Used by transparent-proxy rules to identify locally owned connections; an
application must explicitly configure these rules.
- [iptables-extensions: socket](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)

### `CONFIG_NETFILTER_XT_TARGET_TPROXY`
The **TPROXY xtables target** — redirects a packet to a local socket without changing its destination IP/port, enabling **transparent proxying**. Transparent proxy deployments may use TPROXY with policy routing and
transparent sockets; an ordinary Envoy deployment does not require it.
- [iptables-extensions: TPROXY](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)
- [Envoy transparent proxy](https://www.envoyproxy.io/docs/envoy/latest/configuration/listeners/listener_filters/original_dst_filter)

### `CONFIG_NETFILTER_XT_TARGET_CT`
Sets initial conntrack parameters, such as zone, helper, and event selection,
for subsequently tracked traffic by attaching a conntrack template. It does
not generally edit arbitrary existing conntrack entries. The pinned Kconfig
includes `IP_NF_RAW || IP6_NF_RAW || NFT_COMPAT` among its dependencies. This
profile satisfies that condition through built-in raw tables; NFT compatibility
is another permitted path.
- [Pinned Netfilter Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/netfilter/Kconfig)
- [Pinned CT implementation](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/netfilter/xt_CT.c)

### `CONFIG_IP_NF_RAW` / `CONFIG_IP6_NF_RAW`
Enable the IPv4 and IPv6 raw tables for rules evaluated before normal connection
tracking. These supply the parent dependency for the built-in CT target and are
also used by NOTRACK/TRACE configurations.

---

## 9 · Virtual netdevs — container networking + Cilium overlays

> Virtual devices can connect namespaces or implement overlays. Which devices
> are needed depends on the network mode; host networking, for example, does
> not create the usual per-container bridge/veth topology.

### `CONFIG_TUN`
The **TUN/TAP driver** — creates virtual point-to-point (TUN) or Ethernet (TAP) devices. Used by WireGuard's userspace fallback, some VPN clients, and QEMU/KVM inside WSL2.
- [Kernel docs: tuntap](https://www.kernel.org/doc/html/latest/networking/tuntap.html)

### `CONFIG_VETH`
**Virtual Ethernet pairs** — the fundamental building block of container networking. Bridge-networked containers commonly use a `veth` pair: one end in the container namespace, the other in the host namespace. A CNI can attach BPF programs to appropriate
interfaces according to its datapath mode. Each veth acts as a bidirectional pipe between two network namespaces.
- [man8: ip-link veth](https://man7.org/linux/man-pages/man8/ip-link.8.html)

### `CONFIG_BRIDGE`
The **software bridge driver** — the Linux equivalent of a network switch. Docker's default `bridge` network mode puts containers behind a `docker0` bridge that forwards traffic between the container and host network namespaces.
- [Kernel docs: bridge](https://www.kernel.org/doc/html/latest/networking/bridge.html)

### `CONFIG_BRIDGE_VLAN_FILTERING`
Enables **VLAN filtering on bridges** — allows per-port VLAN membership, used by more advanced CNI plugins and multi-tenant Docker setups.
- [Kernel docs: bridge](https://www.kernel.org/doc/html/latest/networking/bridge.html)

### `CONFIG_VXLAN`
The **VXLAN encapsulation driver** — encapsulates L2 frames in UDP datagrams to create overlay networks across L3 boundaries. Cilium's default overlay mode in many deployments. Provides multi-node pod connectivity by tunneling packets through UDP over the host network.
- [RFC 7348: VXLAN](https://www.rfc-editor.org/rfc/rfc7348)
- [Cilium VXLAN overlay](https://docs.cilium.io/en/stable/network/concepts/routing/#vxlan-based-multi-node-pod-connectivity)
- [GitHub: tunnel-cni VXLAN/Geneve backend](https://github.com/ebpf-networking/tunnel-cni)

### `CONFIG_GENEVE`
The **Geneve encapsulation driver** — a more flexible overlay encapsulation than VXLAN, with extensible TLV options for metadata. Cilium supports Geneve as an alternative overlay; OVN also uses it.
- [RFC 8926: Geneve](https://www.rfc-editor.org/rfc/rfc8926)

### `CONFIG_MACVLAN`
**MAC VLAN** — creates virtual interfaces that share the same physical NIC but have distinct MAC addresses and can be placed in separate namespaces. Used by some CNI plugins and Docker `macvlan` network mode.
- [Kernel docs: macvlan](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/drivers/net/Kconfig)

### `CONFIG_IPVLAN`
**IP VLAN** — like MACVLAN but shares the parent's MAC; only IP addresses differ. Used by Docker ipvlan networking and CNI plugins that select ipvlan.
- [Kernel docs: ipvlan](https://www.kernel.org/doc/html/latest/networking/ipvlan.html)

### `CONFIG_DUMMY`
The **dummy network interface driver** — a virtual interface that swallows all traffic (like loopback but without the loopback semantics). Applications can use dummy interfaces as virtual endpoints or BPF attachment
points; this option alone does not demonstrate a particular agent integration.
- [man8: ip-link dummy](https://man7.org/linux/man-pages/man8/ip-link.8.html)

### `CONFIG_IFB`
**Intermediate Functional Block** — a virtual device used to redirect ingress traffic to an egress queue so that standard tc qdiscs (which only work egress) can be applied to incoming traffic. Used in traffic-shaping setups that explicitly redirect packets to an IFB.
- [man8: tc-ifb](https://man7.org/linux/man-pages/man8/tc-ifb.8.html)

---

## 10 · Crypto / IPsec / WireGuard — Cilium transparent encryption

### `CONFIG_XFRM`
The **IPsec/XFRM framework** — the kernel's transform layer for encrypting and authenticating IP packets. Cilium's IPsec transparent encryption (node-to-node) runs through XFRM.
- [Kernel docs: XFRM](https://docs.kernel.org/networking/xfrm/index.html)
- [Cilium IPsec](https://docs.cilium.io/en/stable/security/network/encryption-ipsec/)

### `CONFIG_XFRM_USER`
The **Netlink interface to XFRM** — exposes XFRM policy and SA management to userspace daemons (strongSwan, Cilium's agent) via `NETLINK_XFRM` messages. The legacy `AF_KEY` interface is separately configured.
- [Kernel docs: XFRM](https://docs.kernel.org/networking/xfrm/index.html)

### `CONFIG_XFRM_ALGO`
Supplies XFRM algorithm descriptors and lookup/probing support for
supported authentication, encryption, and AEAD algorithms. The Crypto API
registers the actual algorithm implementations; enabling this option does not
supply every implementation or configure an IPsec security association.
- [Pinned XFRM Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/xfrm/Kconfig)
- [Pinned algorithm descriptors](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/net/xfrm/xfrm_algo.c)

### `CONFIG_INET_ESP`
Enables the IPv4 ESP implementation. ESP can provide confidentiality,
integrity/authentication, or combined protection according to the configured
security association and algorithms. The config option alone does not select
or enable those protections for traffic. Cilium's IPsec mode requires its
separate key, policy, and datapath configuration.
- [ESP protection modes: RFC 4303](https://www.rfc-editor.org/rfc/rfc4303)
- [Cilium IPsec configuration](https://docs.cilium.io/en/stable/security/network/encryption-ipsec/)

### `CONFIG_INET6_ESP`
**ESP for IPv6** — the IPv6 equivalent of `CONFIG_INET_ESP`.
- [RFC 4303: ESP](https://www.rfc-editor.org/rfc/rfc4303)

### `CONFIG_WIREGUARD`
Enables the in-kernel WireGuard implementation and its selected cryptographic
library dependencies. A WireGuard or Cilium deployment still needs interfaces,
keys, peers, and routing configured; compilation alone establishes no encrypted
connection or comparative performance result.
- [Pinned WireGuard Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/drivers/net/Kconfig)
- [Cilium WireGuard configuration](https://docs.cilium.io/en/stable/security/network/encryption-wireguard/)

---

## 11 · Storage — OverlayFS and userspace filesystems

### `CONFIG_OVERLAY_FS`
Enables OverlayFS, which layers filesystems for copy-on-write image/container
storage. Docker uses it through the classic `overlay2` driver or the containerd
`overlayfs` snapshotter. Docker Engine 29+ fresh installations default to the
containerd image store; upgraded installations can retain the classic driver.
Inspect `docker info` to identify the actual storage backend.
- [Kernel OverlayFS](https://docs.kernel.org/filesystems/overlayfs.html)
- [Docker containerd image store](https://docs.docker.com/engine/storage/containerd/)
- [Docker classic overlay2 driver](https://docs.docker.com/engine/storage/drivers/overlayfs-driver/)

### `CONFIG_FUSE_FS`
The **FUSE (Filesystem in Userspace) driver** — allows filesystems to be implemented in userspace. Applications must select a userspace filesystem backend and supply its
implementation; this option alone does not establish a particular snapshotter
or rootless-container storage integration.
- [Kernel docs: FUSE](https://docs.kernel.org/filesystems/fuse/index.html)

---

## 12 · Security primitives — container sandboxing and audit

> These are separate kernel mechanisms. See [seccomp documentation](https://docs.kernel.org/userspace-api/seccomp_filter.html)
> and [BPF LSM documentation](https://docs.kernel.org/bpf/prog_lsm.html).

### `CONFIG_SECCOMP`
Enables secure-computing infrastructure. Processes can restrict their own
syscall execution, with restrictions inherited by children; this does not let
a parent arbitrarily apply a filter to an existing child. Filter mode is
separately enabled below. Docker normally applies a seccomp profile, subject
to deployment configuration. Seccomp, BPF LSM, namespaces, and capabilities are
separate mechanisms.
- [Kernel seccomp](https://docs.kernel.org/userspace-api/seccomp_filter.html)
- [Docker seccomp profiles](https://docs.docker.com/engine/security/seccomp/)

### `CONFIG_SECCOMP_FILTER`
Enables the **BPF-based seccomp filter** mechanism (as opposed to the older SECCOMP_MODE_STRICT). This is what `docker run --security-opt seccomp=profile.json` uses. Filters are evaluated as BPF bytecode at syscall entry, enabling fine-grained per-syscall argument filtering.
- [Kernel docs: seccomp_filter](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)

### `CONFIG_AUDIT`
Enables audit infrastructure used by facilities such as security modules.
Syscall auditing also needs `CONFIG_AUDITSYSCALL`, which the pinned base enables,
and the appropriate runtime audit configuration. Enabling infrastructure alone
does not configure rules, a userspace audit daemon, or a compliance result.
- [Pinned audit Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/init/Kconfig)

---

## 13 · Misc performance / observability

### `CONFIG_TRANSPARENT_HUGEPAGE`
Enables transparent huge-page support, including sizes and allocation/collapse
paths supported by the architecture and kernel. Runtime policy and workload
behavior determine actual use; the pinned base selects the `madvise` default,
not an always-enabled policy. THP can reduce translation overhead but also has
memory and latency costs; no performance benefit is established by this config.
- [Kernel THP policy and sizes](https://docs.kernel.org/admin-guide/mm/transhuge.html)

### `CONFIG_HUGETLBFS`
Provides the **HugeTLB filesystem** — allows applications to explicitly `mmap` pre-allocated huge pages (page sizes depend on architecture and configuration). Used by performance-sensitive databases and DPDK-style packet processing.
- [Kernel docs: hugetlbpage](https://www.kernel.org/doc/html/latest/admin-guide/mm/hugetlbpage.html)

### `CONFIG_IKCONFIG`
Embeds the build configuration in the kernel image so it can be extracted
without the original build tree. Runtime access needs a configured interface
such as `IKCONFIG_PROC` below; this option alone does not give every process an
access path or permission.
- [Pinned embedded-config Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/init/Kconfig)

### `CONFIG_IKCONFIG_PROC`
Exposes the embedded config via **`/proc/config.gz`**. Tools like `cilium-bugtool`, `tetra`, and `bpftool feature` read this to verify kernel capabilities at runtime.
- [Kconfig: CONFIG_IKCONFIG_PROC](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/init/Kconfig)

### `CONFIG_IKHEADERS`
Embeds in-kernel headers in `/sys/kernel/kheaders.tar.xz` for relevant tooling.
It does not provide a complete installed kernel development tree, compiler, or
guarantee of external-module build support. Precompiled BPF CO-RE objects
normally use kernel BTF instead of compiling against this archive.
- [Pinned header archive Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/init/Kconfig)

### `CONFIG_LOCALVERSION`
Adds `-microsoft-standard-WSL2-ebpf` to the kernel release so the custom profile
can be distinguished from a stock kernel. The runtime check compares the full
release with `kernel-release.txt` recorded during the build.

## Enforcement additions

### `CONFIG_FUNCTION_ERROR_INJECTION`
Enables error injection into kernel functions annotated with
`ALLOW_ERROR_INJECTION()`. It is a dependency of `CONFIG_BPF_KPROBE_OVERRIDE`.

### `CONFIG_BPF_KPROBE_OVERRIDE`
Allows BPF programs to override the return value of eligible kprobed functions.
Tetragon's kprobe `Override` action needs this option. It does not make arbitrary
kernel functions overridable, and ordinary tracing does not require it.
Validate the capability with `sudo tetra probe`, then test the actual policy.
- [Tetragon Override action](https://tetragon.io/docs/concepts/tracing-policy/selectors/)

---

## Quick reference — mechanisms and deployment choices

These entries summarize kernel mechanisms, not a product compatibility matrix.
Use the option sections and application documentation to select a mode; the
repository has not validated every named application integration on WSL.

| Config | Mechanism | Deployment qualification |
|---|---|---|
| `DEBUG_INFO_BTF` | Kernel type metadata | CO-RE relocation requires relevant exposed BTF |
| `BPF_LSM` | Security hook programs | Must also be configured and active at runtime |
| `CGROUP_BPF` | Cgroup BPF attachment | Socket/device hooks differ from cgroup identity correlation |
| `BPF_STREAM_PARSER` | Receive-side socket stream parser | Separate from SK_MSG support |
| Kprobe/uprobe event options | Probe event interfaces | Attachment path and eligible targets vary |
| `NET_CLS_BPF` / `NET_SCH_INGRESS` | Classic tc classifier/qdisc | TCX is a separate attachment path |
| `LWTUNNEL_BPF` | Route-attached BPF | Requires a consumer configuring those routes |
| `NF_CONNTRACK` | Netfilter connection tracking | Separate from BPF conntrack maps |
| `XT_TARGET_TPROXY` | Transparent socket redirection | Requires routing/socket/rule configuration |
| `VETH` | Paired virtual interfaces | Common bridge topology, not every network mode |
| `VXLAN` / `GENEVE` | Overlay tunnel devices | Selected by the configured overlay mode |
| `WIREGUARD` | WireGuard implementation | Requires peer, key, and routing configuration |
| `INET_ESP` / `XFRM` | IPsec transformations | Protection depends on SAs and algorithms |
| `OVERLAY_FS` | Layered filesystem | Used by classic overlay2 and overlayfs snapshotters |
| `SECCOMP_FILTER` | Syscall filter sandboxing | Runtime profile, not a Tetragon sensor guarantee |

---

## Further reading

- [Pinned Microsoft x86 config](https://github.com/microsoft/WSL2-Linux-Kernel/blob/d504d40ab83839cb61942a812a99d183c42227b9/arch/x86/configs/config-wsl)
- [Pinned kernel Kconfig](https://github.com/microsoft/WSL2-Linux-Kernel/tree/d504d40ab83839cb61942a812a99d183c42227b9)
- [Linux BPF documentation](https://docs.kernel.org/bpf/index.html)
- [OBI v0.14.0 support matrix](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/blob/v0.14.0/SUPPORT_MATRIX.md)
- [OBI capabilities](https://opentelemetry.io/docs/zero-code/obi/security/)
- [Cilium system requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)
- [Tetragon hook points](https://tetragon.io/docs/concepts/tracing-policy/hooks/)
- [Docker packet filtering](https://docs.docker.com/engine/network/packet-filtering-firewalls/)

Kernel configuration enables mechanisms; application versions, privileges,
attachment choices, and runtime tests determine whether a workload works.
