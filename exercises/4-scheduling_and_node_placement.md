# Scheduling and Node Placement

This guide describes how to practice Kubernetes scheduling, labels, selectors, taints, tolerations, resource requests, and node maintenance.

At this point, the Kubernetes cluster should already be running with Calico installed, all three nodes should be `Ready`, and `kubectl` should be configured either on the control-plane node or on the local machine.

This exercise is intentionally focused on how Kubernetes decides where Pods should run.

It covers node labels, `nodeSelector`, node affinity, taints, tolerations, resource requests, scheduling failures, events, cordon, drain, and uncordon.

## Architecture

The exercise uses a separate namespace:

```text
scheduling namespace
```

The first Pods are scheduled using node labels:

```text
Node: worker-a
Labels:
  lab-role=frontend
  lab-disk=ssd

Node: worker-b
Labels:
  lab-role=backend
  lab-disk=hdd
```

Then a taint is added to one worker node:

```text
worker-b
  taint: lab=reserved:NoSchedule
```

A normal Pod should avoid the tainted node, while a Pod with a matching toleration can still run there.

Important:

* The scheduler places Pods on nodes.
* Node labels describe nodes.
* `nodeSelector` and node affinity tell the scheduler what kind of node a Pod needs.
* Taints repel Pods from a node.
* Tolerations allow Pods to run on tainted nodes.
* Resource requests affect whether a Pod can be scheduled.
* Cordon and drain are used during node maintenance.

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
kubectl create namespace scheduling
```

Set it as the current namespace:

```bash
kubectl config set-context --current --namespace=scheduling
```

Check the current namespace:

```bash
kubectl config view --minify | grep namespace
```

Expected:

```text
namespace: scheduling
```

Important:

* The namespace keeps the exercise resources separate from earlier exercises.
* The current context is updated so that later commands do not need `-n scheduling`.

## 3. Inspect node labels

Show the labels on all nodes:

```bash
kubectl get nodes --show-labels
```

Check the hostname labels:

```bash
kubectl get nodes -L kubernetes.io/hostname
```

Expected:

```text
NAME            STATUS   ROLES           AGE   VERSION   HOSTNAME
control-plane   Ready    control-plane   ...   ...       control-plane
worker-a        Ready    <none>          ...   ...       worker-a
worker-b        Ready    <none>          ...   ...       worker-b
```

Important:

* Nodes already have built-in labels.
* The `kubernetes.io/hostname` label is commonly used when targeting a specific node.
* Custom labels can be added for practice or for real scheduling decisions.

## 4. Add custom labels to worker nodes

Add labels to the worker nodes:

```bash
kubectl label node worker-a lab-role=frontend lab-disk=ssd
kubectl label node worker-b lab-role=backend lab-disk=hdd
```

Check the labels:

```bash
kubectl get nodes -L lab-role,lab-disk
```

Expected:

```text
NAME            STATUS   ROLES           AGE   VERSION   LAB-ROLE   LAB-DISK
control-plane   Ready    control-plane   ...   ...                  
worker-a        Ready    <none>          ...   ...       frontend   ssd
worker-b        Ready    <none>          ...   ...       backend    hdd
```

Important:

* Labels are key-value metadata.
* Labels do not move any existing Pods by themselves.
* Labels become useful when Pods, Services, or other objects select them.

## 5. Schedule a Pod with nodeSelector

Create a Pod that must run on the frontend node:

```bash
cat <<'EOF' > frontend-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: frontend-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.27
  nodeSelector:
    lab-role: frontend
EOF
```

Apply it:

```bash
kubectl apply -f frontend-pod.yaml
```

Check where the Pod was scheduled:

```bash
kubectl get pod frontend-pod -o wide
```

Expected:

```text
NAME           READY   STATUS    RESTARTS   AGE   IP    NODE
frontend-pod   1/1     Running   0          ...   ...   worker-a
```

Important:

* `nodeSelector` is the simplest way to require a Pod to run on a node with specific labels.
* If no node has the required label, the Pod stays `Pending`.

## 6. Create a scheduling failure

Create a Pod with a label requirement that no node can satisfy:

```bash
cat <<'EOF' > impossible-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: impossible-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.27
  nodeSelector:
    lab-role: database
EOF
```

Apply it:

```bash
kubectl apply -f impossible-pod.yaml
```

Check the Pod:

```bash
kubectl get pod impossible-pod
```

Expected:

```text
NAME             READY   STATUS    RESTARTS   AGE
impossible-pod   0/1     Pending   0          ...
```

Describe the Pod:

```bash
kubectl describe pod impossible-pod
```

Look for an event similar to:

```text
0/3 nodes are available: node(s) didn't match Pod's node affinity/selector.
```

Important:

* `Pending` often means the scheduler cannot find a valid node.
* Events explain why a Pod is not being scheduled.
* `kubectl describe pod` is usually the fastest first troubleshooting command.

Delete the failed Pod before continuing:

```bash
kubectl delete pod impossible-pod
```

## 7. Schedule a Pod with node affinity

Create a Pod that prefers SSD nodes, but can still run elsewhere if needed:

```bash
cat <<'EOF' > affinity-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: affinity-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.27
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: lab-disk
            operator: In
            values:
            - ssd
