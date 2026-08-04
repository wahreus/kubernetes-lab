# Configure workload resource requests and limits

Configure CPU and memory requests and limits for a Deployment, inspect how Kubernetes stores and uses them, and observe how they affect the Pod's quality-of-service class.

## Prerequisites

* The Kubernetes cluster has been initialized.
* A CNI has been installed.

Run all commands on the **control-plane node** unless otherwise specified.

## 1. Verify the cluster

Verify that all nodes are ready:

    kubectl get nodes

Confirm that the system Pods are running:

    kubectl get pods -A

## 2. Create a namespace

Create a namespace for the exercise:

```
kubectl create namespace resources
```

Verify the namespace:

```
kubectl get namespace resources
```

## 3. Create a resource-controlled Deployment

Create a file named `resources.yaml`:

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-demo
  namespace: resources
spec:
  replicas: 1
  selector:
    matchLabels:
      app: resource-demo
  template:
    metadata:
      labels:
        app: resource-demo
    spec:
      containers:
        - name: web
          image: nginx:1.28-alpine
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 128Mi
```

Apply the manifest:

```
kubectl apply -f resources.yaml
```

Wait for the Deployment to become available:

```
kubectl rollout status deployment/resource-demo -n resources
```

Verify the Deployment and Pod:

```
kubectl get deployment,pods -n resources -o wide
```

The requests reserve `100m` of CPU and `64Mi` of memory for scheduling. The container may use up to `250m` of CPU and `128Mi` of memory.

CPU usage above the limit is throttled. Memory usage above the limit can cause the container to be terminated with an `OOMKilled` status.

## 4. Inspect the resource configuration

Inspect the configured requests and limits:

```
kubectl describe pod \
  -n resources \
  -l app=resource-demo
```

Find the `Requests` and `Limits` entries under the `web` container.

## 5. Inspect the scheduling result

Find the node that runs the Pod:

```
kubectl get pods \
  -n resources \
  -l app=resource-demo \
  -o wide
```

Inspect the resources allocated on that node:

```
kubectl describe node <node-name>
```

In the `Allocated resources` section, the Pod's requests contribute to the node's requested CPU and memory totals. Kubernetes uses requests, rather than limits, when deciding whether a Pod fits on a node.

## 6. Inspect the Pod quality-of-service class

Inspect the Pod:

```
kubectl describe pod \
  -n resources \
  -l app=resource-demo
```

Find the `QoS Class` entry. It should be:

```
Burstable
```

The Pod is `Burstable` because it has CPU and memory requests, but the requests are lower than the corresponding limits.

## 7. Set equal requests and limits

Set the CPU request and limit to `100m`, and the memory request and limit to `64Mi`:

```
kubectl set resources deployment/resource-demo \
  -n resources \
  --requests=cpu=100m,memory=64Mi \
  --limits=cpu=100m,memory=64Mi
```

Wait for the updated Deployment to become available:

```
kubectl rollout status deployment/resource-demo -n resources
```

Verify the new resource configuration:

```
kubectl describe pod \
  -n resources \
  -l app=resource-demo
```

Find the `Requests` and `Limits` entries under the `web` container.

Check the `QoS Class` entry again. It should now be:

```
Guaranteed
```

A Pod receives the `Guaranteed` class when every container has CPU and memory requests and limits, and each request equals its corresponding limit.

> **Note:** `kubectl set resources` updates the live Deployment but does not modify `resources.yaml`. Reapplying the original file would restore the original values.

## Troubleshooting

Inspect the Deployment and Pod:

```
kubectl describe deployment resource-demo -n resources
kubectl describe pod -n resources <pod-name>
```

Inspect recent events:

```
kubectl get events \
  -n resources \
  --sort-by=.metadata.creationTimestamp
```

If the Pod remains `Pending`, inspect its scheduling events:

```
kubectl describe pod -n resources <pod-name>
```

Check the allocatable resources on each node:

```
kubectl describe nodes
```

Check the resource fields stored in the Deployment template:

```
kubectl describe deployment resource-demo -n resources
```
