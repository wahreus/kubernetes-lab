# Cluster setup (with Cilium CNI)

Initialize the Kubernetes control plane, install the Cilium CNI, join the worker nodes, and verify the cluster.

## Prerequisites

* `build_lab.sh` has completed successfully.
* A terminal session is open on each node.

Run all initialization and Cilium commands on the **control-plane node** unless otherwise specified.

## 1. Initialize the control plane

Determine the node's private IP address:

```bash
CONTROL_PLANE_PRIVATE_IP=$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')
echo "$CONTROL_PLANE_PRIVATE_IP"
```

Initialize Kubernetes with the Pod network used by Cilium:

```bash
sudo kubeadm init \
  --apiserver-advertise-address="$CONTROL_PLANE_PRIVATE_IP" \
  --pod-network-cidr="192.168.0.0/16"
```

## 2. Configure kubectl

Create a kubeconfig for the current non-root user:

```bash
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```

Verify access to the API server:

```bash
kubectl get nodes
```

The control-plane node will initially report `NotReady` because no CNI has been installed yet.

## 3. Install Cilium

Define the Cilium versions used in this runbook:

```bash
CILIUM_VERSION="1.19.5"
CILIUM_CLI_VERSION="v0.19.5"
```

Install the Cilium CLI:

```bash
CLI_ARCH="amd64"
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH="arm64"; fi

curl -L --fail --remote-name-all \
  "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz"{,.sha256sum}
sha256sum --check "cilium-linux-${CLI_ARCH}.tar.gz.sha256sum"
sudo tar xzvfC "cilium-linux-${CLI_ARCH}.tar.gz" /usr/local/bin
rm "cilium-linux-${CLI_ARCH}.tar.gz"{,.sha256sum}
```

Install Cilium with the configured Pod network:

```bash
cilium install \
  --version "$CILIUM_VERSION" \
  --set=ipam.operator.clusterPoolIPv4PodCIDRList="192.168.0.0/16"
```

Verify that the Cilium Pods are running:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

At this stage, a `cilium` Pod should report `Running` on the control-plane node. Additional Pods will later be created when the worker nodes join the cluster.

## 4. Join the worker nodes

Generate a worker join command on the control-plane node:

```bash
sudo kubeadm token create --print-join-command
```

Run the resulting command with `sudo` on both **worker-a** and **worker-b** nodes.

## 5. Verify the cluster

On the control-plane node, check the Cilium status:

```bash
cilium status
```

Wait until Cilium and the operator report:

```text
Cilium:   OK
Operator: OK
```

Verify the nodes:

```bash
kubectl get nodes -o wide
```

All three nodes should eventually report `Ready`.

Verify the system Pods:

```bash
kubectl get pods -A -o wide
```

Confirm that:

* Cilium Pods are running.
* CoreDNS Pods are running.
* All other system Pods report `Running` or `Completed`.
* No system Pods remain in `Pending`, `CrashLoopBackOff`, or `Error`.

## Troubleshooting

Inspect Cilium status:

```bash
cilium status --verbose
kubectl describe daemonset -n kube-system cilium
kubectl describe deployment -n kube-system cilium-operator
```

Inspect failing Pods:

```bash
kubectl get pods -A -o wide
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> --all-containers
```

Inspect the kubelet on the affected node using its terminal:

```bash
sudo journalctl -u kubelet -n 100 --no-pager
```
