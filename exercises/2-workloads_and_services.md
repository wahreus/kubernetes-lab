# Workloads and Services

This guide describes how to practice basic Kubernetes workloads and Services after the cluster has been initialized.

At this point, the Kubernetes cluster should already be running with Calico installed, all three nodes should be `Ready`, and `kubectl` should be configured either on the control-plane node or on the local machine.

This exercise is intentionally focused on the application layer. It covers Deployments, ReplicaSets, Pods, Services, scaling, self-healing, rolling updates, rollbacks, labels, selectors, and basic traffic testing.

## Architecture

The exercise uses one NGINX application running in a separate namespace:

```text
workloads namespace
└── Deployment: web
    └── ReplicaSet
        ├── Pod: web-...
        ├── Pod: web-...
        ├── Pod: web-...
        └── Pod: web-...
```

The application is exposed in two ways during the exercise:

```text
Temporary curl Pod
    │
    ▼
ClusterIP Service: web
    │
    ▼
NGINX Pods
```

Later, the same application is exposed outside the cluster:

```text
Local machine
    │
    ▼
Worker public IP:<NODE_PORT>
    │
    ▼
NodePort Service: web
    │
    ▼
NGINX Pods
```

Important:

* A Deployment manages ReplicaSets.
* A ReplicaSet keeps the desired number of Pods running.
* A Service provides a stable network endpoint for Pods.
* A ClusterIP Service is reachable only inside the cluster.
* A NodePort Service is reachable through a node IP and an assigned port.

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
kubectl create namespace workloads
```

Set it as the current namespace:

```bash
kubectl config set-context --current --namespace=workloads
```

Check the current namespace:

```bash
kubectl config view --minify | grep namespace
```

Expected:

```text
namespace: workloads
```

Important:

* The namespace keeps the exercise resources separate from the default namespace.
* The current context is updated so that later commands do not need `-n workloads`.

## 3. Create a Deployment

Create an NGINX Deployment with two replicas:

```bash
kubectl create deployment web \
  --image=nginx:1.27 \
  --replicas=2
```

Check the Deployment:

```bash
kubectl get deployments
```

Expected:

```text
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
web    2/2     2            2           ...
```

Check the Pods:

```bash
kubectl get pods -o wide
```

Expected:

```text
NAME                   READY   STATUS    RESTARTS   AGE   IP              NODE
web-...                1/1     Running   0          ...   ...             worker-a
web-...                1/1     Running   0          ...   ...             worker-b
```

The exact Pod names, IP addresses, and nodes may differ.

Important:

* The Deployment creates the ReplicaSet automatically.
* The ReplicaSet creates the Pods.
* The Pods may be scheduled on different worker nodes.

## 4. Inspect the Deployment

Check the ReplicaSet created by the Deployment:

```bash
kubectl get replicasets
```

Expected:

```text
NAME              DESIRED   CURRENT   READY   AGE
web-...           2         2         2       ...
```

Describe the Deployment:

```bash
kubectl describe deployment web
```

Look for:

```text
Replicas:               2 desired | 2 updated | 2 total | 2 available
StrategyType:           RollingUpdate
Selector:               app=web
```

Important:

* A Deployment does not manage Pods directly.
* The Deployment manages ReplicaSets.
* The ReplicaSet manages Pods.
* If a Pod is deleted, a replacement Pod is created to keep the desired replica count.

## 5. Expose the Deployment with a ClusterIP Service

Create a Service for the Deployment:

```bash
kubectl expose deployment web \
  --port=80 \
  --target-port=80
```

Check the Service:

```bash
kubectl get svc web
```

Expected:

```text
NAME   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
web    ClusterIP   ...             <none>        80/TCP    ...
```

Check the Service endpoints:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web
```

Expected:

```text
NAME      ADDRESSTYPE   PORTS   ENDPOINTS           AGE
web-...   IPv4          80      <POD_IP>,<POD_IP>   ...

```

Important:

* The Service selects Pods using labels.
* The Service does not send traffic to the Deployment object itself.
* The Service sends traffic to Pods matching its selector.