EOF
```

Apply it:

```bash
kubectl apply -f affinity-pod.yaml
```

Check where the Pod was scheduled:

```bash
kubectl get pod affinity-pod -o wide
```

Expected:

```text
NAME           READY   STATUS    RESTARTS   AGE   IP    NODE
affinity-pod   1/1     Running   0          ...   ...   worker-a
```

Important:

* Node affinity is more expressive than `nodeSelector`.
* `preferredDuringSchedulingIgnoredDuringExecution` means Kubernetes tries to follow the preference, but it is not required.
* `requiredDuringSchedulingIgnoredDuringExecution` would make the rule mandatory.

## 8. Add a taint to a worker node

Add a `NoSchedule` taint to `worker-b`:

```bash
kubectl taint node worker-b lab=reserved:NoSchedule
```

Check the taint:

```bash
kubectl describe node worker-b | grep -i taints
```

Expected:

```text
Taints: lab=reserved:NoSchedule
```

Important:

* A taint repels Pods from a node.
* `NoSchedule` means new Pods will not be scheduled there unless they tolerate the taint.
* Existing Pods are not automatically removed by a `NoSchedule` taint.

## 9. Create a Pod that cannot tolerate the taint

Create a Pod that requires `worker-b`, but does not tolerate its taint:

```bash
cat <<'EOF' > backend-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: backend-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.27
  nodeSelector:
    lab-role: backend
EOF
```

Apply it:

```bash
kubectl apply -f backend-pod.yaml
```

Check the Pod:

```bash
kubectl get pod backend-pod
```

Expected:

```text
NAME          READY   STATUS    RESTARTS   AGE
backend-pod   0/1     Pending   0          ...
```

Describe the Pod:

```bash
kubectl describe pod backend-pod
```

Look for an event similar to:

```text
node(s) had untolerated taint {lab: reserved}
```

Important:

* The Pod selects `worker-b`.
* The taint on `worker-b` blocks the Pod.
* The fix is either to remove the taint or add a matching toleration to the Pod.

Delete the failed Pod:

```bash
kubectl delete pod backend-pod
```

## 10. Create a Pod with a toleration

Create a Pod that requires `worker-b` and tolerates the taint:

```bash
cat <<'EOF' > tolerated-backend-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: tolerated-backend-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.27
  nodeSelector:
    lab-role: backend
  tolerations:
  - key: lab
    operator: Equal
    value: reserved
    effect: NoSchedule
EOF
```

Apply it:

```bash
kubectl apply -f tolerated-backend-pod.yaml
```

Check where the Pod was scheduled:

```bash
kubectl get pod tolerated-backend-pod -o wide
```

Expected:

```text
NAME                    READY   STATUS    RESTARTS   AGE   IP    NODE
tolerated-backend-pod   1/1     Running   0          ...   ...   worker-b
```

Important:

* A toleration does not force a Pod onto a tainted node.
* It only allows the scheduler to place the Pod there.
* In this example, `nodeSelector` requires `worker-b`, and the toleration allows that placement to succeed.

## 11. Create a scheduling failure with resource requests

Create a Pod that requests more CPU than the lab can provide:

```bash
cat <<'EOF' > cpu-hungry-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: cpu-hungry-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    resources:
      requests:
        cpu: "100"
        memory: "128Mi"
      limits:
        cpu: "100"
        memory: "128Mi"
EOF
```

Apply it:

```bash
kubectl apply -f cpu-hungry-pod.yaml
```

Check the Pod:

```bash
kubectl get pod cpu-hungry-pod
```

Expected:

```text
NAME             READY   STATUS    RESTARTS   AGE
cpu-hungry-pod   0/1     Pending   0          ...
```

Describe the Pod:

```bash
kubectl describe pod cpu-hungry-pod
```

Look for an event similar to:

```text
Insufficient cpu
```

Important:

* Resource requests are used by the scheduler.
* Limits are enforced by the container runtime.
* A Pod can remain `Pending` if no node has enough allocatable resources for its requests.

Delete the failed Pod:

```bash
kubectl delete pod cpu-hungry-pod
```

## 12. Practice cordon

Cordon `worker-a` so new Pods are not scheduled there:

```bash
kubectl cordon worker-a
```

Check the node status:

```bash
kubectl get nodes
```

Expected:

```text
NAME            STATUS                     ROLES           AGE   VERSION
control-plane   Ready                      control-plane   ...   ...
worker-a        Ready,SchedulingDisabled   <none>          ...   ...
worker-b        Ready                      <none>          ...   ...
```

Create a Pod that requires `worker-a`:

```bash
cat <<'EOF' > cordon-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: cordon-test-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.27
  nodeSelector:
    lab-role: frontend
