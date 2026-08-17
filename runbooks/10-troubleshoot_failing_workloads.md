# Troubleshoot failing workloads

Deploy several intentionally broken resources, identify each failure from Pod status and events, apply a targeted fix, and verify recovery.

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

## 2. Create a namespace

Create a namespace for the troubleshooting exercise:

```bash
kubectl create namespace troubleshooting
```

Verify the namespace:

```bash
kubectl get namespace troubleshooting
```

## 3. Create the failing resources

Create a file named `failing-workloads.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-error
  namespace: troubleshooting
spec:
  replicas: 1
  selector:
    matchLabels:
      app: image-error
  template:
    metadata:
      labels:
        app: image-error
    spec:
      containers:
        - name: web
          image: nginx:image-does-not-exist
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: config-error
  namespace: troubleshooting
spec:
  replicas: 1
  selector:
    matchLabels:
      app: config-error
  template:
    metadata:
      labels:
        app: config-error
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command:
            - sleep
            - "3600"
          env:
            - name: APP_MODE
              valueFrom:
                configMapKeyRef:
                  name: missing-config
                  key: APP_MODE
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probe-error
  namespace: troubleshooting
spec:
  replicas: 1
  selector:
    matchLabels:
      app: probe-error
  template:
    metadata:
      labels:
        app: probe-error
    spec:
      containers:
        - name: web
          image: nginx:1.28-alpine
          ports:
            - name: http
              containerPort: 80
          readinessProbe:
            httpGet:
              path: /missing
              port: http
            initialDelaySeconds: 2
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: probe-web
  namespace: troubleshooting
spec:
  selector:
    app: probe-error
  ports:
    - port: 80
      targetPort: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: scheduling-error
  namespace: troubleshooting
spec:
  replicas: 1
  selector:
    matchLabels:
      app: scheduling-error
  template:
    metadata:
      labels:
        app: scheduling-error
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command:
            - sleep
            - "3600"
          resources:
            requests:
              cpu: "1000"
              memory: 16Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-error
  namespace: troubleshooting
spec:
  replicas: 1
  selector:
    matchLabels:
      app: service-error
  template:
    metadata:
      labels:
        app: service-error
    spec:
      containers:
        - name: web
          image: nginx:1.28-alpine
          ports:
            - name: http
              containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: service-web
  namespace: troubleshooting
spec:
  selector:
    app: wrong-label
  ports:
    - port: 80
      targetPort: http
```

Apply the manifest:

```bash
kubectl apply -f failing-workloads.yaml
```

Wait briefly, then list the resources:

```bash
kubectl get deployments,pods,services -n troubleshooting -o wide
```

The resources intentionally contain five different faults. Do not reapply the original manifest after fixing them because it would restore the failures.

## 4. Diagnose the image error

Find the `image-error` Pod:

```bash
kubectl get pods -n troubleshooting -l app=image-error
```

Its status should eventually report `ImagePullBackOff` or `ErrImagePull`.

Inspect the Pod:

```bash
kubectl describe pod -n troubleshooting -l app=image-error
```

The events should show that Kubernetes cannot pull `nginx:image-does-not-exist`.

Fix the image:

```bash
kubectl set image deployment/image-error \
  -n troubleshooting \
  web=nginx:1.28-alpine
```

Wait for recovery:

```bash
kubectl rollout status deployment/image-error -n troubleshooting
```

Verify the Pod:

```bash
kubectl get pods -n troubleshooting -l app=image-error
```

## 5. Diagnose the missing ConfigMap

Find the `config-error` Pod:

```bash
kubectl get pods -n troubleshooting -l app=config-error
```

Its status should report `CreateContainerConfigError`.

Inspect the Pod:

```bash
kubectl describe pod -n troubleshooting -l app=config-error
```

The events should report that the ConfigMap `missing-config` was not found.

Create the required ConfigMap:

```bash
kubectl create configmap missing-config \
  -n troubleshooting \
  --from-literal=APP_MODE=production
```

Wait for the Deployment to become available:

```bash
kubectl rollout status deployment/config-error -n troubleshooting
```

Verify the environment variable:

```bash
kubectl exec deployment/config-error -n troubleshooting -- \
  printenv APP_MODE
```

The output should be:

```text
production
```

## 6. Diagnose the readiness probe

Inspect the `probe-error` Pod:

```bash
kubectl get pods -n troubleshooting -l app=probe-error
```

The Pod should report `Running`, but its `READY` column should remain `0/1`.

Inspect the Pod events:

```bash
kubectl describe pod -n troubleshooting -l app=probe-error
```

The events should report readiness probe failures with HTTP status code `404`.

Inspect the Service EndpointSlice:

```bash
kubectl get endpointslices \
  -n troubleshooting \
  -l kubernetes.io/service-name=probe-web \
  -o yaml
```

The endpoint should not be ready for Service traffic.

Patch the readiness probe path:

```bash
kubectl patch deployment probe-error \
  -n troubleshooting \
  --type=strategic \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"web","readinessProbe":{"httpGet":{"path":"/","port":"http"}}}]}}}}'
```

Wait for recovery:

```bash
kubectl rollout status deployment/probe-error -n troubleshooting
```

Verify that the Pod reports `READY 1/1`:

```bash
kubectl get pods -n troubleshooting -l app=probe-error
```

Check the EndpointSlice again:

```bash
kubectl get endpointslices \
  -n troubleshooting \
  -l kubernetes.io/service-name=probe-web \
  -o yaml
```

## 7. Diagnose the scheduling failure

Find the `scheduling-error` Pod:

```bash
kubectl get pods -n troubleshooting -l app=scheduling-error
```

The Pod should remain `Pending`.

Inspect its events:

```bash
kubectl describe pod -n troubleshooting -l app=scheduling-error
```

The scheduler should report insufficient CPU because the Pod requests `1000` CPU cores.

Inspect node capacity:

```bash
kubectl describe nodes
```

Set realistic resource requests and limits:

```bash
kubectl set resources deployment/scheduling-error \
  -n troubleshooting \
  --requests=cpu=10m,memory=16Mi \
  --limits=cpu=100m,memory=64Mi
```

Wait for recovery:

```bash
kubectl rollout status deployment/scheduling-error -n troubleshooting
```

Verify the assigned node:

```bash
kubectl get pods \
  -n troubleshooting \
  -l app=scheduling-error \
  -o wide
```

## 8. Diagnose the Service selector

Verify that the `service-error` Pod is ready:

```bash
kubectl get pods -n troubleshooting -l app=service-error
```

Inspect the Service:

```bash
kubectl describe service service-web -n troubleshooting
```

Inspect the Pod labels:

```bash
kubectl get pods \
  -n troubleshooting \
  -l app=service-error \
  --show-labels
```

Inspect the EndpointSlice:

```bash
kubectl get endpointslices \
  -n troubleshooting \
  -l kubernetes.io/service-name=service-web
```

The Service has no endpoints because its selector is `app=wrong-label`, while the Pod label is `app=service-error`.

Patch the Service selector:

```bash
kubectl patch service service-web \
  -n troubleshooting \
  -p '{"spec":{"selector":{"app":"service-error"}}}'
```

Verify that an endpoint appears:

```bash
kubectl get endpointslices \
  -n troubleshooting \
  -l kubernetes.io/service-name=service-web
```

Test the Service:

```bash
kubectl run curl \
  --image=curlimages/curl:8.12.1 \
  --restart=Never \
  --rm -it \
  -n troubleshooting \
  -- curl -I http://service-web
```

The response should include:

```text
HTTP/1.1 200 OK
```

## 9. Verify all repairs

List the Deployments and Pods:

```bash
kubectl get deployments,pods -n troubleshooting -o wide
```

Every Deployment should report one available replica, and every Pod should report `Running` and `READY 1/1`.

Check the Services and EndpointSlices:

```bash
kubectl get services,endpointslices -n troubleshooting
```

Inspect recent events:

```bash
kubectl get events \
  -n troubleshooting \
  --sort-by=.metadata.creationTimestamp
```

The event history may still contain the earlier failures even though the current resources are healthy.

## Troubleshooting approach

Start with a broad view:

```bash
kubectl get deployments,pods,services -n troubleshooting -o wide
```

Use the Pod status to select the next command:

* `ImagePullBackOff` or `ErrImagePull`: inspect the image name and image-pull events.
* `CreateContainerConfigError`: inspect referenced ConfigMaps, Secrets, and keys.
* `Running` but `READY 0/1`: inspect readiness probes and container health.
* `Pending`: inspect scheduler events, resource requests, node selectors, affinity, and taints.
* A Service with no endpoints: compare its selector with Pod labels and readiness.

Inspect a specific Pod:

```bash
kubectl describe pod -n troubleshooting <pod-name>
kubectl logs -n troubleshooting <pod-name>
```

Inspect recent events:

```bash
kubectl get events \
  -n troubleshooting \
  --sort-by=.metadata.creationTimestamp
```

Inspect workload ownership and rollout state:

```bash
kubectl get replicasets -n troubleshooting
kubectl rollout status deployment/<deployment-name> -n troubleshooting
```

Inspect Service routing:

```bash
kubectl describe service <service-name> -n troubleshooting
kubectl get pods -n troubleshooting --show-labels
kubectl get endpointslices \
  -n troubleshooting \
  -l kubernetes.io/service-name=<service-name>
```