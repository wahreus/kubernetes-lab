# Gateway API, Envoy, and Helm

This guide describes how to practice the Kubernetes Gateway API using Envoy Gateway as the implementation and Helm as the installation tool.

At this point, the Kubernetes cluster should already be running with Calico installed, all three nodes should be `Ready`, and `kubectl` should be configured either on the control-plane node or on the local machine.

This exercise is intentionally focused on modern Kubernetes ingress-style traffic management.

It covers Gateway API CRDs, `GatewayClass`, `Gateway`, `HTTPRoute`, Envoy Gateway, Helm installation, `LoadBalancer` Service behavior, route inspection, port-forward testing, and Helm release management.

## Architecture

The exercise installs Envoy Gateway into its own namespace:

```text
envoy-gateway-system namespace
└── Envoy Gateway controller
    └── creates and manages Envoy proxy data-plane resources
```

The application runs in a separate namespace:

```text
gateway-lab namespace
├── Deployment: frontend
├── Service: frontend
├── Deployment: api
├── Service: api
├── GatewayClass: envoy
├── Gateway: public-gateway
└── HTTPRoute: web-route
```

Traffic flows through Envoy before reaching the application Services:

```text
Local machine
  │
  ▼
kubectl port-forward localhost:8888
  │
  ▼
Envoy proxy Service
  │
  ▼
Gateway: public-gateway
  │
  ▼
HTTPRoute: web-route
  ├── /api  -> api Service
  └── /     -> frontend Service
```

Important:

* Gateway API resources are CRDs, not built-in core Kubernetes resources.
* Envoy Gateway is the controller that implements the Gateway API resources.
* Helm installs and manages the Envoy Gateway release.
* `GatewayClass` describes the gateway implementation.
* `Gateway` describes the listener where traffic enters.
* `HTTPRoute` describes how HTTP requests are routed to Services.
* A `LoadBalancer` Service asks for an external load balancer, but still behaves like a Kubernetes Service.
* In this EC2 kubeadm lab, there is no cloud `LoadBalancer` integration, so this exercise tests Envoy with `kubectl port-forward`.

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

Check that Helm is available:

```bash
helm version
```

Expected:

```text
version.BuildInfo{Version:"v3...", ...}
```

Important:

* `kubectl` talks to the Kubernetes API server.
* Helm also talks to the Kubernetes API server, but manages a group of resources as a release.
* This exercise assumes Helm 3 is installed.

## 2. Check whether Gateway API already exists

Check for Gateway API resources:

```bash
kubectl api-resources --api-group=gateway.networking.k8s.io
```

In a plain kubeadm cluster, this may return no resources.

You can also check for the CRDs directly:

```bash
kubectl get crds | grep gateway.networking.k8s.io
```

Important:

* `Ingress` is a built-in Kubernetes resource.
* Gateway API resources such as `GatewayClass`, `Gateway`, and `HTTPRoute` are usually installed as CRDs.
* Installing CRDs means the Kubernetes API server learns new resource types.
* Installing a controller means something actually reconciles those resources into working traffic behavior.

## 3. Install Envoy Gateway with Helm

Install Envoy Gateway:

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.8.1 \
  -n envoy-gateway-system \
  --create-namespace
```

Wait for the Envoy Gateway controller:

```bash
kubectl wait --timeout=5m \
  -n envoy-gateway-system \
  deployment/envoy-gateway \
  --for=condition=Available
