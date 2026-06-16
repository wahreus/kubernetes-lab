# ConfigMaps, Secrets, and Storage

This guide describes how to practice application configuration, Secrets, volumes, PersistentVolumes, and PersistentVolumeClaims in Kubernetes.

At this point, the Kubernetes cluster should already be running with Calico installed, all three nodes should be `Ready`, and `kubectl` should be configured either on the control-plane node or on the local machine.

This exercise is intentionally focused on how Pods receive configuration and how data can outlive an individual Pod. It covers ConfigMaps, Secrets, environment variables, mounted configuration files, mounted Secret files, `emptyDir` volumes, hostPath-backed PersistentVolumes, PersistentVolumeClaims, and basic persistence testing.

## Architecture

The exercise uses a separate namespace:

```text
config-storage namespace
```

First, a Pod receives configuration from a ConfigMap and a Secret:

```text
ConfigMap: app-config
Secret: app-secret
        │
        ▼
Pod: config-reader
```

Next, NGINX serves a custom page mounted from a ConfigMap:

```text
ConfigMap: web-content
        │
        ▼
Pod: config-web
        │
        ▼
ClusterIP Service: config-web
```

Then, an `emptyDir` volume is used to share files between an init container and an application container:

```text
Pod: emptydir-demo
├── init container writes a file
└── nginx container serves the file
```

Finally, a PersistentVolume and PersistentVolumeClaim are used to keep data after a Pod is deleted:

```text
PersistentVolume: lab-pv
        │
        ▼
PersistentVolumeClaim: lab-pvc
        │
        ▼
Pod: pvc-writer
```

Important:

* A ConfigMap stores non-sensitive configuration.
* A Secret stores sensitive configuration, but it is not a complete security solution by itself.
* A volume mounts data into a container filesystem.
* An `emptyDir` volume lives as long as the Pod exists.
* A PersistentVolume can outlive the Pod that uses it.
* A PersistentVolumeClaim is a request for storage from a Pod.

## 1. Verify the cluster

Before starting, check that all nodes are `Ready`:

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

If using `kubectl` from the local machine, make sure the correct kubeconfig is active:

```bash
export KUBECONFIG=~/.kube/kubernetes-lab
kubectl get nodes
```

## 2. Create a namespace

Create a separate namespace for the exercise:

```bash
kubectl create namespace config-storage
```

Set it as the current namespace:

```bash
kubectl config set-context --current --namespace=config-storage
```

Check the current namespace:

```bash
kubectl config view --minify | grep namespace
```

Expected:

```text
namespace: config-storage
```

Important:

* The namespace keeps the exercise resources separate from earlier exercises.
* The current context is updated so that later commands do not need `-n config-storage`.

## 3. Create a ConfigMap

Create a ConfigMap with basic application settings:

```bash
kubectl create configmap app-config \
  --from-literal=APP_MODE=practice \
  --from-literal=LOG_LEVEL=debug
```

Check the ConfigMap:

```bash
kubectl get configmap app-config
```

Expected:

```text
NAME         DATA   AGE
app-config   2      ...
```

Inspect the values:

```bash
kubectl describe configmap app-config
```

Expected:

```text
Data
====
APP_MODE:
----
practice
LOG_LEVEL:
----
debug
```

Important:

* A ConfigMap is useful for configuration that should not be hard-coded into a container image.
* ConfigMaps are not intended for passwords, tokens, or private keys.

## 4. Create a Secret

Create a Secret with a fake practice token:

```bash
kubectl create secret generic app-secret \
  --from-literal=API_TOKEN=practice-token
```

Check the Secret:

```bash
kubectl get secret app-secret
```

Expected:

```text
NAME         TYPE     DATA   AGE
app-secret   Opaque   1      ...
```

Inspect the Secret metadata:

```bash
kubectl describe secret app-secret
```

Expected:

```text
Name:         app-secret
Namespace:    config-storage
Type:         Opaque

Data
====
API_TOKEN:  14 bytes
```

Important:

* `kubectl describe secret` shows metadata and key sizes, but not the Secret value.
* Kubernetes stores Secret values as base64-encoded data.
* Base64 encoding is **not** encryption.

## 5. Use the ConfigMap and Secret as environment variables

Create a Pod that reads both objects as environment variables:

```bash
cat <<'EOF' > config-reader.yaml
apiVersion: v1
kind: Pod
metadata:
  name: config-reader
spec:
  restartPolicy: Never
  containers:
    - name: busybox
      image: busybox:1.36
      command: ["sh", "-c", "env | sort | grep -E 'APP_MODE|LOG_LEVEL|API_TOKEN'"]
      envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secret
EOF
```

Apply it:

```bash
kubectl apply -f config-reader.yaml
```

Check the Pod:

```bash
kubectl get pod config-reader
```

Expected:

```text
NAME            READY   STATUS      RESTARTS   AGE
config-reader   0/1     Completed   0          ...
```

Check the logs:

```bash
kubectl logs config-reader
```

Expected:

```text
API_TOKEN=practice-token
APP_MODE=practice
LOG_LEVEL=debug
```

Important:

* `envFrom` can load all keys from a ConfigMap or Secret.
* Environment variables are simple, but changing the ConfigMap or Secret does not automatically restart existing Pods.
* Avoid printing real Secret values in logs.

## 6. Mount a ConfigMap as a file

Create a small HTML file:

```bash
cat <<'EOF' > index.html
<!DOCTYPE html>
<html>
<body>
<h1>Kubernetes config practice</h1>
<p>This page is mounted from a ConfigMap.</p>
</body>
</html>
EOF
```

Create a ConfigMap from the file:

```bash
kubectl create configmap web-content --from-file=index.html
```

Create an NGINX Pod that mounts the file:

```bash
cat <<'EOF' > config-web.yaml
apiVersion: v1
kind: Pod
metadata:
  name: config-web
  labels:
    app: config-web
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
      volumeMounts:
        - name: web-content
          mountPath: /usr/share/nginx/html/index.html
          subPath: index.html
  volumes:
    - name: web-content
      configMap:
        name: web-content
EOF
```

Apply it:

```bash
kubectl apply -f config-web.yaml
```

Check the Pod:

```bash
kubectl get pod config-web
```

Expected:

```text
NAME         READY   STATUS    RESTARTS   AGE
config-web   1/1     Running   0          ...
```

Expose the Pod with a ClusterIP Service:

```bash
kubectl expose pod config-web --port=80 --target-port=80
```

Test it from inside the cluster:

```bash
kubectl run curl \
  --image=curlimages/curl:latest \
  --rm -it \
  --restart=Never \
  -- curl http://config-web
```

Expected:

```html
<!DOCTYPE html>
<html>
<body>
<h1>Kubernetes config practice</h1>
<p>This page is mounted from a ConfigMap.</p>
</body>
</html>
```

Important:

* ConfigMaps can be mounted as files inside containers.
* `subPath` mounts a single key from the ConfigMap as one file.
* The container image did not need to be rebuilt to change the page content.

## 7. Mount a Secret as a file

Create a Pod that mounts the Secret as a file:

```bash
cat <<'EOF' > secret-reader.yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-reader
spec:
  restartPolicy: Never
  containers:
    - name: busybox
      image: busybox:1.36
      command: ["sh", "-c", "ls -l /etc/app-secret && cat /etc/app-secret/API_TOKEN"]
      volumeMounts:
        - name: app-secret
          mountPath: /etc/app-secret
          readOnly: true
  volumes:
    - name: app-secret
      secret:
        secretName: app-secret
EOF
```

Apply it:

```bash
kubectl apply -f secret-reader.yaml
```

Check the logs:

```bash
kubectl logs secret-reader
```

Expected:

```text
total 0
lrwxrwxrwx    ... API_TOKEN -> ..data/API_TOKEN
practice-token
```

Important:

* Secrets can be mounted as files.
* Each Secret key becomes a file by default.
* Mounting Secrets as files is often cleaner than injecting them as environment variables.

## 8. Use an emptyDir volume

Create a Pod with an init container and an `emptyDir` volume:

```bash
cat <<'EOF' > emptydir-demo.yaml
apiVersion: v1
kind: Pod
metadata:
  name: emptydir-demo
  labels:
    app: emptydir-demo
spec:
  initContainers:
    - name: write-page
      image: busybox:1.36
      command: ["sh", "-c", "echo 'This file was written by an init container.' > /work/index.html"]
      volumeMounts:
        - name: shared-data
          mountPath: /work
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
      volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html
  volumes:
    - name: shared-data
      emptyDir: {}
EOF
```

Apply it:

```bash
kubectl apply -f emptydir-demo.yaml
```

