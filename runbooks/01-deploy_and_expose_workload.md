# Deploy and expose a workload

Deploy an NGINX application, expose it internally and externally, verify Service routing, scale the workload, and test self-healing.

## Prerequisites

* The Kubernetes cluster has been initialized.
* A CNI has been installed.

Run all commands on the **control-plane node** unless otherwise specified.

## 1. Verify the cluster

Verify that all nodes are ready:

```bash
kubectl get nodes -o wide
```

Verify that the system Pods are running:

```bash
kubectl get pods -A
```

Confirm that no system Pods remain in `Pending`, `CrashLoopBackOff`, or `Error`.

## 2. Create a namespace

Create a namespace for the workload:

```bash
kubectl create namespace workloads
```

Verify the namespace:

```bash
kubectl get namespace workloads
```

## 3. Create the workload manifest

Create a file named `web.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: workloads
  labels:
    app: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.28-alpine
          ports:
            - name: http
              containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 2
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: workloads
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: http
```

The manifest creates two resources in the `workloads` namespace:

* A Deployment named `web` that runs two replicas of the `nginx:1.28-alpine` container.
* A ClusterIP Service named `web` that exposes the Pods internally on port `80`.

The Deployment assigns the label `app=web` to each Pod. The Service uses the same label as its selector, allowing it to route traffic to the Pods.

The readiness probe sends an HTTP request to `/` every five seconds. A Pod is added as a Service endpoint only after the probe succeeds.

Apply the manifest:

```bash
kubectl apply -f web.yaml
```

Wait for the Deployment to become available:

```bash
kubectl rollout status deployment/web -n workloads
```

## 4. Verify the workload

Check the Deployment:

```bash
kubectl get deployment web -n workloads
```

Check the ReplicaSet and Pods:

```bash
kubectl get replicasets,pods -n workloads -o wide
```

Two Pods should report `Running` and `READY 1/1`.

Inspect the Deployment:

```bash
kubectl describe deployment web -n workloads
```

Confirm that:

* The Deployment has two available replicas.
* The Deployment uses the `RollingUpdate` strategy.
* The selector is `app=web`.
* The container uses the expected NGINX image.

## 5. Verify the Service

Check the Service:

```bash
kubectl get service web -n workloads
```

The Service should report `TYPE=ClusterIP` and expose port `80`.

Check the EndpointSlice created for the Service:

```bash
kubectl get endpointslices -n workloads -l kubernetes.io/service-name=web
```

The EndpointSlice should contain the IP addresses of both NGINX Pods. An EndpointSlice records the network endpoints selected by a Service, allowing Kubernetes to route Service traffic to the correct Pods efficiently.

Inspect the Service selector and Pod labels:

```bash
kubectl get service web -n workloads -o jsonpath='{.spec.selector}{"\n"}'
kubectl get pods -n workloads --show-labels
```

The Service selector must match the `app=web` label on the Pods because Kubernetes uses this match to identify which Pods belong to the Service. If the labels do not match, the Service has no endpoints and cannot route traffic to the application.

## 6. Test the Service

Run a temporary curl Pod inside the namespace:

```bash
kubectl run curl \
  --image=curlimages/curl:8.12.1 \
  --restart=Never \
  --rm -it \
  -n workloads \
  -- curl -I http://web
```

The response should include:

```text
HTTP/1.1 200 OK
```

This confirms that internal DNS resolution and Service routing are working.

## 7. Scale the Deployment

Scale the Deployment to four replicas:

```bash
kubectl scale deployment/web --replicas=4 -n workloads
```

Wait for the additional Pods:

```bash
kubectl rollout status deployment/web -n workloads
```

Verify the replicas:

```bash
kubectl get deployment,pods -n workloads -o wide
```

Check the EndpointSlice again:

```bash
kubectl get endpointslices \
  -n workloads \
  -l kubernetes.io/service-name=web
```

The Service should now have four Pod endpoints.

## 8. Test self-healing

List the Pods:

```bash
kubectl get pods -n workloads
```

Delete one of the Pods:

```bash
kubectl delete pod -n workloads <pod-name>
```

Check the Pods again:

```bash
kubectl get pods -n workloads
```

The ReplicaSet should create a replacement Pod to restore the desired replica count.

Verify that four Pods eventually report `Running`:

```bash
kubectl get pods -n workloads
```

## 9. Expose the workload externally

Change the Service type from `ClusterIP` to `NodePort`:

```bash
kubectl patch service web \
  -n workloads \
  -p '{"spec":{"type":"NodePort"}}'
```

A NodePort Service keeps its internal ClusterIP and also exposes the Service on the same port on every cluster node.

Check the updated Service:

```bash
kubectl get service web -n workloads
```

The Service should report `TYPE=NodePort`. Kubernetes automatically assigns a port from the default NodePort range of `30000-32767`.

Retrieve the assigned port:

```bash
NODE_PORT="$(kubectl get service web \
  -n workloads \
  -o jsonpath='{.spec.ports[0].nodePort}')"

echo "$NODE_PORT"
```

NodePort is available on every cluster node. On your **local machine**, open another terminal in the repository root and find a worker node's public IP:

```bash
grep 'worker-a public' environment_setup/lab_hosts.txt
```

Test the application using the public IP and assigned NodePort:

```bash
curl -I http://<worker-a-public-ip>:<node-port>
```

The response should include:

```text
HTTP/1.1 200 OK
```

This confirms that traffic can reach the Service from outside the cluster. The lab security group restricts NodePort access to the public CIDR configured when the lab was created.

## Troubleshooting

Inspect the workload resources:

```bash
kubectl get deployment,replicasets,pods,service -n workloads -o wide
```

Inspect recent namespace events:

```bash
kubectl get events \
  -n workloads \
  --sort-by=.metadata.creationTimestamp
```

Inspect a failing Pod:

```bash
kubectl describe pod -n workloads <pod-name>
kubectl logs -n workloads <pod-name>
```

Inspect the Deployment:

```bash
kubectl describe deployment web -n workloads
kubectl rollout status deployment/web -n workloads
```

Inspect Service routing:

```bash
kubectl describe service web -n workloads
kubectl get pods -n workloads --show-labels
kubectl get endpointslices \
  -n workloads \
  -l kubernetes.io/service-name=web
```

If the EndpointSlice contains no endpoints, verify that the Service selector matches the Pod labels.

Test the Service from another temporary Pod:

```bash
kubectl run curl \
  --image=curlimages/curl:8.12.1 \
  --restart=Never \
  --rm -it \
  -n workloads \
  -- curl -v http://web
```

Inspect the external Service configuration:

```bash
kubectl get service web -n workloads -o wide
kubectl get service web \
  -n workloads \
  -o jsonpath='{.spec.type}{" "}{.spec.ports[0].nodePort}{"\n"}'
```

If external access fails:

* Confirm that the Service type is `NodePort` and that a NodePort has been assigned.
* Confirm that you are using a node's public IP rather than its private IP.
* Confirm that the assigned port is allowed by the AWS security group from your current public IP.
* If your public IP has changed since the lab was created, rebuild the lab or update the allowed CIDR.

From your local machine, test the connection with verbose output:

```bash
curl -v http://<node-public-ip>:<node-port>
```