```

Check the Helm release:

```bash
helm list -n envoy-gateway-system
```

Expected:

```text
NAME   NAMESPACE              REVISION   UPDATED   STATUS     CHART          APP VERSION
eg     envoy-gateway-system   1          ...       deployed   gateway-helm   ...
```

Check the controller Pod:

```bash
kubectl get pods -n envoy-gateway-system
```

Expected:

```text
NAME                             READY   STATUS    RESTARTS   AGE
envoy-gateway-...                1/1     Running   0          ...
```

Important:

* The Helm release name is `eg`.
* The release is installed into the `envoy-gateway-system` namespace.
* Envoy Gateway is the control plane.
* Envoy proxy instances created later are the data plane.

## 4. Inspect the installed Gateway API resources

Check the Gateway API resources again:

```bash
kubectl api-resources --api-group=gateway.networking.k8s.io
```

Expected resources include:

```text
gatewayclasses
gateways
httproutes
referencegrants
```

Check the CRDs:

```bash
kubectl get crds | grep gateway.networking.k8s.io
```

Expected:

```text
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
...
```

Important:

* Helm installed the Gateway API CRDs.
* The API server now accepts Gateway API manifests.
* Envoy Gateway watches those resources and turns them into Envoy proxy configuration.

## 5. Create a namespace

Create a separate namespace for the exercise:

```bash
kubectl create namespace gateway-lab
```

Set it as the current namespace:

```bash
kubectl config set-context --current --namespace=gateway-lab
```

Check the current namespace:

```bash
kubectl config view --minify | grep namespace
```

Expected:

```text
namespace: gateway-lab
```

Important:

* The application resources live in `gateway-lab`.
* Envoy Gateway itself lives in `envoy-gateway-system`.
* `GatewayClass` is cluster-scoped, while `Gateway` and `HTTPRoute` are namespaced.

## 6. Deploy two backend applications

Create the application resources:

```bash
cat <<'EOF' > gateway-apps.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-content
data:
  index.html: |
    frontend
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-content
data:
  index.html: |
    api
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html/index.html
          subPath: index.html
      volumes:
      - name: content
        configMap:
          name: frontend-content
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html/index.html
          subPath: index.html
      volumes:
      - name: content
        configMap:
          name: api-content
---
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector:
    app: api
  ports:
  - name: http
    port: 80
    targetPort: 80
EOF
```

Apply the manifest:

```bash
kubectl apply -f gateway-apps.yaml
```

Check the Pods and Services:

```bash
kubectl get pods
kubectl get svc
```

Expected:

```text
NAME                            READY   STATUS    RESTARTS   AGE
api-...                         1/1     Running   0          ...
api-...                         1/1     Running   0          ...
frontend-...                    1/1     Running   0          ...
frontend-...                    1/1     Running   0          ...
```

```text
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
api        ClusterIP   ...          <none>        80/TCP    ...
frontend   ClusterIP   ...          <none>        80/TCP    ...
```

Test the Services from inside the cluster:

```bash
kubectl run curl \
  --image=curlimages/curl:latest \
  --rm -it \
  --restart=Never \
  -- curl http://frontend
```

Expected:

```text
frontend
```

Test the API Service:

```bash
kubectl run curl \
  --image=curlimages/curl:latest \
  --rm -it \
  --restart=Never \
  -- curl http://api
```

Expected:

```text
api
```

Important:

* The Services are only `ClusterIP` Services.
* They are reachable inside the cluster, but not directly from outside.
* Gateway API will expose them through Envoy.

## 7. Create a LoadBalancer Service

Before using Gateway API, create a normal `LoadBalancer` Service.

This is included to show how Kubernetes represents external load balancer requests, even if this lab does not automatically provision a real AWS load balancer.

Create a temporary NGINX Deployment:

```bash
kubectl create deployment lb-demo --image=nginx:1.27
```

Expose it with a `LoadBalancer` Service:

```bash
kubectl expose deployment lb-demo \
  --port=80 \
  --target-port=80 \
  --type=LoadBalancer
```

Check the Service:

```bash
kubectl get svc lb-demo
```

Expected:

```text
NAME      TYPE           CLUSTER-IP   EXTERNAL-IP   PORT(S)        AGE
lb-demo   LoadBalancer   ...          <pending>     80:3.../TCP    ...
```

Inspect the Service:

```bash
kubectl describe svc lb-demo
```

Look for:

```text
Type:                     LoadBalancer
Port:                     <unset>  80/TCP
TargetPort:               80/TCP
NodePort:                 <unset>  3.../TCP
Endpoints:                ...
```

Check the EndpointSlice:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=lb-demo
```

