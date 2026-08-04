# Manage Deployment rollouts and rollbacks

Create a Deployment, update its container image, inspect the rollout history, and roll back to the previous revision.

## Prerequisites

* The Kubernetes cluster has been initialized.
* A CNI has been installed.

Run all commands on the **control-plane node** unless otherwise specified.

## 1. Verify the cluster

Verify that all nodes are ready:

```
kubectl get nodes
```

Confirm that the system Pods are running:

```
kubectl get pods -A
```

## 2. Create a namespace

Create a namespace for the rollout exercise:

```
kubectl create namespace rollouts
```

Verify the namespace:

```
kubectl get namespace rollouts
```

## 3. Create the initial Deployment

Create a file named `rollout.yaml`:

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: rollouts
  annotations:
    kubernetes.io/change-cause: "Initial deployment with nginx:1.27-alpine"
spec:
  replicas: 3
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app: web
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.27-alpine
          ports:
            - name: http
              containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 2
            periodSeconds: 5
```

Create the Deployment:

```
kubectl create -f rollout.yaml
```

Wait for the initial rollout to complete:

```
kubectl rollout status deployment/web -n rollouts
```

Verify the Deployment and its Pods:

```
kubectl get deployment,replicasets,pods -n rollouts -o wide
```

Confirm the current container image:

```
kubectl describe deployment web -n rollouts
```

Find the `Image` entry. It should be:

```
nginx:1.27-alpine
```

## 4. Update the Deployment

Update the container image:

```
kubectl set image deployment/web \
  -n rollouts \
  web=nginx:1.28-alpine
```

Watch the rollout:

```
kubectl rollout status deployment/web -n rollouts
```

Record the reason for the update:

```
kubectl annotate deployment web \
  -n rollouts \
  kubernetes.io/change-cause="Update to nginx:1.28-alpine" \
  --overwrite
```

Inspect the ReplicaSets and Pods:

```
kubectl get replicasets,pods -n rollouts -o wide
```

The new ReplicaSet should have three ready replicas. The previous ReplicaSet should remain with zero replicas so that Kubernetes can use it for a rollback.

Confirm the updated image:

```
kubectl describe deployment web -n rollouts
```

Find the `Image` entry. It should be:

```
nginx:1.28-alpine
```

## 5. Inspect the rollout history

List the Deployment revisions:

```
kubectl rollout history deployment/web -n rollouts
```

Inspect the first revision:

```
kubectl rollout history deployment/web \
  -n rollouts \
  --revision=1
```

Inspect the second revision:

```
kubectl rollout history deployment/web \
  -n rollouts \
  --revision=2
```

The revision details should show the container image and the recorded change cause for each version.

## 6. Roll back the Deployment

Roll back to the previous revision:

```
kubectl rollout undo deployment/web -n rollouts
```

Wait for the rollback to complete:

```
kubectl rollout status deployment/web -n rollouts
```

Verify the current image:

```
kubectl describe deployment web -n rollouts
```

Find the `Image` entry. It should again be:

```
nginx:1.27-alpine
```

Inspect the updated rollout history:

```
kubectl rollout history deployment/web -n rollouts
```

A rollback creates a new Deployment revision rather than deleting the newer revision from the history.

## Troubleshooting

Inspect the Deployment:

```
kubectl describe deployment web -n rollouts
```

Inspect the rollout status and history:

```
kubectl rollout status deployment/web -n rollouts
kubectl rollout history deployment/web -n rollouts
```

Inspect the ReplicaSets and Pods:

```
kubectl get replicasets,pods -n rollouts -o wide
```

Inspect recent events:

```
kubectl get events \
  -n rollouts \
  --sort-by=.metadata.creationTimestamp
```

If a Pod cannot start, inspect it and check its container image:

```
kubectl describe pod -n rollouts <pod-name>
```

Find the `Image` entry under the container.