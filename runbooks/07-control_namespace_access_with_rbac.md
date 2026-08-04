# Control namespace access with RBAC

Create a ServiceAccount, grant it read-only Pod access within one namespace, and verify both allowed and denied API operations.

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

Create a namespace for the access-control exercise:

```bash
kubectl create namespace access-control
```

Verify the namespace:

```bash
kubectl get namespace access-control
```

## 3. Create the RBAC resources

Create a file named `rbac.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-reader
  namespace: access-control
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: access-control
rules:
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader
  namespace: access-control
subjects:
  - kind: ServiceAccount
    name: pod-reader
    namespace: access-control
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
```

The Role grants permission to read Pods only in the `access-control` namespace. The RoleBinding assigns those permissions to the `pod-reader` ServiceAccount.

Apply the manifest:

```bash
kubectl apply -f rbac.yaml
```

Verify the resources:

```bash
kubectl get serviceaccount,role,rolebinding -n access-control
```

## 4. Create Pods for the access test

Create a file named `rbac-pods.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: target
  namespace: access-control
  labels:
    app: target
spec:
  containers:
    - name: app
      image: busybox:1.37
      command:
        - sleep
        - "3600"
---
apiVersion: v1
kind: Pod
metadata:
  name: api-client
  namespace: access-control
spec:
  serviceAccountName: pod-reader
  containers:
    - name: curl
      image: curlimages/curl:8.12.1
      command:
        - sleep
        - "3600"
```

Apply the manifest:

```bash
kubectl apply -f rbac-pods.yaml
```

Wait for both Pods to become ready:

```bash
kubectl wait \
  --for=condition=Ready \
  pod/target \
  pod/api-client \
  -n access-control \
  --timeout=120s
```

Verify the Pods:

```bash
kubectl get pods -n access-control -o wide
```

## 5. Test permissions with kubectl

Check whether the ServiceAccount can list Pods in its namespace:

```bash
kubectl auth can-i list pods \
  -n access-control \
  --as=system:serviceaccount:access-control:pod-reader
```

The output should be:

```text
yes
```

Check whether it can delete Pods:

```bash
kubectl auth can-i delete pods \
  -n access-control \
  --as=system:serviceaccount:access-control:pod-reader
```

The output should be:

```text
no
```

Check whether it can list Pods in another namespace:

```bash
kubectl auth can-i list pods \
  -n kube-system \
  --as=system:serviceaccount:access-control:pod-reader
```

The output should be:

```text
no
```

A Role and RoleBinding are namespace-scoped, so the granted permissions do not apply to other namespaces.

## 6. Test allowed API access from the Pod

Open a shell in the API client Pod:

```bash
kubectl exec -it api-client -n access-control -- sh
```

Inside the container, set the ServiceAccount token and certificate paths:

```sh
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
API=https://kubernetes.default.svc
```

List Pods in the `access-control` namespace:

```sh
curl --silent \
  --cacert "$CACERT" \
  --header "Authorization: Bearer $TOKEN" \
  "$API/api/v1/namespaces/access-control/pods"
```

The API should return a Pod list containing `target` and `api-client`.

## 7. Test denied API access from the Pod

Still inside the container, attempt to delete the target Pod:

```sh
curl --silent \
  --request DELETE \
  --cacert "$CACERT" \
  --header "Authorization: Bearer $TOKEN" \
  "$API/api/v1/namespaces/access-control/pods/target"
```

The API response should report a `403 Forbidden` error because the Role does not grant the `delete` verb.

Attempt to list Pods in `kube-system`:

```sh
curl --silent \
  --cacert "$CACERT" \
  --header "Authorization: Bearer $TOKEN" \
  "$API/api/v1/namespaces/kube-system/pods"
```

This request should also report `403 Forbidden`.

Exit the container shell:

```sh
exit
```

Verify that the target Pod still exists:

```bash
kubectl get pod target -n access-control
```

## 8. Inspect the effective permissions

List the permissions granted to the ServiceAccount in the namespace:

```bash
kubectl auth can-i --list \
  -n access-control \
  --as=system:serviceaccount:access-control:pod-reader
```

Inspect the Role:

```bash
kubectl describe role pod-reader -n access-control
```

Inspect the RoleBinding:

```bash
kubectl describe rolebinding pod-reader -n access-control
```

Confirm that the binding references the expected Role and ServiceAccount.

## Troubleshooting

Inspect the RBAC resources:

```bash
kubectl get serviceaccount,role,rolebinding -n access-control -o yaml
```

Check a specific authorization decision:

```bash
kubectl auth can-i <verb> <resource> \
  -n access-control \
  --as=system:serviceaccount:access-control:pod-reader
```

Inspect the API client Pod:

```bash
kubectl describe pod api-client -n access-control
```

Confirm that it uses the expected ServiceAccount:

```bash
kubectl get pod api-client \
  -n access-control \
  -o jsonpath='{.spec.serviceAccountName}{"\n"}'
```

Inspect recent events:

```bash
kubectl get events \
  -n access-control \
  --sort-by=.metadata.creationTimestamp
```

If the in-Pod API request cannot resolve `kubernetes.default.svc`, verify cluster DNS:

```bash
kubectl exec api-client -n access-control -- \
  nslookup kubernetes.default.svc
```

If a request unexpectedly succeeds, inspect all RoleBindings and ClusterRoleBindings that reference the ServiceAccount:

```bash
kubectl get rolebindings -A -o wide
kubectl get clusterrolebindings -o wide
```