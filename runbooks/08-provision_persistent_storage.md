# Provision persistent storage

Create a static local PersistentVolume, bind it to a PersistentVolumeClaim, mount it into a Pod, and verify that data remains after the Pod is recreated.

## Prerequisites

* The Kubernetes cluster has been initialized.
* A CNI has been installed.

Run all commands on the **control-plane node** unless otherwise specified.

## 1. Verify the cluster

Verify that all nodes are ready:

```bash
kubectl get nodes -o wide
```

Confirm that the system Pods are running:

```bash
kubectl get pods -A
```

## 2. Select a worker node

Store the name of one worker node:

```bash
WORKER_NODE=$(kubectl get nodes \
  --selector='!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{.items[0].metadata.name}')
```

Print the selected node:

```bash
echo "$WORKER_NODE"
```

Verify that a worker node name was returned before continuing.

## 3. Create a namespace

Create a namespace for the storage exercise:

```bash
kubectl create namespace storage
```

Verify the namespace:

```bash
kubectl get namespace storage
```

## 4. Prepare local storage on the worker

Create a file named `prepare-storage.yaml` and replace `<worker-node>` with the value of `$WORKER_NODE`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: prepare-storage
  namespace: storage
spec:
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: <worker-node>
  containers:
    - name: prepare
      image: busybox:1.37
      command:
        - sh
        - -c
      args:
        - |
          mkdir -p /host-storage
          chmod 0777 /host-storage
          echo "local storage prepared on $(hostname)"
      volumeMounts:
        - name: local-storage
          mountPath: /host-storage
  volumes:
    - name: local-storage
      hostPath:
        path: /var/local/kubernetes-lab-storage
        type: DirectoryOrCreate
```

Apply the manifest:

```bash
kubectl apply -f prepare-storage.yaml
```

Wait for the Pod to complete:

```bash
kubectl wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  pod/prepare-storage \
  -n storage \
  --timeout=120s
```

Read its output:

```bash
kubectl logs prepare-storage -n storage
```

The helper Pod creates the local directory on the selected worker node.

## 5. Create the PersistentVolume and claim

Create a file named `local-storage.yaml` and replace `<worker-node>` with the same worker node name:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-demo
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /var/local/kubernetes-lab-storage
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - <worker-node>
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-pvc
  namespace: storage
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  resources:
    requests:
      storage: 500Mi
```

A local PersistentVolume must include node affinity because its data is available only on the node that contains the local directory.

Apply the manifest:

```bash
kubectl apply -f local-storage.yaml
```

Verify the binding:

```bash
kubectl get persistentvolume local-pv-demo
kubectl get persistentvolumeclaim local-pvc -n storage
```

Both resources should report `STATUS=Bound`.

Inspect the claim:

```bash
kubectl describe persistentvolumeclaim local-pvc -n storage
```

## 6. Mount the claim into a Pod

Create a file named `storage-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: storage-app
  namespace: storage
spec:
  containers:
    - name: app
      image: busybox:1.37
      command:
        - sh
        - -c
      args:
        - |
          if [ ! -f /data/message.txt ]; then
            echo "Persistent data created at $(date -u)" > /data/message.txt
          fi
          cat /data/message.txt
          sleep 3600
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: local-pvc
```

Apply the manifest:

```bash
kubectl apply -f storage-pod.yaml
```

Wait for the Pod to become ready:

```bash
kubectl wait \
  --for=condition=Ready \
  pod/storage-app \
  -n storage \
  --timeout=120s
```

Verify the assigned node:

```bash
kubectl get pod storage-app -n storage -o wide
```

The scheduler should place the Pod on the worker selected by the PersistentVolume's node affinity.

## 7. Write and inspect persistent data

Read the file created by the container:

```bash
kubectl exec storage-app -n storage -- cat /data/message.txt
```

Append another line:

```bash
kubectl exec storage-app -n storage -- \
  sh -c 'echo "Additional persistent data" >> /data/message.txt'
```

Verify the file:

```bash
kubectl exec storage-app -n storage -- cat /data/message.txt
```

## 8. Recreate the Pod

Delete the Pod:

```bash
kubectl delete pod storage-app -n storage
```

Recreate it from the same manifest:

```bash
kubectl apply -f storage-pod.yaml
```

Wait for it to become ready:

```bash
kubectl wait \
  --for=condition=Ready \
  pod/storage-app \
  -n storage \
  --timeout=120s
```

Read the file again:

```bash
kubectl exec storage-app -n storage -- cat /data/message.txt
```

Both lines should still be present. The Pod was recreated, but the data remained in the local PersistentVolume.

## 9. Inspect the storage relationship

Inspect the PersistentVolume:

```bash
kubectl describe persistentvolume local-pv-demo
```

Inspect the PersistentVolumeClaim:

```bash
kubectl describe persistentvolumeclaim local-pvc -n storage
```

Inspect the Pod volume configuration:

```bash
kubectl describe pod storage-app -n storage
```

Confirm that:

* The claim is bound to `local-pv-demo`.
* The Pod uses `local-pvc`.
* The Pod runs on the node required by the PersistentVolume node affinity.
* The PersistentVolume reclaim policy is `Retain`.

## 10. Clean up the Kubernetes resources

Delete the Pod and claim:

```bash
kubectl delete pod storage-app -n storage
kubectl delete persistentvolumeclaim local-pvc -n storage
```

Delete the PersistentVolume:

```bash
kubectl delete persistentvolume local-pv-demo
```

Delete the helper Pod:

```bash
kubectl delete pod prepare-storage -n storage
```

Because the PersistentVolume used the `Retain` reclaim policy, the local directory and its data remain on the selected worker node after the Kubernetes resources are deleted.

To reuse the same path in a later run, recreate the PersistentVolume and claim. To remove the data completely, delete `/var/local/kubernetes-lab-storage` directly on the selected worker node.

## Troubleshooting

Inspect the storage resources:

```bash
kubectl get persistentvolumes
kubectl get persistentvolumeclaims -n storage
kubectl describe persistentvolume local-pv-demo
kubectl describe persistentvolumeclaim local-pvc -n storage
```

Inspect the Pod and recent events:

```bash
kubectl describe pod storage-app -n storage
kubectl get events \
  -n storage \
  --sort-by=.metadata.creationTimestamp
```

If the claim remains `Pending`, verify that:

* The PersistentVolume and claim use the same `storageClassName`.
* The requested capacity does not exceed the PersistentVolume capacity.
* Their access modes match.
* The PersistentVolume is not already bound to another claim.

If the Pod remains `Pending`, inspect its scheduling events and the PersistentVolume node affinity:

```bash
kubectl describe pod storage-app -n storage
kubectl get persistentvolume local-pv-demo -o yaml
```

If the helper Pod remains `Pending`, verify that `<worker-node>` was replaced with a valid worker node name:

```bash
kubectl get nodes
kubectl describe pod prepare-storage -n storage
```