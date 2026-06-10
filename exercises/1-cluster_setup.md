# Kubernetes Cluster Setup

This guide describes how to initialize a Kubernetes cluster after running:

```bash
./build_lab.sh
```

At this point, the AWS EC2 instances have been provisioned and the required Kubernetes tools are installed, but the cluster has not yet been initialized. This is intentional, so that `kubeadm init`, CNI installation (Calico), worker joins, and local `kubectl` setup can be practiced manually.

## Architecture

The lab uses three EC2 instances:

```text
control-plane
worker-a
worker-b
```

The control-plane node exposes the Kubernetes API server on port `6443`.

Use the control-plane **private IP** for communication between cluster nodes, and use the control-plane **public IP** only when connecting from your local machine. After running `./build_lab.sh`, these IP's are available in `lab_hosts.txt`.

## 1. Initialize the control plane

On the control-plane node, replace the IP values below with the actual values from Terraform:

```bash
CONTROL_PRIVATE_IP=<CONTROL_PLANE_PRIVATE_IP>
CONTROL_PUBLIC_IP=<CONTROL_PLANE_PUBLIC_IP>

sudo kubeadm init \
  --apiserver-advertise-address="$CONTROL_PRIVATE_IP" \
  --control-plane-endpoint="$CONTROL_PRIVATE_IP:6443" \
  --apiserver-cert-extra-sans="$CONTROL_PUBLIC_IP" \
  --apiserver-cert-extra-sans="$CONTROL_PRIVATE_IP" \
  --pod-network-cidr=192.168.0.0/16
```

Important:

* `--control-plane-endpoint` uses the private IP so worker nodes can join through the internal VPC network.
* `--apiserver-cert-extra-sans` includes the public IP so local `kubectl` can be used later from your machine.
* `--pod-network-cidr=192.168.0.0/16` is used for Calico.

## 2. Configure kubectl on the control-plane node

After `kubeadm init` completes, run:

```bash
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```

Check the node:

```bash
kubectl get nodes
```

At this stage, the control-plane node may show `NotReady`. This is expected until a CNI plugin is installed.

## 3. Install Calico

Download the Calico manifest:

```bash
curl -fL --retry 5 --retry-delay 5 \
  -o calico.yaml \
  https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/calico.yaml
```

Apply it:

```bash
kubectl apply -f calico.yaml
```

Check the system Pods:

```bash
kubectl get pods -A
```

Expected result:

```text
kube-system   calico-kube-controllers-...   1/1   Running
kube-system   calico-node-...               1/1   Running
kube-system   coredns-...                   1/1   Running
kube-system   etcd-control-plane            1/1   Running
kube-system   kube-apiserver-control-plane  1/1   Running
kube-system   kube-controller-manager-...   1/1   Running
kube-system   kube-proxy-...                1/1   Running
kube-system   kube-scheduler-control-plane  1/1   Running
```

Then check the node again:

```bash
kubectl get nodes
```

Expected:

```text
NAME            STATUS   ROLES           AGE   VERSION
control-plane   Ready    control-plane   ...   ...
```

## 4. Join the worker nodes

On the control-plane node, generate the join command:

```bash
kubeadm token create --print-join-command
```

It should produce a command using the control-plane private IP:

```bash
kubeadm join <CONTROL_PLANE_PRIVATE_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Run the join command on each worker with `sudo`:

```bash
sudo kubeadm join <CONTROL_PLANE_PRIVATE_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Back on the control-plane node, verify that all nodes joined:

```bash
kubectl get nodes
```

Expected:

```text
NAME            STATUS   ROLES           AGE   VERSION
control-plane   Ready    control-plane   ...   ...
worker-a        Ready    <none>          ...   ...
worker-b        Ready    <none>          ...   ...
```

## 5. Test the cluster

On the control plane node, create a simple deployment:

```bash
kubectl create deployment nginx --image=nginx
```

Check where the Pod is running:

```bash
kubectl get pods -o wide
```

Expose it with a NodePort service:

```bash
kubectl expose deployment nginx --port=80 --type=NodePort
```

Check the service:

```bash
kubectl get svc nginx
```

Get the assigned NodePort:

```bash
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
echo "$NODE_PORT"
```

From your local machine, test the service using a worker public IP:

```bash
WORKER_PUBLIC_IP=$(terraform -chdir=environment_setup/terraform output -raw worker_a_public_ip)

curl "http://$WORKER_PUBLIC_IP:$NODE_PORT"
```

Clean up the test deployment:

```bash
kubectl delete svc nginx
kubectl delete deployment nginx
```

## 6. Use kubectl from your local machine

Copy the kubeconfig from the control-plane node:

```bash
mkdir -p ~/.kube

scp -F environment_setup/ssh_config \
  k8s-control-plane:/home/ubuntu/.kube/config \
  ~/.kube/kubernetes-lab
```

Edit the copied file:

```bash
nano ~/.kube/kubernetes-lab
```

Change the API server from the private IP:

```yaml
server: https://<CONTROL_PLANE_PRIVATE_IP>:6443
```

to the public IP:

```yaml
server: https://<CONTROL_PLANE_PUBLIC_IP>:6443
```

Then use it locally:

```bash
export KUBECONFIG=~/.kube/kubernetes-lab
kubectl get nodes
```

Expected:

```text
NAME            STATUS   ROLES           AGE   VERSION
control-plane   Ready    control-plane   ...   ...
worker-a        Ready    <none>          ...   ...
worker-b        Ready    <none>          ...   ...
```

## 7. Destroy the lab

When finished, destroy the AWS resources to avoid unnecessary cost:

```bash
cd environment_setup
./destroy_lab.sh
```

## Commands practiced

```text
kubeadm init
kubeadm token create --print-join-command
kubeadm join
kubectl get nodes
kubectl get pods -A
kubectl apply
kubectl create deployment
kubectl get pods -o wide
kubectl expose deployment
kubectl get svc
kubectl delete svc
kubectl delete deployment
```

## Summary

This guide showed how to initialize a Kubernetes cluster on three AWS EC2 instances using `kubeadm`.

The control-plane node was initialized with the private IP as the internal cluster endpoint. The public IP was added to the API server certificate so that `kubectl` could connect from the local machine. Calico was then installed as the CNI plugin using the `192.168.0.0/16` Pod network CIDR.

After the control plane was ready, the worker nodes joined the cluster through the control-plane private IP. A simple NGINX Deployment and NodePort Service were used to verify that workloads could run on the cluster and be reached externally through a worker node public IP.

Finally, the kubeconfig was copied from the control-plane node to the local machine and updated to use the control-plane public IP, allowing the cluster to be managed locally with `kubectl`.