## 6. Test the Service from inside the cluster

Run a temporary curl Pod:

```bash
kubectl run curl \
  --image=curlimages/curl:latest \
  --rm -it \
  --restart=Never \
  -- curl -I http://web
```

Expected:

```text
HTTP/1.1 200 OK
Server: nginx/...
```

Important:

* The Service name `web` works as an internal DNS name inside the cluster.
* The temporary curl Pod is removed automatically because `--rm` is used.
* This test confirms that cluster-internal Service discovery is working.

## 7. Scale the Deployment

Scale the Deployment to four replicas:

```bash
kubectl scale deployment web --replicas=4
```

Check the Deployment:

```bash
kubectl get deployments
```

Expected:

```text
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
web    4/4     4            4           ...
```

Check the Pods:

```bash
kubectl get pods -o wide
```

Check the Service endpoints again:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web
```

Expected:

```text
NAME      ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
web-...   IPv4          80      <POD_IP>,<POD_IP>,<POD_IP>,<POD_IP>   ...

```

Important:

* Scaling the Deployment changes the desired number of Pods.
* The Service automatically includes the new Pods if their labels match the Service selector.

## 8. Delete a Pod and observe self-healing

List the Pods:

```bash
kubectl get pods
```

Delete one of them:

```bash
kubectl delete pod <POD_NAME>
```

Check the Pods again:

```bash
kubectl get pods
```

Expected:

```text
NAME                   READY   STATUS              RESTARTS   AGE
web-...                1/1     Running             0          ...
web-...                1/1     Running             0          ...
web-...                1/1     Running             0          ...
web-...                0/1     ContainerCreating   0          ...
```

After a short time, the replacement Pod should become `Running`:

```bash
kubectl get pods
```

Expected:

```text
NAME                   READY   STATUS    RESTARTS   AGE
web-...                1/1     Running   0          ...
web-...                1/1     Running   0          ...
web-...                1/1     Running   0          ...
web-...                1/1     Running   0          ...
```

Important:

* Deleting a Pod does not delete the Deployment.
* The ReplicaSet notices that the actual number of Pods is lower than the desired number.
* Kubernetes creates a replacement Pod automatically.

## 9. Perform a rolling update

Update the NGINX image:

```bash
kubectl set image deployment/web nginx=nginx:1.28
```

Watch the rollout:

```bash
kubectl rollout status deployment web
```

Expected:

```text
deployment "web" successfully rolled out
```

Check the rollout history:

```bash
kubectl rollout history deployment web
```

Check the image:

```bash
kubectl describe deployment web | grep Image
```

Expected:

```text
Image: nginx:1.28
```

Important:

* A rolling update replaces old Pods gradually.
* The Deployment creates a new ReplicaSet for the new version.
* The old ReplicaSet is kept so the Deployment can roll back if needed.

## 10. Roll back the Deployment

Undo the last rollout:

```bash
kubectl rollout undo deployment web
```

Watch the rollback:

```bash
kubectl rollout status deployment web
```

Expected:

```text
deployment "web" successfully rolled out
```

Check the image again:

```bash
kubectl describe deployment web | grep Image
```

Expected:

```text
Image: nginx:1.27
```

Important:

* A rollback returns the Deployment to the previous revision.
* Rollbacks are possible because the Deployment keeps rollout history.

## 11. Inspect labels and selectors

Show Pod labels:

```bash
kubectl get pods --show-labels
```

Describe the Service:

```bash
kubectl describe svc web
```

Look for the selector:

```text
Selector: app=web
```

Important:

* Labels identify the Pods.
* Selectors decide which Pods belong to a Service.
* If the Service selector does not match the Pod labels, the Service has no working endpoints.

## 12. Expose the Deployment with NodePort

The current Service is only reachable inside the cluster. Delete it:

```bash
kubectl delete svc web
```

Create a NodePort Service instead:

```bash
kubectl expose deployment web \
  --port=80 \
  --target-port=80 \
  --type=NodePort
