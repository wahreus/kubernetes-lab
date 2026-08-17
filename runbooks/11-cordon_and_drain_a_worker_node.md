# Cordon and drain a worker node

Cordon and drain a worker node, observe how controller-managed and unmanaged Pods are handled, and return the node to service.

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

Create a namespace for the maintenance exercise:

```bash
kubectl create namespace maintenance
```

Verify the namespace:

```bash
kubectl get namespace maintenance
```

## 4. Create maintenance workloads

Create a file named `maintenance.yaml` and replace `<worker-node>` with the value of `$WORKER_NODE`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: maintenance
spec:
  replicas: 4
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values:
                      - <worker-node>
      containers:
        - name: web
          image: nginx:1.28-alpine
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: unmanaged
  namespace: maintenance
spec:
  nodeName: <worker-node>
  containers:
    - name: app
      image: busybox:1.37
      command:
        - sleep
        - "3600"
```

The Deployment Pods are controller-managed and prefer the selected worker node. The standalone `unmanaged` Pod is assigned directly to that node and has no controller that can recreate it.

Apply the manifest:

```bash
kubectl apply -f maintenance.yaml
```

Wait for the Deployment to become available:

```bash
kubectl rollout status deployment/web -n maintenance
```

Wait for the standalone Pod:

```bash
kubectl wait \
  --for=condition=Ready \
  pod/unmanaged \
  -n maintenance \
  --timeout=120s
```

Inspect the Pod placement:

```bash
kubectl get pods -n maintenance -o wide
```

## 5. Cordon the worker node

Mark the selected node as unschedulable:

```bash
kubectl cordon "$WORKER_NODE"
```

Verify the node state:

```bash
kubectl get node "$WORKER_NODE"
```

The node should report `SchedulingDisabled`.

Cordoning prevents new Pods from being scheduled onto the node, but it does not remove Pods that are already running there.

Verify that the existing Pods remain:

```bash
kubectl get pods -n maintenance -o wide
```

## 6. Observe how drain handles an unmanaged Pod

Attempt to drain the node while ignoring DaemonSet Pods:

```bash
kubectl drain "$WORKER_NODE" --ignore-daemonsets
```

The command should refuse to complete because the node contains the standalone `unmanaged` Pod, which is not controlled by a Deployment, ReplicaSet, Job, DaemonSet, or another controller.

Inspect the Pod ownership:

```bash
kubectl describe pod unmanaged -n maintenance
```

The Pod should have no `Controlled By` entry.

Delete the unmanaged Pod explicitly:

```bash
kubectl delete pod unmanaged -n maintenance
```

Deleting it is safe for this exercise because it contains no persistent application state.

## 7. Drain the worker node

Drain the node again:

```bash
kubectl drain "$WORKER_NODE" --ignore-daemonsets
```

The command should evict the Deployment Pods while leaving DaemonSet Pods in place.

Verify the node and workload:

```bash
kubectl get node "$WORKER_NODE"
kubectl get pods -n maintenance -o wide
```

The Deployment controller should create replacement Pods on another schedulable worker node.

Wait for the Deployment to become available:

```bash
kubectl rollout status deployment/web -n maintenance
```

Inspect Pods that remain on the drained node:

```bash
kubectl get pods -A \
  --field-selector spec.nodeName="$WORKER_NODE" \
  -o wide
```

DaemonSet Pods, such as CNI agents, normally remain because `--ignore-daemonsets` allows the drain to continue without evicting them.

## 8. Return the node to service

Mark the worker node as schedulable again:

```bash
kubectl uncordon "$WORKER_NODE"
```

Verify the node state:

```bash
kubectl get node "$WORKER_NODE"
```

The node should no longer report `SchedulingDisabled`.

## 9. Verify new scheduling

Scale the Deployment to five replicas:

```bash
kubectl scale deployment/web --replicas=5 -n maintenance
```

Wait for the Deployment:

```bash
kubectl rollout status deployment/web -n maintenance
```

Inspect the Pod placement:

```bash
kubectl get pods -n maintenance -o wide
```

Because the Deployment prefers the selected worker node, at least one new Pod should normally be scheduled there after the node is uncordoned. Preferred affinity is not a guarantee, so the scheduler may choose another suitable node.

## 10. Restore the exercise state

Scale the Deployment back to four replicas:

```bash
kubectl scale deployment/web --replicas=4 -n maintenance
```

Verify that the selected worker is ready and schedulable:

```bash
kubectl get node "$WORKER_NODE"
```

Always uncordon the node before finishing the runbook.

## Troubleshooting

Inspect node conditions, taints, and scheduling state:

```bash
kubectl describe node "$WORKER_NODE"
```

List all Pods on the selected node:

```bash
kubectl get pods -A \
  --field-selector spec.nodeName="$WORKER_NODE" \
  -o wide
```

If drain reports unmanaged Pods, inspect each Pod's owner:

```bash
kubectl describe pod -n <namespace> <pod-name>
```

If drain reports Pods using `emptyDir` volumes, decide whether their local data can be discarded. For disposable data, rerun drain with:

```bash
kubectl drain "$WORKER_NODE" \
  --ignore-daemonsets \
  --delete-emptydir-data
```

If drain reports a PodDisruptionBudget violation, inspect the budgets and available replicas before forcing any action:

```bash
kubectl get poddisruptionbudgets -A
```

Inspect recent events:

```bash
kubectl get events \
  -n maintenance \
  --sort-by=.metadata.creationTimestamp
```

If replacement Pods remain `Pending`, inspect their scheduling events and the capacity of the remaining worker node:

```bash
kubectl describe pod -n maintenance <pod-name>
kubectl describe nodes
```

If the procedure is interrupted, return the node to service:

```bash
kubectl uncordon "$WORKER_NODE"
```