EOF
```

Apply it:

```bash
kubectl apply -f cordon-test-pod.yaml
```

Check the Pod:

```bash
kubectl get pod cordon-test-pod
```

Expected:

```text
NAME              READY   STATUS    RESTARTS   AGE
cordon-test-pod   0/1     Pending   0          ...
```

Important:

* Cordon marks a node as unschedulable.
* Existing Pods keep running.
* New Pods are not scheduled onto the cordoned node.

Delete the failed Pod:

```bash
kubectl delete pod cordon-test-pod
```

## 13. Practice drain and uncordon

Before draining, list the Pods with their nodes:

```bash
kubectl get pods -o wide
```

Drain `worker-a`:

```bash
kubectl drain worker-a --ignore-daemonsets --delete-emptydir-data --force
```

Check the Pods:

```bash
kubectl get pods -o wide
```

Some standalone Pods may be deleted and not recreated. This is expected because they are not managed by a Deployment.

Uncordon `worker-a`:

```bash
kubectl uncordon worker-a
```

Check the node status:

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

Important:

* Drain prepares a node for maintenance by evicting workloads.
* Drain also marks the node as unschedulable.
* `--force` is used here because this exercise created standalone Pods.
* Uncordon allows new Pods to be scheduled there again.
* Standalone Pods are fragile during drain. Deployments are safer because they recreate Pods.

## 14. Inspect scheduler events

Show recent events:

```bash
kubectl get events --sort-by=.lastTimestamp
```

Look for scheduling-related reasons:

```text
Scheduled
FailedScheduling
```

Describe one of the remaining Pods:

```bash
kubectl describe pod tolerated-backend-pod
```

Look for:

```text
Node-Selectors: lab-role=backend
Tolerations:    lab=reserved:NoSchedule
```

Important:

* Events are useful when a Pod is `Pending`, evicted, or repeatedly recreated.
* `kubectl describe` combines object configuration, status, and recent events.
* Scheduling issues are often visible before application logs exist.

## 15. Clean up

Delete the Pods:

```bash
kubectl delete pod frontend-pod affinity-pod tolerated-backend-pod --ignore-not-found
```

Remove the taint from `worker-b`:

```bash
kubectl taint node worker-b lab=reserved:NoSchedule-
```

Remove the custom labels:

```bash
kubectl label node worker-a lab-role- lab-disk-
kubectl label node worker-b lab-role- lab-disk-
```

Delete the generated local files:

```bash
rm -f \
  frontend-pod.yaml \
  impossible-pod.yaml \
  affinity-pod.yaml \
  backend-pod.yaml \
  tolerated-backend-pod.yaml \
  cpu-hungry-pod.yaml \
  cordon-test-pod.yaml
```

Delete the namespace:

```bash
kubectl delete namespace scheduling
```

Return to the default namespace:

```bash
kubectl config set-context --current --namespace=default
```

Check that the namespace was removed:

```bash
kubectl get namespace scheduling
```

Expected:

```text
Error from server (NotFound): namespaces "scheduling" not found
```

Important:

* Labels and taints live on nodes, so they must be cleaned up separately.
* Deleting the namespace removes namespaced resources inside it.
* Returning to the default namespace avoids confusion in later exercises.

## Commands practiced

```text
kubectl get nodes
kubectl create namespace
kubectl config set-context
kubectl config view
kubectl label node
kubectl get pod -o wide
kubectl apply
kubectl describe pod
kubectl delete pod
kubectl taint node
kubectl describe node
kubectl cordon
kubectl drain
kubectl uncordon
kubectl get events
kubectl delete namespace
```

## Summary

This guide showed how Kubernetes scheduling decisions are affected by node labels, selectors, affinity, taints, tolerations, resource requests, and node maintenance state.

Custom labels were added to the worker nodes, and `nodeSelector` was used to place a Pod on a specific node. A failed scheduling example showed how a Pod remains `Pending` when no node matches its selector. Node affinity was then used to express a softer preference for SSD-labeled nodes.

A taint was added to `worker-b` to repel ordinary Pods. A Pod that selected `worker-b` stayed `Pending` until a matching toleration was added. Another failed scheduling example used an oversized CPU request to show how resource requests affect placement.

Finally, `worker-a` was cordoned and drained to practice node maintenance. The exercise ended by inspecting scheduling events, removing the taint and custom labels, deleting the namespace, and returning the current context to the default namespace.