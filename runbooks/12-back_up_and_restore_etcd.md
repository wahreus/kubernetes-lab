# Back up and restore etcd

Create and verify an etcd snapshot, add data after the snapshot, restore the snapshot on a single-control-plane kubeadm cluster, and verify the recovered state.

## Prerequisites

* The Kubernetes cluster has been initialized.
* A CNI has been installed.

Run all commands on the **control-plane node** unless otherwise specified.

## 1. Verify the cluster

Verify that all nodes are ready:

```bash
kubectl get nodes
```

Confirm that the system Pods are running:

```bash
kubectl get pods -A
```

Verify the local etcd Pod:

```bash
kubectl get pods \
  -n kube-system \
  -l component=etcd \
  -o wide
```

The kubeadm cluster uses a stacked etcd member running as a static Pod on the control-plane node.

## 2. Record the etcd Pod and configuration

Store the etcd Pod name:

```bash
ETCD_POD=$(kubectl get pods \
  -n kube-system \
  -l component=etcd \
  -o jsonpath='{.items[0].metadata.name}')
```

Store the etcd image name:

```bash
ETCD_IMAGE=$(kubectl get pod "$ETCD_POD" \
  -n kube-system \
  -o jsonpath='{.spec.containers[0].image}')
```

Read the member settings from the kubeadm static Pod manifest:

```bash
ETCD_NAME=$(sudo sed -n 's/.*--name=//p' \
  /etc/kubernetes/manifests/etcd.yaml | head -n 1)

ETCD_INITIAL_CLUSTER=$(sudo sed -n 's/.*--initial-cluster=//p' \
  /etc/kubernetes/manifests/etcd.yaml | head -n 1)

ETCD_INITIAL_ADVERTISE_PEER_URLS=$(sudo sed -n \
  's/.*--initial-advertise-peer-urls=//p' \
  /etc/kubernetes/manifests/etcd.yaml | head -n 1)
```

Print the recorded values:

```bash
echo "ETCD_POD=$ETCD_POD"
echo "ETCD_IMAGE=$ETCD_IMAGE"
echo "ETCD_NAME=$ETCD_NAME"
echo "ETCD_INITIAL_CLUSTER=$ETCD_INITIAL_CLUSTER"
echo "ETCD_INITIAL_ADVERTISE_PEER_URLS=$ETCD_INITIAL_ADVERTISE_PEER_URLS"
```

Verify that every value was returned before continuing. The restore must use the same member name and peer URL configuration as the kubeadm static Pod.

## 3. Create data to include in the snapshot

Create a namespace and ConfigMap that should survive the restore:

```bash
kubectl create namespace etcd-backup

kubectl create configmap snapshot-marker \
  -n etcd-backup \
  --from-literal=state=before-snapshot
```

Verify the marker:

```bash
kubectl get configmap snapshot-marker \
  -n etcd-backup \
  -o jsonpath='{.data.state}{"\n"}'
```

The output should be:

```text
before-snapshot
```

## 4. Create the etcd snapshot

Create a live snapshot in the etcd data directory, which is mounted from the control-plane filesystem:

```bash
kubectl exec "$ETCD_POD" -n kube-system -- \
  etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save /var/lib/etcd/etcd-snapshot.db
```

Verify the snapshot:

```bash
kubectl exec "$ETCD_POD" -n kube-system -- \
  etcdutl --write-out=table snapshot status \
  /var/lib/etcd/etcd-snapshot.db
```

Copy the snapshot from the mounted etcd data directory to the control-plane user's home directory:

```bash
sudo cp /var/lib/etcd/etcd-snapshot.db "$HOME/etcd-snapshot.db"
sudo chown "$USER:$USER" "$HOME/etcd-snapshot.db"
```

Verify the file:

```bash
ls -lh "$HOME/etcd-snapshot.db"
```

The snapshot file should exist and have a non-zero size.

Remove the temporary copy from the etcd data directory:

```bash
sudo rm /var/lib/etcd/etcd-snapshot.db
```

## 5. Create data after the snapshot