Expected:

```text
NAME          ADDRESSTYPE   PORTS   ENDPOINTS   AGE
lb-demo-...   IPv4          80      ...         ...
```

Important:

* `LoadBalancer` is a Kubernetes Service type.
* It gives the Service a stable `ClusterIP`.
* It also allocates a `NodePort` behind the scenes.
* It asks an external load balancer implementation for an external IP or hostname.
* In this kubeadm EC2 lab, `EXTERNAL-IP` stays `<pending>` because no cloud load balancer controller is installed.
* The important part is knowing how to create, inspect, and reason about the Service type.

Clean up the temporary demo:

```bash
kubectl delete svc lb-demo
kubectl delete deployment lb-demo
```

## 8. Create a GatewayClass

Create a `GatewayClass` for Envoy Gateway:

```bash
cat <<'EOF' > gatewayclass.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
```

Apply it:

```bash
kubectl apply -f gatewayclass.yaml
```

Check it:

```bash
kubectl get gatewayclass
```

Expected:

```text
NAME    CONTROLLER                                      ACCEPTED   AGE
envoy   gateway.envoyproxy.io/gatewayclass-controller   True       ...
```

Describe it:

```bash
kubectl describe gatewayclass envoy
```

Important:

* `GatewayClass` is cluster-scoped.
* It defines which controller should handle Gateways using this class.
* This is similar in spirit to how `StorageClass` describes a type of storage that can be requested.
* This object does not expose traffic by itself.

## 9. Create a Gateway

Create a `Gateway`:

```bash
cat <<'EOF' > gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public-gateway
spec:
  gatewayClassName: envoy
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    hostname: gateway.lab.local
    allowedRoutes:
      namespaces:
        from: Same
EOF
```

Apply it:

```bash
kubectl apply -f gateway.yaml
```

Check it:

```bash
kubectl get gateway
```

Expected:

```text
NAME             CLASS   ADDRESS   PROGRAMMED   AGE
public-gateway   envoy             True         ...
```

Describe it:

```bash
kubectl describe gateway public-gateway
```

Look for conditions similar to:

```text
Accepted:    True
Programmed:  True
```

Important:

* The `Gateway` creates the traffic entry point.
* The listener accepts HTTP traffic on port `80`.
* The hostname is `gateway.lab.local`.
* The Gateway references the `envoy` `GatewayClass`.
* Envoy Gateway should react by creating Envoy data-plane resources.

## 10. Create an HTTPRoute

Create an `HTTPRoute`:

```bash
cat <<'EOF' > httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
spec:
  parentRefs:
  - name: public-gateway
  hostnames:
  - gateway.lab.local
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /
    backendRefs:
    - name: api
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: frontend
      port: 80
EOF
```

Apply it:

```bash
kubectl apply -f httproute.yaml
```

Check it:

```bash
kubectl get httproute
```

Expected:

```text
NAME        HOSTNAMES               AGE
web-route   ["gateway.lab.local"]    ...
```

Describe it:

```bash
kubectl describe httproute web-route
```

Look for conditions similar to:

```text
Accepted:      True
ResolvedRefs:  True
```

Important:

* `parentRefs` attaches the route to the `public-gateway`.
* `hostnames` means the route only matches requests for `gateway.lab.local`.
* `/api` is routed to the `api` Service.
* `/` is routed to the `frontend` Service.
* The URL rewrite changes `/api` to `/` before sending the request to the NGINX API backend.

## 11. Inspect the Envoy data plane

List the Envoy Gateway namespace:

```bash
kubectl get all -n envoy-gateway-system
```

You should see the Envoy Gateway controller and additional Envoy proxy resources created for the `Gateway`.

Get the Envoy proxy Service created for this Gateway:

```bash
ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=gateway-lab,gateway.envoyproxy.io/owning-gateway-name=public-gateway \
  -o jsonpath='{.items[0].metadata.name}')

echo "$ENVOY_SERVICE"
```

Check the Service:

```bash
kubectl get svc "$ENVOY_SERVICE" -n envoy-gateway-system
```

Expected:

```text
NAME              TYPE           CLUSTER-IP   EXTERNAL-IP   PORT(S)        AGE
envoy-...         LoadBalancer   ...          <pending>     80:.../TCP     ...
```

Important:

* Envoy Gateway created a Service for the Envoy data plane.
* In a managed cloud Kubernetes cluster, a `LoadBalancer` Service may get an external IP or hostname.
* In this kubeadm EC2 lab, `EXTERNAL-IP` will probably stay `<pending>` because there is no cloud load balancer controller.
* This is why the next step uses `kubectl port-forward`.

## 12. Test traffic through Envoy

Port-forward to the Envoy proxy Service:

```bash
kubectl -n envoy-gateway-system port-forward \
  service/${ENVOY_SERVICE} \
  8888:80
```

Keep this command running and open  another control-plane terminal.

In the newly opened control-plane terminal, test the frontend route:

```bash
curl -H "Host: gateway.lab.local" http://localhost:8888/
```

Expected:

```text
frontend
```

Test the API route:

```bash
curl -H "Host: gateway.lab.local" http://localhost:8888/api
```

Expected:

```text
api
```

Test a request with the wrong host:

```bash
curl -i -H "Host: wrong.lab.local" http://localhost:8888/
```

Expected:

```text
HTTP/1.1 404 Not Found
```

Important:

* The request enters through the Envoy proxy.
* The `Gateway` listener accepts HTTP traffic for `gateway.lab.local`.
* The `HTTPRoute` decides which Service receives the request.
* The `Host` header matters because the route has a hostname match.

## 13. Inspect the relationship between the resources

Show the three main Gateway API resources:

```bash
kubectl get gatewayclass
kubectl get gateway
kubectl get httproute
```

Follow the chain:

```bash
kubectl get gateway public-gateway \
  -o jsonpath='gatewayClassName={.spec.gatewayClassName}{"\n"}'
```

Expected:

```text
gatewayClassName=envoy
```

Check which Gateway the route attaches to:

```bash
kubectl get httproute web-route \
  -o jsonpath='parentRef={.spec.parentRefs[0].name}{"\n"}'
```

Expected:

```text
parentRef=public-gateway
```

Check the backends used by the route:

```bash
kubectl get httproute web-route \
  -o jsonpath='{range .spec.rules[*]}{range .backendRefs[*]}{.name}{"\n"}{end}{end}'
```

Expected:

```text
api
frontend
```

Important:

* `GatewayClass` points to the controller.
* `Gateway` points to the `GatewayClass`.
* `HTTPRoute` points to the `Gateway`.
* `HTTPRoute` backend references point to Services.
* Services point to Pods through selectors.

## 14. Practice a Helm upgrade and rollback

Check the current Helm release:

```bash
helm status eg -n envoy-gateway-system
```

Upgrade the release by scaling the Envoy Gateway controller to two replicas:

```bash
helm upgrade eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.8.1 \
  -n envoy-gateway-system \
  --reuse-values \
  --set deployment.replicas=2
```

Check the Deployment:

```bash
kubectl get deployment envoy-gateway -n envoy-gateway-system
```

Expected:

```text
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
envoy-gateway    2/2     2            2           ...
```

Check the Helm history:

```bash
helm history eg -n envoy-gateway-system
```

Expected:

```text
REVISION   UPDATED   STATUS      CHART          APP VERSION   DESCRIPTION
1          ...       superseded   gateway-helm   ...           Install complete
2          ...       deployed     gateway-helm   ...           Upgrade complete
```

Roll back to the first revision:

```bash
helm rollback eg 1 -n envoy-gateway-system
```

Check the Deployment again:

