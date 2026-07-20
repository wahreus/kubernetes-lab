# Cluster setup (with Calico CNI)

Initialize the Kubernetes control plane, install the Calico CNI, join the worker nodes, and verify the cluster.

## Prerequisites

* `build_lab.sh` has completed successfully.
* A terminal session is open on each node.

Run all initialization and Calico commands on the **control-plane node** unless otherwise specified.

## 1. Initialize the control plane

Determine the node's private IP address:

```bash
CONTROL_PLANE_PRIVATE_IP=$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')
echo "$CONTROL_PLANE_PRIVATE_IP"
```

Initialize Kubernetes with the Pod network used by Calico:

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

## 3. Install Calico

Define the Calico version used in this runbook:

```bash
CALICO_VERSION="v3.32.1"
```

Install the Calico custom resource definitions:

```bash
kubectl create -f \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/v1_crd_projectcalico_org.yaml"
```

Install the Tigera Operator:

```bash
kubectl create -f \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
```

Download the Calico installation configuration:

```bash
curl -fsSLo custom-resources.yaml \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml"
```

Configure Calico to use VXLAN encapsulation for all inter-node Pod traffic:

```bash
sed -i \
  's/encapsulation: VXLANCrossSubnet/encapsulation: VXLAN/' \
  custom-resources.yaml
```

Apply the Calico installation configuration:

```bash
kubectl create -f custom-resources.yaml
```

Verify that the Calico Pods are running:

```bash
kubectl get pods -n calico-system
```

At this stage, a `calico-node` Pod should report `Running` on the control-plane node. Additional Pods will be created when the worker nodes join the cluster.


## 4. Join the worker nodes

Generate a worker join command on the control-plane node:

```bash
sudo kubeadm token create --print-join-command
```

Run the resulting command with `sudo` on both **worker-a** and **worker-b** nodes.

## 5. Verify the cluster

On the control-plane node, check the Calico status:

```bash
kubectl get tigerastatus
```

Wait until every component reports:

```text
AVAILABLE   PROGRESSING   DEGRADED
True        False         False
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

* Calico Pods are running.
* CoreDNS Pods are running.
* All other system Pods report `Running` or `Completed`.
* No system Pods remain in `Pending`, `CrashLoopBackOff`, or `Error`.

## Troubleshooting

Inspect Calico status:

```bash
kubectl get tigerastatus
kubectl describe tigerastatus calico
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