Create a second ConfigMap that should disappear after the restore:

```bash
kubectl create configmap post-snapshot-marker \
  -n etcd-backup \
  --from-literal=state=after-snapshot
```

Verify both ConfigMaps:

```bash
kubectl get configmaps -n etcd-backup
```

At this point, the live cluster contains both markers, but the snapshot contains only `snapshot-marker`.

## 6. Prepare for the restore

Create a directory outside the static Pod manifest path:

```bash
sudo mkdir -p /etc/kubernetes/manifests-disabled
```

Confirm that the snapshot is available:

```bash
ls -lh "$HOME/etcd-snapshot.db"
```

Record the current etcd data directory size:

```bash
sudo du -sh /var/lib/etcd
```

Confirm that the etcd image exists in containerd:

```bash
sudo ctr -n k8s.io images list | grep "$ETCD_IMAGE"
```

Do not continue unless the snapshot file and etcd image are available.

## 7. Stop the control plane

Move the control-plane static Pod manifests out of the directory watched by the kubelet:

```bash
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml \
  /etc/kubernetes/manifests-disabled/

sudo mv /etc/kubernetes/manifests/kube-controller-manager.yaml \
  /etc/kubernetes/manifests-disabled/

sudo mv /etc/kubernetes/manifests/kube-scheduler.yaml \
  /etc/kubernetes/manifests-disabled/

sudo mv /etc/kubernetes/manifests/etcd.yaml \
  /etc/kubernetes/manifests-disabled/
```

The kubelet detects that the manifests are gone and stops the static Pods.

Wait until all four containers are no longer running:

```bash
sudo crictl ps --name kube-apiserver
sudo crictl ps --name kube-controller-manager
sudo crictl ps --name kube-scheduler
sudo crictl ps --name etcd
```

Repeat the commands until each command returns only the table header and no running container.

`kubectl` commands will fail while the API server is stopped.

## 8. Preserve the current etcd data directory

Move the current etcd data directory aside:

```bash
sudo mv /var/lib/etcd /var/lib/etcd.pre-restore
```

Confirm that the original directory was moved:

```bash
sudo ls -ld /var/lib/etcd.pre-restore
```

Keeping the original directory provides a local rollback option if the snapshot restoration fails.

## 9. Restore the snapshot

Run `etcdutl` from the existing etcd image and restore the snapshot into a new data directory:

```bash
sudo ctr -n k8s.io run --rm \
  --mount "type=bind,src=$HOME,dst=/backup,options=rbind:rw" \
  --mount "type=bind,src=/var/lib,dst=/var/lib,options=rbind:rw" \
  "$ETCD_IMAGE" \
  etcd-restore \
  etcdutl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd \
  --name="$ETCD_NAME" \
  --initial-cluster="$ETCD_INITIAL_CLUSTER" \
  --initial-advertise-peer-urls="$ETCD_INITIAL_ADVERTISE_PEER_URLS"
```

Verify the restored directory:

```bash
sudo ls -la /var/lib/etcd
sudo ls -la /var/lib/etcd/member
```

Do not continue unless `/var/lib/etcd/member` exists.

## 10. Restart the control plane

Restore the etcd static Pod manifest first:

```bash
sudo mv /etc/kubernetes/manifests-disabled/etcd.yaml \
  /etc/kubernetes/manifests/
```

Wait for the etcd container to start:

```bash
sudo crictl ps --name etcd
```

Repeat the command until a running etcd container appears.

Restore the remaining control-plane manifests:

```bash
sudo mv /etc/kubernetes/manifests-disabled/kube-apiserver.yaml \
  /etc/kubernetes/manifests/

sudo mv /etc/kubernetes/manifests-disabled/kube-controller-manager.yaml \
  /etc/kubernetes/manifests/

sudo mv /etc/kubernetes/manifests-disabled/kube-scheduler.yaml \
  /etc/kubernetes/manifests/
```

Wait for the API server to respond:

```bash
until kubectl get nodes; do
  sleep 5
done
```

Verify the system Pods:

```bash
kubectl get pods -A
```

