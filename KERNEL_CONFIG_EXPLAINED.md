# WSL2 eBPF Kernel Configuration — Explained

This document explains every option in `ebpf-kernel.config`, grouped by the same sections used in that file.
Each entry covers **what it is**, **why it's needed**, and links to upstream documentation.

---

## Target workloads

| Tool | Purpose |
|---|---|
| **Docker** | Container runtime using overlay2 storage, bridge networking, iptables/nftables |
| **Tetragon** | Cilium's runtime security agent — uses kprobes, tracepoints, and BPF-LSM for enforcement |
| **Cilium** | eBPF-native CNI — tc-BPF datapath, LWT, sockmap, conntrack, overlay encapsulation, WireGuard/IPsec |
| **OpenTelemetry OBI** | eBPF-based auto-instrumentation — uprobes, CO-RE, cgroup-BPF, kTLS tracing |
| **Envoy** | L7 proxy — kTLS offload, TPROXY for transparent interception, sockmap LB bypass |

---

## 1 · Networking baseline

> These may be stripped by `Microsoft/config-wsl`; they are pinned here so that every eBPF feature that depends on the network stack is guaranteed to be present.

### `CONFIG_INET`
Enables the **IPv4 Internet protocol suite** (TCP, UDP, ICMP, raw sockets) inside the kernel.
Without it, virtually every network-using workload — and many BPF program types — fails to compile or load.
- [Kconfig: CONFIG_INET](https://cateee.net/lkddb/web-lkddb/INET.html)

### `CONFIG_IPV6`
Enables the **IPv6 protocol stack**. Required by Cilium (dual-stack), OBI, and any workload that targets modern cloud networks.
- [Kconfig: CONFIG_IPV6](https://cateee.net/lkddb/web-lkddb/IPV6.html)

### `CONFIG_NETDEVICES`
Gates compilation of all **network device drivers and virtual devices** (veth, tun, bridge, etc.). Without it, container networking and virtual network interfaces cannot exist.
- [Kconfig: CONFIG_NETDEVICES](https://cateee.net/lkddb/web-lkddb/NETDEVICES.html)

### `CONFIG_CRYPTO`
Enables the kernel **crypto API framework** — the substrate used by TLS, IPsec (ESP), WireGuard, and BPF crypto helpers.
- [Kconfig: CONFIG_CRYPTO](https://cateee.net/lkddb/web-lkddb/CRYPTO.html)

### `CONFIG_KEYS`
Provides the **kernel key-retention service** used by keyrings for TLS session keys, IPsec SAs, and module signing.
- [Kconfig: CONFIG_KEYS](https://cateee.net/lkddb/web-lkddb/KEYS.html)

---

## 2 · BTF / CO-RE — required for Tetragon, OBI, Cilium

> **CO-RE** (Compile Once – Run Everywhere) lets a single pre-compiled eBPF binary adapt to any kernel version at load time by reading BTF type information embedded in the kernel image. This eliminates the need to ship a compiler with your eBPF tooling or to recompile code on every target machine.

### `CONFIG_DEBUG_INFO`
Instructs the compiler to embed **DWARF debug information** in kernel objects.
`CONFIG_DEBUG_INFO_BTF` depends on this to generate BTF from the DWARF data via `pahole` (v1.16+, v1.21+ for DWARF 5).
- [Kernel docs: BTF](https://www.kernel.org/doc/html/latest/bpf/btf.html)
- [Medium: Building the Linux kernel with BTF](https://medium.com/@suruti94/building-the-linux-kernel-with-btf-1a617cfb4a24)

### `CONFIG_DEBUG_INFO_BTF`
Generates the **vmlinux BTF blob** — a compact, deduplicated type description of the entire kernel. The standard location is `/sys/kernel/btf/vmlinux`. 
This is the cornerstone of CO-RE: tools like `bpftool`, Tetragon, Cilium, and OBI read it at startup to resolve struct offsets without needing kernel headers or source code.
- [Kernel docs: BTF](https://www.kernel.org/doc/html/latest/bpf/btf.html)
- [CO-RE reference guide — Andrii Nakryiko](https://nakryiko.com/posts/bpf-core-reference-guide/)
- [BPF CO-RE Portability and Design](https://nakryiko.com/posts/bpf-portability-and-co-re/)
- [BTF Troubleshooting Guide](https://www.virtvps.com/btf-mastering-bpf-troubleshooting-unlocking/)

### `CONFIG_DEBUG_INFO_BTF_MODULES`
Extends BTF coverage to **loadable kernel modules**. Tetragon and OBI hook into subsystems that may live in modules (e.g., `nf_conntrack`, `virtio`, filesystem drivers), so their BTF is needed for CO-RE relocation to work in those paths. Without this, BPF programs may fail to load or relocate on systems with kernel module dependencies.
- [Kernel docs: BTF](https://www.kernel.org/doc/html/latest/bpf/btf.html)
- [BCC to libbpf conversion guide — Nakryiko](https://nakryiko.com/posts/bcc-to-libbpf-howto-guide/)

---

## 3 · BPF core

> Most of these are already set by `Microsoft/config-wsl`; they are pinned here to prevent accidental regression when rebasing on a new WSL2 kernel tag. See [eBPF ecosystem progress (eunomia 2025)](https://eunomia.dev/blog/2025/02/12/ebpf-ecosystem-progress-in-20242025-a-technical-deep-dive/) for recent kernel improvements.

### `CONFIG_BPF`
The **BPF interpreter and verifier** core. Every other BPF option depends on this.
- [Kernel docs: BPF](https://www.kernel.org/doc/html/latest/bpf/index.html)
- [eBPF.io: Introduction & Community Resources](https://ebpf.io/)

### `CONFIG_BPF_SYSCALL`
Exposes the `bpf(2)` system call to user space, allowing programs to **load, attach, and manage BPF programs and maps**.
Without it, no eBPF tooling can function.
- [man2: bpf(2)](https://man7.org/linux/man-pages/man2/bpf.2.html)

### `CONFIG_BPF_JIT`
Enables the **BPF Just-In-Time compiler**. On x86-64 and arm64, BPF bytecode is translated to native machine code at load time, eliminating interpreter overhead. Cilium's data-plane throughput critically depends on JIT being enabled — without it, packet processing is 5–10× slower.
- [Kernel docs: BPF JIT](https://www.kernel.org/doc/html/latest/bpf/index.html)
- [Cilium system requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)

### `CONFIG_BPF_JIT_DEFAULT_ON`
Makes the JIT compiler **active by default** without requiring `sysctl net.core.bpf_jit_enable=1`. Ensures JIT is on even before any userspace tuning step runs. Recommended for production deployments.
- [Cilium system requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)
- [How to Tune Kernel Parameters for eBPF Performance](https://oneuptime.com/blog/post/2026-01-07-ebpf-kernel-parameter-tuning/view)

### `CONFIG_BPF_LSM`
Enables **BPF Linux Security Module** hooks (since Linux 5.7). Tetragon uses BPF-LSM to enforce policy decisions (e.g., deny `execve`, restrict file access) directly in the kernel, without a traditional LSM module like SELinux or AppArmor. BPF LSM programs are **privileged, validated at load time, and executed at LSM hook points** to perform runtime checks and access control.
- [Kernel docs: BPF LSM](https://www.kernel.org/doc/html/latest/bpf/bpf_lsm.html)
- [Practical Guide to LSM BPF](https://www.ebpf.top/en/post/lsm_bpf_intro/)
- [Tetragon docs](https://tetragon.io/docs/)
- [Medium: LSM BPF and eBPF Security](https://medium.com/@lumontec/some-freshness-with-linux-security-modules-and-ebpf-676ac363a135)

### `CONFIG_CGROUP_BPF`
Allows **BPF programs to be attached to cgroup v2 hooks** (socket, connect, sendmsg, etc.). Cilium uses this for per-pod socket-level load balancing and OBI uses it for kTLS tracing scoped to a container's cgroup.
- [Kernel docs: cgroup BPF](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

### `CONFIG_XDP_SOCKETS`
Enables **AF_XDP** — zero-copy packet I/O from userspace via XDP sockets. Used by high-performance network applications and some Cilium XDP offload paths.
- [Kernel docs: AF_XDP](https://www.kernel.org/doc/html/latest/networking/af_xdp.html)

### `CONFIG_BPF_STREAM_PARSER`
Enables **sockmap** and **sk_msg** BPF program types. Cilium's socket-level load balancer (bypass kube-proxy) and Envoy's transparent pass-through use these to redirect TCP streams between sockets without copying data through userspace.
- [Kernel docs: sockmap](https://www.kernel.org/doc/html/latest/bpf/map_sockmap.html)

### `CONFIG_BPF_EVENTS`
Wires **BPF into the perf-events subsystem**, enabling `BPF_PROG_TYPE_PERF_EVENT` programs and perf ring-buffer output from BPF via `bpf_perf_event_output()`. Used by Tetragon and OBI to stream telemetry to userspace.
- [Kernel docs: BPF perf events](https://www.kernel.org/doc/html/latest/bpf/index.html)

---

## 4 · Tracing — Tetragon (kprobes/tracepoints) + OBI (uprobes)

> These configurations enable **kernel instrumentation points** that BPF programs can hook into at runtime. Collectively, they enable low-overhead observability without code modification or recompilation. See [Brendan Gregg's eBPF tracing tools](https://www.brendangregg.com/ebpf.html) and [BPF Performance Tools book](https://www.brendangregg.com/bpf-performance-tools-book.html) for comprehensive observability patterns.

### `CONFIG_FTRACE`
The **Function Tracer framework** — the infrastructure that all kernel tracing facilities build on. Kprobes, tracepoints, and dynamic ftrace hooks all depend on it.
- [Kernel docs: ftrace](https://www.kernel.org/doc/html/latest/trace/ftrace.html)
- [Brendan Gregg: Kernel analysis with bpftrace (LWN)](https://lwn.net/Articles/794135/)

### `CONFIG_FUNCTION_TRACER`
Instruments every kernel function with a **5-byte NOP** at entry (on x86) that can be patched at runtime to a call into ftrace. Required by `CONFIG_DYNAMIC_FTRACE` and kprobe trampolines.
- [Kernel docs: ftrace](https://www.kernel.org/doc/html/latest/trace/ftrace.html)

### `CONFIG_DYNAMIC_FTRACE`
Enables **runtime patching of ftrace NOP stubs** so only actively traced functions carry overhead. Without this, every function call in the kernel would pay a tracing tax even when no probe is active. Critical for production performance.
- [Kernel docs: ftrace](https://www.kernel.org/doc/html/latest/trace/ftrace.html)

### `CONFIG_FTRACE_SYSCALLS`
Creates **dedicated tracepoints for every syscall entry/exit** (`sys_enter_<name>`, `sys_exit_<name>`). Tetragon uses these for low-overhead syscall monitoring without kprobing individual syscall handlers. Enables rich syscall observability with minimal performance impact.
- [Kernel docs: ftrace syscalls](https://www.kernel.org/doc/html/latest/trace/ftrace.html)
- [Tetragon: Hook points documentation](https://tetragon.io/docs/concepts/tracing-policy/hooks/)

### `CONFIG_KPROBES`
Enables **kernel probes** — dynamic breakpoints on any kernel instruction address, inserted at runtime without modifying kernel code or rebooting.
Tetragon places kprobes on security-sensitive kernel functions (`security_file_open`, `tcp_connect`, `do_exec`, etc.) to observe and optionally block them. Kprobes incur overhead (trap/INT3 instruction) but can hook anywhere.
- [Kernel docs: kprobes](https://www.kernel.org/doc/html/latest/trace/kprobes.html)
- [Tetragon: Hook points documentation](https://tetragon.io/docs/concepts/tracing-policy/hooks/)

### `CONFIG_KPROBE_EVENTS`
Exposes kprobe attachment through the **perf/trace event API** (as opposed to the ftrace text interface). `BPF_PROG_TYPE_KPROBE` and `BPF_PROG_TYPE_KRETPROBE` programs are attached via this interface.
- [Kernel docs: kprobe-event](https://www.kernel.org/doc/html/latest/trace/kprobetrace.html)

### `CONFIG_UPROBES`
Enables **user-space probes** — breakpoints inserted into ELF binaries at specific offsets, mapped into process memory. OpenTelemetry OBI uses uprobes to auto-instrument language runtimes (Go, Python, Node.js, Java, Rust) for distributed tracing without modifying application code. Unlike kprobes (which hook the kernel), uprobes hook into userspace processes.
- [Kernel docs: uprobes](https://www.kernel.org/doc/html/latest/trace/uprobetracer.html)
- [OpenTelemetry eBPF Instrumentation (OBI)](https://opentelemetry.io/docs/zero-code/obi/)
- [Using eBPF with OpenTelemetry: Zero-Code Auto-Instrumentation](https://oneuptime.com/blog/post/2025-12-10-ebpf-with-opentelemetry-auto-instrumentation/view)

### `CONFIG_UPROBE_EVENTS`
The perf-event interface layer for uprobes; analogous to `CONFIG_KPROBE_EVENTS` but for userspace targets. Required for `BPF_PROG_TYPE_KPROBE` programs attached to uprobes. Enables functions like `bpf_get_current_pid_tgid()` and map operations to work correctly in uprobe context.
- [Kernel docs: uprobe-event](https://www.kernel.org/doc/html/latest/trace/uprobetracer.html)

### `CONFIG_TRACEPOINTS`
Defines the **static tracepoint instrumentation framework** — pre-placed hooks in the kernel (scheduler, memory, networking subsystems) with stable ABIs. Used by Tetragon (`sched_process_exec`, etc.) and OBI.
- [Kernel docs: tracepoints](https://www.kernel.org/doc/html/latest/trace/tracepoints.html)

### `CONFIG_PERF_EVENTS`
The **perf subsystem** — hardware performance counters, software events, and the ring-buffer transport used by BPF programs to send data to userspace. All `perf_event_open`-based BPF attachment (kprobes, uprobes, tracepoints) depends on this.
- [Kernel docs: perf events](https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html)

---

## 5 · tc-BPF — Cilium datapath

> Cilium's primary datapath attaches BPF programs at the **Traffic Control (tc)** layer on each veth/pod interface to implement load balancing, policy enforcement, and encapsulation without going through iptables. This is the **fast path** that processes every packet in the kernel. See [Cilium datapath architecture](https://docs.cilium.io/en/stable/network/ebpf/index.html) and [technical deep dives](https://medium.com/codex/cilium-technical-deep-dive-understanding-the-ebpf-data-path-2b942e3150ed) for implementation details.

### `CONFIG_NET_SCHED`
The **Queueing Discipline (qdisc) framework** — the scheduling and classification layer that sits between the network stack and device drivers. tc-BPF programs execute here at ingress and egress, making it the optimal hook for network policy and load balancing.
- [Kernel docs: tc](https://www.kernel.org/doc/html/latest/networking/net_sched.html)
- [How to Deploy Cilium CNI for eBPF-Powered Kubernetes Networking](https://oneuptime.com/blog/post/2026-01-07-ebpf-cilium-kubernetes-networking/view)

### `CONFIG_NET_SCH_INGRESS`
Enables the **clsact / ingress qdisc**, which is where Cilium hooks `BPF_PROG_TYPE_SCHED_CLS` programs on the *ingress* path (packets arriving at a veth before the network stack processes them). Without this, tc ingress BPF cannot be attached.
- [Cilium datapath](https://docs.cilium.io/en/stable/network/ebpf/intro/)

### `CONFIG_NET_CLS_ACT`
Enables **classifier-action chaining** within tc, allowing classifiers (like `cls_bpf`) to invoke actions (like `act_bpf` or `act_mirred`). Cilium's tc programs act both as classifier and action, making this option essential for its operation.
- [Kernel docs: tc actions](https://www.kernel.org/doc/html/latest/networking/net_sched.html)

### `CONFIG_NET_CLS_BPF`
The **`cls_bpf` classifier** — loads a BPF program as a tc classifier. This is the primary mechanism Cilium uses to attach eBPF programs to tc hooks on host and pod interfaces.
- [Cilium BPF and XDP reference](https://docs.cilium.io/en/stable/network/ebpf/intro/)
- [BPF Architecture — Cilium documentation](https://docs.cilium.io/en/latest/reference-guides/bpf/architecture/)

### `CONFIG_NET_ACT_BPF`
The **`act_bpf` action** — allows a BPF program to be invoked as a tc action (distinct from a classifier). Some Cilium and Tetragon configurations use this for supplementary actions.
- [Kernel docs: tc BPF](https://www.kernel.org/doc/html/latest/networking/net_sched.html)

### `CONFIG_NET_ACT_MIRRED`
The **`act_mirred` action** — redirects or mirrors packets between interfaces at the tc layer. Cilium uses this to steer traffic from host interfaces into container namespaces and vice versa, enabling pod-to-node and node-to-pod packet steering.
- [man8: tc-mirred](https://man7.org/linux/man-pages/man8/tc-mirred.8.html)
- [Container Networking Deep Dive](https://blog.shellnetsecurity.com/posts/2025/container-networking-fundamentals/)

---

## 6 · LWT-BPF — Cilium host routing / IPv6

> **Lightweight Tunnels (LWT)** allow custom packet transformations to be associated with routing table entries. Cilium uses LWT-BPF for host-routing and encapsulation decisions on specific routes.

### `CONFIG_LWTUNNEL`
The **LWT framework** core. Provides the hooks (input, output, xmit) that BPF and other encapsulation modules register handlers for within the routing layer.
- [Kernel docs: LWT](https://www.kernel.org/doc/html/latest/networking/lwtunnel.html)

### `CONFIG_LWTUNNEL_BPF`
Enables **BPF programs as LWT hooks**. Cilium uses `lwt_xmit` BPF programs to handle encapsulation (VXLAN/Geneve) for specific routing table entries, enabling per-route eBPF processing without tc.
- [Cilium routing](https://docs.cilium.io/en/stable/network/concepts/routing/)

---

## 7 · Cgroup v2 controllers — Docker, Tetragon process correlation

> cgroup v2 is the unified hierarchy used by Docker (with systemd cgroup driver) and Kubernetes. Tetragon reads cgroup identity to correlate kernel events with pods/containers.

### `CONFIG_CGROUPS`
The **cgroup subsystem core**. Required by every container runtime and by Tetragon for process tree tracking.
- [Kernel docs: cgroup v2](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

### `CONFIG_MEMCG`
**Memory cgroup controller** — enforces per-container memory limits and provides OOM tracking. Docker's `--memory` flag and Kubernetes resource limits both depend on this.
- [Kernel docs: memory cgroup](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#memory)

### `CONFIG_BLK_CGROUP`
**Block I/O cgroup controller** — enables per-container I/O throttling (used by Docker's `blkio` settings and the newer `io` cgroup v2 controller).
- [Kernel docs: io cgroup](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#io)

### `CONFIG_CGROUP_PIDS`
**PID cgroup controller** — limits the number of processes a container can create, preventing fork bombs. Required by Docker's `--pids-limit`.
- [Kernel docs: pids cgroup](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#pid)

### `CONFIG_CGROUP_FREEZER`
**Freezer cgroup controller** — allows a container's processes to be paused/resumed atomically. Used by Docker checkpoint/restore (CRIU) and some orchestrators.
- [Kernel docs: cgroup freezer](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

### `CONFIG_CGROUP_DEVICE`
**Device cgroup controller** — allows/denies access to specific device nodes within a container (used to implement Docker's device whitelist and Kubernetes `allowedDevices`).
- [Kernel docs: device cgroup](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#device-controller)

### `CONFIG_CGROUP_SCHED`
**CPU cgroup controller** — enforces CPU shares, quotas (`cpu.max`), and real-time scheduling limits per cgroup. Required for Docker `--cpus` and Kubernetes CPU requests/limits.
- [Kernel docs: cpu cgroup](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#cpu)

### `CONFIG_SOCK_CGROUP_DATA`
Embeds **cgroup identity into socket structures** so BPF programs can read `sk->cgroup` directly. This is how Cilium and OBI associate a network connection with the pod/container that owns it, without an expensive cgroup lookup per packet.
- [Kernel docs: cgroup BPF](https://www.kernel.org/doc/html/latest/bpf/index.html)

---

## 8 · Netfilter / iptables / conntrack

> Cilium can run in pure eBPF mode (no iptables) but ships compatibility shims; Docker's network plumbing always uses iptables/netfilter. Tetragon reads conntrack to correlate network events.

### `CONFIG_NETFILTER`
The **Netfilter framework** — the hook-based packet filtering layer that iptables, nftables, and conntrack all live on.
- [Netfilter project](https://www.netfilter.org/)

### `CONFIG_NETFILTER_ADVANCED`
Unlocks **advanced Netfilter features** (set matching, ipset, newer match/target modules). Required to compile in `NETFILTER_XT_*` modules below.
- [Netfilter project](https://www.netfilter.org/)

### `CONFIG_NF_CONNTRACK`
The **connection tracking subsystem** — maintains state tables for TCP/UDP/ICMP sessions. Docker MASQUERADE, Cilium NAT, and Tetragon network-event enrichment all depend on conntrack.
- [Kernel docs: conntrack](https://www.kernel.org/doc/html/latest/networking/nf_conntrack-sysctl.html)

### `CONFIG_NF_NAT`
The **NAT engine** built on top of conntrack. Docker uses MASQUERADE for container egress NAT; Cilium uses it in iptables-compatibility mode.
- [Netfilter NAT documentation](https://www.netfilter.org/documentation/)

### `CONFIG_NF_TABLES`
The **nftables framework** — the modern, set-based replacement for iptables. Required by newer Docker versions that default to nftables as the backend, and by Kubernetes clusters using the nftables kube-proxy mode.
- [nftables wiki](https://wiki.nftables.org/)

### `CONFIG_NF_TABLES_INET`
The **inet (dual IPv4/IPv6) nftables family** — allows writing a single nftables ruleset that applies to both IP versions, which is how Docker and Cilium use it.
- [nftables wiki](https://wiki.nftables.org/)

### `CONFIG_IP_NF_IPTABLES`
The **iptables framework for IPv4** — the classic packet filter table architecture.
- [iptables man page](https://man7.org/linux/man-pages/man8/iptables.8.html)

### `CONFIG_IP_NF_FILTER`
The **`filter` table** for iptables (`INPUT`, `OUTPUT`, `FORWARD` chains). Docker and kube-proxy write FORWARD rules here.
- [iptables man page](https://man7.org/linux/man-pages/man8/iptables.8.html)

### `CONFIG_IP_NF_NAT`
The **`nat` table** for iptables (`PREROUTING`, `POSTROUTING` chains). Docker's container MASQUERADE and port publishing rules live here.
- [iptables man page](https://man7.org/linux/man-pages/man8/iptables.8.html)

### `CONFIG_IP_NF_MANGLE`
The **`mangle` table** for iptables — used for packet marking and TTL manipulation. Cilium (iptables mode) uses marks to identify traffic that has already been processed by BPF.
- [iptables man page](https://man7.org/linux/man-pages/man8/iptables.8.html)

### `CONFIG_IP6_NF_IPTABLES`
The **ip6tables framework** — IPv6 equivalent of `CONFIG_IP_NF_IPTABLES`.
- [ip6tables man page](https://man7.org/linux/man-pages/man8/ip6tables.8.html)

### `CONFIG_IP6_NF_FILTER`
The IPv6 **`filter` table** for ip6tables.
- [ip6tables man page](https://man7.org/linux/man-pages/man8/ip6tables.8.html)

### `CONFIG_IP6_NF_NAT`
The IPv6 **`nat` table** for ip6tables — required for IPv6 NAT (NPTv6, masquerade in IPv6-only setups).
- [ip6tables man page](https://man7.org/linux/man-pages/man8/ip6tables.8.html)

### `CONFIG_NETFILTER_XT_MARK`
The **`mark` xtables match/target** — sets or matches the `skb->mark` field on packets. Cilium uses marks heavily in iptables mode to steer traffic and avoid double-NAT.
- [iptables-extensions: mark](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)

### `CONFIG_NETFILTER_XT_MATCH_BPF`
The **`bpf` xtables match** — runs a classic BPF filter on a packet as an iptables match condition. Allows existing iptables rules to delegate classification to a BPF program.
- [iptables-extensions: bpf](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)

### `CONFIG_NETFILTER_XT_MATCH_SOCKET`
The **`socket` xtables match** — looks up the socket that would receive the packet. Used by Cilium and Envoy to identify locally-owned connections for transparent proxy rules.
- [iptables-extensions: socket](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)

### `CONFIG_NETFILTER_XT_TARGET_TPROXY`
The **TPROXY xtables target** — redirects a packet to a local socket without changing its destination IP/port, enabling **transparent proxying**. Envoy relies on TPROXY to intercept traffic without `SO_REUSEPORT` tricks.
- [iptables-extensions: TPROXY](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)
- [Envoy transparent proxy](https://www.envoyproxy.io/docs/envoy/latest/configuration/listeners/lis_filters/original_dst_filter)

### `CONFIG_NETFILTER_XT_TARGET_CT`
The **`CT` xtables target** — allows explicit manipulation of conntrack entries (set zone, helper, status flags). Used by some Cilium configurations to assign conntrack zones per interface.
- [iptables-extensions: CT](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)

---

## 9 · Virtual netdevs — container networking + Cilium overlays

> Container networking is built on virtual network devices that connect namespaces and interfaces. Understanding these is essential for debugging container connectivity issues. See [container networking deep dives](https://blog.shellnetsecurity.com/posts/2025/container-networking-fundamentals/) and [advanced Linux networking techniques](https://blog.shellnetsecurity.com/posts/2025/advanced-linux-networking-techniques/) for comprehensive explanations.

### `CONFIG_TUN`
The **TUN/TAP driver** — creates virtual point-to-point (TUN) or Ethernet (TAP) devices. Used by WireGuard's userspace fallback, some VPN clients, and QEMU/KVM inside WSL2.
- [Kernel docs: tuntap](https://www.kernel.org/doc/html/latest/networking/tuntap.html)

### `CONFIG_VETH`
**Virtual Ethernet pairs** — the fundamental building block of container networking. Every Docker/Kubernetes container gets a `veth` pair: one end in the container namespace, the other on the host where Cilium attaches tc-BPF programs. Each veth acts as a bidirectional pipe between two network namespaces.
- [man8: ip-link veth](https://man7.org/linux/man-pages/man8/ip-link.8.html)
- [UMA Technology: Network Configurations for Kubernetes pods](https://umatechnology.org/network-configurations-for-kubernetes-pods-built-on-linux/)

### `CONFIG_BRIDGE`
The **software bridge driver** — the Linux equivalent of a network switch. Docker's default `bridge` network mode puts containers behind a `docker0` bridge that forwards traffic between the container and host network namespaces.
- [Kernel docs: bridge](https://www.kernel.org/doc/html/latest/networking/bridge.html)
- [Container Networking Deep Dive: Bridge, Host, and Overlay](https://dasroot.net/posts/2026/03/container-networking-deep-dive-bridge-host-overlay/)

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
- [Capturing Network Traffic Over Cilium VTEP Tunnels with eBPF](https://engineering.01cloud.com/2026/01/26/capturing-network-traffic-over-cilium-vtep-tunnels-with-ebpf-a-practical-guide/)

### `CONFIG_MACVLAN`
**MAC VLAN** — creates virtual interfaces that share the same physical NIC but have distinct MAC addresses and can be placed in separate namespaces. Used by some CNI plugins and Docker `macvlan` network mode.
- [Kernel docs: macvlan](https://www.kernel.org/doc/html/latest/networking/net_dev_ctx.html)

### `CONFIG_IPVLAN`
**IP VLAN** — like MACVLAN but shares the parent's MAC; only IP addresses differ. Used by `ipvlan`-mode CNI plugins and some Cilium routing configurations.
- [Kernel docs: ipvlan](https://www.kernel.org/doc/html/latest/networking/ipvlan.html)

### `CONFIG_DUMMY`
The **dummy network interface driver** — a virtual interface that swallows all traffic (like loopback but without the loopback semantics). Cilium uses dummy interfaces as attachment points for host-facing BPF programs.
- [man8: ip-link dummy](https://man7.org/linux/man-pages/man8/ip-link.8.html)

### `CONFIG_IFB`
**Intermediate Functional Block** — a virtual device used to redirect ingress traffic to an egress queue so that standard tc qdiscs (which only work egress) can be applied to incoming traffic. Used in some bandwidth-shaping setups alongside Cilium.
- [man8: tc-ifb](https://man7.org/linux/man-pages/man8/tc-ifb.8.html)

---

## 10 · Crypto / IPsec / WireGuard — Cilium transparent encryption

### `CONFIG_XFRM`
The **IPsec/XFRM framework** — the kernel's transform layer for encrypting and authenticating IP packets. Cilium's IPsec transparent encryption (node-to-node) runs through XFRM.
- [Kernel docs: XFRM](https://www.kernel.org/doc/html/latest/networking/xfrm_device.html)
- [Cilium IPsec](https://docs.cilium.io/en/stable/network/encryption-ipsec/)

### `CONFIG_XFRM_USER`
The **Netlink interface to XFRM** — exposes XFRM policy and SA management to userspace daemons (strongSwan, Cilium's IPsec operator) via `AF_KEY`/`XFRM_MSG_*`.
- [Kernel docs: XFRM](https://www.kernel.org/doc/html/latest/networking/xfrm_device.html)

### `CONFIG_XFRM_ALGO`
The **algorithm module framework for XFRM** — allows cipher and hash modules (AES-GCM, ChaCha20-Poly1305, SHA-256, etc.) to be registered and used by ESP/AH.
- [Kernel docs: XFRM](https://www.kernel.org/doc/html/latest/networking/xfrm_device.html)

### `CONFIG_INET_ESP`
**ESP (Encapsulating Security Payload) for IPv4** — the IPsec encapsulation protocol that provides encryption + authentication. Cilium IPsec mode uses ESP between nodes.
- [RFC 4303: ESP](https://www.rfc-editor.org/rfc/rfc4303)

### `CONFIG_INET6_ESP`
**ESP for IPv6** — the IPv6 equivalent of `CONFIG_INET_ESP`.
- [RFC 4303: ESP](https://www.rfc-editor.org/rfc/rfc4303)

### `CONFIG_WIREGUARD`
The **WireGuard VPN module** — a modern, high-performance, cryptographically opinionated VPN built into the kernel. Cilium uses WireGuard as its alternative transparent encryption mode (simpler key management than IPsec).
- [WireGuard project](https://www.wireguard.com/)
- [Cilium WireGuard](https://docs.cilium.io/en/stable/network/encryption-wireguard/)

---

## 11 · Storage — Docker overlay2 + alternate drivers

### `CONFIG_OVERLAY_FS`
The **OverlayFS union filesystem** — the default Docker storage driver (`overlay2`). Stacks a read-only image layer with a per-container read-write layer, enabling copy-on-write semantics for container image layers.
- [Kernel docs: overlayfs](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html)
- [Docker overlay2 driver](https://docs.docker.com/storage/storagedriver/overlayfs-driver/)

### `CONFIG_FUSE_FS`
The **FUSE (Filesystem in Userspace) driver** — allows filesystems to be implemented in userspace. Used by some container image formats (Nydus, SOCI snapshotter), rootless container storage drivers, and development tooling inside WSL2.
- [Kernel docs: FUSE](https://www.kernel.org/doc/html/latest/filesystems/fuse.html)

---

## 12 · Security primitives — required by Docker/runc, Tetragon, BPF-LSM

> These options provide kernel-level security mechanisms used by container runtimes and security agents. See [Linux Observability with BPF](https://www.oreilly.com/library/view/linux-observability-with/9781492050193/ch08.html) and [LSM BPF documentation](https://docs.kernel.org/bpf/prog_lsm.html) for comprehensive coverage.

### `CONFIG_SECCOMP`
The **secure computing mode** framework — allows a process to restrict its own (or a child's) allowed syscalls to a whitelist. Docker and runc apply seccomp profiles to every container; Tetragon's BPF-LSM mode can also leverage it. This is the **default container sandbox mechanism**.
- [Kernel docs: seccomp](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)
- [Docker seccomp profile](https://docs.docker.com/engine/security/seccomp/)
- [Seccomp BPF documentation](https://docs.kernel.org/userspace-api/seccomp_filter.html)

### `CONFIG_SECCOMP_FILTER`
Enables the **BPF-based seccomp filter** mechanism (as opposed to the older SECCOMP_MODE_STRICT). This is what `docker run --security-opt seccomp=profile.json` uses. Filters are evaluated as BPF bytecode at syscall entry, enabling fine-grained per-syscall argument filtering.
- [Kernel docs: seccomp_filter](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)
- [Practical Guide to Linux Security with Seccomp](https://www.oreilly.com/library/view/linux-observability-with/9781492050193/ch08.html)

### `CONFIG_AUDIT`
The **Linux Audit subsystem** — logs security-relevant events (syscalls, file accesses, policy decisions) to a ring buffer readable by `auditd`. Required by many container security benchmarks (CIS Docker Benchmark) and by SELinux/AppArmor policy enforcement logging. Essential for compliance and forensics.
- [Kernel docs: audit](https://www.kernel.org/doc/html/latest/admin-guide/audit.html)
- [Kernel runtime security instrumentation (LWN)](https://lwn.net/Articles/798157/)

---

## 13 · Misc performance / observability

### `CONFIG_TRANSPARENT_HUGEPAGE`
Enables **Transparent Huge Pages (THP)** — the kernel automatically promotes 4 KiB page mappings to 2 MiB huge pages when possible. Reduces TLB pressure for large working sets (JVM heaps, Envoy proxy buffers, BPF map backing memory).
- [Kernel docs: THP](https://www.kernel.org/doc/html/latest/admin-guide/mm/transhuge.html)

### `CONFIG_HUGETLBFS`
Provides the **HugeTLB filesystem** — allows applications to explicitly `mmap` pre-allocated huge pages (1 GiB on x86). Used by performance-sensitive databases and DPDK-style packet processing.
- [Kernel docs: hugetlbpage](https://www.kernel.org/doc/html/latest/admin-guide/mm/hugetlbpage.html)

### `CONFIG_IKCONFIG`
Embeds the **full kernel config** into the kernel binary itself. Allows any tool running on the system to read the config without needing access to the build tree.
- [Kconfig: CONFIG_IKCONFIG](https://cateee.net/lkddb/web-lkddb/IKCONFIG.html)

### `CONFIG_IKCONFIG_PROC`
Exposes the embedded config via **`/proc/config.gz`**. Tools like `cilium-bugtool`, `tetra`, and `bpftool feature` read this to verify kernel capabilities at runtime.
- [Kconfig: CONFIG_IKCONFIG_PROC](https://cateee.net/lkddb/web-lkddb/IKCONFIG_PROC.html)

### `CONFIG_IKHEADERS`
Embeds the **kernel headers** (the subset needed for BPF CO-RE) into the kernel via `/sys/kernel/kheaders.tar.xz`. Allows BPF programs to be compiled against the running kernel's exact headers without an external toolchain package.
- [Kconfig: CONFIG_IKHEADERS](https://cateee.net/lkddb/web-lkddb/IKHEADERS.html)

---

## Quick reference — option → workload mapping

| Config | Docker | Tetragon | Cilium | OBI | Envoy |
|---|:---:|:---:|:---:|:---:|:---:|
| `DEBUG_INFO_BTF` | | ✓ | ✓ | ✓ | |
| `BPF_LSM` | | ✓ | | | |
| `CGROUP_BPF` | | ✓ | ✓ | ✓ | |
| `BPF_STREAM_PARSER` | | | ✓ | | ✓ |
| `KPROBES` / `KPROBE_EVENTS` | | ✓ | | ✓ | |
| `UPROBES` / `UPROBE_EVENTS` | | | | ✓ | |
| `NET_CLS_BPF` / `NET_SCH_INGRESS` | | | ✓ | | |
| `LWTUNNEL_BPF` | | | ✓ | | |
| `NF_CONNTRACK` | ✓ | ✓ | ✓ | | |
| `XT_TARGET_TPROXY` | | | | | ✓ |
| `VETH` | ✓ | | ✓ | | |
| `VXLAN` / `GENEVE` | | | ✓ | | |
| `WIREGUARD` | | | ✓ | | |
| `INET_ESP` / `XFRM` | | | ✓ | | |
| `OVERLAY_FS` | ✓ | | | | |
| `SECCOMP_FILTER` | ✓ | ✓ | | | |

---

## Further reading

### Official & Kernel Documentation
- [Linux BPF Documentation](https://www.kernel.org/doc/html/latest/bpf/index.html) — Official kernel documentation for all BPF subsystems
- [BTF (BPF Type Format) Documentation](https://docs.kernel.org/bpf/btf.html) — Compact type metadata enabling CO-RE
- [LSM BPF Programs](https://docs.kernel.org/bpf/prog_lsm.html) — Linux Security Module BPF integration
- [Seccomp BPF Documentation](https://docs.kernel.org/userspace-api/seccomp_filter.html) — Syscall filtering
- [eBPF.io](https://ebpf.io/) — eBPF community hub with applications landscape and resources

### Authoritative Technical Guides
- [BPF CO-RE reference guide — Andrii Nakryiko](https://nakryiko.com/posts/bpf-core-reference-guide/) — Comprehensive guide to writing portable BPF with CO-RE
- [BPF CO-RE Portability — Nakryiko](https://nakryiko.com/posts/bpf-portability-and-co-re/) — Deep dive on CO-RE design and principles
- [BCC to libbpf conversion — Nakryiko](https://nakryiko.com/posts/bcc-to-libbpf-howto-guide/) — Modernizing BPF development practices
- [Brendan Gregg's eBPF Tracing Tools](https://www.brendangregg.com/ebpf.html) — Catalog of eBPF tools for observability
- [BPF Performance Tools (Book)](https://www.brendangregg.com/bpf-performance-tools-book.html) — Definitive guide to kernel tracing observability (80+ tools)

### Project Documentation & Blogs
- [Cilium Documentation](https://docs.cilium.io/) — eBPF-native networking and security
  - [BPF Architecture](https://docs.cilium.io/en/latest/reference-guides/bpf/architecture/)
  - [eBPF Datapath](https://docs.cilium.io/en/stable/network/ebpf/index.html)
  - [System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)
- [Cilium Technical Deep Dive — CodeX/Medium](https://medium.com/codex/cilium-technical-deep-dive-understanding-the-ebpf-data-path-2b942e3150ed) — Packet flow through Cilium's eBPF datapath
- [Demystifying Cilium — Solo.io](https://www.solo.io/blog/cilium-build-ebpf-cni-plugin) — Building eBPF CNI plugins from scratch
- [How to Deploy Cilium CNI — OneUptime](https://oneuptime.com/blog/post/2026-01-07-ebpf-cilium-kubernetes-networking/view) — Kubernetes deployment guide

- [Tetragon Documentation](https://tetragon.io/docs/) — eBPF-based security observability and runtime enforcement
  - [Overview](https://tetragon.io/docs/overview/)
  - [Hook Points](https://tetragon.io/docs/concepts/tracing-policy/hooks/)
  - [FAQ](https://tetragon.io/docs/installation/faq/)
- [eBPF Security with Tetragon — mylinux.work](https://mylinux.work/guides/ebpf-security-with-tetragon/) — Practical security observability guide
- [eBPF Security Monitoring — OneUptime](https://oneuptime.com/blog/post/2026-01-07-ebpf-security-monitoring-falco-tetragon/view) — Falco vs Tetragon comparison

- [OpenTelemetry eBPF Instrumentation (OBI)](https://opentelemetry.io/docs/zero-code/obi/) — Zero-code auto-instrumentation
- [Using eBPF with OpenTelemetry — OneUptime](https://oneuptime.com/blog/post/2025-12-10-ebpf-with-opentelemetry-auto-instrumentation/view) — Zero-code observability deep dive
- [OBI Complete Guide — DEV Community](https://dev.to/x4nent/opentelemetry-ebpf-instrumentation-obi-the-complete-guide-kubecon-eu-2026-beta-launch-5e2o) — KubeCon EU 2026 announcement and roadmap

### Container Networking & Architecture
- [Container Networking Fundamentals — Shell Net Security](https://blog.shellnetsecurity.com/posts/2025/container-networking-fundamentals/) — Comprehensive networking deep dive
- [Advanced Linux Networking Techniques — Shell Net Security](https://blog.shellnetsecurity.com/posts/2025/advanced-linux-networking-techniques/) — Namespaces, routing, traffic control
- [Container Networking Deep Dive — dasroot](https://dasroot.net/posts/2026/03/container-networking-deep-dive-bridge-host-overlay/) — Bridge, host, and overlay networking modes
- [CNI Specification & Implementation — Medium](https://bhattacharya-ratnadeep.medium.com/container-network-interface-cni-a-summary-279db1872fef) — Container Network Interface overview
- [Network Configurations for Kubernetes — UMA Technology](https://umatechnology.org/network-configurations-for-kubernetes-pods-built-on-linux/)

### Security & LSM
- [Practical Guide to LSM BPF](https://www.ebpf.top/en/post/lsm_bpf_intro/) — LSM BPF implementation patterns
- [Linux Observability with BPF (O'Reilly)](https://www.oreilly.com/library/view/linux-observability-with/9781492050193/ch08.html) — Chapter on security, capabilities, and seccomp
- [Some Freshness with LSM and eBPF — Medium](https://medium.com/@lumontec/some-freshness-with-linux-security-modules-and-ebpf-676ac363a135) — Modern kernel security with eBPF

### Ecosystem & 2024-2025 Progress
- [eBPF Ecosystem Progress 2024–2025 — eunomia](https://eunomia.dev/blog/2025/02/12/ebpf-ecosystem-progress-in-20242025-a-technical-deep-dive/) — Recent kernel improvements and tool maturation
- [eBPF Security: Top 5 Use Cases — Oligo Security](https://www.oligo.security/academy/ebpf-security-top-5-use-cases-challenges-and-best-practices)
- [Demystifying eBPF — Groundcover](https://www.groundcover.com/ebpf) — Common use cases and best practices
- [Best of 2025: eBPF — Cloud Native Now](https://cloudnativenow.com/editorial-calendar/best-of-2025/ebpf-the-silent-power-behind-cloud-natives-next-phase-2/) — eBPF's role in cloud native 2025

### Performance & BTF Troubleshooting
- [How to Tune Kernel Parameters for eBPF — OneUptime](https://oneuptime.com/blog/post/2026-01-07-ebpf-kernel-parameter-tuning/view) — Memory limits, stack size, verifier tuning
- [Building the Linux Kernel with BTF — Medium](https://medium.com/@suruti94/building-the-linux-kernel-with-btf-1a617cfb4a24) — BTF compilation and toolchain requirements
- [Mastering BPF Troubleshooting: BTF Support — VirtVPS](https://www.virtvps.com/btf-mastering-bpf-troubleshooting-unlocking/) — Debugging BTF issues
- [How I Compile the Linux Kernel for Security — Medium](https://medium.com/@jethomas100/how-i-compile-the-linux-kernel-for-security-9f3f0fc28de9) — Security-focused kernel compilation
- [Kernel Runtime Security Instrumentation — LWN](https://lwn.net/Articles/798157/) — LSM BPF and runtime security

### RFCs & Standards
- [RFC 7348: VXLAN](https://www.rfc-editor.org/rfc/rfc7348) — VXLAN encapsulation protocol
- [RFC 8926: Geneve](https://www.rfc-editor.org/rfc/rfc8926) — Generic Network Virtualization Encapsulation
- [RFC 4303: IPsec ESP](https://www.rfc-editor.org/rfc/rfc4303) — Encapsulating Security Payload
- [WireGuard White Paper](https://www.wireguard.com/papers/wireguard.pdf) — Modern cryptographic VPN design
- [nftables Wiki](https://wiki.nftables.org/) — Modern iptables replacement

### Tools & Practical Guides
- [eBPF Based Container Networking Performance Comparison — TNO/OS3](https://rp.os3.nl/2016-2017/p84/presentation.pdf) — Network performance analysis
- [GitHub: tunnel-cni](https://github.com/ebpf-networking/tunnel-cni) — VXLAN/Geneve CNI plugin
- [Capturing Traffic Over Cilium VTEP Tunnels with eBPF — 01cloud](https://engineering.01cloud.com/2026/01/26/capturing-network-traffic-over-cilium-vtep-tunnels-with-ebpf-a-practical-guide/) — Practical packet capture guide
- [Envoy Original Destination Filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/listeners/lis_filters/original_dst_filter) — Transparent proxy configuration