Check the Pod:

```bash
kubectl get pod emptydir-demo
```

Expected:

```text
NAME            READY   STATUS    RESTARTS   AGE
emptydir-demo   1/1     Running   0          ...
```

Expose it:

```bash
kubectl expose pod emptydir-demo --port=80 --target-port=80
```

Test it:

```bash
kubectl run curl \
  --image=curlimages/curl:latest \
  --rm -it \
  --restart=Never \
  -- curl http://emptydir-demo
```

Expected:

```text
This file was written by an init container.
```

Important:

* The init container runs before the main container.
* Both containers can mount the same `emptyDir` volume.
* `emptyDir` data disappears when the Pod is deleted.

## 9. Create a PersistentVolume

Check whether the cluster has a default StorageClass:

```bash
kubectl get storageclass
```

In this EC2 kubeadm lab, there may be no default StorageClass. That is fine. This exercise uses a manually created hostPath PersistentVolume.

Check the hostname label on `worker-a`:

```bash
kubectl get node worker-a --show-labels
```

Look for:

```text
kubernetes.io/hostname=worker-a
```

Important:

* The PersistentVolume below is pinned to `worker-a`.
* This keeps the writer Pod and reader Pod on the same node.
* If your worker node has a different name, change `worker-a` in the manifest before applying it.

Create a PersistentVolume:

```bash
cat <<'EOF' > lab-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: lab-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/kubernetes-lab-data
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - worker-a
EOF
```

Apply it:

```bash
kubectl apply -f lab-pv.yaml
```

Check the PersistentVolume:

```bash
kubectl get pv lab-pv
```

Expected:

```text
NAME     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   AGE
lab-pv   1Gi        RWO            Retain           Available           manual         ...
```

Important:

* A PersistentVolume is a cluster-level resource.
* It is not namespaced.
* `hostPath` is useful for practice, but it is not suitable for production multi-node storage.
* The node affinity tells Kubernetes that this volume belongs on `worker-a`.
* `Retain` means the PersistentVolume is not automatically deleted when the claim is deleted.

## 10. Create a PersistentVolumeClaim

Create a PersistentVolumeClaim:

```bash
cat <<'EOF' > lab-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lab-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  resources:
    requests:
      storage: 1Gi
EOF
```

Apply it:

```bash
kubectl apply -f lab-pvc.yaml
```

Check the claim:

```bash
kubectl get pvc lab-pvc
```

Expected:

```text
NAME      STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
lab-pvc   Bound    lab-pv   1Gi        RWO            manual         ...
```

Check the PersistentVolume again:

```bash
kubectl get pv lab-pv
```

Expected:

```text
NAME     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                    STORAGECLASS   AGE
lab-pv   1Gi        RWO            Retain           Bound    config-storage/lab-pvc   manual         ...
```

Important:

* A PersistentVolumeClaim is namespaced.
* The claim binds to a matching PersistentVolume.
* The Pod uses the claim, not the PersistentVolume directly.

## 11. Write data to the PersistentVolumeClaim

Create a Pod that writes data into the claim:

```bash
cat <<'EOF' > pvc-writer.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pvc-writer
spec:
  restartPolicy: Never
  containers:
    - name: busybox
      image: busybox:1.36
      command: ["sh", "-c", "date > /data/message.txt && cat /data/message.txt"]
      volumeMounts:
        - name: lab-storage
          mountPath: /data
  volumes:
    - name: lab-storage
      persistentVolumeClaim:
        claimName: lab-pvc
EOF
```

Apply it:

```bash
kubectl apply -f pvc-writer.yaml
```

Check the Pod:

```bash
kubectl get pod pvc-writer
```

Expected:

```text
NAME         READY   STATUS      RESTARTS   AGE
pvc-writer   0/1     Completed   0          ...
```

Check the logs:

```bash
kubectl logs pvc-writer
```

Expected:

```text
Tue Jun 16 10:30:00 UTC 2026
```

The exact date and timestamp will differ.

Important:

* The Pod writes to `/data/message.txt`.
* `/data` is backed by the PersistentVolumeClaim.
* The written file should remain available after this Pod is deleted.

## 12. Delete the Pod and read the data again

Delete the writer Pod:

```bash
kubectl delete pod pvc-writer
```

Create a new Pod that reads the same file:

