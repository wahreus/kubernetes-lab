# Calico vs. Cilium

Both Calico and Cilium provide Kubernetes networking and network policy, but their strengths lie in different areas.

| | Calico | Cilium |
|---|---|---|
| **Primary strength** | Flexible routing and network policy | eBPF networking and observability |
| **Routing** | Strong BGP and direct-routing support | Overlay or native routing, with optional BGP advertisement |
| **Network policies** | Ordered, global, deny, and host policies | Identity-, DNS-, and L7-aware policies |
| **Observability** | Available, but some features depend on edition | Hubble provides integrated flow visibility |
| **kube-proxy replacement** | Available with the eBPF dataplane | First-class optional capability |
| **Windows workers** | Supported with limitations | Not supported |
| **Kernel flexibility** | Can use non-eBPF dataplanes | Requires a modern Linux kernel |

Choose Calico for flexible routing, Windows support, and advanced policy controls. Choose Cilium for eBPF networking, Hubble observability, application-aware policies, and kube-proxy replacement.