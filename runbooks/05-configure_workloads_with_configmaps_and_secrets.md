# Configure workloads with ConfigMaps and Secrets

Create a ConfigMap and Secret, consume their values from a Deployment, update the configuration, and restart the workload to apply the changes.

## Prerequisites

* The Kubernetes cluster has been initialized using either cluster setup runbook.
* A CNI has been installed.

This runbook is independent of the other workload-management runbooks.

Run all commands on the control-plane node unless otherwise specified.

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

Create a namespace for the configuration exercise:

```bash
kubectl create namespace configuration
```

Verify the namespace:

```bash
kubectl get namespace configuration
```

## 3. Create the configuration manifest

Create a file named `configuration.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: configuration
data:
  APP_MODE: development
  message.txt: |
    Configuration loaded from a ConfigMap.
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: configuration
type: Opaque
stringData:
  API_USERNAME: demo-user
  API_PASSWORD: demo-password
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: config-demo
  namespace: configuration
spec:
  replicas: 1
  selector:
    matchLabels:
      app: config-demo
  template:
    metadata:
      labels:
        app: config-demo
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command:
            - sh
            - -c
          args:
            - |
              while true; do
                echo "APP_MODE=$APP_MODE"
                echo "API_USERNAME=$API_USERNAME"
                echo "message=$(cat /etc/app/message.txt)"
                sleep 30
              done
          env:
            - name: APP_MODE
              valueFrom:
                configMapKeyRef:
                  name: app-config
                  key: APP_MODE
            - name: API_USERNAME
              valueFrom:
                secretKeyRef:
                  name: app-secret
                  key: API_USERNAME
          volumeMounts:
            - name: app-config
              mountPath: /etc/app
              readOnly: true
      volumes:
        - name: app-config
          configMap:
            name: app-config
```

The ConfigMap stores non-confidential application configuration. The Secret stores values that should be handled separately from normal configuration.

The Deployment consumes:

* `APP_MODE` from the ConfigMap as an environment variable.
* `API_USERNAME` from the Secret as an environment variable.
* `message.txt` from the ConfigMap as a mounted file.

Apply the manifest:

```bash
kubectl apply -f configuration.yaml
```

Wait for the Deployment to become available:

```bash
kubectl rollout status deployment/config-demo -n configuration
```

## 4. Inspect the configuration objects

Inspect the ConfigMap:

```bash
kubectl describe configmap app-config -n configuration
```

Inspect the Secret metadata:

```bash
kubectl describe secret app-secret -n configuration
```

`kubectl describe secret` shows the stored keys and their sizes without printing their values.

List the resources:

```bash
kubectl get configmap,secret,deployment,pods -n configuration
```

## 5. Verify the consumed values

Read the Deployment logs:

```bash
kubectl logs deployment/config-demo -n configuration
```

The output should include:

```text
APP_MODE=development
API_USERNAME=demo-user
message=Configuration loaded from a ConfigMap.
```

Inspect the environment variables inside the container:

```bash
kubectl exec deployment/config-demo -n configuration -- \
  sh -c 'printf "APP_MODE=%s\nAPI_USERNAME=%s\n" "$APP_MODE" "$API_USERNAME"'
```

Inspect the mounted ConfigMap file:

```bash
kubectl exec deployment/config-demo -n configuration -- \
  cat /etc/app/message.txt
```

## 6. Inspect a Secret value

Read and decode the `API_USERNAME` value:

```bash
kubectl get secret app-secret \
  -n configuration \
  -o jsonpath='{.data.API_USERNAME}' | base64 --decode

echo
```

Kubernetes stores Secret data in base64-encoded form in the API. **Base64 encoding is NOT encryption**, so access to Secrets should be restricted with RBAC and encryption at rest should be considered for sensitive clusters.

## 7. Update the ConfigMap

Update both ConfigMap values:

```bash
kubectl patch configmap app-config \
  -n configuration \
  --type=merge \
  -p '{"data":{"APP_MODE":"production","message.txt":"Updated configuration loaded from a ConfigMap.\n"}}'
```

Inspect the ConfigMap:

```bash
kubectl get configmap app-config -n configuration -o yaml
```

The mounted file is updated automatically after Kubernetes refreshes the projected volume. The environment variable in the existing container does not change because environment variables are set when the container starts.

Wait briefly, then inspect the mounted file:

```bash
kubectl exec deployment/config-demo -n configuration -- \
  cat /etc/app/message.txt
```

Inspect the unchanged environment variable:

```bash
kubectl exec deployment/config-demo -n configuration -- \
  printenv APP_MODE
```

It should still report:

```text
development
```

## 8. Restart the Deployment

Restart the Deployment so that the Pod reads the updated environment variable:

```bash
kubectl rollout restart deployment/config-demo -n configuration
```

Wait for the restart to complete:

```bash
kubectl rollout status deployment/config-demo -n configuration
```

Verify the updated values:

```bash
kubectl exec deployment/config-demo -n configuration -- \
  sh -c 'printf "APP_MODE=%s\nmessage=%s\n" "$APP_MODE" "$(cat /etc/app/message.txt)"'
```

The output should now include:

```text
APP_MODE=production
message=Updated configuration loaded from a ConfigMap.
```

> **Note:** The `kubectl patch` command updates the live ConfigMap but does not modify `configuration.yaml`. Reapplying the original file would restore the original values.

## Troubleshooting

Inspect the Deployment and Pod:

```bash
kubectl describe deployment config-demo -n configuration
kubectl describe pod -n configuration -l app=config-demo
```

Inspect the configuration objects:

```bash
kubectl get configmap app-config -n configuration -o yaml
kubectl describe secret app-secret -n configuration
```

Inspect recent events:

```bash
kubectl get events \
  -n configuration \
  --sort-by=.metadata.creationTimestamp
```

If the Pod reports `CreateContainerConfigError`, verify that the referenced ConfigMap, Secret, and keys exist:

```bash
kubectl get configmap,secret -n configuration
kubectl describe pod -n configuration -l app=config-demo
```

If a mounted file has not updated yet, wait briefly and inspect it again. ConfigMap volume updates are eventually propagated to running Pods.

If an environment variable remains unchanged, restart the Deployment:

```bash
kubectl rollout restart deployment/config-demo -n configuration
kubectl rollout status deployment/config-demo -n configuration
```