```bash
cat <<'EOF' > pvc-reader.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pvc-reader
spec:
  restartPolicy: Never
  containers:
    - name: busybox
      image: busybox:1.36
      command: ["sh", "-c", "cat /data/message.txt"]
      volumeMounts:
        - name: lab-storage
          mountPath: /data
  volumes:
    - name: lab-storage
      persistentVolumeClaim:
        claimName: lab-pvc
EOF
```

Apply it:

```bash
kubectl apply -f pvc-reader.yaml
```

Check the logs:

```bash
kubectl logs pvc-reader
```

Expected:

```text
Tue Jun 16 10:30:00 UTC 2026
```

Important:

* The second Pod can read data written by the first Pod.
* The data survived Pod deletion.
* This is the key difference between container-local files and persistent storage.

## 13. Inspect the resources

List the ConfigMaps:

```bash
kubectl get configmaps
```

List the Secrets:

```bash
kubectl get secrets
```

List the Pods:

```bash
kubectl get pods
```

List the PersistentVolumeClaims:

```bash
kubectl get pvc
```

List the PersistentVolumes:

```bash
kubectl get pv
```

Describe the claim:

```bash
kubectl describe pvc lab-pvc
```

Important:

* ConfigMaps, Secrets, Pods, Services, and PersistentVolumeClaims are namespaced.
* PersistentVolumes are cluster-level resources.
* `kubectl describe` is often the fastest way to understand why a storage resource is not binding or mounting.

## 14. Clean up

Delete the namespaced resources:

```bash
kubectl delete pod config-reader secret-reader emptydir-demo pvc-reader --ignore-not-found
kubectl delete pod config-web --ignore-not-found
kubectl delete svc config-web emptydir-demo --ignore-not-found
kubectl delete configmap app-config web-content --ignore-not-found
kubectl delete secret app-secret --ignore-not-found
kubectl delete pvc lab-pvc --ignore-not-found
```

Delete the PersistentVolume:

```bash
kubectl delete pv lab-pv
```

Delete the generated local files:

```bash
rm -f \
  config-reader.yaml \
  index.html \
  config-web.yaml \
  secret-reader.yaml \
  emptydir-demo.yaml \
  lab-pv.yaml \
  lab-pvc.yaml \
  pvc-writer.yaml \
  pvc-reader.yaml
```

Delete the namespace:

```bash
kubectl delete namespace config-storage
```

Return to the default namespace:

```bash
kubectl config set-context --current --namespace=default
```

Check that the namespace was removed:

```bash
kubectl get namespace config-storage
```

Expected:

```text
Error from server (NotFound): namespaces "config-storage" not found
```

Important:

* Deleting the namespace removes namespaced resources inside it.
* PersistentVolumes are not namespaced, so they must be cleaned up separately.
* Returning to the default namespace avoids confusion in later exercises.

## Commands practiced

```text
kubectl get nodes
kubectl create namespace
kubectl config set-context
kubectl config view
kubectl create configmap
kubectl get configmap
kubectl describe configmap
kubectl create secret generic
kubectl get secret
kubectl describe secret
kubectl apply
kubectl get pod
kubectl logs
kubectl expose pod
kubectl run
kubectl get storageclass
kubectl get pv
kubectl get pvc
kubectl describe pvc
kubectl delete pod
kubectl delete svc
kubectl delete configmap
kubectl delete secret
kubectl delete pvc
kubectl delete pv
kubectl delete namespace
```

## Summary

This guide showed how to provide configuration and storage to Kubernetes Pods.

A separate namespace was created for the exercise. A ConfigMap was used for ordinary application settings, and a Secret was used for a fake practice token. Both objects were first injected as environment variables, then mounted as files to show the two most common ways Pods consume configuration.

An NGINX Pod served an HTML page mounted from a ConfigMap, demonstrating that application behavior can be changed without rebuilding a container image. A Secret was then mounted as a read-only directory, where each key became a file.

An `emptyDir` volume was used to share a file between an init container and an NGINX container inside the same Pod. This showed how containers in one Pod can share temporary storage, while also making clear that `emptyDir` data disappears when the Pod is deleted.

Finally, a hostPath-backed PersistentVolume and a PersistentVolumeClaim were created manually. One Pod wrote a timestamp into the claim, then a second Pod read the same file after the first Pod had been deleted. This demonstrated the main purpose of persistent storage: data can outlive the individual Pod that created it.