Some system components may take additional time to recover after the API server becomes available. Wait until the expected system Pods report ready before proceeding.

If system Pods remain unready, inspect their logs before continuing.

## 11. Verify the restored state

Verify that the pre-snapshot marker exists:

```bash
kubectl get configmap snapshot-marker \
  -n etcd-backup \
  -o jsonpath='{.data.state}{"\n"}'
```

The output should be:

```text
before-snapshot
```

Check for the post-snapshot marker:

```bash
kubectl get configmap post-snapshot-marker -n etcd-backup
```

The command should return `NotFound` because the ConfigMap was created after the snapshot.

Verify the nodes and system Pods:

```bash
kubectl get nodes
kubectl get pods -A
```

All nodes should be `Ready`, and all expected system Pods should be ready.

## 12. Remove the preserved data directory

Only after verifying both the restored API state and cluster health, remove the previous etcd data directory:

```bash
sudo rm -rf /var/lib/etcd.pre-restore
```

Retain `$HOME/etcd-snapshot.db` if you want to practise the restore again. Remove it when it is no longer needed:

```bash
rm "$HOME/etcd-snapshot.db"
```

## Troubleshooting

### Verify the snapshot

Confirm that the snapshot file exists:

```bash
ls -lh "$HOME/etcd-snapshot.db"
```

If the control plane is still running and you need to create or verify the snapshot again, repeat Step 4.

### Inspect static Pod manifests

```bash
sudo ls -l /etc/kubernetes/manifests
sudo ls -l /etc/kubernetes/manifests-disabled
```

### Inspect running and stopped containers

```bash
sudo crictl ps --name etcd
sudo crictl ps -a --name etcd

sudo crictl ps --name kube-apiserver
sudo crictl ps -a --name kube-apiserver

sudo crictl ps --name kube-controller-manager
sudo crictl ps -a --name kube-controller-manager

sudo crictl ps --name kube-scheduler
sudo crictl ps -a --name kube-scheduler
```

### Inspect container logs

```bash
sudo crictl logs <container-id>
```

### Inspect kubelet logs

```bash
sudo journalctl -u kubelet --since "10 minutes ago"
```

### etcd does not start

If the restored etcd container repeatedly exits, inspect its logs and confirm that:

* `/var/lib/etcd/member` exists.
* The restored directory is mounted by the static Pod.
* The etcd manifest points to `/var/lib/etcd`.
* The snapshot was created from this cluster.
* The member name and peer configuration used during restoration match the static Pod manifest.

If `ctr` cannot find the etcd image, confirm the exact image reference:

```bash
echo "$ETCD_IMAGE"
sudo ctr -n k8s.io images list
```

### System Pods cannot reach the Kubernetes API Service

After the restore, `kubectl` may work while Pods remain unable to reach the Kubernetes API through the `kubernetes` Service ClusterIP.

A typical error is:

```text
Get "https://10.96.0.1:443/api": connect: connection refused
```

Verify the Kubernetes Service:

```bash
kubectl get service kubernetes -o wide
```

Verify that its EndpointSlice points to the API server:

```bash
kubectl get endpointslices \
  -n default \
  -l kubernetes.io/service-name=kubernetes \
  -o wide
```

Verify kube-proxy:

```bash
kubectl get pods \
  -n kube-system \
  -l k8s-app=kube-proxy \
  -o wide
```

If the Service and EndpointSlice are correct but Pods on a node still cannot reach the Service ClusterIP, restart kube-proxy so that it rebuilds its Service-routing state:

```bash
kubectl rollout restart daemonset kube-proxy -n kube-system
```

Wait for the kube-proxy DaemonSet to become ready:

```bash
kubectl rollout status daemonset kube-proxy \
  -n kube-system \
  --timeout=120s
```

Then verify the system Pods again:

```bash
kubectl get pods -A
```

If a system component entered `CrashLoopBackOff` while the API Service was unavailable, inspect its logs and allow Kubernetes to restart it after Service connectivity has recovered.

Do not remove `/var/lib/etcd.pre-restore` until all recovery checks have passed.
