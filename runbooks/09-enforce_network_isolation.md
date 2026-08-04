# Enforce network isolation

Deploy a server and client Pods, apply a default-deny ingress policy, and allow traffic only from a selected namespace and Pod label.

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

NetworkPolicy rules require a CNI that enforces the Kubernetes NetworkPolicy API. Both cluster setup options used by this repository support NetworkPolicy enforcement.

## 2. Create the namespaces

Create a file named `network-namespaces.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: network-server
---
apiVersion: v1
kind: Namespace
metadata:
  name: network-allowed
  labels:
    network-access: allowed
---
apiVersion: v1
kind: Namespace
metadata:
  name: network-denied
  labels:
    network-access: denied
```

Apply the manifest:

```bash
kubectl apply -f network-namespaces.yaml
```

Verify the namespaces and labels:

```bash
kubectl get namespaces --show-labels | grep network-
```

## 3. Create the server workload

Create a file named `network-server.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: network-server
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
  namespace: network-server
spec:
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: http
```

Apply the manifest:

```bash
kubectl apply -f network-server.yaml
```

Wait for the Deployment to become available:

```bash
kubectl rollout status deployment/web -n network-server
```

Verify the server resources:

```bash
kubectl get deployment,pods,service -n network-server -o wide
```

## 4. Create the client Pods

Create a file named `network-clients.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: network-allowed
  labels:
    role: client
spec:
  containers:
    - name: curl
      image: curlimages/curl:8.12.1
      command:
        - sleep
        - "3600"
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: network-denied
  labels:
    role: client
spec:
  containers:
    - name: curl
      image: curlimages/curl:8.12.1
      command:
        - sleep
        - "3600"
```

Apply the manifest:

```bash
kubectl apply -f network-clients.yaml
```

Wait for both Pods to become ready:

```bash
kubectl wait \
  --for=condition=Ready \
  pod/client \
  -n network-allowed \
  --timeout=120s

kubectl wait \
  --for=condition=Ready \
  pod/client \
  -n network-denied \
  --timeout=120s
```

## 5. Verify unrestricted traffic

Test the Service from the allowed client:

```bash
kubectl exec client -n network-allowed -- \
  curl --silent --show-error --fail \
  http://web.network-server.svc.cluster.local
```

Test the Service from the denied client:

```bash
kubectl exec client -n network-denied -- \
  curl --silent --show-error --fail \
  http://web.network-server.svc.cluster.local
```

Both requests should return the NGINX welcome page because no NetworkPolicy currently selects the server Pods.

## 6. Apply default-deny ingress

Create a file named `default-deny-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: network-server
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

The empty Pod selector selects every Pod in the namespace. Because the policy defines no ingress rules, selected Pods accept no ingress traffic except traffic that is allowed by another NetworkPolicy.

Apply the policy:

```bash
kubectl apply -f default-deny-ingress.yaml
```

Verify the policy:

```bash
kubectl get networkpolicy -n network-server
kubectl describe networkpolicy default-deny-ingress -n network-server
```

## 7. Verify that ingress is denied

Test the Service from the allowed client:

```bash
kubectl exec client -n network-allowed -- \
  curl --connect-timeout 5 --max-time 10 \
  http://web.network-server.svc.cluster.local
```

Test the Service from the denied client:

```bash
kubectl exec client -n network-denied -- \
  curl --connect-timeout 5 --max-time 10 \
  http://web.network-server.svc.cluster.local
```

Both requests should time out or fail because the server Pods are isolated from ingress traffic.

## 8. Allow selected client traffic

Create a file named `allow-selected-client.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-selected-client
  namespace: network-server
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              network-access: allowed
          podSelector:
            matchLabels:
              role: client
      ports:
        - protocol: TCP
          port: 80
```

This policy allows TCP port `80` only when both conditions match:

* The source namespace has the label `network-access=allowed`.
* The source Pod has the label `role=client`.

Apply the policy:

```bash
kubectl apply -f allow-selected-client.yaml
```

Inspect both policies:

```bash
kubectl get networkpolicy -n network-server
kubectl describe networkpolicy allow-selected-client -n network-server
```

NetworkPolicy rules are additive. The allow policy adds permitted traffic without removing the default-deny policy.

## 9. Verify allowed and denied traffic

Test the Service from the allowed client:

```bash
kubectl exec client -n network-allowed -- \
  curl --silent --show-error --fail \
  http://web.network-server.svc.cluster.local
```

The request should return the NGINX welcome page.

Test the Service from the denied client:

```bash
kubectl exec client -n network-denied -- \
  curl --connect-timeout 5 --max-time 10 \
  http://web.network-server.svc.cluster.local
```

The request should still time out or fail because the source namespace label does not match the allow policy.

## 10. Verify selector behavior

Remove the required Pod label from the allowed client:

```bash
kubectl label pod client -n network-allowed role-
```

Test the connection again:

```bash
kubectl exec client -n network-allowed -- \
  curl --connect-timeout 5 --max-time 10 \
  http://web.network-server.svc.cluster.local
```

The request should fail because the source Pod no longer matches `role=client`.

Restore the label:

```bash
kubectl label pod client -n network-allowed role=client
```

Verify that the connection succeeds again:

```bash
kubectl exec client -n network-allowed -- \
  curl --silent --show-error --fail \
  http://web.network-server.svc.cluster.local
```

## Troubleshooting

Inspect the NetworkPolicies:

```bash
kubectl get networkpolicy -n network-server -o yaml
```

Inspect namespace and Pod labels:

```bash
kubectl get namespaces network-allowed network-denied --show-labels
kubectl get pods -A --show-labels | grep -E 'network-(server|allowed|denied)'
```

Inspect the server Service and EndpointSlice:

```bash
kubectl describe service web -n network-server
kubectl get endpointslices \
  -n network-server \
  -l kubernetes.io/service-name=web
```

Test DNS resolution separately from HTTP connectivity:

```bash
kubectl exec client -n network-allowed -- \
  nslookup web.network-server.svc.cluster.local
```

Inspect recent events:

```bash
kubectl get events \
  -n network-server \
  --sort-by=.metadata.creationTimestamp
```

If both clients can still connect after applying default deny:

* Confirm that the policies are in the same namespace as the server Pods.
* Confirm that the server Pods match the policy's Pod selector.
* Confirm that Calico or Cilium is healthy and configured to enforce NetworkPolicy.

Inspect the CNI Pods:

```bash
kubectl get pods -n kube-system -o wide
```