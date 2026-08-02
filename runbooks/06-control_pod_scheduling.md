# Control Pod scheduling

Label and taint a worker node, constrain Pods with node selectors and node affinity, and observe how tolerations affect scheduling.

## Prerequisites

* The Kubernetes cluster has been initialized using either cluster setup runbook.
* A CNI has been installed.

This runbook is independent of the other workload-management runbooks.

Run all commands on the control-plane node unless otherwise specified.

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

Create a namespace for the scheduling exercise:

```bash
kubectl create namespace scheduling
```

Verify the namespace:

```bash
kubectl get namespace scheduling
```

## 4. Label the worker node

Add a workload label to the selected node:

```bash
kubectl label node "$WORKER_NODE" workload-tier=compute
```

Verify the label:

```bash
kubectl get node "$WORKER_NODE" --show-labels
```

Labels provide information that scheduling rules can use to select suitable nodes.

## 5. Schedule a Pod with a node selector

Create a file named `node-selector.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: node-selector
  namespace: scheduling
spec:
  nodeSelector:
    workload-tier: compute
  containers:
    - name: app
      image: busybox:1.37
      command:
        - sleep
        - "3600"
```

Apply the manifest:

```bash
kubectl apply -f node-selector.yaml
```

Verify the assigned node:

```bash
kubectl get pod node-selector -n scheduling -o wide
```

The Pod should run on the node labeled `workload-tier=compute`.

Inspect the scheduling configuration:

```bash
kubectl describe pod node-selector -n scheduling
```

## 6. Schedule a Pod with required node affinity

Create a file named `required-affinity.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: required-affinity
  namespace: scheduling
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: workload-tier
                operator: In
                values:
                  - compute
  containers:
    - name: app
      image: busybox:1.37
      command:
        - sleep
        - "3600"
```

Apply the manifest:

```bash
kubectl apply -f required-affinity.yaml
```

Verify the assigned node:

```bash
kubectl get pod required-affinity -n scheduling -o wide
```

Required node affinity prevents the Pod from being scheduled on nodes that do not match the expression.

## 7. Schedule a Pod with preferred node affinity

Create a file named `preferred-affinity.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: preferred-affinity
  namespace: scheduling
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
              - key: workload-tier
                operator: In
                values:
                  - compute
  containers:
    - name: app
      image: busybox:1.37
      command:
        - sleep
        - "3600"
```

Apply the manifest:

```bash
kubectl apply -f preferred-affinity.yaml
```

Verify the assigned node:

```bash
kubectl get pod preferred-affinity -n scheduling -o wide
```

The scheduler prefers the labeled node, but it may use another suitable node because the rule is not required.

## 8. Taint the worker node

Delete the existing exercise Pods:

```bash
kubectl delete pod \
  node-selector \
  required-affinity \
  preferred-affinity \
  -n scheduling
```

Add a `NoSchedule` taint to the selected worker node:

```bash
kubectl taint node "$WORKER_NODE" dedicated=scheduling:NoSchedule
```

Verify the taint:

```bash
kubectl describe node "$WORKER_NODE"
```

Find the `Taints` entry. It should include:

```text
dedicated=scheduling:NoSchedule
```

A `NoSchedule` taint prevents new Pods from being scheduled on the node unless they tolerate the taint.

## 9. Observe a Pod without a toleration

Create a file named `blocked.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: blocked
  namespace: scheduling
spec:
  nodeSelector:
    workload-tier: compute
  containers:
    - name: app
      image: busybox:1.37
      command:
        - sleep
        - "3600"
```

Apply the manifest:

```bash
kubectl apply -f blocked.yaml
```

Check the Pod:

```bash
kubectl get pod blocked -n scheduling -o wide
```

The Pod should remain `Pending` because its node selector requires the tainted node but it has no matching toleration.

Inspect the scheduling events:

```bash
kubectl describe pod blocked -n scheduling
```

The events should report that the node had an untolerated taint.

## 10. Schedule a Pod with a toleration

Create a file named `tolerated.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tolerated
  namespace: scheduling
spec:
  nodeSelector:
    workload-tier: compute
  tolerations:
    - key: dedicated
      operator: Equal
      value: scheduling
      effect: NoSchedule
  containers:
    - name: app
      image: busybox:1.37
      command:
        - sleep
        - "3600"
```

Apply the manifest:

```bash
kubectl apply -f tolerated.yaml
```

Verify the assigned node:

```bash
kubectl get pod tolerated -n scheduling -o wide
```

The Pod should run on the selected worker because its toleration matches the taint and its node selector matches the label.

A toleration permits scheduling onto a tainted node, but it does not by itself require the Pod to use that node.

## 11. Restore the worker node

Delete the exercise Pods:

```bash
kubectl delete pod blocked tolerated -n scheduling
```

Remove the taint:

```bash
kubectl taint node "$WORKER_NODE" dedicated=scheduling:NoSchedule-
```

Remove the label:

```bash
kubectl label node "$WORKER_NODE" workload-tier-
```

Verify the restored node configuration:

```bash
kubectl describe node "$WORKER_NODE"
kubectl get node "$WORKER_NODE" --show-labels
```

## Troubleshooting

Inspect all exercise Pods and their assigned nodes:

```bash
kubectl get pods -n scheduling -o wide
```

Inspect a Pending Pod:

```bash
kubectl describe pod -n scheduling <pod-name>
```

Inspect node labels and taints:

```bash
kubectl get nodes --show-labels
kubectl describe node "$WORKER_NODE"
```

Inspect recent events:

```bash
kubectl get events \
  -n scheduling \
  --sort-by=.metadata.creationTimestamp
```

If `WORKER_NODE` is empty, list the nodes and select a worker manually:

```bash
kubectl get nodes
WORKER_NODE=<worker-node-name>
```

If a Pod remains `Pending`, verify that:

* Its node selector or required affinity matches an existing node label.
* The selected node is ready and schedulable.
* Every `NoSchedule` taint on the selected node has a matching toleration.
* The selected node has enough allocatable resources.

Always remove the exercise taint when finished:

```bash
kubectl taint node "$WORKER_NODE" dedicated=scheduling:NoSchedule-
```