```bash
kubectl get deployment envoy-gateway -n envoy-gateway-system
```

Expected:

```text
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
envoy-gateway    1/1     1            1           ...
```

Important:

* Helm tracks release revisions.
* `helm upgrade` changes the release.
* `helm history` shows previous revisions.
* `helm rollback` returns the release to an earlier revision.
* Helm is commonly used to install controllers such as Envoy Gateway, ingress controllers, cert-manager, metrics-server, and monitoring stacks.

## 15. Create a routing failure and debug it

Change the route to point `/api` at a Service that does not exist:

```bash
kubectl patch httproute web-route \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/name","value":"missing-api"}]'
```

Describe the route:

```bash
kubectl describe httproute web-route
```

Look for a condition showing that backend references are not fully resolved:

```text
ResolvedRefs: False
```

Test the broken route:

```bash
curl -i -H "Host: gateway.lab.local" http://localhost:8888/api
```

Expected:

```text
HTTP/1.1 500 Internal Server Error
```

Restore the route:

```bash
kubectl patch httproute web-route \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/name","value":"api"}]'
```

Check the condition again:

```bash
kubectl describe httproute web-route
```

Test the API route again:

```bash
curl -H "Host: gateway.lab.local" http://localhost:8888/api
```

Expected:

```text
api
```

Important:

* Gateway API status conditions are useful for debugging.
* A route can exist but still not be fully valid.
* `ResolvedRefs` tells you whether referenced objects such as Services can be found.
* This is similar to checking Events on Pods, but for traffic routing configuration.

## 16. Clean up

Stop the `kubectl port-forward` command with `Ctrl+C`.

Delete the application namespace:

```bash
kubectl delete namespace gateway-lab
```

Uninstall Envoy Gateway:

```bash
helm uninstall eg -n envoy-gateway-system
```

Delete the Envoy Gateway namespace:

```bash
kubectl delete namespace envoy-gateway-system
```

Check whether Gateway API CRDs remain:

```bash
kubectl get crds | grep gateway.networking.k8s.io
```

Important:

* Helm usually does not remove CRDs installed from a chart's `crds/` directory.
* Leaving the Gateway API CRDs installed is fine if you plan to continue practicing Gateway API.
* Only remove Gateway API and Envoy Gateway CRDs manually if this is a disposable lab cluster and you are sure nothing else uses them.

On a disposable lab cluster, remove the Gateway API and Envoy Gateway CRDs with:

```bash
kubectl get crd -o name | grep -E 'gateway.networking.k8s.io|gateway.envoyproxy.io' | xargs kubectl delete
```

## Commands practiced

```text
helm install
helm list
helm status
helm upgrade
helm history
helm rollback
helm uninstall
kubectl api-resources
kubectl get crds
kubectl create deployment
kubectl expose deployment
kubectl describe svc
kubectl get endpointslices
kubectl get gatewayclass
kubectl get gateway
kubectl get httproute
kubectl describe gatewayclass
kubectl describe gateway
kubectl describe httproute
kubectl port-forward
kubectl patch httproute
kubectl get svc --selector
kubectl get jsonpath
```

## Summary

This guide showed how to inspect `LoadBalancer` Service behavior, install Envoy Gateway with Helm, and use Envoy Gateway as a Gateway API implementation.

A temporary `LoadBalancer` Service was created to show that Kubernetes allocates a Service, EndpointSlice, and backing NodePort even when the external IP remains `<pending>`. Helm then installed the Envoy Gateway controller and the Gateway API CRDs. A `GatewayClass` was created to point at the Envoy Gateway controller, a `Gateway` was created to define an HTTP listener, and an `HTTPRoute` was created to route traffic to two backend Services.


Because this kubeadm-based EC2 lab does not include a cloud load balancer controller, traffic was tested through `kubectl port-forward` to the Envoy proxy Service. The exercise also showed how to inspect Gateway API status conditions, debug a broken backend reference, and use Helm to upgrade and roll back the Envoy Gateway release.