```

Check the Service:

```bash
kubectl get svc web
```

Expected:

```text
NAME   TYPE       CLUSTER-IP   EXTERNAL-IP   PORT(S)        AGE
web    NodePort   ...          <none>        80:<NODE_PORT>/TCP   ...
```

Get the assigned NodePort:

```bash
NODE_PORT=$(kubectl get svc web -o jsonpath='{.spec.ports[0].nodePort}')
echo "$NODE_PORT"
```

From your local machine, get a worker public IP:

```bash
WORKER_PUBLIC_IP=$(terraform -chdir=environment_setup/terraform output -raw worker_a_public_ip)
echo "$WORKER_PUBLIC_IP"
```

Test the Service from your local machine:

```bash
curl "http://$WORKER_PUBLIC_IP:$NODE_PORT"
```

Expected:

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

Important:

* NodePort exposes the Service on every node.
* The request can be sent to a worker node public IP and the assigned NodePort.
* The security group must allow access to the NodePort range from your IP.

## 13. Additional challenge: create the resources with YAML

Generate Deployment YAML:

```bash
kubectl create deployment web-yaml \
  --image=nginx:1.27 \
  --replicas=2 \
  --dry-run=client \
  -o yaml > web-deployment.yaml
```

Generate Service YAML:

```bash
kubectl expose deployment web-yaml \
  --port=80 \
  --target-port=80 \
  --type=NodePort \
  --dry-run=client \
  -o yaml > web-service.yaml
```

Apply the files:

```bash
kubectl apply -f web-deployment.yaml
kubectl apply -f web-service.yaml
```

Check the resources:

```bash
kubectl get deployments
kubectl get pods
kubectl get svc
```

Clean up the YAML-created resources:

```bash
kubectl delete -f web-service.yaml
kubectl delete -f web-deployment.yaml
rm web-deployment.yaml web-service.yaml
```

Important:

* `--dry-run=client -o yaml` is useful for generating starter manifests.
* `kubectl apply -f` is closer to how Kubernetes resources are usually managed in real projects.

## 14. Clean up

Delete the Service:

```bash
kubectl delete svc web
```

Delete the Deployment:

```bash
kubectl delete deployment web
```

Delete the namespace:

```bash
kubectl delete namespace workloads
```

Return to the default namespace:

```bash
kubectl config set-context --current --namespace=default
```

Check that the namespace was removed:

```bash
kubectl get namespace workloads
```

Expected:

```text
Error from server (NotFound): namespaces "workloads" not found
```

Important:

* Deleting the namespace removes all resources inside it.
* Returning to the default namespace avoids confusion in later exercises.

## Commands practiced

```text
kubectl get nodes
kubectl create namespace
kubectl config set-context
kubectl config view
kubectl create deployment
kubectl get deployments
kubectl get pods -o wide
kubectl get replicasets
kubectl describe deployment
kubectl expose deployment
kubectl get svc
kubectl get endpoints
kubectl run
kubectl scale deployment
kubectl delete pod
kubectl set image
kubectl rollout status
kubectl rollout history
kubectl rollout undo
kubectl get pods --show-labels
kubectl describe svc
kubectl apply
kubectl delete
```

## Summary

This guide showed how to run and expose a basic Kubernetes workload.

A separate namespace was created for the exercise. An NGINX Deployment was then created with two replicas, and Kubernetes created the ReplicaSet and Pods needed to match the desired state. The Deployment was inspected to show how Deployments, ReplicaSets, and Pods relate to each other.

A ClusterIP Service was created to provide stable internal access to the Pods. A temporary curl Pod was used to verify that the Service could be reached through the internal DNS name `web`. The Deployment was then scaled, and the Service endpoints updated automatically as more Pods were added.

Self-healing was tested by deleting one Pod and observing Kubernetes create a replacement. A rolling update changed the NGINX image version, and a rollback restored the previous version. Labels and selectors were inspected to show how Services decide which Pods receive traffic.

Finally, the internal Service was replaced with a NodePort Service so the application could be reached from the local machine through a worker node public IP and the assigned NodePort. The exercise ended by deleting the Service, Deployment, and namespace.